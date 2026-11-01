// 职责: Assistant 桥接协调器 — 把 RemoteBridgeService.onInboundMessage
//       接到 AssistantTurnRunner，按 chatId 串行执行 turn 并回发 Assistant 结果。
// 关联文件:
//   lib/shared/services/remote/remote_bridge_service.dart
//   lib/shared/services/ai/assistant/turn_runner.dart
//   lib/shared/services/ai/assistant/tool_dispatcher.dart
//   lib/shared/services/ai/prompts/ai_prompt_service.dart
//   lib/shared/database/daos/assistant_session_dao.dart
//   lib/shared/database/daos/assistant_inbox_dao.dart
//   lib/shared/database/daos/novel_dao.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//   .agents/rules/ai-calling.md
//   .agents/rules/service-naming.md

import 'dart:async';

import '../../../database/app_database.dart';
import '../../../database/daos/assistant_session_dao.dart';
import '../../../database/daos/assistant_inbox_dao.dart';
import '../../../logger/app_logger.dart';
import '../../../models/ai_provider.dart';
import '../../remote/channel_adapter.dart';
import '../../remote/remote_bridge_service.dart';
import '../usage_service.dart';
import '../prompts/ai_prompt_service.dart';
import 'tool_dispatcher.dart';
import 'turn_runner.dart';

final _log = AppLogger.forModule('AssistantCoordinator');

/// Coordinator 层的 startJob 回调签名。
///
/// 与 [AiStartJobCallback] 的差异：coordinator 从 inbound 上下文注入
/// chatId / channelType，用于写订阅行（remote_chat → chatId）。
typedef AssistantStartJobCallback =
    Future<Map<String, dynamic>> Function(
      String novelId,
      String seed, {
      required String chatId,
      required String channelType,
    });

/// Coordinator 层的 jobStatus 回调签名。
///
/// chatId / channelType 用于归属校验（session_subscriptions.target_id == chatId），
/// 防止跨 chat 越权查询其他会话的 Job 状态。
typedef AssistantJobStatusCallback =
    Future<Map<String, dynamic>> Function(
      String jobId, {
      required String chatId,
      required String channelType,
    });

/// Coordinator 层的 sendToJob 回调签名。
///
/// chatId / channelType 用于归属校验（session_subscriptions.target_id == chatId）。
typedef AssistantSendToJobCallback =
    Future<Map<String, dynamic>> Function(
      String jobId,
      String text, {
      required String chatId,
      required String channelType,
    });

/// Coordinator 层的 createNovel 回调签名。
typedef AssistantCreateNovelCallback =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> novel);

/// Coordinator 层的 editNovel 回调签名。
typedef AssistantEditNovelCallback =
    Future<Map<String, dynamic>> Function(
      String novelId,
      Map<String, dynamic> fields,
    );

typedef AssistantListChaptersCallback =
    Future<Map<String, dynamic>> Function(String novelId);

/// 把 [RemoteBridgeService] 的入站消息接到 [AssistantTurnRunner]。
///
/// PR-3 范围：完成 bridge → turn runner 的端到端编排。
/// - 同 chatId 串行（由 bridge 自身的 _sessionLocks 保证）
/// - 跨 chatId 并发
/// - 失败兜底：发友好错误消息给用户，不向 bridge 透出异常
class AssistantCoordinator {
  AssistantCoordinator({
    required this.bridge,
    required this.dao,
    required this.inboxDao,
    required this.aiPromptService,
    required this.usageService,
    required this.clientFactory,
    required this.readAiSettings,
    required this.listNovels,
    required this.startJob,
    required this.jobStatus,
    required this.sendToJob,
    required this.createNovel,
    required this.editNovel,
    required this.listChapters,
    this.onUsageChanged,
  });

  final RemoteBridgeService bridge;
  final AssistantSessionDao dao;
  final AssistantInboxDao inboxDao;
  final AiPromptService aiPromptService;
  final UsageService usageService;
  final AiClientFactory clientFactory;
  final AiSettings Function() readAiSettings;
  final Future<List<Map<String, dynamic>>> Function() listNovels;
  final AssistantStartJobCallback startJob;
  final AssistantJobStatusCallback jobStatus;
  final AssistantSendToJobCallback sendToJob;
  final AssistantCreateNovelCallback createNovel;
  final AssistantEditNovelCallback editNovel;
  final AssistantListChaptersCallback listChapters;

  final void Function()? onUsageChanged;

  bool _started = false;

