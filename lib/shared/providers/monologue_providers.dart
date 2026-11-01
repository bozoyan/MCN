// 职责: Monologue 模式状态管理 — session 级 runtime 与状态，支持后台处理与会话切换不取消。
// 关联文件:
//   lib/shared/models/monologue_models.dart
//   lib/shared/services/ai/monologue_orchestrator.dart
//   lib/shared/providers/ai_mode_processing.dart
//   lib/shared/services/ai/monologue_session_codec.dart
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
import '../models/monologue_models.dart';
import '../services/ai/chat.dart';
import '../services/ai/mode_run_resources.dart';
import '../services/ai/monologue_orchestrator.dart';
import '../services/ai/monologue_session_codec.dart';
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

part 'monologue_providers.g.dart';

final _log = AppLogger.forModule('Monologue');

@Riverpod(keepAlive: true)
class MonologueActiveRun extends _$MonologueActiveRun {
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
class MonologueRunHistoryStore extends _$MonologueRunHistoryStore {
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
class MonologueRuntime extends _$MonologueRuntime {
  MonologueOrchestrator? orchestrator;

  @override
  AiModeRuntimeState build(String? sessionId) {
    return const AiModeRuntimeState();
  }

  MonologueOrchestrator obtainOrchestrator({bool recreate = false}) {
    if (recreate) {
      orchestrator?.cancel();
      orchestrator = (MonologueOrchestrator()
        ..pluginHost = ref.read(pluginHostServiceProvider));
    }
    return orchestrator ??= (MonologueOrchestrator()
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
          mode: AiSessionMode.monologue,
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
class MonologueSessionNotifier extends _$MonologueSessionNotifier {
  String? _persistenceDatabasePath;
  AiModeRunResources? _runResources;
  Future<void> _writeChain = Future.value();

  @override
  MonologueSession? build(String? sessionId) {
    ref.onDispose(() {
      final resources = _runResources;
      if (resources != null) {
        resources.cancelAll();
      }
    });
    return null;
  }

  MonologueRuntime get _runtime =>
      ref.read(monologueRuntimeProvider(sessionId).notifier);

  MonologueActiveRun get _activeRun =>
      ref.read(monologueActiveRunProvider(sessionId).notifier);

  MonologueRunHistoryStore get _runHistory =>
      ref.read(monologueRunHistoryStoreProvider(sessionId).notifier);

  bool _isRunProcessing(String targetSessionId) =>
      ref.mounted &&
      ref.read(monologueRuntimeProvider(targetSessionId)).isProcessing;

  MonologueSession? _sessionFor(String targetSessionId) {
    return sessionId == targetSessionId
        ? state
        : ref.read(monologueSessionProvider(targetSessionId));
  }

  void _setSessionFor(String targetSessionId, MonologueSession session) {
    if (sessionId == targetSessionId) {
      state = session;
    } else {
      ref.read(monologueSessionProvider(targetSessionId).notifier).state =
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
    final failure = error is MonologueRunException
        ? error
        : MonologueRunException(
            const AiRunFailure.requestFailed(),
            cause: error,
          );
    _log.error(
      'monologue $operation failed sessionId=$targetSessionId error=$error',
      error: error,
      stackTrace: stackTrace,
    );
    final current = _sessionFor(targetSessionId);
    if (current != null) {
      _setSessionFor(
        targetSessionId,
        current.copyWith(
          phase: MonologuePhase.error,
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
        ref.read(monologueRuntimeProvider(targetSessionId)).isProcessing) {
      throw StateError('Monologue session already has an active operation.');
    }
    final runtime = ref.read(
      monologueRuntimeProvider(targetSessionId).notifier,
    );
    final resources = AiModeRunResources(
      factory: ref.read(aiModeClientFactoryProvider),
      selection: selection,
      context: context,
      sessionId: targetSessionId,
      mode: AiSessionMode.monologue,
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
                      monologueSessionProvider(targetSessionId).notifier,
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
          runtime.setProcessing(false, notifyOnComplete: completed);
        }
      }
    }
  }

  Future<({String sessionId, MonologuePhase phase})> startSession({
    required String novelId,
    required String topic,
    required MonologueParticipant character,
    required AiModeRunSelection selection,
    required AiSessionContext context,
    String? preferredSessionId,
    MonologueConfig config = const MonologueConfig(),
  }) {
    final id = preferredSessionId ?? sessionId ?? buildRandomId('monologue');
    return _withRunResources(
      targetSessionId: id,
      selection: selection,
      context: context,
      run: (resources) async => _startSession(
        aiService: await resources.mainClient(),
        novelId: novelId,
        topic: topic,
        character: character,
        context: context,
        preferredSessionId: id,
        config: config,
        providerId: selection.model.providerId,
        model: selection.model.model,
      ),
    );
  }

  Future<({String sessionId, MonologuePhase phase})?> continueMonologue({
    required AiModeRunSelection selection,
    required AiSessionContext context,
    MonologueConfig config = const MonologueConfig(),
  }) {
    final current = state;
    if (current == null || current.isActive) {
      return Future.value(null);
    }
    final id = current.id;
    return _withRunResources(
      targetSessionId: id,
      selection: selection,
      context: context,
      run: (resources) async => _continueMonologue(
        aiService: await resources.mainClient(),
        context: context,
        config: config,
        providerId: selection.model.providerId,
        model: selection.model.model,
      ),
    );
  }

  Future<({String sessionId, MonologuePhase phase})> _startSession({
    required String novelId,
    required String topic,
    required MonologueParticipant character,
    required AiClient aiService,
    AiSessionContext? context,
    String? preferredSessionId,
    MonologueConfig config = const MonologueConfig(),
    MonologueAiServiceResolver? aiServiceResolver,
    String? providerId,
    String? model,
  }) async {
    final targetSessionId =
        preferredSessionId ?? sessionId ?? buildRandomId('mono_session');
    _persistenceDatabasePath = context?.databasePath;
    final now = DateTime.now();
    _setSessionFor(
      targetSessionId,
      MonologueSession(
        id: targetSessionId,
        novelId: novelId,
        topic: topic,
        character: character,
        providerId: providerId,
        model: model,
        phase: MonologuePhase.generating,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final service =
        ref
            .read(monologueRuntimeProvider(targetSessionId).notifier)
            .obtainOrchestrator(recreate: true)
          ..titleClientRunner = _runResources!.withDetachedClient;
    ref
        .read(monologueRuntimeProvider(targetSessionId).notifier)
        .setProcessing(true);
    final agentProfile = ref.read(
      agentProfileBySlugProvider(slug: builtinAgentSlugMonologueNarrator),
    );
    final activeRun = ref.read(
      monologueActiveRunProvider(targetSessionId).notifier,
    );

    try {
      final result = await service.startSession(
        novelId: novelId,
        topic: topic,
        character: character,
        aiService: aiService,
        context: context,
        sessionId: targetSessionId,
        systemPrompt: agentProfile?.systemPrompt,
        config: config,
        onMonologueGenerated: _onMonologueGenerated,
        onPhaseChanged: _onPhaseChanged,
        onTitleGenerated: (title) => _onTitleGenerated(targetSessionId, title),
        aiServiceResolver: aiServiceResolver,
        onTextDelta: (characterId, text) {
          activeRun.onTextDelta(characterId, character.name, text);
        },
        onThinkingDelta: (characterId, thinking) {
          activeRun.onThinkingDelta(characterId, character.name, thinking);
        },
        onToolCall: (characterId, record) {
          activeRun.onToolCall(characterId, record);
        },
        traceReporter: ref.read(traceReporterServiceProvider),
        usageService: ref.read(usageServiceProvider),
      );
      // 标题完成回调会独立合并并落库；返回后再确保一次，用于覆盖取消等
      // 不再发 phase 回调的路径，正常完成时是幂等写入。
      unawaited(_ensurePersistedSession(result));

      final current = _sessionFor(targetSessionId);
      if (current != null && (providerId != null || model != null)) {
        final updated = current.copyWith(
          providerId: providerId ?? current.providerId,
          model: model ?? current.model,
        );
        _setSessionFor(targetSessionId, updated);
      }
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
      service.cancel();
    }
    return (
      sessionId: targetSessionId,
      phase: _sessionFor(targetSessionId)?.phase ?? MonologuePhase.error,
    );
  }

  Future<({String sessionId, MonologuePhase phase})?> _continueMonologue({
    required AiClient aiService,
    AiSessionContext? context,
    MonologueConfig config = const MonologueConfig(),
    MonologueAiServiceResolver? aiServiceResolver,
    String? providerId,
    String? model,
  }) async {
    final current = state;
    if (current == null || current.isActive) {
      return null;
    }

    if (context?.databasePath != null && context!.databasePath!.isNotEmpty) {
      _persistenceDatabasePath = context.databasePath;
    }
    final service = _runtime.obtainOrchestrator();
    _runtime.setProcessing(true);

    try {
      final updated = await service.continueMonologue(
        session: current,
        aiService: aiService,
        context: context,
        systemPrompt: ref
            .read(
              agentProfileBySlugProvider(
                slug: builtinAgentSlugMonologueNarrator,
              ),
            )
            ?.systemPrompt,
        config: config,
        onMonologueGenerated: _onMonologueGenerated,
        onPhaseChanged: _onPhaseChanged,
        aiServiceResolver: aiServiceResolver,
        onTextDelta: (characterId, text) {
          _activeRun.onTextDelta(characterId, current.character.name, text);
        },
        onThinkingDelta: (characterId, thinking) {
          _activeRun.onThinkingDelta(
            characterId,
            current.character.name,
            thinking,
          );
        },
        onToolCall: (characterId, record) {
          _activeRun.onToolCall(characterId, record);
        },
        traceReporter: ref.read(traceReporterServiceProvider),
        usageService: ref.read(usageServiceProvider),
      );

      if (_isRunProcessing(current.id)) {
        state = updated.copyWith(
          providerId: providerId ?? current.providerId,
          model: model ?? current.model,
        );
      }
    } catch (error, stackTrace) {
      _failRun(
        error,
        stackTrace,
        operation: 'continue',
        targetSessionId: current.id,
      );
    } finally {
      if (ref.mounted) {
        _activeRun.clear();
      }
      service.cancel();
    }
    return (
      sessionId: current.id,
      phase: _sessionFor(current.id)?.phase ?? current.phase,
    );
  }

  void _onMonologueGenerated(
    MonologueSession session,
    MonologueEntry monologue,
  ) {
    if (!ref.mounted) {
      return;
    }
    if (!_isRunProcessing(session.id)) {
      return;
    }
    final activeRun = ref.read(monologueActiveRunProvider(session.id));
    if (activeRun != null && activeRun.agentId == monologue.characterId) {
      ref
          .read(monologueRunHistoryStoreProvider(session.id).notifier)
          .save(
            monologue.id,
            activeRun.copyWith(
              accumulatedText: [
                if (monologue.innerThoughts.isNotEmpty) monologue.innerThoughts,
                if (monologue.plannedActions.isNotEmpty)
                  monologue.plannedActions,
              ].join('\n\n'),
            ),
          );
    }
    if (sessionId == session.id) {
      state = session;
    } else {
      ref.read(monologueSessionProvider(session.id).notifier).state = session;
    }
    unawaited(
      _upsertCompletedMessages(session, eventName: 'monologue_generated'),
    );
  }

  void _onPhaseChanged(MonologueSession session) {
    if (!ref.mounted) {
      return;
    }
    if (!_isRunProcessing(session.id)) {
      return;
    }
    if (sessionId == session.id) {
      state = session;
    } else {
      ref.read(monologueSessionProvider(session.id).notifier).state = session;
    }
    unawaited(_ensurePersistedSession(session));
    if (session.phase == MonologuePhase.completed &&
        session.monologues.isNotEmpty) {
      unawaited(
        _upsertCompletedMessages(
          session,
          eventName: 'monologue_phase_completed',
        ),
      );
    }
  }

  void _onTitleGenerated(String targetSessionId, String title) {
    if (!ref.mounted) {
      return;
    }
    final targetProvider = monologueSessionProvider(targetSessionId);
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

  Future<void> _ensurePersistedSession(MonologueSession session) async {
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
              LocaleKeys.monologueSessionTitleFmt,
              namedArgs: {
                'character': session.character.name,
                'topic': session.topic,
              },
            ),
      provider: session.providerId,
      model: session.model,
      mode: AiSessionMode.monologue.value,
      metadata: {
        'mode': 'monologue',
        'topic': session.topic,
        monologueParticipantMetadataKey: session.character.toJson(),
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

  void pause() {
    _runResources?.cancelMain();
    _runtime.cancelOrchestrator();
    _activeRun.clear();
    final current = state;
    if (current != null) {
      state = current.copyWith(
        phase: MonologuePhase.completed,
        clearFailure: true,
        updatedAt: DateTime.now(),
      );
    }
  }

  void cancel() {
    _runResources?.cancelMain();
    _runtime.cancelOrchestrator();
    _activeRun.clear();
    final current = state;
    if (current != null) {
      state = current.copyWith(
        phase: MonologuePhase.cancelled,
        clearFailure: true,
        updatedAt: DateTime.now(),
      );
    }
  }

  void setSession(MonologueSession session) {
    _runHistory.clear();
    state = session;
  }

  /// 仅在该 family 尚无内存会话时恢复持久化快照。
  ///
  /// Monologue 允许离页后继续运行；持久化读取可能晚于后台回调返回，因此 UI
  /// hydration 必须保留 keepAlive 的 session 与 run history。
  bool restorePersistedSessionIfAbsent({
    required MonologueSession session,
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

  Future<void> _upsertCompletedMessages(
    MonologueSession session, {
    required String eventName,
  }) {
    final next = _writeChain.then(
      (_) => _writeCompletedMessages(session, eventName: eventName),
    );
    _writeChain = next;
    return next;
  }

  Future<void> _writeCompletedMessages(
    MonologueSession session, {
    required String eventName,
  }) async {
    final databasePath = _persistenceDatabasePath;
    if (databasePath == null || databasePath.isEmpty) {
      return;
    }
    if (session.monologues.isEmpty) {
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
        'persisted monologue completed messages from $eventName '
        'sessionId=${session.id}',
      );
    } catch (error, stackTrace) {
      _log.error(
        'persist monologue completed messages failed '
        'event=$eventName sessionId=${session.id} error=$error',
        stackTrace: stackTrace,
      );
    }
  }

  List<AiMessage> _encodeMessages(MonologueSession session) =>
      encodeMonologueMessages(
        session,
        ref.read(monologueRunHistoryStoreProvider(session.id)),
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
class MonologueConfigNotifier extends _$MonologueConfigNotifier {
  @override
  MonologueConfig build() {
    return const MonologueConfig();
  }

  void updateConfig(MonologueConfig config) {
    state = config;
  }
}
