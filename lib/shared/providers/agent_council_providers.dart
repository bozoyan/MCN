// 职责: Agent Council 状态管理 — 提供多智能体讨论的状态、配置与操作入口，支持实时消息更新、流式输出与自定义模型。
// 关联文件:
//   lib/shared/models/agent_council_models.dart
//   lib/shared/models/agent_run_state.dart
//   lib/shared/services/ai/agent_council_orchestrator.dart
//   lib/shared/services/ai/council_session_codec.dart
import 'plugin_providers.dart';
import 'mcp_providers.dart';
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/novel_content_database.dart';
import '../models/agent_council_models.dart';
import '../models/ai_run_failure.dart';
import '../agent/agent_run_state.dart';
import '../logger/app_logger.dart';
import '../models/ai_chat_models.dart';
import '../models/ai_session_mode.dart';
import '../models/subagent.dart';
import '../services/ai/agent_council_orchestrator.dart';
import '../services/ai/chat.dart';
import '../services/ai/mode_run_resources.dart';
import '../services/ai/council_session_codec.dart';
import 'usage_query_providers.dart';
import '../services/ai/session_persistence.dart';
import '../utils/random_id.dart';
import 'trace_providers.dart';
import 'package:easy_localization/easy_localization.dart';

import '../localization/locale_keys.dart';
import 'ai_mode_processing.dart';
import 'ai_mode_runtime.dart';
import 'novel_providers.dart';
import 'subagent_providers.dart';

part 'agent_council_providers.g.dart';

final _log = AppLogger.forModule('Council');

/// 把发言放进它所属的轮次；该轮还不存在时按轮次号插入新的一轮。
AgentCouncilSession _insertMessage(
  AgentCouncilSession session,
  CouncilMessage message,
) {
  final rounds = List<CouncilRound>.from(session.rounds);
  final index = rounds.indexWhere((r) => r.roundNumber == message.round);
  if (index >= 0) {
    rounds[index] = rounds[index].copyWith(
      messages: [...rounds[index].messages, message],
    );
  } else {
    final insertAt = rounds.indexWhere((r) => r.roundNumber > message.round);
    final round = CouncilRound(roundNumber: message.round, messages: [message]);
    if (insertAt < 0) {
      rounds.add(round);
    } else {
      rounds.insert(insertAt, round);
    }
  }
  return session.copyWith(rounds: rounds, updatedAt: DateTime.now());
}

@Riverpod(keepAlive: true)
class AgentCouncilActiveRun extends _$AgentCouncilActiveRun {
  @override
  AgentRunState? build(String? sessionId) => null;

  void onTextDelta(
    String participantId,
    String participantName,
    int round,
    String text,
  ) {
    final current = state;
    if (current == null || current.agentId != participantId) {
      state = AgentRunState(
        agentId: participantId,
        agentName: participantName,
        round: round,
        accumulatedText: text,
      );
    } else {
      state = current.withAppendedText(text);
    }
  }

  void onThinkingDelta(
    String participantId,
    String participantName,
    int round,
    String thinking,
  ) {
    final current = state;
    if (current == null || current.agentId != participantId) {
      state = AgentRunState(
        agentId: participantId,
        agentName: participantName,
        round: round,
      ).withAppendedThinking(thinking);
    } else {
      state = current.withAppendedThinking(thinking);
    }
  }

  void onToolCall(String participantId, AiToolCallBlock block) {
    final current =
        state ?? AgentRunState(agentId: participantId, agentName: '', round: 0);
    state = current.withToolCall(block);
  }

  void clear() {
    state = null;
  }
}

@Riverpod(keepAlive: true)
class AgentCouncilRunHistoryStore extends _$AgentCouncilRunHistoryStore {
  @override
  Map<String, AgentRunState> build(String? sessionId) => const {};

  void save(String messageId, AgentRunState runState) {
    state = {...state, messageId: runState.copyWith(isComplete: true)};
  }

  void clear() {
    state = const {};
  }

  /// 只保留仍在讨论里的消息的运行记录。
  void retain(Set<String> messageIds) {
    state = {
      for (final entry in state.entries)
        if (messageIds.contains(entry.key)) entry.key: entry.value,
    };
  }
}

@Riverpod(keepAlive: true)
class AgentCouncilRuntime extends _$AgentCouncilRuntime {
  AgentCouncilOrchestrator? orchestrator;

  @override
  AiModeRuntimeState build(String? sessionId) {
    return const AiModeRuntimeState();
  }

