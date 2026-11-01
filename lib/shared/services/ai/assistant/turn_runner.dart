// 职责: Assistant 独立 turn runner — 编排一轮对话，不依赖 novel content DB
// 关联文件:
//   lib/shared/services/remote/remote_bridge_service.dart
//   lib/shared/services/ai/assistant/tool_dispatcher.dart
//   lib/shared/database/daos/assistant_session_dao.dart
//   lib/shared/database/daos/assistant_inbox_dao.dart
//   lib/shared/services/ai/context_summarizer.dart
//   lib/shared/services/ai/usage_hook.dart
//   lib/shared/agent/agent.dart
//   lib/shared/services/ai/chat_session_controller.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//   .agents/rules/ai-calling.md
//   .agents/rules/service-naming.md

import 'dart:async';
import 'dart:math';

import '../../../agent/agent.dart';
import '../../../agent/agent_context_manager.dart';
import '../../../agent/agent_event.dart';
import '../../../agent/agent_hook.dart';
import '../../../agent/message.dart';
import '../../../database/app_database.dart';
import '../../../database/daos/assistant_session_dao.dart';
import '../../../database/daos/assistant_inbox_dao.dart';
import '../../../logger/app_logger.dart';
import '../../../models/ai_chat_models.dart';
import '../../../models/models_catalog.dart';
import '../../../utils/random_id.dart';
import '../agent_message_mapping.dart';
import '../chat.dart';
import '../chat_session_controller.dart'
    show
        buildCurrentDateRemind,
        currentDateRemindDateString,
        hasLatestCurrentDateReminder;
import '../context_summarizer.dart';
import '../usage_service.dart';
import '../usage_hook.dart';
import '../prompts/ai_prompt_service.dart';
import 'tool_dispatcher.dart';

final _log = AppLogger.forModule('AssistantTurnRunner');

/// 构造一个已初始化的 [AiClient]（仅含 ProviderClient + AgentConfig，无 novel content 依赖）。
typedef AiClientFactory =
    Future<AiClient> Function({
      required String providerId,
      required String model,
      required String sessionId,
    });

/// Remote Assistant 单轮 turn 的执行结果。
class AssistantTurnOutcome {
  const AssistantTurnOutcome({
    required this.sessionId,
    required this.completed,
    required this.finalText,
    this.error,
  });

  final String sessionId;
  final bool completed;
  final String finalText;
  final String? error;
}

/// 跑一轮 Remote Assistant turn：编排 ProviderClient、Agent、tool dispatcher，
/// 消费事件流并落库到 [AssistantSessionDao]。
///
/// 与 novel-scoped `ChatTurnRunner` 完全独立：
/// - 持久化：[AssistantSessionDao] (app DB) 而非 novel content DB
/// - 工具：[AssistantToolDispatcher]（list_novels/start_job/job_status/send_to_job 等）
/// - 上下文：[SmartAgentContextManager]（compactThreshold 按 model catalog 推导，
///   含 LLM summarizer，镜像 chat 路径）
/// - 系统提示：[AssistantPromptUseCase]
/// - 无 UI 状态（无 aiChatSessionProvider / aiChatRuntimeProvider）
class AssistantTurnRunner {
  AssistantTurnRunner({
    required this.clientFactory,
    required this.dao,
    required this.inboxDao,
    required this.sessionId,
    required this.providerId,
    required this.model,
    required this.toolDispatcher,
    required this.aiPromptService,
    required this.usageService,
    this.onUsageChanged,
    this.userName,
    this.maxIterations = 15,
    this.contextTokenLimit = defaultContextTokenLimit,
  });

  final AiClientFactory clientFactory;
  final AssistantSessionDao dao;
  final AssistantInboxDao inboxDao;
  final String sessionId;
  final String providerId;
  final String model;
  final AssistantToolDispatcher toolDispatcher;
  final AiPromptService aiPromptService;
  final UsageService usageService;

  final void Function()? onUsageChanged;
  final String? userName;
  final int maxIterations;
  final int contextTokenLimit;

  bool _cancelled = false;

  /// 取消当前 turn。下一次事件循环检查时中断 agent。
  void cancel() => _cancelled = true;

