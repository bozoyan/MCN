// 职责: Run 最小观察者 — 监听 aiChatRuntimeProvider 的 isRequestInFlight 转换，
//       turn 结束（true→false）时把最新 assistant 文本转发到 IM chat；若 turn 结束但
//       未产生新 assistant 消息（疑似崩溃）则写 assistant_inbox 并转发错误文案。
// 关联文件:
//   lib/shared/services/remote/remote_bridge_service.dart
//   lib/shared/providers/ai_providers.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/models/ai_chat_models.dart
//   lib/shared/database/daos/assistant_inbox_dao.dart
//   lib/shared/providers/remote_bridge_providers.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//   .agents/rules/service-naming.md

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logger/app_logger.dart';
import '../../models/ai_chat_models.dart';
import '../../providers/ai_providers.dart';
import '../../providers/novel_providers.dart';
import 'remote_bridge_service.dart';

final _log = AppLogger.forModule('RunOutputForwarder');

/// 单条转发消息的字符上限（adapter chunking 兜底，此处提前截断减少分片数）。
const _maxMessageChars = 2000;

/// turn 异常结束时写入 inbox 与转发 IM 的兜底文案（微信用户可见，中文）。
const _runCrashedFallbackText = '运行异常结束，未生成有效输出。';

/// 观察某 run session 的 isRequestInFlight 转换并在 turn 结束时转发最终文本。
class _SessionSubscription {
  _SessionSubscription({
    required this.runTitle,
    required this.chatId,
    required this.assistantSessionId,
    required this.listener,
    required this.wasInFlight,
    this.lastForwardedMessageId,
    this.baselineUnknown = false,
  });

  final String runTitle;
  final String chatId;
  final String assistantSessionId;
  final ProviderSubscription<bool> listener;

  /// 上一次观察到的 isRequestInFlight 值，用于检测 true→false 转换。
  bool wasInFlight;

  /// 已转发过的最后一条 assistant 消息 id，避免重复转发上一轮残留消息。
  String? lastForwardedMessageId;

  /// restore 后基线未知（session 未加载、lastForwardedMessageId 不可靠）。
  ///
  /// 为 true 时，首轮 turn 结束只转发不判崩溃：
  /// - 有 assistant 消息 → 转发（可能为新一输出；若本轮未产生新输出则为旧消息
  ///   重发，属可接受边界）。
  /// - 无 assistant 消息 → 跳过崩溃兜底（基线未知，无法判定是否真的崩溃）。
  /// 首轮过后置 false，恢复 normal 转发 + 崩溃判定路径。
  bool baselineUnknown;
}

/// Run 最小观察者（方案 §5.3 流程 4 / PR-4）。
///
/// 设计要点：
/// - **纯代码、无 LLM 参与**：直接订阅 `aiChatRuntimeProvider(sessionId)
///   .select((s) => s.isRequestInFlight)`，在 true→false 转换时转发最终文本。
/// - **per-turn 一次转发**：一轮 turn 内 agent 可能产出多条 assistant 消息，
///   仅转发最后一条（用户看到的是 turn 收尾的总结），避免刷屏。
///   进度通知由 run agent 自身通过 `Run notify` 子命令写入 inbox（B1 通道）。
/// - **崩溃兜底**：若 turn 结束时未产生新 assistant 消息（与上一轮转发 id 相同
///   或无 assistant 消息），视为异常结束，写 inbox（source=run_observer,
///   type=error）并把兜底文案转发 IM，让用户与 Assistant 均可感知。
/// - **来源标签**：每条消息前缀 `【<run 标题>】`，让用户区分多个并行 run。
///
/// 生命周期：
/// - [register] 在远程 run 启动时（startRun 回调）或 app 重启恢复订阅时调用。
/// - [unregister] 在 session 清理时调用（V1 暂不自动调用）。
/// - [dispose] 在 forwarder 所在 provider 销毁时调用。
class RunOutputForwarder {
  RunOutputForwarder({required this.ref, required this.bridge});

  /// 所在 provider 的 [Ref]，用于订阅 `aiChatRuntimeProvider` 与读取 appDatabase。
  /// forwarder provider 为单例（非 autoDispose），故 [ref] 生命周期 = app 生命周期。
  final Ref ref;
  final RemoteBridgeService bridge;

  final Map<String, _SessionSubscription> _subscriptions = {};

  /// 注册监听某 run session 的 turn 结束事件。
  ///
  /// [assistantSessionId] 为该 run 所属 Assistant 会话 id，崩溃兜底时写入其 inbox。
  /// 幂等：重复 register 同 sessionId 会先 unregister 旧的再注册新的
  ///（run 标题 / assistantSessionId 可能变化，例如重命名后重启 run）。
  Future<void> register({
    required String sessionId,
    required String runTitle,
    required String chatId,
    required String channelType,
    required String assistantSessionId,
  }) async {
    if (_subscriptions.containsKey(sessionId)) {
      await unregister(sessionId);
    }

    // 注册即读当前 isRequestInFlight 与最新 assistant 消息 id，建立基线：
    // - wasInFlight 防止把 register 时的 in-flight 状态误判为 turn 结束
    // - lastForwardedMessageId 防止把上一轮残留消息当作本轮新输出转发
    // restore 路径下 session 尚未加载（messages 为空），lastForwardedMessageId
    // 无法从内存推导 → 标记 baselineUnknown，首轮只转发不判崩溃（见 _onTurnEnded）。
    final runtime = ref.read(aiChatRuntimeProvider(sessionId));
    final session = ref.read(aiChatSessionProvider(sessionId));
    final baselineUnknown = !session.isLoaded;
    final latest = baselineUnknown
        ? null
        : _latestCompletedAssistantMessage(session.messages);

    final sub = _SessionSubscription(
      runTitle: runTitle,
      chatId: chatId,
      assistantSessionId: assistantSessionId,
      wasInFlight: runtime.isRequestInFlight,
      lastForwardedMessageId: latest?.id,
      baselineUnknown: baselineUnknown,
      listener: ref.listen(
        aiChatRuntimeProvider(sessionId).select((s) => s.isRequestInFlight),
        (_, isInFlight) => _onInFlightChanged(sessionId, isInFlight),
        fireImmediately: false,
      ),
    );
    _subscriptions[sessionId] = sub;
    _log.info(
      'registered session=$sessionId runTitle=$runTitle chatId=$chatId '
      'assistantSession=$assistantSessionId wasInFlight=${sub.wasInFlight} '
      'lastForwarded=${sub.lastForwardedMessageId} '
      'baselineUnknown=$baselineUnknown',
    );
  }