  AgentCouncilOrchestrator obtainOrchestrator({bool recreate = false}) {
    if (recreate) {
      orchestrator?.cancel();
      orchestrator = (AgentCouncilOrchestrator()
        ..pluginHost = ref.read(pluginHostServiceProvider));
    }
    final current = orchestrator ??= (AgentCouncilOrchestrator()
      ..pluginHost = ref.read(pluginHostServiceProvider));
    current.mcpService = ref.read(mcpSettingsServiceProvider);
    return current;
  }

  void setProcessing(bool processing, {bool notifyOnComplete = true}) {
    final sid = sessionId;
    if (sid == null || sid.isEmpty) {
      return;
    }
    ref
        .read(aiModeProcessingTrackerProvider.notifier)
        .setProcessing(
          mode: AiSessionMode.council,
          sessionId: sid,
          processing: processing,
          notifyOnComplete: notifyOnComplete,
        );
    if (state.isProcessing != processing) {
      state = state.copyWith(isProcessing: processing);
    }
  }

  void cancelOrchestrator() {
    orchestrator?.cancel();
    setProcessing(false, notifyOnComplete: false);
  }
}

@Riverpod(keepAlive: true)
class AgentCouncilSessionNotifier extends _$AgentCouncilSessionNotifier {
  String? _persistenceDatabasePath;
  AiModeRunResources? _runResources;
  Future<void> _writeChain = Future.value();

  /// 讨论中插入、编排器尚未并入的作者插话。立即对 UI 可见，
  /// 编排器快照回写时补回去，运行结束/暂停/取消时落定。
  final List<CouncilMessage> _pendingUserMessages = [];

  /// 还在排队的插话 id。插话或被并入时都会写 state，读到的值与当前 state 一致。
  Set<String> get pendingUserMessageIds => {
    for (final m in _pendingUserMessages) m.id,
  };

  AgentCouncilSession _withPendingUserMessages(AgentCouncilSession session) {
    final known = {
      for (final r in session.rounds)
        for (final m in r.messages) m.id,
    };
    var merged = session;
    for (final message in _pendingUserMessages) {
      if (known.contains(message.id)) continue;
      merged = _insertMessage(merged, message);
    }
    return merged;
  }

  /// 并入剩余插话并落库：最后一位发言后才插的话没人消费，离页后 hook 也不会补存。
  void _settlePendingUserMessages() {
    final current = state;
    if (current != null && _pendingUserMessages.isNotEmpty) {
      final merged = _withPendingUserMessages(current);
      state = merged;
      unawaited(
        _upsertCompletedMessages(
          merged,
          eventName: 'council_user_messages_settled',
        ),
      );
    }
    _pendingUserMessages.clear();
  }

  @override
  AgentCouncilSession? build(String? sessionId) {
    ref.onDispose(() {
      final resources = _runResources;
      if (resources != null) {
        resources.cancelAll();
      }
    });
    return null;
  }

  AgentCouncilRuntime get _runtime =>
      ref.read(agentCouncilRuntimeProvider(sessionId).notifier);

  AgentCouncilActiveRun get _activeRun =>
      ref.read(agentCouncilActiveRunProvider(sessionId).notifier);

  AgentCouncilRunHistoryStore get _runHistory =>
      ref.read(agentCouncilRunHistoryStoreProvider(sessionId).notifier);

  bool _isRunProcessing(String targetSessionId) =>
      ref.mounted &&
      ref.read(agentCouncilRuntimeProvider(targetSessionId)).isProcessing;

  AgentCouncilSession? _sessionFor(String targetSessionId) {
    return sessionId == targetSessionId
        ? state
        : ref.read(agentCouncilSessionProvider(targetSessionId));
  }

  void _setSessionFor(String targetSessionId, AgentCouncilSession session) {
    if (sessionId == targetSessionId) {
      state = session;
    } else {
      ref.read(agentCouncilSessionProvider(targetSessionId).notifier).state =
          session;
    }
  }

  Never _failRun(
    Object error,
    StackTrace stackTrace, {
    required String operation,
    required String targetSessionId,
  }) {
    if (!ref.mounted || (_runResources?.isClosed ?? false)) {
      throw const AiModeRunCancelled();
    }
    final failure = error is AgentCouncilRunException
        ? error
        : AgentCouncilRunException(
            const AiRunFailure.requestFailed(),
            cause: error,
          );
    _log.error(
      'council $operation failed sessionId=$targetSessionId error=$error',
      error: error,
      stackTrace: stackTrace,
    );
    final current = _sessionFor(targetSessionId);
    if (current != null) {
      _setSessionFor(
        targetSessionId,
        current.copyWith(
          phase: CouncilPhase.error,
          failure: failure.failure,
          updatedAt: DateTime.now(),
        ),
      );
    }
    Error.throwWithStackTrace(failure, stackTrace);
  }