  /// 执行一轮 turn。
  ///
  /// 步骤：
  /// 1. 通过 [clientFactory] 构造 AiClient（ProviderClient + AgentConfig）
  /// 2. 加载历史 + 写入本轮用户消息
  /// 3. 构造 system prompt + Agent + SmartAgentContextManager
  /// 4. 消费 agent.process 事件流，累积 assistant 文本
  /// 5. 持久化 assistant 消息
  Future<AssistantTurnOutcome> run(String userInput) async {
    if (userInput.trim().isEmpty) {
      return AssistantTurnOutcome(
        sessionId: sessionId,
        completed: true,
        finalText: '',
      );
    }

    // 1. 构造 AiClient（作为 ProviderClient + AgentConfig 工厂，不依赖 novel content）
    final AiClient aiClient;
    try {
      aiClient = await clientFactory(
        providerId: providerId,
        model: model,
        sessionId: sessionId,
      );
    } catch (e, st) {
      _log.error('clientFactory failed: $e', error: e, stackTrace: st);
      return AssistantTurnOutcome(
        sessionId: sessionId,
        completed: false,
        finalText: '',
        error: 'AI client initialization failed: $e',
      );
    }

    try {
      return await _runWithClient(aiClient, userInput);
    } finally {
      aiClient.dispose();
    }
  }

