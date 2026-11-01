// 职责: Roleplay 模式状态管理 — session 级 runtime 与状态，支持后台处理与会话切换不取消。
// 关联文件:
//   lib/shared/models/roleplay_models.dart
//   lib/shared/services/ai/roleplay_orchestrator.dart
//   lib/shared/providers/ai_mode_processing.dart
//   lib/shared/services/ai/roleplay_session_codec.dart
import 'plugin_providers.dart';
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/novel_content_database.dart';
import '../agent/agent_run_state.dart';
import '../models/agent_profile.dart';
import '../models/ai_chat_models.dart';
import '../models/ai_run_failure.dart';
import '../logger/app_logger.dart';
import '../models/ai_session_mode.dart';
import '../models/roleplay_models.dart';
import '../services/ai/chat.dart';
import '../services/ai/mode_run_resources.dart';
import '../services/ai/roleplay_orchestrator.dart';
import '../services/ai/roleplay_session_codec.dart';
import 'usage_query_providers.dart';
import '../services/ai/session_persistence.dart';
import '../utils/random_id.dart';
import 'trace_providers.dart';
import 'agent_profile_providers.dart';
import 'package:easy_localization/easy_localization.dart';

import '../localization/locale_keys.dart';
import 'ai_mode_processing.dart';
import 'ai_mode_runtime.dart';
import 'novel_providers.dart';

part 'roleplay_providers.g.dart';

final _log = AppLogger.forModule('Roleplay');

@Riverpod(keepAlive: true)
class RoleplayActiveRun extends _$RoleplayActiveRun {
  @override
  AgentRunState? build(String? sessionId) => null;

  void onTextDelta(String characterId, String characterName, String text) {
    final current = state;
    if (current == null || current.agentId != characterId) {
      state = AgentRunState(
        agentId: characterId,
        agentName: characterName,
        round: 0,
        accumulatedText: text,
      );
    } else {
      state = current.withAppendedText(text);
    }
  }

  void onThinkingDelta(
    String characterId,
    String characterName,
    String thinking,
  ) {
    final current = state;
    if (current == null || current.agentId != characterId) {
      state = AgentRunState(
        agentId: characterId,
        agentName: characterName,
        round: 0,
      ).withAppendedThinking(thinking);
    } else {
      state = current.withAppendedThinking(thinking);
    }
  }

  void onToolCall(String characterId, AiToolCallBlock block) {
    final current =
        state ?? AgentRunState(agentId: characterId, agentName: '', round: 0);
    state = current.withToolCall(block);
  }

  void clear() {
    state = null;
  }
}

@Riverpod(keepAlive: true)
class RoleplayRunHistoryStore extends _$RoleplayRunHistoryStore {
  @override
  Map<String, AgentRunState> build(String? sessionId) => const {};

  void save(String messageId, AgentRunState runState) {
    state = {...state, messageId: runState.copyWith(isComplete: true)};
  }

  void clear() {
    state = const {};
  }
}

@Riverpod(keepAlive: true)
class RoleplayRuntime extends _$RoleplayRuntime {
  RoleplayOrchestrator? orchestrator;

  @override
  AiModeRuntimeState build(String? sessionId) {
    return const AiModeRuntimeState();
  }

  RoleplayOrchestrator obtainOrchestrator() {
    return orchestrator ??= (RoleplayOrchestrator()
      ..pluginHost = ref.read(pluginHostServiceProvider));
  }