  Future<void> _persistCurrentSession({String? databasePath}) async {
    final current = state;
    final path = databasePath ?? _persistenceDatabasePath;
    if (current == null || path == null) {
      return;
    }
    await persistToChatSession(
      persistence: ref.read(
        aiSessionPersistenceServiceProvider(
          novelId: current.novelId,
          databasePath: path,
        ),
      ),
      novelDatabase: ref.read(novelContentDatabaseProvider(path)),
      databasePath: path,
    );
  }

  Future<T> _withRunResources<T>({
    required String targetSessionId,
    required AiModeRunSelection selection,
    required AiSessionContext context,
    required Future<T> Function(AiModeRunResources resources) run,
  }) async {
    if (_runResources != null ||
        ref.read(agentCouncilRuntimeProvider(targetSessionId)).isProcessing) {
      throw StateError('Council session already has an active operation.');
    }
    final runtime = ref.read(
      agentCouncilRuntimeProvider(targetSessionId).notifier,
    );
    final resources = AiModeRunResources(
      factory: ref.read(aiModeClientFactoryProvider),
      selection: selection,
      context: context,
      sessionId: targetSessionId,
      mode: AiSessionMode.council,
    );
    _runResources = resources;
    _persistenceDatabasePath = context.databasePath;
    runtime.setProcessing(true);
    var completed = false;
    try {
      final result = await run(resources);
      completed = true;
      return result;
    } catch (error) {
      if (!ref.mounted || resources.isClosed) {
        throw const AiModeRunCancelled();
      }
      rethrow;
    } finally {
      try {
        if (ref.mounted) {
          await _writeChain;
          if (ref.mounted) {
            final current = _sessionFor(targetSessionId);
            if (current != null) {
              final target = targetSessionId == sessionId
                  ? this
                  : ref.read(
                      agentCouncilSessionProvider(targetSessionId).notifier,
                    );
              await target._persistCurrentSession(
                databasePath: _persistenceDatabasePath,
              );
            }
          }
        }
      } finally {
        await resources.close();
        runtime.orchestrator?.titleClientRunner = null;
        _runResources = null;
        if (ref.mounted) {
          _settlePendingUserMessages();
          runtime.setProcessing(false, notifyOnComplete: completed);
          await _writeChain;
        }
      }
    }
  }

  Future<({String sessionId, CouncilPhase phase})> startCouncil({
    required String novelId,
    required String topic,
    required List<CouncilParticipant> participants,
    required AiModeRunSelection selection,
    required AiSessionContext context,
    String? preferredSessionId,
    AgentCouncilConfig config = const AgentCouncilConfig(),
  }) {
    final id = preferredSessionId ?? sessionId ?? buildRandomId('council');
    return _withRunResources(
      targetSessionId: id,
      selection: selection,
      context: context,
      run: (resources) async => _startCouncil(
        novelId: novelId,
        topic: topic,
        participants: participants,
        aiService: await resources.mainClient(),
        context: context,
        preferredSessionId: id,
        config: config,
        aiServiceResolver: resources.memberClient,
        t: tr,
      ),
    );
  }

  Future<({String sessionId, CouncilPhase phase})?> runAdditionalRound({
    required AiModeRunSelection selection,
    required AiSessionContext context,
    AgentCouncilConfig config = const AgentCouncilConfig(),
    String? speakerId,
    String? rewindFromMessageId,
  }) async {
    final current = state;
    if (current == null || current.isActive) {
      return null;
    }
    return _withRunResources(
      targetSessionId: current.id,
      selection: selection,
      context: context,
      run: (resources) async {
        final client = await resources.mainClient();
        if (rewindFromMessageId != null) {
          _rewindMessages(rewindFromMessageId, inclusive: true);
          await _persistCurrentSession();
        }
        return _runAdditionalRound(
          aiService: client,
          context: context,
          config: config,
          aiServiceResolver: resources.memberClient,
          t: tr,
          speakerId: speakerId,
        );
      },
    );
  }