  /// 取消监听。
  Future<void> unregister(String sessionId) async {
    final sub = _subscriptions.remove(sessionId);
    if (sub == null) return;
    sub.listener.close();
    _log.info('unregistered session=$sessionId');
  }

  /// 清理所有订阅（dispose 时调用）。
  Future<void> dispose() async {
    final ids = _subscriptions.keys.toList(growable: false);
    _subscriptions.clear();
    for (final id in ids) {
      await unregister(id);
    }
  }

  void _onInFlightChanged(String sessionId, bool isInFlight) {
    final sub = _subscriptions[sessionId];
    if (sub == null) return;
    final previous = sub.wasInFlight;
    sub.wasInFlight = isInFlight;
    // 只在 true→false 转换（turn 结束）时触发转发；false→true（turn 开始）忽略。
    if (previous && !isInFlight) {
      _onTurnEnded(sessionId, sub);
    }
  }

  Future<void> _onTurnEnded(String sessionId, _SessionSubscription sub) async {
    // A4: 取消不视为崩溃 —— 在任何 await 之前读取 runtime 的 cancelledRequestIds，
    // 保证 cancelRequest 写入的 id 尚未被 markRequestIdle 清除（后者在 headless turn
    // 的 finally 块中、state 变更之后执行）。
    final isCancelled = ref
        .read(aiChatRuntimeProvider(sessionId).notifier)
        .cancelledRequestIds
        .isNotEmpty;
    if (isCancelled) {
      _log.info('turn ended by cancel session=$sessionId — skip crash inbox');
      return;
    }

    final session = ref.read(aiChatSessionProvider(sessionId));
    final latest = _latestCompletedAssistantMessage(session.messages);

    // A5: restore 后基线未知 —— 首轮只转发不判崩溃。
    if (sub.baselineUnknown) {
      sub.baselineUnknown = false;
      sub.lastForwardedMessageId = latest?.id;
      if (latest != null) {
        final text = latest.effectiveText.trim();
        if (text.isNotEmpty) {
          await _forwardToChat(sub, text);
        } else {
          _log.info(
            'baseline unknown, first turn empty text session=$sessionId — skip',
          );
        }
      } else {
        _log.info(
          'baseline unknown, first turn no assistant message '
          'session=$sessionId — skip crash judgment',
        );
      }
      return;
    }

    if (latest != null && latest.id != sub.lastForwardedMessageId) {
      // 正常 turn 结束：转发最新 assistant 文本到 IM。
      sub.lastForwardedMessageId = latest.id;
      final text = latest.effectiveText.trim();
      if (text.isEmpty) {
        // 文本为空（极端情况：assistant 消息存在但只有 tool call block），
        // 不转发 IM，也不写 inbox —— 视为无可见输出。
        _log.info('turn ended with empty text session=$sessionId — skip');
        return;
      }
      await _forwardToChat(sub, text);
      return;
    }

    // 异常结束：未产生新 assistant 消息。写 inbox + 转发兜底文案到 IM。
    _log.warning(
      'turn ended without new assistant message session=$sessionId '
      'lastForwarded=${sub.lastForwardedMessageId} latestId=${latest?.id} '
      '— treating as crash',
    );
    await _writeCrashInbox(sub);
    await _forwardToChat(sub, _runCrashedFallbackText);
  }

  Future<void> _forwardToChat(_SessionSubscription sub, String text) async {
    final labeled = '【${sub.runTitle}】$text';
    final truncated = labeled.length > _maxMessageChars
        ? '${labeled.substring(0, _maxMessageChars)}…'
        : labeled;
    final ok = await bridge.sendToUser(sub.chatId, truncated);
    if (!ok) {
      _log.warning(
        'sendToUser failed chatId=${sub.chatId} chars=${truncated.length}',
      );
    } else {
      if (_log.isDebugEnabled) {
        _log.debug('forwarded chatId=${sub.chatId} chars=${truncated.length}');
      }
    }
  }

  Future<void> _writeCrashInbox(_SessionSubscription sub) async {
    try {
      await ref
          .read(appDatabaseProvider)
          .assistantInboxDao
          .append(
            assistantSessionId: sub.assistantSessionId,
            source: 'run_observer',
            messageType: 'error',
            content: _runCrashedFallbackText,
            sourceRef: null,
          );
      _log.info(
        'crash inbox written assistantSession=${sub.assistantSessionId}',
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] crash inbox write failed '
        'assistantSession=${sub.assistantSessionId}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// 取 messages 中最新一条 assistant 非流式消息（用于 turn 结束时转发最终文本）。
AiMessage? _latestCompletedAssistantMessage(List<AiMessage> messages) {
  for (final msg in messages.reversed) {
    if (msg.role != AiMessageRole.assistant || msg.isStreaming) continue;
    return msg;
  }
  return null;
}