  Future<AssistantTurnOutcome> _runWithClient(
    AiClient aiClient,
    String userInput,
  ) async {
    // 2. 系统 prompt（inbox 不注入 system prompt —— 作为普通 user 消息注入，见 step 4/5）
    final systemPrompt = aiPromptService.assistant.system(userName: userName);
    // 拉 inbox 中未处理的 run 事件（run_agent notify / run_observer 崩溃兜底）。
    // 仅读取，不在此删除 —— 删除与 reminder 落库在 step 4 同事务，保证 app 中途关闭时不丢不重。
    // 按本轮已读 id 删除（deleteByIds），保留 load 与 delete 窗口内并发写入的新消息。
    final inbox = await _loadInbox();
    AiMessage? inboxReminder;
    if (inbox.text.isNotEmpty) {
      inboxReminder = AiMessage.user(
        id: buildRandomId('inbox_reminder'),
        content: '<system-remind>\n${inbox.text}\n</system-remind>',
      );
    }

    // 3. 加载历史 + 构造本轮用户消息；system prompt 不再携带固定日期，
    //    发送前按需补投 current_date remind（跨天/缺失时）。
    final history = await _loadHistory();
    final userMessageId = buildRandomId('assistant_msg');
    final userMessage = AiMessage.user(id: userMessageId, content: userInput);
    final dateRemind = _buildCurrentDateRemindIfStale(history);

    // 4. 持久化 userMessage（含 inboxReminder 时与清空 inbox 同事务）。
    //    inbox 作为 `<system-remind>` user 消息持久化到 assistant_messages ——
    //    assistant_messages 代表发送给 AI provider 的消息记录，inbox 事件是发给
    //    provider 的事实，应留痕以便后续 turn 回溯（区别于 chat agent 的 system-mind：
    //    那是 ephemeral UI 态提示、不持久化；inbox 是 durable run 事件、需持久化）。
    //    current_date remind 同样随消息流持久化，作为后续轮次的去重真源。
    //    事务保证 reminder 落库 与 inbox 消费 原子 —— app 中途关闭时要么都完成、
    //    要么都回滚，避免「已清未落」丢事件 或 「已落未清」下轮重复注入。
    //    仅按本轮已读 id 删除（deleteByIds），保留 load 与 delete 窗口内并发写入的
    //    新消息，避免下轮丢失。
    final persistBase = <AiMessage>[...history, ?dateRemind, userMessage];
    if (inboxReminder != null) {
      try {
        await dao.attachedDatabase.transaction(() async {
          await dao.upsertMessages(
            sessionId: sessionId,
            messages: [...history, inboxReminder!, ?dateRemind, userMessage],
          );
          await inboxDao.deleteByIds(inbox.ids);
        });
      } catch (e, st) {
        _log.error(
          '[DB] persist+consume-inbox tx failed: $e',
          error: e,
          stackTrace: st,
        );
        // 事务已回滚：reminder 未落库、inbox 未清。降级为不含 reminder 的普通持久化，
        // 本轮在无 inbox 上下文下继续；inbox 留待下轮重新注入（不丢不重）。
        inboxReminder = null;
        await _persistMessages(persistBase);
      }
    } else {
      await _persistMessages(persistBase);
    }

    // 5. 转 AgentMessage（按最近一条 compact_summary 截断，避免把已压缩的旧历史
    //    重新喂给 agent；inboxReminder / dateRemind 置于 userInput 之前，让
    //    Assistant 处理输入时已感知 run 进展与当前日期）
    final scopedHistory = _messagesSinceLatestCompact(history);
    final initialMessages = <AgentMessage>[
      ...await _convertHistoryToAgentMessages(scopedHistory),
      if (inboxReminder != null)
        AgentMessage.user(id: inboxReminder.id, content: inboxReminder.content),
      if (dateRemind != null)
        AgentMessage.user(id: dateRemind.id, content: dateRemind.content),
    ];

    // 6. 上下文管理器（镜像 chat 路径：compactThreshold 按 model catalog 动态推导，
    //    summarizer 复用 buildDefaultContextSummarizer，compact_summary 落库 append-only
    //    并由下轮 step 5 截断回放）
    final catalogLimit = lookupCatalogLimit(model);
    final contextTokens = catalogLimit?.context ?? contextTokenLimit;
    final outputFloor = catalogLimit?.output != null
        ? min(16000, catalogLimit!.output!)
        : 16000;
    final compactThreshold = max(20000, contextTokens - outputFloor - 4000);
    _log.info(
      '[ctx] scope=assistant model=$model context=$contextTokens '
      'compactAt=$compactThreshold',
    );
    final ctxMgr = SmartAgentContextManager(
      compactThreshold: compactThreshold,
      contextTokens: contextTokens,
      outputFloor: outputFloor,
    );
    ctxMgr.summarizer = buildDefaultContextSummarizer(
      agentId: 'assistant',
      systemPrompt: systemPrompt,
      allowedTools: toolDispatcher.allToolNames(),
      client: aiClient.providerClient,
      providerId: aiClient.providerId,
      config: aiClient.agentConfig,
      toolManager: toolDispatcher,
      hooks: _buildHooks(source: 'assistant'),
    );

    // 7. hooks（用量记录）
    final hooks = _buildHooks(source: 'assistant');

    // 8. 创建 agent
    final agent = Agent.custom(
      id: 'assistant',
      systemPrompt: systemPrompt,
      client: aiClient.providerClient,
      providerId: aiClient.providerId,
      config: aiClient.agentConfig,
      toolManager: toolDispatcher,
      contextManager: ctxMgr,
      initialMessages: initialMessages,
      allowedTools: toolDispatcher.allToolNames(),
      hooks: hooks,
    );

    // 9. 跑事件循环
    final textBuffer = StringBuffer();
    var wasCancelled = false;
    String? errorMessage;
    try {
      await for (final event in agent.process(userInput)) {
        if (_cancelled) {
          wasCancelled = true;
          agent.cancel();
          break;
        }
        switch (event) {
          case AgentStart(:final task):
            _log.info('AgentStart sessionId=$sessionId task=$task');
          case AgentMessageStart(:final round):
            _log.info('AgentMessageStart sessionId=$sessionId round=$round');
          case AgentTextDelta(:final text):
            if (text.trim().isNotEmpty) {
              textBuffer.write(text);
            }
          case AgentThinkingDelta():
          case AgentThinkingComplete():
            break;
          case AgentTextComplete(:final text):
            _log.info('AgentTextComplete chars=${text.length}');
          case AgentToolCallProgress():
          case AgentToolCallDelta():
          case AgentToolCallComplete():
          case AgentToolCallIncomplete():
            break;
          case AgentToolCallStart(:final toolName, :final callId):
            _log.info('tool start tool=$toolName callId=$callId');
          case AgentToolCallResult(
            :final toolName,
            :final callId,
            :final errorMessage,
          ):
            _log.info(
              'tool result tool=$toolName callId=$callId error=$errorMessage',
            );
          case AgentToolSkipped(:final callId, :final reason):
            _log.info('tool skipped callId=$callId reason=$reason');
          case AgentRoundText(:final text):
            if (textBuffer.isEmpty && text.trim().isNotEmpty) {
              textBuffer.write(text);
            }
          case AgentSteeringApplied():
          case AgentFollowUpApplied():
          case AgentNextTurnApplied():
            break;
          case AgentMessageAdded(:final message):
            _log.info(
              'AgentMessageAdded id=${message.id} role=${message.role.name}',
            );
          case AgentMessageEnd(:final round):
            _log.info('AgentMessageEnd round=$round');
          case AgentLoopDetected(:final reason):
            _log.warning('loop detected: $reason');
          case AgentCompactionStart(:final tokensBefore):
            _log.info(
              'AgentCompactionStart sessionId=$sessionId tokensBefore=$tokensBefore',
            );
          case AgentCompactionEnd(
            :final ok,
            :final tokensBefore,
            :final tokensAfter,
            :final reason,
          ):
            _log.info(
              'AgentCompactionEnd sessionId=$sessionId ok=$ok '
              'tokensBefore=$tokensBefore tokensAfter=$tokensAfter reason=$reason',
            );
          case AgentDone(:final finalText):
            _log.info('AgentDone chars=${finalText.length}');
            if (finalText.trim().isNotEmpty && textBuffer.isEmpty) {
              textBuffer.write(finalText);
            }
          case AgentCancelled():
            _log.info('AgentCancelled sessionId=$sessionId');
            wasCancelled = true;
          case AgentError(:final failure, :final technicalMessage):
            _log.error(
              'AgentError failure=$failure technicalMessage=$technicalMessage',
            );
            errorMessage = failure.toString();
          case AgentEnd():
            _log.info('AgentEnd sessionId=$sessionId');
          case AgentRoundRetry(:final attempt, :final reason):
            _log.info(
              'AgentRoundRetry sessionId=$sessionId attempt=$attempt reason=$reason',
            );
            // 重试同一 round：清空本轮 partial 文本，避免跨 attempt 累加产生重复/乱码。
            textBuffer.clear();
        }
      }
    } catch (e, st) {
      _log.error('turn failed: $e', error: e, stackTrace: st);
      return AssistantTurnOutcome(
        sessionId: sessionId,
        completed: false,
        finalText: textBuffer.toString(),
        error: e.toString(),
      );
    }

    // 10. 持久化 assistant 消息
    final finalText = textBuffer.toString();
    if (finalText.trim().isNotEmpty) {
      final assistantMessage = AiMessage.assistant(
        id: buildRandomId('assistant_msg'),
        content: finalText,
      );
      try {
        await dao.upsertMessages(
          sessionId: sessionId,
          messages: [
            ...history,
            ?inboxReminder,
            ?dateRemind,
            userMessage,
            assistantMessage,
          ],
          contextSnapshot: ctxMgr.snapshot(),
        );
      } catch (e, st) {
        _log.error('[DB] persist failed: $e', error: e, stackTrace: st);
      }
    }

    if (errorMessage != null) {
      return AssistantTurnOutcome(
        sessionId: sessionId,
        completed: false,
        finalText: finalText,
        error: errorMessage,
      );
    }
    if (wasCancelled) {
      return AssistantTurnOutcome(
        sessionId: sessionId,
        completed: false,
        finalText: finalText,
        error: 'cancelled',
      );
    }
    return AssistantTurnOutcome(
      sessionId: sessionId,
      completed: true,
      finalText: finalText,
    );
  }