  /// 启动协调器：注册 inbound handler。
  ///
  /// 重复调用是 no-op。bridge 自己的 start/stop 控制是否消费消息。
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    bridge.onInboundMessage = _handleInbound;
    _log.info('coordinator started — inbound handler registered');
  }

  /// 本机伪入站：把回流批注当作当前 chat 的一条用户消息跑一轮 Assistant。

  /// 停止协调器：解绑 inbound handler。
  ///
  /// 不停止 bridge 自身（bridge.stop 由 UI/生命周期控制）。
  void stop() {
    if (!_started) {
      return;
    }
    _started = false;
    bridge.onInboundMessage = null;
    _log.info('coordinator stopped — inbound handler unregistered');
  }

  Future<void> _handleInbound(InboundMessage message) async {
    final chatId = message.address.chatId;
    final channelType = message.address.channelType;
    final userText = message.text.trim();
    final displayName = message.address.displayName;

    if (userText.isEmpty) {
      if (_log.isDebugEnabled) {
        _log.debug('empty inbound text — ignoring chatId=$chatId');
      }
      return;
    }

    await bridge.notifyProcessingStart(chatId);
    try {
      await _processTurn(
        chatId: chatId,
        channelType: channelType,
        userText: userText,
        displayName: displayName,
      );
    } catch (error, stack) {
      _log.error(
        'turn orchestration failed chatId=$chatId: $error',
        error: error,
        stackTrace: stack,
      );
      await _sendSafe(chatId, '抱歉，处理消息时遇到问题，请稍后重试。');
    } finally {
      await bridge.notifyProcessingEnd(chatId);
    }
  }

  Future<void> _processTurn({
    required String chatId,
    required String channelType,
    required String userText,
    required String? displayName,
  }) async {
    // 1. get-or-create session。
    final session = await dao.getOrCreateByChat(
      channelType: channelType,
      chatId: chatId,
    );

    // 2. resolve provider+model (session 优先，回退全局默认)
    final resolved = _resolveModelSelection(session);
    if (resolved == null) {
      await _sendSafe(
        chatId,
        '尚未配置默认聊天模型。请在 Reveric 设置中先配置一个 AI 提供方并选择默认聊天模型。',
      );
      return;
    }

    // 若 session 没存过选择，写回 DB 以便下次复用
    if (session.provider != resolved.providerId ||
        session.model != resolved.model) {
      try {
        await dao.updateModelSelection(
          id: session.id,
          provider: resolved.providerId,
          model: resolved.model,
        );
      } catch (e, st) {
        _log.error(
          '[DB] updateModelSelection failed: $e',
          error: e,
          stackTrace: st,
        );
        // 不阻断 turn — 内存里已知 provider/model，可以继续
      }
    }

    // 3. build tool dispatcher — coordinator 注入 chat 上下文到业务回调
    final dispatcher = AssistantToolDispatcher(
      listNovelsCallback: listNovels,
      startJobCallback: (novelId, seed) =>
          startJob(novelId, seed, chatId: chatId, channelType: channelType),
      jobStatusCallback: (jobId) =>
          jobStatus(jobId, chatId: chatId, channelType: channelType),
      sendToJobCallback: (jobId, text) =>
          sendToJob(jobId, text, chatId: chatId, channelType: channelType),
      createNovelCallback: createNovel,
      editNovelCallback: editNovel,
      listChaptersCallback: listChapters,
    );

    // 4. build + run turn
    final runner = AssistantTurnRunner(
      clientFactory: clientFactory,
      dao: dao,
      inboxDao: inboxDao,
      sessionId: session.id,
      providerId: resolved.providerId,
      model: resolved.model,
      toolDispatcher: dispatcher,
      aiPromptService: aiPromptService,
      usageService: usageService,
      onUsageChanged: onUsageChanged,
      userName: displayName,
    );

    final outcome = await runner.run(userText);

    // 5. 回发结果
    if (outcome.finalText.trim().isNotEmpty) {
      await _sendSafe(chatId, outcome.finalText);
    } else if (!outcome.completed) {
      final err = outcome.error ?? 'unknown error';
      _log.warning('turn incomplete chatId=$chatId error=$err');
      await _sendSafe(chatId, '抱歉，本轮处理未能完成。原因：${_friendlyError(err)}');
    } else {
      // completed but empty — 不发空消息，仅记日志
      _log.info('turn completed with empty finalText chatId=$chatId');
    }
  }

  /// 解析 session 上记录的 provider/model；缺失时回退全局默认聊天模型。
  _ResolvedModel? _resolveModelSelection(AssistantSession session) {
    final settings = readAiSettings();

    // session 已有有效选择 → 校验仍然可用
    if (session.provider != null &&
        session.provider!.isNotEmpty &&
        session.model != null &&
        session.model!.isNotEmpty) {
      final config = settings.findConfigForSelection(
        providerId: session.provider!,
        model: session.model,
      );
      if (config != null) {
        return _ResolvedModel(
          providerId: session.provider!,
          model: session.model!,
        );
      }
      _log.warning(
        'session provider/model no longer valid — falling back to default '
        'session=${session.id} provider=${session.provider} model=${session.model}',
      );
    }

    // 回退：全局默认 chat 模型
    final options = settings.availableModelOptionsForKind(AiModelKind.chat);
    if (options.isEmpty) {
      _log.warning('no chat model options available in settings');
      return null;
    }
    final defaultId = settings.defaultOptionIdForKind(AiModelKind.chat);
    final preferred = defaultId != null && defaultId.isNotEmpty
        ? options.firstWhere(
            (o) => o.id == defaultId,
            orElse: () => options.first,
          )
        : options.first;
    return _ResolvedModel(
      providerId: preferred.providerId,
      model: preferred.model,
    );
  }

  Future<void> _sendSafe(String chatId, String text) async {
    final ok = await bridge.sendToUser(chatId, text);
    if (!ok) {
      _log.warning('sendToUser failed chatId=$chatId textLen=${text.length}');
    }
  }

  String _friendlyError(String err) {
    final lower = err.toLowerCase();
    if (lower.contains('401') ||
        lower.contains('unauthorized') ||
        lower.contains('api key')) {
      return 'AI 提供方认证失败';
    }
    if (lower.contains('429') || lower.contains('rate limit')) {
      return '请求过于频繁';
    }
    if (lower.contains('timeout')) {
      return '请求超时';
    }
    if (lower.contains('credit')) {
      return '额度不足';
    }
    if (lower.contains('cancel')) {
      return '已取消';
    }
    return '内部错误';
  }
}

class _ResolvedModel {
  const _ResolvedModel({required this.providerId, required this.model});

  final String providerId;
  final String model;
}
