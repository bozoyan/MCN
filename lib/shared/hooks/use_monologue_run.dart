// 职责: 独白运行内核 hook — 会话可见性、角色与议题输入、开始/继续/暂停/取消、历史恢复、交接到 chat，桌面面板与移动页共用。
// 关联文件:
//   lib/shared/hooks/use_ai_mode_model_selection.dart
//   lib/shared/services/ai/mode_run_resources.dart
//   lib/shared/providers/monologue_providers.dart
//   lib/shared/services/ai/monologue_session_codec.dart
//   lib/shared/services/ai/handoff_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/monologue.json
//   assets/translations/zh-CN/monologue.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../agent/agent_run_state.dart';
import '../database/novel_content_database.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../models/agent_profile.dart';
import '../models/ai_chat_models.dart';
import '../models/ai_provider.dart';
import '../models/ai_session_mode.dart';
import '../models/character_profile.dart';
import '../models/monologue_models.dart';
import '../providers/ai_mode_processing.dart';
import '../providers/monologue_providers.dart';
import '../providers/novel_providers.dart';
import '../services/ai/handoff_service.dart';
import '../services/ai/monologue_orchestrator.dart';
import '../services/ai/monologue_session_codec.dart';
import '../services/ai/session_persistence.dart';
import '../utils/random_id.dart';
import '../services/ai/mode_run_resources.dart';
import 'use_ai_mode_model_selection.dart';

/// 独白页面的状态与操作。
class MonologueRun {
  const MonologueRun({
    required this.sessionId,
    required this.session,
    required this.activeRun,
    required this.runHistory,
    required this.characters,
    required this.selectedCharacterId,
    required this.topicController,
    required this.isRunning,
    required this.models,
    required this.toggleCharacter,
    required this.start,
    required this.continueRun,
    required this.pause,
    required this.cancel,
    required this.restore,
    required this.startNew,
    required this.handoff,
  });

  final String? sessionId;
  final MonologueSession? session;
  final AgentRunState? activeRun;
  final Map<String, AgentRunState> runHistory;
  final List<CharacterProfile> characters;
  final String? selectedCharacterId;
  final TextEditingController topicController;
  final bool isRunning;
  final AiModeModelSelection models;

  bool get canStart => !isRunning && selectedCharacterId != null;

  /// 单选：再次点击已选角色取消选择。
  final void Function(String characterId) toggleCharacter;
  final Future<void> Function() start;