  /// current_date system-remind：assistant 的 system prompt 不再注入固定日期，
  /// 每轮发送前检查回放窗口内最后一条日期 remind 是否为今天，跨天/缺失时补投
  /// （随消息流持久化，后续轮次以持久化历史为去重真源）。
  AiMessage? _buildCurrentDateRemindIfStale(List<AiMessage> history) {
    final date = currentDateRemindDateString(DateTime.now());
    if (hasLatestCurrentDateReminder(
      _messagesSinceLatestCompact(history),
      date,
    )) {
      return null;
    }
    return AiMessage.user(
      id: buildRandomId('system_remind_current_date'),
      content: buildCurrentDateRemind(date),
      type: AiMessageType.system_remind,
    );
  }

  Future<List<AiMessage>> _loadHistory() async {
    try {
      return await dao.loadMessages(sessionId);
    } catch (e, st) {
      _log.error('load history failed: $e', error: e, stackTrace: st);
      return const [];
    }
  }

  /// 加载 inbox 中本会话的未处理 run 事件，拼成 `<system-remind>` 正文。
  ///
  /// 仅读取，不删除 —— 删除与 reminder 落库在 [run] step 4 同事务完成，保证
  /// app 中途关闭时不丢不重。返回 `text` 为空表示无 inbox 消息；非空时 `text`
  /// 为正文（不含外层 `<system-remind>` 标签，由调用方包裹），`ids` 为本轮已读
  /// 行 id（供 step 4 按id删除，保留并发写入的新消息），格式：
  /// ```
  /// 自上次 turn 以来的 run 事件（按时间顺序）：
  /// [progress] run=<sourceRef?> <content>
  /// [complete] run=<sourceRef?> <content>
  /// [error] run=<sourceRef?> <content>
  /// ```
  /// 调用方将其作为 user 消息（`<system-remind>` 包裹）持久化到 assistant_messages
  /// 并注入 agent context —— assistant_messages 代表发送给 AI provider 的消息记录，
  /// inbox 事件是发给 provider 的事实，需留痕供后续 turn 回溯。
  Future<({String text, List<String> ids})> _loadInbox() async {
    final List<AssistantInboxData> entries;
    try {
      entries = await inboxDao.loadByAssistantSession(sessionId);
    } catch (e, st) {
      _log.error('[DB] inbox load failed: $e', error: e, stackTrace: st);
      // 读失败不阻断 turn —— Assistant 在无 inbox 上下文下继续（inbox 未消费，下轮重试）。
      return (text: '', ids: const <String>[]);
    }
    if (entries.isEmpty) return (text: '', ids: const <String>[]);

    final buffer = StringBuffer()..writeln('自上次 turn 以来的 run 事件（按时间顺序）：');
    final ids = <String>[];
    for (final entry in entries) {
      ids.add(entry.id);
      final runTag = entry.sourceRef == null ? '' : ' run=${entry.sourceRef}';
      buffer.writeln('[${entry.messageType}]$runTag ${entry.content}');
    }
    _log.info('inbox loaded session=$sessionId count=${entries.length}');
    return (text: buffer.toString().trimRight(), ids: ids);
  }