  Future<({String sessionId, CouncilPhase phase})?> generateSummary({
    required AiModeRunSelection selection,
    required AiSessionContext context,
  }) async {
    final current = state;
    if (current == null || current.isActive) {
      return null;
    }
    return _withRunResources(
      targetSessionId: current.id,
      selection: selection,
      context: context,
      run: (resources) async =>
          _generateSummary(aiService: await resources.mainClient(), t: tr),
    );
  }

  Future<({String sessionId, CouncilPhase phase})> _startCouncil({
    required String novelId,
    required String topic,
    required List<CouncilParticipant> participants,
    required AiClient aiService,
    required AiSessionContext context,
    String? preferredSessionId,
    AgentCouncilConfig config = const AgentCouncilConfig(),
    CouncilAiServiceResolver? aiServiceResolver,
    String Function(String)? t,
  }) async {
    final targetSessionId =
        preferredSessionId ?? sessionId ?? buildRandomId('council');
    _persistenceDatabasePath = context.databasePath;
    final now = DateTime.now();
    _setSessionFor(
      targetSessionId,
      AgentCouncilSession(
        id: targetSessionId,
        novelId: novelId,
        topic: topic,
        participants: participants,
        phase: CouncilPhase.discussing,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final service =
        ref
            .read(agentCouncilRuntimeProvider(targetSessionId).notifier)
            .obtainOrchestrator(recreate: true)
          ..titleClientRunner = _runResources!.withDetachedClient;
    ref
        .read(agentCouncilRuntimeProvider(targetSessionId).notifier)
        .setProcessing(true);
    final participantMap = {
      for (final p in participants) p.id: p.resolveName(t ?? _identity),
    };
    final activeRun = ref.read(
      agentCouncilActiveRunProvider(targetSessionId).notifier,
    );

    try {
      final result = await service.startDiscussion(
        novelId: novelId,
        topic: topic,
        participants: participants,
        aiService: aiService,
        context: context,
        sessionId: targetSessionId,
        config: config,
        onMessageGenerated: _onMessageGenerated,
        onPhaseChanged: _onPhaseChanged,
        onTitleGenerated: (title) => _onTitleGenerated(targetSessionId, title),
        aiServiceResolver: aiServiceResolver,
        t: t,
        onTextDelta: (participantId, round, text) {
          activeRun.onTextDelta(
            participantId,
            participantMap[participantId] ?? participantId,
            round,
            text,
          );
        },
        onThinkingDelta: (participantId, round, thinking) {
          activeRun.onThinkingDelta(
            participantId,
            participantMap[participantId] ?? participantId,
            round,
            thinking,
          );
        },
        onToolCall: (participantId, round, record) {
          activeRun.onToolCall(participantId, record);
        },
        traceReporter: ref.read(traceReporterServiceProvider),
        usageService: ref.read(usageServiceProvider),
      );
      // 标题完成回调会独立合并并落库；返回后再确保一次，用于覆盖取消等
      // 不再发 phase 回调的路径，正常完成时是幂等写入。
      // 只写 sessions 行，不回写 state —— 取消时 result.phase 仍是 discussing，
      // 回写会让 UI 退回「讨论中」。
      unawaited(_ensurePersistedSession(result));
    } catch (error, stackTrace) {
      _failRun(
        error,
        stackTrace,
        operation: 'start',
        targetSessionId: targetSessionId,
      );
    } finally {
      if (ref.mounted) {
        activeRun.clear();
      }
      // 保留各参与者的 Agent，让「追加一轮」带着本场已读到的上下文继续。
      service.finishRun();
      if (ref.mounted) {
        _settlePendingUserMessages();
      }
    }
    return (
      sessionId: targetSessionId,
      phase: _sessionFor(targetSessionId)?.phase ?? CouncilPhase.error,
    );
  }

  /// 追加一轮；传 [speakerId] 时只让该成员发言一次，算作最后一轮的追加。
  Future<({String sessionId, CouncilPhase phase})?> _runAdditionalRound({
    required AiClient aiService,
    required AiSessionContext context,
    AgentCouncilConfig config = const AgentCouncilConfig(),
    CouncilAiServiceResolver? aiServiceResolver,
    String Function(String)? t,
    String? speakerId,
  }) async {
    final current = state;
    if (current == null || current.isActive) return null;
    final databasePath = context.databasePath;
    if (databasePath != null && databasePath.isNotEmpty) {
      _persistenceDatabasePath = databasePath;
    }

    final service = _runtime.obtainOrchestrator();
    _runtime.setProcessing(true);
    final translate = t ?? _identity;
    final participantMap = {
      for (final p in current.participants) p.id: p.resolveName(translate),
    };

    try {
      final updated = await service.runRound(
        session: current,
        aiService: aiService,
        context: context,
        config: config,
        speakerId: speakerId,
        onMessageGenerated: _onMessageGenerated,
        onPhaseChanged: _onPhaseChanged,
        aiServiceResolver: aiServiceResolver,
        t: t,
        onTextDelta: (participantId, round, text) {
          _activeRun.onTextDelta(
            participantId,
            participantMap[participantId] ?? participantId,
            round,
            text,
          );
        },
        onThinkingDelta: (participantId, round, thinking) {
          _activeRun.onThinkingDelta(
            participantId,
            participantMap[participantId] ?? participantId,
            round,
            thinking,
          );
        },
        onToolCall: (participantId, round, record) {
          _activeRun.onToolCall(participantId, record);
        },
        traceReporter: ref.read(traceReporterServiceProvider),
        usageService: ref.read(usageServiceProvider),
      );

      if (_isRunProcessing(current.id)) {
        state = _withPendingUserMessages(updated);
      }
    } catch (error, stackTrace) {
      _failRun(
        error,
        stackTrace,
        operation: 'additional_round',
        targetSessionId: current.id,
      );
    } finally {
      if (ref.mounted) {
        _activeRun.clear();
      }
      // 同上：追加轮之间保留 Agent 上下文，避免每轮重新调工具取背景。
      service.finishRun();
      if (ref.mounted) {
        _settlePendingUserMessages();
      }
    }
    return (
      sessionId: current.id,
      phase: _sessionFor(current.id)?.phase ?? current.phase,
    );
  }

  Future<({String sessionId, CouncilPhase phase})?> _generateSummary({
    required AiClient aiService,
    String Function(String)? t,
  }) async {
    final current = state;
    if (current == null || current.isActive) return null;

    final service = _runtime.obtainOrchestrator();
    _runtime.setProcessing(true);
    final summarizingSession = current.copyWith(
      phase: CouncilPhase.summarizing,
      clearFailure: true,
    );
    state = summarizingSession;
    try {
      final summary = await service.generateSummary(
        session: summarizingSession,
        aiService: aiService,
        t: t,
        traceReporter: ref.read(traceReporterServiceProvider),
        usageService: ref.read(usageServiceProvider),
      );

      if (_isRunProcessing(current.id)) {
        // 总结期间的插话不在 summarizingSession 里，要补回来，否则直接被覆盖掉。
        state = _withPendingUserMessages(
          summarizingSession.copyWith(
            summary: summary,
            phase: CouncilPhase.completed,
            updatedAt: DateTime.now(),
          ),
        );
      }
    } catch (error, stackTrace) {
      _failRun(
        error,
        stackTrace,
        operation: 'summary',
        targetSessionId: current.id,
      );
    } finally {
      if (ref.mounted) {
        _settlePendingUserMessages();
      }
    }
    return (
      sessionId: current.id,
      phase: _sessionFor(current.id)?.phase ?? current.phase,
    );
  }

  void _onMessageGenerated(
    AgentCouncilSession snapshot,
    CouncilMessage message,
  ) {
    if (!ref.mounted) {
      return;
    }
    if (!_isRunProcessing(snapshot.id)) {
      return;
    }
    // 编排器并入的插话已随本条快照落库，不再算待定。
    _pendingUserMessages.removeWhere((m) => m.id == message.id);
    final session = _withPendingUserMessages(snapshot);
    final activeRun = ref.read(agentCouncilActiveRunProvider(session.id));
    if (activeRun != null && activeRun.agentId == message.participantId) {
      ref
          .read(agentCouncilRunHistoryStoreProvider(session.id).notifier)
          .save(
            message.id,
            activeRun.copyWith(
              accumulatedText: message.content,
              round: message.round,
              isComplete: true,
            ),
          );
      // 该 agent 已发言完毕并落为正式消息气泡，清空流式态，避免气泡与流式卡片重复。
      ref.read(agentCouncilActiveRunProvider(session.id).notifier).clear();
    }
    if (sessionId == session.id) {
      state = session;
    } else {
      ref.read(agentCouncilSessionProvider(session.id).notifier).state =
          session;
    }
    unawaited(
      _upsertCompletedMessages(session, eventName: 'council_message_generated'),
    );
  }

  void _onPhaseChanged(AgentCouncilSession snapshot) {
    if (!ref.mounted) {
      return;
    }
    if (!_isRunProcessing(snapshot.id)) {
      return;
    }
    final session = _withPendingUserMessages(snapshot);
    if (sessionId == session.id) {
      state = session;
    } else {
      ref.read(agentCouncilSessionProvider(session.id).notifier).state =
          session;
    }
    unawaited(_ensurePersistedSession(session));
    if (session.phase == CouncilPhase.completed && session.rounds.isNotEmpty) {
      unawaited(
        _upsertCompletedMessages(session, eventName: 'council_phase_completed'),
      );
    }
  }

  void _onTitleGenerated(String targetSessionId, String title) {
    if (!ref.mounted) {
      return;
    }
    final targetProvider = agentCouncilSessionProvider(targetSessionId);
    final current = sessionId == targetSessionId
        ? state
        : ref.read(targetProvider);
    if (current == null || title.isEmpty || current.title == title) {
      return;
    }
    final updated = current.copyWith(title: title, updatedAt: DateTime.now());
    if (sessionId == targetSessionId) {
      state = updated;
    } else {
      ref.read(targetProvider.notifier).state = updated;
    }
    unawaited(_ensurePersistedSession(updated));
  }

  Future<void> _ensurePersistedSession(AgentCouncilSession session) async {
    final databasePath = _persistenceDatabasePath;
    if (databasePath == null || databasePath.isEmpty) {
      return;
    }
    final persistence = ref.read(
      aiSessionPersistenceServiceProvider(
        novelId: session.novelId,
        databasePath: databasePath,
      ),
    );
    final participantNames = session.participants.map((p) => p.name).join('、');
    await persistence.createActiveSession(
      id: session.id,
      title: session.title.isNotEmpty
          ? session.title
          : tr(
              LocaleKeys.councilSessionTitleFmt,
              namedArgs: {
                'participants': participantNames,
                'topic': session.topic,
              },
            ),
      mode: AiSessionMode.council.value,
      metadata: councilRowMetadata(session),
      createdAt: session.createdAt,
    );
  }

  static String _identity(String key) => key;

  Future<void> _upsertCompletedMessages(
    AgentCouncilSession session, {
    required String eventName,
  }) {
    final next = _writeChain.then(
      (_) => _writeCompletedMessages(session, eventName: eventName),
    );
    _writeChain = next;
    return next;
  }

  Future<void> _writeCompletedMessages(
    AgentCouncilSession session, {
    required String eventName,
  }) async {
    final databasePath = _persistenceDatabasePath;
    if (databasePath == null || databasePath.isEmpty) {
      return;
    }
    if (session.rounds.isEmpty) {
      return;
    }

    try {
      await _ensurePersistedSession(session);
      final persistence = ref.read(
        aiSessionPersistenceServiceProvider(
          novelId: session.novelId,
          databasePath: databasePath,
        ),
      );
      final novelDatabase = ref.read(
        novelContentDatabaseProvider(databasePath),
      );
      await persistence.upsertCompletedMessages(
        sessionId: session.id,
        messages: _buildCouncilAiMessages(session),
        novelDatabase: novelDatabase,
      );
      _log.info(
        'persisted council completed messages from $eventName '
        'sessionId=${session.id}',
      );
    } catch (error, stackTrace) {
      _log.error(
        'persist council completed messages failed '
        'event=$eventName sessionId=${session.id} error=$error',
        stackTrace: stackTrace,
      );
    }
  }

  List<AiMessage> _buildCouncilAiMessages(AgentCouncilSession current) =>
      encodeCouncilMessages(
        current,
        ref.read(agentCouncilRunHistoryStoreProvider(current.id)),
      );

  Future<void> persistToChatSession({
    required AiSessionPersistenceService persistence,
    required NovelContentDatabase novelDatabase,
    String? databasePath,
  }) async {
    final current = state;
    if (current == null) {
      return;
    }

    if (databasePath != null && databasePath.isNotEmpty) {
      _persistenceDatabasePath = databasePath;
    }
    await _ensurePersistedSession(current);
    // 发言被删空也要落库，否则持久化里留着已删除的旧发言。
    await persistence.saveMessages(
      sessionId: current.id,
      messages: _buildCouncilAiMessages(current),
      novelDatabase: novelDatabase,
    );
  }

  void setSession(AgentCouncilSession session) {
    _runHistory.clear();
    state = session;
  }

  /// 仅在该 family 尚无内存会话时恢复持久化快照。
  ///
  /// Council 允许离页后继续运行，持久化读取可能晚于后台回调返回；此入口把
  /// session 与 run history 的恢复检查收敛到 notifier 边界，避免旧快照覆盖
  /// keepAlive 的运行态。需要主动替换已有会话的内部流程仍使用 [setSession]。
  bool restorePersistedSessionIfAbsent({
    required AgentCouncilSession session,
    required Map<String, AgentRunState> runHistory,
  }) {
    if (sessionId != session.id) {
      throw ArgumentError.value(
        session.id,
        'session',
        'Session id must match the provider family argument $sessionId',
      );
    }
    if (state != null) {
      return false;
    }
    setSession(session);
    restoreRunHistory(runHistory);
    return true;
  }

  void restoreRunHistory(Map<String, AgentRunState> entries) {
    _runHistory.clear();
    for (final entry in entries.entries) {
      _runHistory.save(entry.key, entry.value);
    }
  }

  /// 作者插话。讨论进行中排队到下一位成员发言前；空闲时上一轮已结束则开启新一轮，
  /// 让下一轮的成员在本轮上下文里看到它。
  void addUserMessage(String content, {String? databasePath}) {
    final current = state;
    final text = content.trim();
    if (current == null || text.isEmpty) return;
    if (databasePath != null && databasePath.isNotEmpty) {
      _persistenceDatabasePath = databasePath;
    }
    final running = _isRunProcessing(current.id);
    final lastRound = current.rounds.lastOrNull;
    final roundNumber = running
        ? ref.read(agentCouncilActiveRunProvider(sessionId))?.round ??
              current.nextDiscussionRoundNumber
        : lastRound == null
        ? 1
        : lastRound.isComplete
        ? lastRound.roundNumber + 1
        : lastRound.roundNumber;
    final message = CouncilMessage(
      id: buildRandomId('msg'),
      participantId: councilUserParticipantId,
      participantName: tr(LocaleKeys.councilUserSpeakerLabel),
      content: text,
      timestamp: DateTime.now(),
      round: roundNumber,
    );
    if (running) {
      _pendingUserMessages.add(message);
      _runtime.orchestrator?.queueUserMessage(message);
      state = _withPendingUserMessages(current);
      return;
    }
    state = _insertMessage(current, message);
    unawaited(
      _upsertCompletedMessages(state!, eventName: 'council_user_message_added'),
    );
  }

  /// 删除一条发言（用于撤回作者插话）。讨论进行中不可改写历史。
  void removeMessage(String messageId) {
    _editMessages(
      (messages) => [
        for (final m in messages)
          if (m.id != messageId) m,
      ],
    );
  }

  /// 回退到 [messageId]：删除其后所有发言；[inclusive] 时连同该条一起删除。
  void rewindTo(String messageId, {required bool inclusive}) {
    final current = state;
    if (current == null || _isRunProcessing(current.id)) {
      return;
    }
    _rewindMessages(messageId, inclusive: inclusive);
  }

  void _rewindMessages(String messageId, {required bool inclusive}) {
    _applyMessageEdit((messages) {
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index < 0) return messages;
      return messages.sublist(0, inclusive ? index : index + 1);
    });
  }

  void _editMessages(
    List<CouncilMessage> Function(List<CouncilMessage> messages) edit,
  ) {
    final current = state;
    if (current == null || _isRunProcessing(current.id)) return;
    _applyMessageEdit(edit);
  }

  void _applyMessageEdit(
    List<CouncilMessage> Function(List<CouncilMessage>) edit,
  ) {
    final current = state;
    if (current == null) {
      return;
    }
    final before = [for (final r in current.rounds) ...r.messages];
    final after = edit(before);
    if (after.length == before.length) return;
    final kept = {for (final m in after) m.id};
    final rounds = [
      for (final r in current.rounds)
        if (r.messages.any((m) => kept.contains(m.id)))
          r.copyWith(
            messages: [
              for (final m in r.messages)
                if (kept.contains(m.id)) m,
            ],
          ),
    ];
    // 被改动的最早一轮已经不再是总结看到的样子。
    final firstChanged = before.firstWhere((m) => !kept.contains(m.id)).round;
    final summary = current.summary;
    _runHistory.retain(kept);
    _runtime.orchestrator?.forgetTranscripts();
    state = current.copyWith(
      rounds: rounds,
      clearSummary:
          summary != null && firstChanged <= summary.coveredThroughRound,
      phase: CouncilPhase.completed,
      clearFailure: true,
      updatedAt: DateTime.now(),
    );
  }

  void clear() {
    _runtime.cancelOrchestrator();
    _runHistory.clear();
    _activeRun.clear();
    state = null;
  }

  void pause() {
    _runResources?.cancelMain();
    _runtime.cancelOrchestrator();
    _activeRun.clear();
    _settlePendingUserMessages();
    final current = state;
    if (current != null) {
      state = current.copyWith(
        phase: CouncilPhase.completed,
        clearFailure: true,
        updatedAt: DateTime.now(),
      );
    }
  }

  void cancel() {
    _runResources?.cancelMain();
    _runtime.cancelOrchestrator();
    _activeRun.clear();
    _settlePendingUserMessages();
    final current = state;
    if (current != null) {
      state = current.copyWith(
        phase: CouncilPhase.cancelled,
        clearFailure: true,
        updatedAt: DateTime.now(),
      );
    }
  }
}

@riverpod
class AgentCouncilConfigNotifier extends _$AgentCouncilConfigNotifier {
  @override
  AgentCouncilConfig build() {
    return const AgentCouncilConfig();
  }

