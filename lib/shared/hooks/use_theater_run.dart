// 职责: 小剧场运行内核 hook — 会话可见性、选角与场景输入、开演/加一轮/暂停/取消、历史恢复、交接到 chat，桌面面板与移动页共用。
// 关联文件:
//   lib/shared/hooks/use_ai_mode_model_selection.dart
//   lib/shared/providers/theater_providers.dart
//   lib/shared/services/ai/theater_session_codec.dart
//   lib/shared/services/ai/theater_orchestrator.dart
//   lib/shared/services/ai/handoff_service.dart
//   lib/desktop/features/theater/panel.dart
//   lib/mobile/features/theater/page.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../agent/agent_run_state.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../models/agent_profile.dart';
import '../database/novel_content_database.dart';
import '../models/ai_chat_models.dart';
import '../models/ai_provider.dart';
import '../models/ai_session_mode.dart';
import '../models/character_profile.dart';
import '../models/theater_models.dart';
import '../providers/ai_mode_processing.dart';
import '../providers/novel_providers.dart';
import '../providers/theater_providers.dart';
import '../services/ai/handoff_service.dart';
import '../services/ai/session_persistence.dart';
import '../services/ai/theater_orchestrator.dart';
import '../services/ai/theater_session_codec.dart';
import '../utils/random_id.dart';
import '../services/ai/mode_run_resources.dart';
import 'use_ai_mode_model_selection.dart';

/// 小剧场页面的状态与操作。
class TheaterRun {
  const TheaterRun({
    required this.sessionId,
    required this.session,
    required this.activeRun,
    required this.runHistory,
    required this.config,
    required this.characters,
    required this.selectedCharacterIds,
    required this.sceneController,
    required this.directionController,
    required this.isRunning,
    required this.models,
    required this.toggleCharacter,
    required this.setSelectedCharacters,
    required this.start,
    required this.continueRun,
    required this.speak,
    required this.direct,
    required this.removeLine,
    required this.rewindAfter,
    required this.regenerate,
    required this.pause,
    required this.cancel,
    required this.restore,
    required this.startNew,
    required this.handoff,
  });

  final String? sessionId;
  final TheaterSession? session;
  final AgentRunState? activeRun;
  final Map<String, AgentRunState> runHistory;
  final TheaterConfig config;
  final List<CharacterProfile> characters;
  final Set<String> selectedCharacterIds;
  final TextEditingController sceneController;

  /// 导演指令输入框；加一轮/点名发言时若有内容会先作为指令插入。
  final TextEditingController directionController;
  final bool isRunning;
  final AiModeModelSelection models;

  bool get canStart => !isRunning && selectedCharacterIds.length >= 2;

  final void Function(String characterId) toggleCharacter;
  final void Function(Set<String> characterIds) setSelectedCharacters;
  final Future<void> Function() start;

  /// 追加一轮，所有角色各说一句，被点名者优先接话。
  final Future<void> Function() continueRun;

  /// 只让指定角色说一句。
  final Future<void> Function(String characterId) speak;

  /// 插入输入框里的导演指令；表演中会排到下一位发言前生效。
  final VoidCallback direct;
  final void Function(String lineId) removeLine;

  /// 删除该句之后的所有内容，从这里重新往下演。
  final void Function(String lineId) rewindAfter;

  /// 删除该句及之后内容，让同一角色重说这一句。
  final Future<void> Function(TheaterLine line) regenerate;
  final VoidCallback pause;
  final VoidCallback cancel;
  final Future<void> Function(String sessionId) restore;

  /// 保存并清空当前会话，回到选角界面。
  final Future<void> Function() startNew;

  /// 保存当前会话并生成交接上下文，随后清空本会话。
  /// [createTargetSession] 为 true 时同时创建 chat 目标会话。
  final Future<AiModeHandoff?> Function({required bool createTargetSession})
  handoff;
}