  Future<void> _persistMessages(List<AiMessage> messages) async {
    try {
      await dao.upsertMessages(sessionId: sessionId, messages: messages);
    } catch (e, st) {
      _log.error('[DB] persist failed: $e', error: e, stackTrace: st);
    }
  }

  /// 构造用量 hooks，[source] 区分主对话与 summarizer 压缩调用。
  List<AgentHook> _buildHooks({required String source}) {
    return [
      UsageHook(
        service: usageService,
        providerId: () => providerId,
        model: () => model,
        sessionId: () => sessionId,
        novelId: () => null,
        source: source,
        onUsageChanged: onUsageChanged,
      ),
    ];
  }
}

Future<List<AgentMessage>> _convertHistoryToAgentMessages(
  List<AiMessage> messages,
) => restoreAgentMessages(
  messages.where((m) => !m.isStreaming && m.role != AiMessageRole.system),
);

/// 截取最近一条 compact_summary 及其之后的消息（同 chat 路径 _messagesSinceLatestCompact）。
/// compact_summary 自身保留为上下文首条，其前的旧历史已被压缩、不再回放。
List<AiMessage> _messagesSinceLatestCompact(List<AiMessage> messages) {
  final compactIndex = messages.lastIndexWhere(
    (message) => message.type == AiMessageType.compact_summary,
  );
  if (compactIndex <= 0) {
    return messages;
  }
  return messages.sublist(compactIndex);
}