  void updateConfig(AgentCouncilConfig config) {
    state = config;
  }

  void updateMaxRounds(int maxRounds) {
    state = AgentCouncilConfig(
      maxRounds: maxRounds,
      autoSummarize: state.autoSummarize,
    );
  }
}

const _councilParticipantMeta = {
  'plot_architect': ('🏗️', '#E67E22', CouncilParticipantRole.plot_architect),
  'character_analyst': (
    '🎭',
    '#9B59B6',
    CouncilParticipantRole.character_analyst,
  ),
  'world_builder': ('🌍', '#3498DB', CouncilParticipantRole.world_builder),
  'pacing_expert': ('⏱️', '#1ABC9C', CouncilParticipantRole.pacing_expert),
  'conflict_designer': (
    '⚔️',
    '#E74C3C',
    CouncilParticipantRole.conflict_designer,
  ),
  'theme_guardian': ('🔮', '#F1C40F', CouncilParticipantRole.theme_guardian),
};

CouncilParticipant _subAgentToCouncilParticipant(SubAgent agent) {
  final meta = _councilParticipantMeta[agent.slug];
  final providerId = agent.providerId;
  final model = agent.model;
  return CouncilParticipant(
    id: agent.slug,
    name: agent.name,
    description: agent.description,
    prompt: agent.prompt,
    role: meta?.$3 ?? CouncilParticipantRole.custom,
    avatarEmoji: meta?.$1 ?? agent.avatarEmoji,
    avatarPath: agent.avatarPath,
    colorHex: meta?.$2,
    // 与专家设置页共用同一份模型配置，id 形如 AiModelOption.id。
    modelOptionId:
        providerId != null &&
            providerId.isNotEmpty &&
            model != null &&
            model.isNotEmpty
        ? '$providerId::$model'
        : null,
  );
}

/// 议会成员即 mode=council 的全局 SubAgent；编辑直接写回 SubAgent，
/// 与专家团队页、智能体模型设置页看到的是同一份数据。
@riverpod
class AgentCouncilParticipantsNotifier
    extends _$AgentCouncilParticipantsNotifier {
  @override
  Future<List<CouncilParticipant>> build() async {
    final agents = await ref.watch(globalSubAgentsProvider.future);
    return [
      for (final agent in agents)
        if (agent.mode == AiSessionMode.council.value)
          _subAgentToCouncilParticipant(agent),
    ];
  }

  /// 保存成员的名字、提示词与专属模型；[modelOptionId] 为 null 表示跟随会话模型。
  Future<void> updateParticipant(CouncilParticipant participant) async {
    final agents = await ref.read(globalSubAgentsProvider.future);
    final agent = agents.where((a) => a.slug == participant.id).firstOrNull;
    if (agent == null) return;
    final promptChanged = participant.prompt != agent.prompt;
    final optionId = participant.modelOptionId;
    final separator = optionId?.indexOf('::') ?? -1;
    await ref
        .read(globalSubAgentsProvider.notifier)
        .updateSubAgent(
          agent.copyWith(
            name: participant.name,
            prompt: participant.prompt,
            useCustomPrompt: agent.useCustomPrompt || promptChanged,
            providerId: separator > 0
                ? optionId!.substring(0, separator)
                : null,
            model: separator > 0 ? optionId!.substring(separator + 2) : null,
          ),
        );
  }
}