  /// 同一角色、同一议题再生成一段独白。
  final Future<void> Function() continueRun;
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

MonologueRun useMonologueRun(
  WidgetRef ref, {
  required String? novelId,
  required String? databasePath,
  required String? novelName,
  required String? chapterTitle,
  required String? workspaceContent,
  required String? initialSessionId,
  required String? initialCharacterId,
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

  // 前台会话追踪：处理中徽章/通知在本页显示期间归属当前独白会话。
  useEffect(() {
    final sid = visibleSessionId.value;
    if (sid == null || sid.isEmpty) return null;
    final tracker = ref.read(aiModeProcessingTrackerProvider.notifier);
    tracker.setForegroundSession(
      mode: AiSessionMode.monologue,
      sessionId: sid,
      foreground: true,
    );
    return () => tracker.setForegroundSession(
      mode: AiSessionMode.monologue,
      sessionId: sid,
      foreground: false,
    );
  }, [visibleSessionId.value]);

  final session = ref.watch(monologueSessionProvider(visibleSessionId.value));
  final activeRun = ref.watch(
    monologueActiveRunProvider(visibleSessionId.value),
  );
  final runHistory = ref.watch(
    monologueRunHistoryStoreProvider(visibleSessionId.value),
  );
  final config = ref.watch(monologueConfigProvider);
  final characters = path == null
      ? const <CharacterProfile>[]
      : ref.watch(characterProfilesProvider(path)).asData?.value ??
            const <CharacterProfile>[];
  final models = useAiModeModelSelection(ref);
  final runtimeProcessing = ref.watch(
    monologueRuntimeProvider(
      visibleSessionId.value,
    ).select((state) => state.isProcessing),
  );

  final topicController = useTextEditingController();
  // 侧栏「新建独白」会把 initialSessionId 置为 null：面板实例被复用，
  // hook 状态保留，需重置上一条会话恢复时写入的议题，否则 setup 页残留旧议题。
  useEffect(() {
    if (initialSessionId == null) topicController.clear();
    return null;
  }, [initialSessionId]);
  final selectedCharacterId = useState<String?>(initialCharacterId);
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
    final current = ref.read(monologueSessionProvider(sessionId));
    final target = persistenceTarget();
    if (current == null || current.monologues.isEmpty || target == null) {
      return;
    }
    await ref
        .read(monologueSessionProvider(sessionId).notifier)
        .persistToChatSession(
          persistence: target.persistence,
          novelDatabase: target.database,
          databasePath: path,
        );
  }

  Future<void> runWithSelection(
    Future<({String sessionId, MonologuePhase phase})?> Function(
      AiModeRunSelection selection,
      AiModelOption option,
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
      await perform(selection, option);
    } on AiModeRunCancelled {
      // 取消由会话执行层处理，这里只释放界面执行态。
    } on AiModeClientUnavailable {
      // 模型初始化失败时结束本次操作，由 finally 释放界面执行态。
    } on MonologueRunException {
      // 执行层已记录会话错误，这里只释放界面执行态。
    } finally {
      if (context.mounted) isRunning.value = false;
    }
  }

  Future<void> start() async {
    final topic = topicController.text.trim();
    final character = characters
        .where((c) => c.id == selectedCharacterId.value)
        .firstOrNull;
    if (topic.isEmpty || character == null) return;
    await runWithSelection((selection, option) {
      final sessionId = visibleSessionId.value ?? buildRandomId('mono_session');
      showSession(sessionId);
      return ref
          .read(monologueSessionProvider(sessionId).notifier)
          .startSession(
            novelId: novelId ?? 'unknown',
            topic: topic,
            character: MonologueParticipant(
              characterId: character.id,
              name: character.name,
              role: character.role,
              biography: character.biography,
              description: character.promptPersonaContext,
              avatarAssetId: character.avatarAssetId,
            ),
            selection: selection,
            context: sessionContext(),
            preferredSessionId: sessionId,
            config: config,
          );
    });
  }

  Future<void> continueRun() async {
    final sessionId = visibleSessionId.value;
    if (sessionId == null || sessionId.isEmpty) return;
    await runWithSelection(
      (selection, option) => ref
          .read(monologueSessionProvider(sessionId).notifier)
          .continueMonologue(
            selection: selection,
            context: sessionContext(),
            config: config,
          ),
    );
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
    final targetProvider = monologueSessionProvider(sessionId);
    if (ref.read(targetProvider) == null) {
      final restored = decodeMonologueSession(aiSession, persisted.messages);
      if (restored == null) return;
      ref
          .read(targetProvider.notifier)
          .restorePersistedSessionIfAbsent(
            session: restored,
            runHistory: decodeMonologueRunHistory(persisted.messages),
          );
    }
    final effective = ref.read(targetProvider);
    if (effective == null) return;
    showSession(sessionId);
    topicController.text = effective.topic;
    selectedCharacterId.value = effective.character.characterId;
    // 继续生成沿用该会话当时的模型；已不可用时保持当前选择。
    final match = models.availableModels
        .where(
          (m) =>
              m.providerId == effective.providerId &&
              m.model == effective.model,
        )
        .firstOrNull;
    if (match != null) models.select(match);
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
    ref.read(monologueSessionProvider(sessionId).notifier).clear();
    visibleSessionId.value = null;
    topicController.clear();
  }

  Future<AiModeHandoff?> handoff({required bool createTargetSession}) async {
    final current = ref.read(monologueSessionProvider(visibleSessionId.value));
    final target = persistenceTarget();
    if (current == null || current.monologues.isEmpty || target == null) {
      return null;
    }
    final chatName = context.t(LocaleKeys.aiSessionModeChat);
    final monologueName = context.t(LocaleKeys.aiSessionModeMonologue);
    final topicLabel = context.t(LocaleKeys.monologueTopic);
    final sourceTitle = current.title.trim().isEmpty
        ? '$monologueName · ${current.topic}'
        : current.title;
    final chatTitle = '$chatName · $sourceTitle';
    await persist(current.id);
    final handoffContext = AiHandoffContext(
      sourceSessionId: current.id,
      sourceTitle: sourceTitle,
      fromMode: AiSessionMode.monologue,
      fromAgentName: monologueName,
      target: AiHandoffTarget(
        mode: AiSessionMode.chat,
        agentSlug: builtinAgentSlugOrchestrator,
        agentName: chatName,
        providerId: current.providerId,
        model: current.model,
      ),
      summary: monologueHandoffTranscript(current),
      constraints: ['$topicLabel: ${current.topic}'],
    );
    final targetSessionId = createTargetSession
        ? await const AiHandoffService().createTargetSession(
            persistence: target.persistence,
            novelDatabase: target.database,
            title: chatTitle,
            context: handoffContext,
          )
        : null;
    ref.read(monologueSessionProvider(current.id).notifier).clear();
    return AiModeHandoff(
      sourceSessionId: current.id,
      sourceTitle: sourceTitle,
      chatTitle: chatTitle,
      context: handoffContext,
      targetSessionId: targetSessionId,
    );
  }

  return MonologueRun(
    sessionId: visibleSessionId.value,
    session: session,
    activeRun: activeRun,
    runHistory: runHistory,
    characters: characters,
    selectedCharacterId: selectedCharacterId.value,
    topicController: topicController,
    isRunning: isRunning.value || runtimeProcessing,
    models: models,
    toggleCharacter: (id) =>
        selectedCharacterId.value = selectedCharacterId.value == id ? null : id,
    start: start,
    continueRun: continueRun,
    pause: () {
      final sessionId = visibleSessionId.value;
      if (sessionId == null) return;
      unawaited(persist(sessionId));
      ref.read(monologueSessionProvider(sessionId).notifier).pause();
    },
    cancel: () => ref
        .read(monologueSessionProvider(visibleSessionId.value).notifier)
        .cancel(),
    restore: restore,
    startNew: startNew,
    handoff: handoff,
  );
}