  void setProcessing(bool processing, {bool notifyOnComplete = true}) {
    final sid = sessionId;
    if (sid == null || sid.isEmpty) {
      return;
    }
    ref
        .read(aiModeProcessingTrackerProvider.notifier)
        .setProcessing(
          mode: AiSessionMode.roleplay,
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
class RoleplaySessionNotifier extends _$RoleplaySessionNotifier {
  String? _persistenceDatabasePath;
  AiModeRunResources? _runResources;
  Future<void> _writeChain = Future.value();

  @override
  RoleplaySession? build(String? sessionId) {
    ref.onDispose(() {
      final resources = _runResources;
      if (resources != null) {
        resources.cancelAll();
      }
    });
    return null;
  }

  RoleplayRuntime get _runtime =>
      ref.read(roleplayRuntimeProvider(sessionId).notifier);

  RoleplayActiveRun get _activeRun =>
      ref.read(roleplayActiveRunProvider(sessionId).notifier);

  RoleplayRunHistoryStore get _runHistory =>
      ref.read(roleplayRunHistoryStoreProvider(sessionId).notifier);

  bool _isRunProcessing(String targetSessionId) =>
      ref.mounted &&
      ref.read(roleplayRuntimeProvider(targetSessionId)).isProcessing;

  RoleplaySession? _sessionFor(String targetSessionId) {
    return sessionId == targetSessionId
        ? state
        : ref.read(roleplaySessionProvider(targetSessionId));
  }

  void _setSessionFor(String targetSessionId, RoleplaySession session) {
    if (sessionId == targetSessionId) {
      state = session;
    } else {
      ref.read(roleplaySessionProvider(targetSessionId).notifier).state =
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
    final failure = error is RoleplayRunException
        ? error
        : RoleplayRunException(
            const AiRunFailure.requestFailed(),
            cause: error,
          );
    _log.error(
      'roleplay $operation failed sessionId=$targetSessionId error=$error',
      error: error,
      stackTrace: stackTrace,
    );
    final current = _sessionFor(targetSessionId);
    if (current != null) {
      _setSessionFor(
        targetSessionId,
        current.copyWith(
          phase: RoleplayPhase.error,
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
        ref.read(roleplayRuntimeProvider(targetSessionId)).isProcessing) {
      throw StateError('Roleplay session already has an active operation.');
    }
    final runtime = ref.read(roleplayRuntimeProvider(targetSessionId).notifier);
    final resources = AiModeRunResources(
      factory: ref.read(aiModeClientFactoryProvider),
      selection: selection,
      context: context,
      sessionId: targetSessionId,
      mode: AiSessionMode.roleplay,
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
                  : ref.read(roleplaySessionProvider(targetSessionId).notifier);
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
          runtime.setProcessing(false, notifyOnComplete: completed);
        }
      }
    }
  }

  Future<({String sessionId, RoleplayPhase phase})> sendMessage({
    required String novelId,
    required String userMessage,
    required RoleplayParticipant character,
    required AiModeRunSelection selection,
    required AiSessionContext context,
    String? preferredSessionId,
    RoleplayConfig config = const RoleplayConfig(),
  }) {
    final id = preferredSessionId ?? sessionId ?? buildRandomId('roleplay');
    return _withRunResources(
      targetSessionId: id,
      selection: selection,
      context: context,
      run: (resources) async => _sendMessage(
        aiService: await resources.mainClient(),
        novelId: novelId,
        userMessage: userMessage,
        character: character,
        context: context,
        preferredSessionId: id,
        config: config,
        providerId: selection.model.providerId,
        model: selection.model.model,
      ),
    );
  }

  Future<({String sessionId, RoleplayPhase phase})> _sendMessage({
    required String novelId,
    required String userMessage,
    required RoleplayParticipant character,
    required AiClient aiService,
    AiSessionContext? context,
    String? preferredSessionId,
    RoleplayConfig config = const RoleplayConfig(),
    String? providerId,
    String? model,
  }) async {
    final sourceCurrent = state;
    final targetSessionId =
        preferredSessionId ??
        sessionId ??
        sourceCurrent?.id ??
        buildRandomId('rp');
    final current = _sessionFor(targetSessionId);
    final runtime = ref.read(roleplayRuntimeProvider(targetSessionId).notifier);
    final activeRun = ref.read(
      roleplayActiveRunProvider(targetSessionId).notifier,
    );
    final service = runtime.obtainOrchestrator()
      ..titleClientRunner = _runResources!.withDetachedClient;
    runtime.setProcessing(true);
    final agentProfile = ref.read(
      agentProfileBySlugProvider(slug: builtinAgentSlugRoleplayMaster),
    );

    final session = current == null
        ? RoleplaySession(
            id: targetSessionId,
            novelId: novelId,
            character: character,
            providerId: providerId,
            model: model,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          )
        : _refreshCharacter(current, character);

    _persistenceDatabasePath = context?.databasePath;
    _setSessionFor(targetSessionId, session);

    try {
      final optimisticUserMessageId = buildRandomId('rmsg');
      final optimisticSession = session.copyWith(
        messages: [
          ...session.messages,
          RoleplayMessage(
            id: optimisticUserMessageId,
            speakerId: 'user',
            speakerName: 'user',
            content: userMessage,
            timestamp: DateTime.now(),
          ),
        ],
        phase: RoleplayPhase.generating,
        clearFailure: true,
        updatedAt: DateTime.now(),
      );
      _setSessionFor(targetSessionId, optimisticSession);

      final updated = await service.sendMessage(
        novelId: novelId,
        userMessage: userMessage,
        character: character,
        session: session,
        aiService: aiService,
        context: context,
        systemPrompt: agentProfile?.systemPrompt,
        config: config,
        onMessageGenerated: (s, m) =>
            _onMessageGenerated(targetSessionId, s, m),
        onPhaseChanged: (s) => _onPhaseChanged(targetSessionId, s),
        onTitleGenerated: (title) => _onTitleGenerated(targetSessionId, title),
        onTextDelta: (characterId, text) {
          activeRun.onTextDelta(characterId, character.name, text);
        },
        onThinkingDelta: (characterId, thinking) {
          activeRun.onThinkingDelta(characterId, character.name, thinking);
        },
        onToolCall: (characterId, record) {
          activeRun.onToolCall(characterId, record);
        },
        userMessageId: optimisticUserMessageId,
        traceReporter: ref.read(traceReporterServiceProvider),
        usageService: ref.read(usageServiceProvider),
      );

      if (_isRunProcessing(targetSessionId)) {
        _setSessionFor(targetSessionId, updated);
      }
      // 标题完成回调会独立合并并落库；返回后再确保一次，用于覆盖取消等
      // 不再发 phase 回调的路径，正常完成时是幂等写入。
      unawaited(_ensurePersistedSession(updated));
    } catch (error, stackTrace) {
      _failRun(
        error,
        stackTrace,
        operation: 'send_message',
        targetSessionId: targetSessionId,
      );
    } finally {
      if (ref.mounted) {
        activeRun.clear();
      }
      service.cancel();
    }
    return (
      sessionId: targetSessionId,
      phase: _sessionFor(targetSessionId)?.phase ?? RoleplayPhase.error,
    );
  }

  void _onMessageGenerated(
    String targetSessionId,
    RoleplaySession session,
    RoleplayMessage message,
  ) {
    if (!ref.mounted) {
      return;
    }
    if (!_isRunProcessing(targetSessionId)) {
      return;
    }
    final activeRun = ref.read(roleplayActiveRunProvider(session.id));
    if (activeRun != null && activeRun.agentId == message.speakerId) {
      ref
          .read(roleplayRunHistoryStoreProvider(session.id).notifier)
          .save(
            message.id,
            activeRun.copyWith(accumulatedText: message.content),
          );
    }
    if (sessionId == session.id) {
      state = session;
    } else {
      ref.read(roleplaySessionProvider(session.id).notifier).state = session;
    }
    unawaited(
      _upsertCompletedMessages(
        session,
        eventName: 'roleplay_message_generated',
      ),
    );
  }

  void _onPhaseChanged(String targetSessionId, RoleplaySession session) {
    if (!ref.mounted) {
      return;
    }
    if (!_isRunProcessing(targetSessionId)) {
      return;
    }
    if (sessionId == session.id) {
      state = session;
    } else {
      ref.read(roleplaySessionProvider(session.id).notifier).state = session;
    }
    unawaited(_ensurePersistedSession(session));
    if (session.messages.isNotEmpty) {
      unawaited(
        _upsertCompletedMessages(session, eventName: 'roleplay_phase_changed'),
      );
    }
  }

  void _onTitleGenerated(String targetSessionId, String title) {
    if (!ref.mounted) {
      return;
    }
    final targetProvider = roleplaySessionProvider(targetSessionId);
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

  Future<void> _ensurePersistedSession(RoleplaySession session) async {
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
    await persistence.createActiveSession(
      id: session.id,
      title: session.title.isNotEmpty
          ? session.title
          : tr(
              LocaleKeys.roleplaySessionTitleFmt,
              namedArgs: {'character': session.character.name},
            ),
      provider: session.providerId,
      model: session.model,
      mode: AiSessionMode.roleplay.value,
      metadata: {
        'mode': 'roleplay',
        roleplayParticipantMetadataKey: session.character.toJson(),
      },
      createdAt: session.createdAt,
    );
  }

  void clear() {
    _runtime.cancelOrchestrator();
    _runHistory.clear();
    _activeRun.clear();
    state = null;
  }

  void cancel() {
    _runResources?.cancelMain();
    _runtime.cancelOrchestrator();
    _activeRun.clear();
    final current = state;
    if (current != null) {
      state = current.copyWith(
        phase: RoleplayPhase.cancelled,
        clearFailure: true,
        updatedAt: DateTime.now(),
      );
    }
  }

  void setSession(RoleplaySession session) {
    _runHistory.clear();
    state = session;
  }

  /// 仅在该 family 尚无内存会话时恢复持久化快照。
  ///
  /// Roleplay 允许离页后继续运行；持久化读取可能晚于后台回调返回，因此 UI
  /// hydration 必须保留 keepAlive 的 session 与 run history。
  bool restorePersistedSessionIfAbsent({
    required RoleplaySession session,
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

  RoleplaySession _refreshCharacter(
    RoleplaySession session,
    RoleplayParticipant character,
  ) {
    final sameCharacter =
        session.character.characterId == character.characterId ||
        session.character.characterId.isEmpty;
    if (!sameCharacter) {
      return session;
    }
    return session.copyWith(character: character);
  }

  Future<void> _upsertCompletedMessages(
    RoleplaySession session, {
    required String eventName,
  }) {
    final next = _writeChain.then(
      (_) => _writeCompletedMessages(session, eventName: eventName),
    );
    _writeChain = next;
    return next;
  }

  Future<void> _writeCompletedMessages(
    RoleplaySession session, {
    required String eventName,
  }) async {
    final databasePath = _persistenceDatabasePath;
    if (databasePath == null || databasePath.isEmpty) {
      return;
    }
    if (session.messages.isEmpty) {
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
        messages: _encodeMessages(session),
        novelDatabase: novelDatabase,
      );
      _log.info(
        'persisted roleplay completed messages from $eventName '
        'sessionId=${session.id}',
      );
    } catch (error, stackTrace) {
      _log.error(
        'persist roleplay completed messages failed '
        'event=$eventName sessionId=${session.id} error=$error',
        stackTrace: stackTrace,
      );
    }
  }

  List<AiMessage> _encodeMessages(RoleplaySession session) =>
      encodeRoleplayMessages(
        session,
        ref.read(roleplayRunHistoryStoreProvider(session.id)),
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

    await persistence.saveMessages(
      sessionId: current.id,
      messages: _encodeMessages(current),
      novelDatabase: novelDatabase,
    );
  }
}

@riverpod
class RoleplayConfigNotifier extends _$RoleplayConfigNotifier {
  @override
  RoleplayConfig build() {
    return const RoleplayConfig();
  }

  void updateConfig(RoleplayConfig config) {
    state = config;
  }
}