TheaterRun useTheaterRun(
  WidgetRef ref, {
  required String? novelId,
  required String? databasePath,
  required String? novelName,
  required String? chapterTitle,
  required String? workspaceContent,
  required String? initialSessionId,
  required String? initialScene,
  ValueChanged<String>? onActiveSessionIdChanged,
}) {
  final context = useContext();
  final path = databasePath != null && databasePath.isNotEmpty
      ? databasePath
      : null;
  final visibleSessionId = useState<String?>(initialSessionId);
  useEffect(() {
    visibleSessionId.value = initialSessionId;
    return null;
  }, [initialSessionId]);

  // 前台会话追踪：处理中徽章/通知在本页显示期间归属当前小剧场会话。
  useEffect(() {
    final sid = visibleSessionId.value;
    if (sid == null || sid.isEmpty) return null;
    final tracker = ref.read(aiModeProcessingTrackerProvider.notifier);
    tracker.setForegroundSession(
      mode: AiSessionMode.theater,
      sessionId: sid,
      foreground: true,
    );
    return () => tracker.setForegroundSession(
      mode: AiSessionMode.theater,
      sessionId: sid,
      foreground: false,
    );
  }, [visibleSessionId.value]);

  final session = ref.watch(theaterSessionProvider(visibleSessionId.value));
  final activeRun = ref.watch(theaterActiveRunProvider(visibleSessionId.value));
  final runHistory = ref.watch(
    theaterRunHistoryStoreProvider(visibleSessionId.value),
  );
  final config = ref.watch(theaterConfigProvider);
  final characters = path == null
      ? const <CharacterProfile>[]
      : ref.watch(characterProfilesProvider(path)).asData?.value ??
            const <CharacterProfile>[];
  final models = useAiModeModelSelection(ref);
  final runtimeProcessing = ref.watch(
    theaterRuntimeProvider(
      visibleSessionId.value,
    ).select((state) => state.isProcessing),
  );

  final sceneController = useTextEditingController(text: initialScene ?? '');
  // seed 变化时刷新场景框；恢复历史会话时由 restore 覆盖。
  useEffect(() {
    final seed = initialScene?.trim();
    if (seed != null && seed.isNotEmpty) {
      sceneController.text = seed;
    }
    return null;
  }, [initialScene]);
  final directionController = useTextEditingController();
  final selectedCharacterIds = useState<Set<String>>(const {});
  final isRunning = useState(false);

  void showSession(String? sessionId) {
    visibleSessionId.value = sessionId;
    if (sessionId != null) onActiveSessionIdChanged?.call(sessionId);
  }

  AiSessionContext sessionContext() => AiSessionContext(
    workId: novelId,
    databasePath: path,
    novelName: novelName,
    chapterTitle: chapterTitle,
    workspaceContent: workspaceContent,
  );

  ({AiSessionPersistenceService persistence, NovelContentDatabase database})?
  persistenceTarget() {
    final id = novelId;
    if (id == null || path == null) return null;
    return (
      persistence: ref.read(
        aiSessionPersistenceServiceProvider(novelId: id, databasePath: path),
      ),
      database: ref.read(novelContentDatabaseProvider(path)),
    );
  }

  Future<void> persist(String sessionId) async {
    if (sessionId.isEmpty) return;
    // 常被 unawaited 调用，widget 可能已卸载：卸载后使用 ref 会抛 StateError。
    if (!context.mounted) return;
    final current = ref.read(theaterSessionProvider(sessionId));
    final target = persistenceTarget();
    // 台词被删空也要落库，否则持久化里留着已撤回的旧台词。
    if (current == null || target == null) return;
    await ref
        .read(theaterSessionProvider(sessionId).notifier)
        .persistToChatSession(
          persistence: target.persistence,
          novelDatabase: target.database,
          databasePath: path,
        );
  }

  Future<void> runWithSelection(
    Future<({String sessionId, TheaterPhase phase})?> Function(
      AiModeRunSelection,
    )
    perform,
  ) async {
    if (!context.mounted) {
      return;
    }
    final option = models.runnable();
    if (option == null) {
      return;
    }
    final selection = AiModeRunSelection(
      model: option,
      reasoningEffort: reasoningEffortForOption(option, models.selectedEffort),
    );

    isRunning.value = true;
    try {
      await perform(selection);
    } on AiModeRunCancelled {
      // 取消由会话执行层处理，这里只释放界面执行态。
    } on AiModeClientUnavailable {
      // 模型初始化失败时结束本次操作，由 finally 释放界面执行态。
    } on TheaterRunException {
      // 执行层已记录会话错误，这里只释放界面执行态。
    } finally {
      if (context.mounted) isRunning.value = false;
    }
  }

  Future<void> start() async {
    final scene = sceneController.text.trim();
    final selectedIds = selectedCharacterIds.value;
    if (scene.isEmpty || selectedIds.length < 2) return;
    await runWithSelection((selection) {
      final participants = [
        for (final c in characters)
          if (selectedIds.contains(c.id))
            TheaterParticipant(
              characterId: c.id,
              name: c.name,
              role: c.role,
              biography: c.biography,
              description: c.promptPersonaContext,
              avatarAssetId: c.avatarAssetId,
            ),
      ];
      final sessionId = visibleSessionId.value ?? buildRandomId('theater');
      showSession(sessionId);
      return ref
          .read(theaterSessionProvider(sessionId).notifier)
          .startPerformance(
            novelId: novelId ?? 'unknown',
            sceneDescription: scene,
            participants: participants,
            selection: selection,
            context: sessionContext(),
            preferredSessionId: sessionId,
            config: config,
          );
    });
  }

  TheaterSessionNotifier? sessionNotifier() {
    final sessionId = visibleSessionId.value;
    if (sessionId == null || sessionId.isEmpty) return null;
    return ref.read(theaterSessionProvider(sessionId).notifier);
  }

  void direct() {
    final notifier = sessionNotifier();
    final text = directionController.text.trim();
    if (notifier == null || text.isEmpty) return;
    notifier.addDirection(text);
    directionController.clear();
    final sessionId = visibleSessionId.value;
    if (!isRunning.value && !runtimeProcessing && sessionId != null) {
      unawaited(persist(sessionId));
    }
  }

  Future<void> perform({String? speakerId, String? rewindFromLineId}) async {
    final notifier = sessionNotifier();
    final sessionId = visibleSessionId.value;
    if (notifier == null || sessionId == null) {
      return;
    }
    await runWithSelection((selection) async {
      if (visibleSessionId.value != sessionId) {
        return null;
      }
      final draft = directionController.value;
      final direction = draft.text.trim();
      var accepted = direction.isEmpty;
      final acceptanceSubscription = ref.listenManual(
        theaterSessionProvider(sessionId),
        (previous, next) {
          if (accepted || next == null) {
            return;
          }
          final line = next.lines.lastOrNull;
          accepted =
              line != null &&
              line.isDirection &&
              line.dialogue == direction &&
              !(previous?.lines.any((l) => l.id == line.id) ?? false);
        },
      );
      // 提交中的草稿先移出输入框，避免初始化期间再次插入同一条指令。
      if (direction.isNotEmpty) {
        directionController.clear();
      }
      try {
        return await notifier.continuePerformance(
          selection: selection,
          context: sessionContext(),
          config: config,
          speakerId: speakerId,
          rewindFromLineId: rewindFromLineId,
          direction: direction,
        );
      } finally {
        acceptanceSubscription.close();
        // 已接收的指令即使生成失败也不重发；未接收时保留草稿，不覆盖新输入。
        if (!accepted &&
            context.mounted &&
            visibleSessionId.value == sessionId &&
            directionController.text.isEmpty) {
          directionController.value = draft;
        }
      }
    });
  }

  void editLines(void Function(TheaterSessionNotifier notifier) edit) {
    final notifier = sessionNotifier();
    final sessionId = visibleSessionId.value;
    if (notifier == null ||
        sessionId == null ||
        isRunning.value ||
        runtimeProcessing) {
      return;
    }
    edit(notifier);
    unawaited(persist(sessionId));
  }

  Future<void> restore(String sessionId) async {
    final target = persistenceTarget();
    if (target == null) return;
    final aiSession = await target.persistence.getSession(sessionId);
    if (aiSession == null) return;
    final persisted = await target.persistence.loadSessionMessages(
      sessionId: aiSession.id,
      novelDatabase: target.database,
    );
    if (!context.mounted) return;
    final currentId = visibleSessionId.value;
    if (currentId != null && currentId.isNotEmpty && currentId != sessionId) {
      await persist(currentId);
      if (!context.mounted) return;
    }
    final targetProvider = theaterSessionProvider(sessionId);
    if (ref.read(targetProvider) == null) {
      final restored = decodeTheaterSession(aiSession, persisted.messages);
      if (restored == null) return;
      ref
          .read(targetProvider.notifier)
          .restorePersistedSessionIfAbsent(
            session: restored,
            runHistory: decodeTheaterRunHistory(persisted.messages),
          );
    }
    final effective = ref.read(targetProvider);
    if (effective == null) return;
    showSession(sessionId);
    sceneController.text = effective.sceneDescription;
    selectedCharacterIds.value = {
      for (final p in effective.participants) p.characterId,
    };
  }

  useEffect(() {
    final sid = initialSessionId;
    if (sid != null && sid.isNotEmpty) {
      // 推迟到首帧之后：restore 会改 provider 与 hook 状态，不能发生在 build 内。
      Future<void>(() {
        if (context.mounted) restore(sid);
      });
    }
    return null;
  }, [initialSessionId]);

  Future<void> startNew() async {
    final sessionId = visibleSessionId.value;
    if (sessionId == null || sessionId.isEmpty) return;
    await persist(sessionId);
    ref.read(theaterSessionProvider(sessionId).notifier).clear();
    visibleSessionId.value = null;
    sceneController.clear();
    selectedCharacterIds.value = const {};
  }

  Future<AiModeHandoff?> handoff({required bool createTargetSession}) async {
    final current = ref.read(theaterSessionProvider(visibleSessionId.value));
    final target = persistenceTarget();
    if (current == null || current.lines.isEmpty || target == null) {
      return null;
    }
    final chatName = context.t(LocaleKeys.aiSessionModeChat);
    final theaterName = context.t(LocaleKeys.aiSessionModeTheater);
    final sceneLabel = context.t(LocaleKeys.theaterSceneDescription);
    final sourceTitle = current.title.trim().isEmpty
        ? '$theaterName · ${current.sceneDescription}'
        : current.title;
    final chatTitle = '$chatName · $sourceTitle';
    await persist(current.id);
    final handoffContext = AiHandoffContext(
      sourceSessionId: current.id,
      sourceTitle: sourceTitle,
      fromMode: AiSessionMode.theater,
      fromAgentName: theaterName,
      target: AiHandoffTarget(
        mode: AiSessionMode.chat,
        agentSlug: builtinAgentSlugOrchestrator,
        agentName: chatName,
      ),
      summary: theaterHandoffTranscript(current),
      constraints: ['$sceneLabel: ${current.sceneDescription}'],
    );
    final targetSessionId = createTargetSession
        ? await const AiHandoffService().createTargetSession(
            persistence: target.persistence,
            novelDatabase: target.database,
            title: chatTitle,
            context: handoffContext,
          )
        : null;
    ref.read(theaterSessionProvider(current.id).notifier).clear();
    return AiModeHandoff(
      sourceSessionId: current.id,
      sourceTitle: sourceTitle,
      chatTitle: chatTitle,
      context: handoffContext,
      targetSessionId: targetSessionId,
    );
  }

  return TheaterRun(
    sessionId: visibleSessionId.value,
    session: session,
    activeRun: activeRun,
    runHistory: runHistory,
    config: config,
    characters: characters,
    selectedCharacterIds: selectedCharacterIds.value,
    sceneController: sceneController,
    isRunning: isRunning.value || runtimeProcessing,
    models: models,
    toggleCharacter: (id) {
      final next = {...selectedCharacterIds.value};
      if (!next.remove(id)) next.add(id);
      selectedCharacterIds.value = next;
    },
    setSelectedCharacters: (ids) => selectedCharacterIds.value = ids,
    start: start,
    directionController: directionController,
    continueRun: perform,
    speak: (characterId) => perform(speakerId: characterId),
    direct: direct,
    removeLine: (lineId) => editLines((n) => n.removeLine(lineId)),
    rewindAfter: (lineId) =>
        editLines((n) => n.rewindTo(lineId, inclusive: false)),
    regenerate: (line) =>
        perform(speakerId: line.characterId, rewindFromLineId: line.id),
    pause: () {
      final sessionId = visibleSessionId.value;
      if (sessionId == null) return;
      unawaited(persist(sessionId));
      ref.read(theaterSessionProvider(sessionId).notifier).pause();
    },
    cancel: () => ref
        .read(theaterSessionProvider(visibleSessionId.value).notifier)
        .cancel(),
    restore: restore,
    startNew: startNew,
    handoff: handoff,
  );
}
