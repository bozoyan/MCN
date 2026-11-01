// 职责: 小剧场模式状态管理 — session 级 runtime 与状态，支持后台处理与会话切换不取消。
// 关联文件:
//   lib/shared/models/theater_models.dart
//   lib/shared/services/ai/theater_orchestrator.dart
//   lib/shared/providers/ai_mode_processing.dart
//   lib/desktop/features/theater/panel.dart
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
import '../models/theater_models.dart';
import '../services/ai/chat.dart';
import '../services/ai/mode_run_resources.dart';
import '../services/ai/session_persistence.dart';
import '../services/ai/theater_orchestrator.dart';
import '../services/ai/theater_session_codec.dart';
import 'usage_query_providers.dart';
import '../utils/random_id.dart';
import 'trace_providers.dart';
import 'agent_profile_providers.dart';
import 'package:easy_localization/easy_localization.dart';

import '../localization/locale_keys.dart';
import 'ai_mode_processing.dart';
import 'ai_mode_runtime.dart';
import 'novel_providers.dart';

part 'theater_providers.g.dart';

final _log = AppLogger.forModule('Theater');

@Riverpod(keepAlive: true)
class TheaterActiveRun extends _$TheaterActiveRun {
  @override
  AgentRunState? build(String? sessionId) => null;

  void onTextDelta(
    String characterId,
    String characterName,
    int round,
    String text,
  ) {
    final current = state;
    if (current == null || current.agentId != characterId) {
      state = AgentRunState(
        agentId: characterId,
        agentName: characterName,
        round: round,
        accumulatedText: text,
      );
    } else {
      state = current.withAppendedText(text);
    }
  }

  void onThinkingDelta(
    String characterId,
    String characterName,
    int round,
    String thinking,
  ) {
    final current = state;
    if (current == null || current.agentId != characterId) {
      state = AgentRunState(
        agentId: characterId,
        agentName: characterName,
        round: round,
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
class TheaterRunHistoryStore extends _$TheaterRunHistoryStore {
  @override
  Map<String, AgentRunState> build(String? sessionId) => const {};

  void save(String messageId, AgentRunState runState) {
    state = {...state, messageId: runState.copyWith(isComplete: true)};
  }

  void retain(Set<String> messageIds) {
    state = {
      for (final entry in state.entries)
        if (messageIds.contains(entry.key)) entry.key: entry.value,
    };
  }

  void clear() {
    state = const {};
  }
}

@Riverpod(keepAlive: true)
class TheaterRuntime extends _$TheaterRuntime {
  TheaterOrchestrator? orchestrator;

  @override
  AiModeRuntimeState build(String? sessionId) {
    return const AiModeRuntimeState();
  }

  TheaterOrchestrator obtainOrchestrator({bool recreate = false}) {
    if (recreate) {
      orchestrator?.cancel();
      orchestrator = (TheaterOrchestrator()
        ..pluginHost = ref.read(pluginHostServiceProvider));
    }
    return orchestrator ??= (TheaterOrchestrator()
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
          mode: AiSessionMode.theater,
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
class TheaterSessionNotifier extends _$TheaterSessionNotifier {
  String? _persistenceDatabasePath;
  AiModeRunResources? _runResources;
  Future<void> _writeChain = Future.value();

  /// 表演中插入、编排器尚未并入台词流的导演指令。立即对 UI 可见，
  /// 编排器快照回写时补在末尾，运行结束/暂停/取消时落定。
  final List<TheaterLine> _pendingDirections = [];

  TheaterSession _withPendingDirections(TheaterSession session) {
    final known = {for (final line in session.lines) line.id};
    final pending = [
      for (final line in _pendingDirections)
        if (!known.contains(line.id)) line,
    ];
    if (pending.isEmpty) return session;
    return session.copyWith(lines: [...session.lines, ...pending]);
  }

  /// 合并剩余指令并落库：末位发言后插入的指令没人消费，离页后 hook 也不会补存。
  void _settlePendingDirections() {
    final current = state;
    // 被编排器消费的指令已在 _onLineGenerated 移出并随台词落库，剩下的都需补存。
    if (current != null && _pendingDirections.isNotEmpty) {
      final merged = _withPendingDirections(current);
      state = merged;
      unawaited(
        _upsertCompletedMessages(
          merged,
          eventName: 'theater_directions_settled',
        ),
      );
    }
    _pendingDirections.clear();
  }

  @override
  TheaterSession? build(String? sessionId) {
    ref.onDispose(() {
      final resources = _runResources;
      if (resources != null) {
        resources.cancelAll();
      }
    });
    return null;
  }

  TheaterRuntime get _runtime =>
      ref.read(theaterRuntimeProvider(sessionId).notifier);

  TheaterActiveRun get _activeRun =>
      ref.read(theaterActiveRunProvider(sessionId).notifier);

  TheaterRunHistoryStore get _runHistory =>
      ref.read(theaterRunHistoryStoreProvider(sessionId).notifier);

  bool _isRunProcessing(String targetSessionId) =>
      ref.mounted &&
      ref.read(theaterRuntimeProvider(targetSessionId)).isProcessing;

  TheaterSession? _sessionFor(String targetSessionId) {
    return sessionId == targetSessionId
        ? state
        : ref.read(theaterSessionProvider(targetSessionId));
  }

  void _setSessionFor(String targetSessionId, TheaterSession session) {
    if (sessionId == targetSessionId) {
      state = session;
    } else {
      ref.read(theaterSessionProvider(targetSessionId).notifier).state =
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
    final failure = error is TheaterRunException
        ? error
        : TheaterRunException(const AiRunFailure.requestFailed(), cause: error);
    _log.error(
      'theater $operation failed sessionId=$targetSessionId error=$error',
      error: error,
      stackTrace: stackTrace,
    );
    final current = _sessionFor(targetSessionId);
    if (current != null) {
      _setSessionFor(
        targetSessionId,
        current.copyWith(
          phase: TheaterPhase.error,
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
        ref.read(theaterRuntimeProvider(targetSessionId)).isProcessing) {
      throw StateError('Theater session already has an active operation.');
    }
    final runtime = ref.read(theaterRuntimeProvider(targetSessionId).notifier);
    final resources = AiModeRunResources(
      factory: ref.read(aiModeClientFactoryProvider),
      selection: selection,
      context: context,
      sessionId: targetSessionId,
      mode: AiSessionMode.theater,
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
                  : ref.read(theaterSessionProvider(targetSessionId).notifier);
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
          _settlePendingDirections();
          runtime.setProcessing(false, notifyOnComplete: completed);
          await _writeChain;
        }
      }
    }
  }

  Future<({String sessionId, TheaterPhase phase})> startPerformance({
    required String novelId,
    required String sceneDescription,
    required List<TheaterParticipant> participants,
    required AiModeRunSelection selection,
    required AiSessionContext context,
    String? preferredSessionId,
    TheaterConfig config = const TheaterConfig(),
  }) {
    final id = preferredSessionId ?? sessionId ?? buildRandomId('theater');
    return _withRunResources(
      targetSessionId: id,
      selection: selection,
      context: context,
      run: (resources) async => _startPerformance(
        aiService: await resources.mainClient(),
        novelId: novelId,
        sceneDescription: sceneDescription,
        participants: participants,
        context: context,
        preferredSessionId: id,
        config: config,
      ),
    );
  }

  Future<({String sessionId, TheaterPhase phase})?> continuePerformance({
    required AiModeRunSelection selection,
    required AiSessionContext context,
    TheaterConfig config = const TheaterConfig(),
    String? speakerId,
    String? rewindFromLineId,
    String? direction,
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
      run: (resources) async {
        final client = await resources.mainClient();
        if (rewindFromLineId != null) {
          _rewindLines(rewindFromLineId, inclusive: true);
          await _persistCurrentSession();
        }
        if (direction != null && direction.isNotEmpty) {
          addDirection(direction);
        }
        return _continuePerformance(
          aiService: client,
          context: context,
          config: config,
          speakerId: speakerId,
        );
      },
    );
  }

  Future<({String sessionId, TheaterPhase phase})> _startPerformance({
    required String novelId,
    required String sceneDescription,
    required List<TheaterParticipant> participants,
    required AiClient aiService,
    AiSessionContext? context,
    String? preferredSessionId,
    TheaterConfig config = const TheaterConfig(),
  }) async {
    final targetSessionId =
        preferredSessionId ?? sessionId ?? buildRandomId('theater');
    _persistenceDatabasePath = context?.databasePath;
    final now = DateTime.now();
    _setSessionFor(
      targetSessionId,
      TheaterSession(
        id: targetSessionId,
        novelId: novelId,
        sceneDescription: sceneDescription,
        participants: participants,
        phase: TheaterPhase.performing,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final service =
        ref
            .read(theaterRuntimeProvider(targetSessionId).notifier)
            .obtainOrchestrator(recreate: true)
          ..titleClientRunner = _runResources!.withDetachedClient;
    ref
        .read(theaterRuntimeProvider(targetSessionId).notifier)
        .setProcessing(true);
    final agentProfile = ref.read(
      agentProfileBySlugProvider(slug: builtinAgentSlugTheaterActor),
    );
    final activeRun = ref.read(
      theaterActiveRunProvider(targetSessionId).notifier,
    );
    final participantMap = {
      for (final p in participants) p.characterId: p.name,
    };

    try {
      final result = await service.startPerformance(
        novelId: novelId,
        sceneDescription: sceneDescription,
        participants: participants,
        aiService: aiService,
        context: context,
        sessionId: targetSessionId,
        systemPrompt: agentProfile?.systemPrompt,
        config: config,
        onLineGenerated: _onLineGenerated,
        onPhaseChanged: _onPhaseChanged,
        onTitleGenerated: (title) => _onTitleGenerated(targetSessionId, title),
        onTextDelta: (characterId, round, text) {
          activeRun.onTextDelta(
            characterId,
            participantMap[characterId] ?? characterId,
            round,
            text,
          );
        },
        onThinkingDelta: (characterId, round, thinking) {
          activeRun.onThinkingDelta(
            characterId,
            participantMap[characterId] ?? characterId,
            round,
            thinking,
          );
        },
        onToolCall: (characterId, round, record) {
          activeRun.onToolCall(characterId, record);
        },
        traceReporter: ref.read(traceReporterServiceProvider),
        usageService: ref.read(usageServiceProvider),
      );
      // 标题完成回调会独立合并并落库；返回后再确保一次，用于覆盖取消等
      // 不再发 phase 回调的路径，正常完成时是幂等写入。
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
      service.cancel();
      if (ref.mounted) {
        _settlePendingDirections();
      }
    }
    return (
      sessionId: targetSessionId,
      phase: _sessionFor(targetSessionId)?.phase ?? TheaterPhase.error,
    );
  }

  /// 追加一轮；传 [speakerId] 时只让该角色说一句。
  Future<({String sessionId, TheaterPhase phase})?> _continuePerformance({
    required AiClient aiService,
    AiSessionContext? context,
    TheaterConfig config = const TheaterConfig(),
    String? speakerId,
  }) async {
    final current = state;
    if (current == null || current.isActive) {
      return null;
    }

    final databasePath = context?.databasePath;
    if (databasePath != null && databasePath.isNotEmpty) {
      _persistenceDatabasePath = databasePath;
    }
    final service = _runtime.obtainOrchestrator();
    _runtime.setProcessing(true);
    final agentProfile = ref.read(
      agentProfileBySlugProvider(slug: builtinAgentSlugTheaterActor),
    );

    try {
      final updated = await service.continuePerformance(
        session: current,
        aiService: aiService,
        context: context,
        systemPrompt: agentProfile?.systemPrompt,
        config: config,
        onLineGenerated: _onLineGenerated,
        onPhaseChanged: _onPhaseChanged,
        speakerId: speakerId,
        onTextDelta: (characterId, round, text) {
          _activeRun.onTextDelta(
            characterId,
            current.participants
                    .where((p) => p.characterId == characterId)
                    .map((p) => p.name)
                    .firstOrNull ??
                characterId,
            round,
            text,
          );
        },
        onThinkingDelta: (characterId, round, thinking) {
          _activeRun.onThinkingDelta(
            characterId,
            current.participants
                    .where((p) => p.characterId == characterId)
                    .map((p) => p.name)
                    .firstOrNull ??
                characterId,
            round,
            thinking,
          );
        },
        onToolCall: (characterId, round, record) {
          _activeRun.onToolCall(characterId, record);
        },
        traceReporter: ref.read(traceReporterServiceProvider),
        usageService: ref.read(usageServiceProvider),
      );

      if (_isRunProcessing(current.id)) {
        state = _withPendingDirections(updated);
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
      if (ref.mounted) {
        _settlePendingDirections();
      }
    }
    return (
      sessionId: current.id,
      phase: _sessionFor(current.id)?.phase ?? current.phase,
    );
  }

  void _onLineGenerated(TheaterSession session, TheaterLine line) {
    if (!ref.mounted) {
      return;
    }
    if (!_isRunProcessing(session.id)) {
      return;
    }
    final activeRun = ref.read(theaterActiveRunProvider(session.id));
    if (activeRun != null && activeRun.agentId == line.characterId) {
      ref
          .read(theaterRunHistoryStoreProvider(session.id).notifier)
          .save(
            line.id,
            activeRun.copyWith(
              accumulatedText: [
                if (line.stageDirection != null &&
                    line.stageDirection!.isNotEmpty)
                  '（${line.stageDirection}）',
                line.dialogue,
              ].join('\n'),
              round: line.turn,
            ),
          );
    }
    if (line.isDirection) _pendingDirections.remove(line);
    final merged = _withPendingDirections(session);
    if (sessionId == session.id) {
      state = merged;
    } else {
      ref.read(theaterSessionProvider(session.id).notifier).state = merged;
    }
    unawaited(
      _upsertCompletedMessages(merged, eventName: 'theater_line_generated'),
    );
  }

  void _onPhaseChanged(TheaterSession session) {
    if (!ref.mounted) {
      return;
    }
    if (!_isRunProcessing(session.id)) {
      return;
    }
    final merged = _withPendingDirections(session);
    if (sessionId == session.id) {
      state = merged;
    } else {
      ref.read(theaterSessionProvider(session.id).notifier).state = merged;
    }
    unawaited(_ensurePersistedSession(session));
    if (session.phase == TheaterPhase.completed && merged.lines.isNotEmpty) {
      unawaited(
        _upsertCompletedMessages(merged, eventName: 'theater_phase_completed'),
      );
    }
  }

  void _onTitleGenerated(String targetSessionId, String title) {
    if (!ref.mounted) {
      return;
    }
    final targetProvider = theaterSessionProvider(targetSessionId);
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

  Future<void> _ensurePersistedSession(TheaterSession session) async {
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
              LocaleKeys.theaterSessionTitleFmt,
              namedArgs: {
                'participants': participantNames,
                'scene': session.sceneDescription,
              },
            ),
      mode: AiSessionMode.theater.value,
      metadata: {
        'mode': 'theater',
        'scene': session.sceneDescription,
        theaterParticipantsMetadataKey: session.participants
            .map((p) => p.toJson())
            .toList(),
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
    _settlePendingDirections();
    final current = state;
    if (current != null) {
      state = current.copyWith(
        phase: TheaterPhase.completed,
        clearFailure: true,
        updatedAt: DateTime.now(),
      );
    }
  }

  void cancel() {
    _runResources?.cancelMain();
    _runtime.cancelOrchestrator();
    _activeRun.clear();
    _settlePendingDirections();
    final current = state;
    if (current != null) {
      state = current.copyWith(
        phase: TheaterPhase.cancelled,
        clearFailure: true,
        updatedAt: DateTime.now(),
      );
    }
  }

  /// 插入导演指令：表演中排队到下一位发言前，否则直接追加到台词流。
  void addDirection(String text) {
    final trimmed = text.trim();
    final current = state;
    if (trimmed.isEmpty || current == null) return;
    final line = TheaterLine.direction(
      id: buildRandomId('line'),
      text: trimmed,
      turn: current.currentTurn,
      timestamp: DateTime.now(),
    );
    if (_isRunProcessing(current.id)) {
      _pendingDirections.add(line);
      _runtime.orchestrator?.queueDirection(line);
    }
    state = current.copyWith(
      lines: [...current.lines, line],
      updatedAt: DateTime.now(),
    );
  }

  /// 删除单条台词流条目（用于撤回导演指令）。表演中不可改写历史。
  void removeLine(String lineId) {
    final current = state;
    if (current == null || _isRunProcessing(current.id)) return;
    _replaceLines(current, [
      for (final line in current.lines)
        if (line.id != lineId) line,
    ]);
  }

  /// 回退到 [lineId]：删除其后所有条目；[inclusive] 时连同该条一起删除。
  void rewindTo(String lineId, {required bool inclusive}) {
    final current = state;
    if (current == null || _isRunProcessing(current.id)) return;
    _rewindLines(lineId, inclusive: inclusive);
  }

  void _rewindLines(String lineId, {required bool inclusive}) {
    final current = state;
    if (current == null) {
      return;
    }
    final index = current.lines.indexWhere((line) => line.id == lineId);
    if (index < 0) return;
    _replaceLines(
      current,
      current.lines.sublist(0, inclusive ? index : index + 1),
    );
  }

  void _replaceLines(TheaterSession current, List<TheaterLine> lines) {
    _runHistory.retain({for (final line in lines) line.id});
    state = current.copyWith(
      lines: lines,
      phase: TheaterPhase.completed,
      clearFailure: true,
      updatedAt: DateTime.now(),
    );
  }

  void setSession(TheaterSession session) {
    _runHistory.clear();
    state = session;
  }

  /// 仅在该 family 尚无内存会话时恢复持久化快照。
  ///
  /// Theater 允许离页后继续运行；持久化读取可能晚于后台回调返回，因此 UI
  /// hydration 必须保留 keepAlive 的 session 与 run history。
  bool restorePersistedSessionIfAbsent({
    required TheaterSession session,
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
    TheaterSession session, {
    required String eventName,
  }) {
    final next = _writeChain.then(
      (_) => _writeCompletedMessages(session, eventName: eventName),
    );
    _writeChain = next;
    return next;
  }

  Future<void> _writeCompletedMessages(
    TheaterSession session, {
    required String eventName,
  }) async {
    final databasePath = _persistenceDatabasePath;
    if (databasePath == null || databasePath.isEmpty) {
      return;
    }
    if (session.lines.isEmpty) {
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
        'persisted theater completed messages from $eventName '
        'sessionId=${session.id}',
      );
    } catch (error, stackTrace) {
      _log.error(
        'persist theater completed messages failed '
        'event=$eventName sessionId=${session.id} error=$error',
        stackTrace: stackTrace,
      );
    }
  }

  List<AiMessage> _encodeMessages(TheaterSession session) =>
      encodeTheaterMessages(
        session,
        ref.read(theaterRunHistoryStoreProvider(session.id)),
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
class TheaterConfigNotifier extends _$TheaterConfigNotifier {
  @override
  TheaterConfig build() {
    return const TheaterConfig();
  }

  void updateConfig(TheaterConfig config) {
    state = config;
  }

  void updateMaxRounds(int maxRounds) {
    state = TheaterConfig(maxRounds: maxRounds);
  }
}
