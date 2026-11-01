// 职责: 议会运行内核 hook — 会话可见性、议题与成员选择、开始/追加一轮/更新总结/插话/暂停/取消、历史恢复、交接到 chat，桌面面板与移动页共用。
// 关联文件:
//   lib/shared/hooks/use_ai_mode_model_selection.dart
//   lib/shared/services/ai/mode_run_resources.dart
//   lib/shared/providers/agent_council_providers.dart
//   lib/shared/services/ai/council_session_codec.dart
//   lib/shared/services/ai/handoff_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../agent/agent_run_state.dart';
import '../database/app_database.dart' show Novel;
import '../database/novel_content_database.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../logger/app_logger.dart';
import '../models/agent_council_models.dart';
import '../models/agent_profile.dart';
import '../models/ai_chat_models.dart';
import '../models/ai_provider.dart';
import '../models/ai_session_mode.dart';
import '../providers/agent_council_providers.dart';
import '../providers/ai_mode_processing.dart';
import '../providers/novel_providers.dart';
import '../services/ai/agent_council_orchestrator.dart';
import '../services/ai/council_session_codec.dart';
import '../services/ai/handoff_service.dart';
import '../services/ai/session_persistence.dart';
import '../utils/random_id.dart';
import '../services/ai/mode_run_resources.dart';
import 'use_ai_mode_model_selection.dart';

final _log = AppLogger.forModule('CouncilRun');

/// 议会页面的状态与操作。
class CouncilRun {
  const CouncilRun({
    required this.sessionId,
    required this.session,
    required this.activeRun,
    required this.runHistory,
    required this.queuedMessageIds,
    required this.config,
    required this.participants,
    required this.selectedParticipantIds,
    required this.topicController,
    required this.userInputController,
    required this.isRunning,
    required this.models,
    required this.toggleParticipant,
    required this.setSelectedParticipants,
    required this.setMaxRounds,
    required this.updateParticipant,
    required this.start,
    required this.addRound,
    required this.speak,
    required this.regenerate,
    required this.rewindAfter,
    required this.removeMessage,
    required this.updateSummary,
    required this.sendUserMessage,
    required this.pause,
    required this.cancel,
    required this.restore,
    required this.startNew,
    required this.handoff,
  });

  final String? sessionId;
  final AgentCouncilSession? session;
  final AgentRunState? activeRun;
  final Map<String, AgentRunState> runHistory;

  /// 讨论中插入、还没轮到并入的插话；时间线把它们排在正在生成的发言之后。
  final Set<String> queuedMessageIds;
  final AgentCouncilConfig config;

  /// 可选的议会成员（mode=council 的 SubAgent）。
  final List<CouncilParticipant> participants;
  final Set<String> selectedParticipantIds;
  final TextEditingController topicController;

  /// 讨论间隙的插话输入框。
  final TextEditingController userInputController;
  final bool isRunning;
  final AiModeModelSelection models;

  bool get canStart => !isRunning && selectedParticipantIds.isNotEmpty;

  final void Function(String participantId) toggleParticipant;
  final void Function(Set<String> participantIds) setSelectedParticipants;
  final void Function(int maxRounds) setMaxRounds;

  /// 保存成员设定（名字、提示词、专属模型），写回对应的 SubAgent。
  final Future<void> Function(CouncilParticipant participant) updateParticipant;
  final Future<void> Function() start;

  /// 追加一轮，所有成员各发言一次，被点名者优先接话。
  final Future<void> Function() addRound;

  /// 只让指定成员发言一次。
  final Future<void> Function(String participantId) speak;

  /// 删除该条及之后的内容，让同一成员重说这一条。
  final Future<void> Function(CouncilMessage message) regenerate;

  /// 删除该条之后的所有内容，从这里重新讨论。
  final void Function(String messageId) rewindAfter;

  /// 删除单条发言（用于撤回作者插话）。
  final void Function(String messageId) removeMessage;
  final Future<void> Function() updateSummary;

  /// 发送插话；讨论进行中会排到下一位成员发言前。
  final VoidCallback sendUserMessage;
  final VoidCallback pause;
  final VoidCallback cancel;
  final Future<void> Function(String sessionId) restore;

  /// 保存并清空当前会话，回到设置界面。
  final Future<void> Function() startNew;

  /// 保存当前会话并生成交接上下文，随后清空本会话。
  /// [createTargetSession] 为 true 时同时创建 chat 目标会话。
  final Future<AiModeHandoff?> Function({required bool createTargetSession})
  handoff;
}

CouncilRun useCouncilRun(
  WidgetRef ref, {
  required Novel novel,
  required String? databasePath,
  required String? initialSessionId,
  required String? initialTopic,
  ValueChanged<String?>? onActiveSessionIdChanged,
}) {
  final context = useContext();
  final novelId = novel.id;
  final path = databasePath != null && databasePath.isNotEmpty
      ? databasePath
      : null;
  final visibleSessionId = useState<String?>(initialSessionId);
  useEffect(() {
    visibleSessionId.value = initialSessionId;
    return null;
  }, [initialSessionId]);

  // 前台会话追踪：处理中徽章/通知在本页显示期间归属当前议会会话。
  useEffect(() {
    final sid = visibleSessionId.value;
    if (sid == null || sid.isEmpty) return null;
    final tracker = ref.read(aiModeProcessingTrackerProvider.notifier);
    tracker.setForegroundSession(
      mode: AiSessionMode.council,
      sessionId: sid,
      foreground: true,
    );
    return () => tracker.setForegroundSession(
      mode: AiSessionMode.council,
      sessionId: sid,
      foreground: false,
    );
  }, [visibleSessionId.value]);

  final session = ref.watch(
    agentCouncilSessionProvider(visibleSessionId.value),
  );
  final activeRun = ref.watch(
    agentCouncilActiveRunProvider(visibleSessionId.value),
  );
  final runHistory = ref.watch(
    agentCouncilRunHistoryStoreProvider(visibleSessionId.value),
  );
  final config = ref.watch(agentCouncilConfigProvider);
  final participants =
      ref.watch(agentCouncilParticipantsProvider).value ??
      const <CouncilParticipant>[];
  final models = useAiModeModelSelection(ref);
  final runtimeProcessing = ref.watch(
    agentCouncilRuntimeProvider(
      visibleSessionId.value,
    ).select((state) => state.isProcessing),
  );

  final topicController = useTextEditingController(text: initialTopic ?? '');
  // seed 变化（用户在 chat 里又点了一条圆桌建议）时刷新议题框；
  // 恢复历史会话时由 restore 写入真值。
  useEffect(() {
    final seed = initialTopic?.trim();
    if (seed != null && seed.isNotEmpty) {
      topicController.text = seed;
    }
    return null;
  }, [initialTopic]);
  final userInputController = useTextEditingController();
  // 侧栏「新建圆桌」会把 initialSessionId 置为 null 而复用面板实例：
  // 清掉上一条会话恢复时写入的议题与输入；带种子进入时由种子逻辑填充。
  useEffect(() {
    final seed = initialTopic?.trim();
    if (initialSessionId == null && (seed == null || seed.isEmpty)) {
      topicController.clear();
      userInputController.clear();
    }
    return null;
  }, [initialSessionId]);

  // null 表示用户还没动过选择，默认全选；成员列表异步加载完也能全部选中。
  final pickedParticipantIds = useState<Set<String>?>(null);
  final selectedParticipantIds =
      pickedParticipantIds.value ?? {for (final p in participants) p.id};
  final isRunning = useState(false);

  void showSession(String? sessionId) {
    visibleSessionId.value = sessionId;
    onActiveSessionIdChanged?.call(sessionId);
  }

  void showError(String key) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(context.t(key))));
  }

  ({AiSessionPersistenceService persistence, NovelContentDatabase database})?
  persistenceTarget() {
    if (path == null) return null;
    return (
      persistence: ref.read(
        aiSessionPersistenceServiceProvider(
          novelId: novelId,
          databasePath: path,
        ),
      ),
      database: ref.read(novelContentDatabaseProvider(path)),
    );
  }

  Future<void> persist(String sessionId) async {
    if (sessionId.isEmpty) return;
    // 常被 unawaited 调用，widget 可能已卸载：卸载后使用 ref 会抛 StateError。
    if (!context.mounted) return;
    final current = ref.read(agentCouncilSessionProvider(sessionId));
    final target = persistenceTarget();
    // 发言被删空也要落库，否则持久化里留着已删除的旧发言。
    if (current == null || target == null) return;
    await ref
        .read(agentCouncilSessionProvider(sessionId).notifier)
        .persistToChatSession(
          persistence: target.persistence,
          novelDatabase: target.database,
          databasePath: path,
        );
  }

  Future<void> runWithSelection(
    Iterable<CouncilParticipant> members,
    Future<({String sessionId, CouncilPhase phase})?> Function(
      AiModeRunSelection selection,
      AiSessionContext sessionContext,
    )
    perform,
  ) async {
    if (isRunning.value || runtimeProcessing) return;
    isRunning.value = true;
    try {
      // 作品已删除时这里会抛错，必须先于借租约，否则租约漏还。
      final sessionContext = AiSessionContext(
        databasePath: path,
      ).withWork(novel);
      if (!context.mounted) {
        return;
      }
      final option = models.runnable();
      if (option == null) {
        showError(LocaleKeys.aiServiceUnavailable);
        return;
      }
      final selection = AiModeRunSelection(
        model: option,
        reasoningEffort: reasoningEffortForOption(
          option,
          models.selectedEffort,
        ),
        memberModels: models.availableModels,
        disabledModelIds: const <String>{},
      );
      await perform(selection, sessionContext);
    } on AiModeRunCancelled {
      // 取消由会话执行层处理，这里只释放界面执行态。
    } on AiModeClientUnavailable {
      showError(LocaleKeys.aiServiceUnavailable);
    } on AgentCouncilRunException {
      // 执行层已记录会话错误，这里只释放界面执行态。
    } catch (error, stackTrace) {
      _log.error('council run failed', error: error, stackTrace: stackTrace);
      showError(LocaleKeys.aiRequestFailed);
    } finally {
      if (context.mounted) isRunning.value = false;
    }
  }

  Future<void> start() async {
    final topic = topicController.text.trim();
    final members = [
      for (final p in participants)
        if (selectedParticipantIds.contains(p.id)) p,
    ];
    if (topic.isEmpty || members.isEmpty) return;
    await runWithSelection(members, (selection, sessionContext) {
      final sessionId = visibleSessionId.value ?? buildRandomId('council');
      showSession(sessionId);
      return ref
          .read(agentCouncilSessionProvider(sessionId).notifier)
          .startCouncil(
            novelId: novelId,
            topic: topic,
            participants: members,
            selection: selection,
            context: sessionContext,
            preferredSessionId: sessionId,
            config: config,
          );
    });
  }

  AgentCouncilSessionNotifier? sessionNotifier() {
    final sessionId = visibleSessionId.value;
    if (sessionId == null || sessionId.isEmpty) return null;
    return ref.read(agentCouncilSessionProvider(sessionId).notifier);
  }

  Future<void> perform({String? speakerId, String? rewindFromMessageId}) async {
    final notifier = sessionNotifier();
    final current = session;
    if (notifier == null || current == null) return;
    final members = speakerId == null
        ? current.participants
        : current.participants.where((p) => p.id == speakerId);
    await runWithSelection(members, (selection, sessionContext) async {
      return notifier.runAdditionalRound(
        selection: selection,
        context: sessionContext,
        config: config,
        speakerId: speakerId,
        rewindFromMessageId: rewindFromMessageId,
      );
    });
  }

  void editMessages(void Function(AgentCouncilSessionNotifier notifier) edit) {
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

  Future<void> updateSummary() async {
    final notifier = sessionNotifier();
    if (notifier == null) return;
    await runWithSelection(
      const [],
      (selection, sessionContext) => notifier.generateSummary(
        selection: selection,
        context: sessionContext,
      ),
    );
  }

  void sendUserMessage() {
    final notifier = sessionNotifier();
    final text = userInputController.text.trim();
    if (notifier == null || text.isEmpty) return;
    notifier.addUserMessage(text, databasePath: path);
    userInputController.clear();
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
    final targetProvider = agentCouncilSessionProvider(sessionId);
    if (ref.read(targetProvider) == null) {
      final restored = decodeCouncilSession(aiSession, persisted.messages);
      if (restored == null) return;
      ref
          .read(targetProvider.notifier)
          .restorePersistedSessionIfAbsent(
            session: restored,
            runHistory: decodeCouncilRunHistory(persisted.messages),
          );
    }
    final effective = ref.read(targetProvider);
    if (effective == null) return;
    showSession(sessionId);
    topicController.text = effective.topic;
  }

  useEffect(() {
    final sid = initialSessionId;
    if (sid != null && sid.isNotEmpty) {
      // restore 先 await 持久化读取，provider 与 hook 状态都在 build 之后才改。
      unawaited(restore(sid));
    }
    return null;
  }, [initialSessionId]);

  Future<void> startNew() async {
    final sessionId = visibleSessionId.value;
    if (sessionId == null || sessionId.isEmpty) return;
    await persist(sessionId);
    ref.read(agentCouncilSessionProvider(sessionId).notifier).clear();
    showSession(null);
    topicController.clear();
    userInputController.clear();
  }

  Future<AiModeHandoff?> handoff({required bool createTargetSession}) async {
    final current = ref.read(
      agentCouncilSessionProvider(visibleSessionId.value),
    );
    final target = persistenceTarget();
    if (current == null || current.rounds.isEmpty || target == null) {
      return null;
    }
    final chatName = context.t(LocaleKeys.aiSessionModeChat);
    final councilName = context.t(LocaleKeys.aiSessionModeCouncil);
    final topicLabel = context.t(LocaleKeys.councilTopic);
    final sourceTitle = current.title.trim().isEmpty
        ? '$councilName · ${current.topic}'
        : current.title;
    final chatTitle = '$chatName · $sourceTitle';
    await persist(current.id);
    final summary = current.summary;
    final summaryText = summary?.content.trim() ?? '';
    final handoffContext = AiHandoffContext(
      sourceSessionId: current.id,
      sourceTitle: sourceTitle,
      fromMode: AiSessionMode.council,
      fromAgentName: councilName,
      target: AiHandoffTarget(
        mode: AiSessionMode.chat,
        agentSlug: builtinAgentSlugOrchestrator,
        agentName: chatName,
      ),
      summary: summaryText.isNotEmpty
          ? summaryText
          : councilHandoffTranscript(current),
      decisions: summary?.keyPoints ?? const [],
      openQuestions: summary?.openQuestions ?? const [],
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
    ref.read(agentCouncilSessionProvider(current.id).notifier).clear();
    return AiModeHandoff(
      sourceSessionId: current.id,
      sourceTitle: sourceTitle,
      chatTitle: chatTitle,
      context: handoffContext,
      targetSessionId: targetSessionId,
    );
  }

  return CouncilRun(
    sessionId: visibleSessionId.value,
    session: session,
    activeRun: activeRun,
    runHistory: runHistory,
    queuedMessageIds: ref
        .read(agentCouncilSessionProvider(visibleSessionId.value).notifier)
        .pendingUserMessageIds,
    config: config,
    participants: participants,
    selectedParticipantIds: selectedParticipantIds,
    topicController: topicController,
    userInputController: userInputController,
    isRunning: isRunning.value || runtimeProcessing,
    models: models,
    toggleParticipant: (id) {
      final next = {...selectedParticipantIds};
      if (!next.remove(id)) next.add(id);
      pickedParticipantIds.value = next;
    },
    setSelectedParticipants: (ids) => pickedParticipantIds.value = ids,
    setMaxRounds: (maxRounds) => ref
        .read(agentCouncilConfigProvider.notifier)
        .updateMaxRounds(maxRounds),
    updateParticipant: (participant) => ref
        .read(agentCouncilParticipantsProvider.notifier)
        .updateParticipant(participant),
    start: start,
    addRound: perform,
    speak: (participantId) => perform(speakerId: participantId),
    regenerate: (message) => perform(
      speakerId: message.participantId,
      rewindFromMessageId: message.id,
    ),
    rewindAfter: (messageId) =>
        editMessages((n) => n.rewindTo(messageId, inclusive: false)),
    removeMessage: (messageId) =>
        editMessages((n) => n.removeMessage(messageId)),
    updateSummary: updateSummary,
    sendUserMessage: sendUserMessage,
    pause: () {
      final sessionId = visibleSessionId.value;
      if (sessionId == null) return;
      unawaited(persist(sessionId));
      ref.read(agentCouncilSessionProvider(sessionId).notifier).pause();
    },
    cancel: () => ref
        .read(agentCouncilSessionProvider(visibleSessionId.value).notifier)
        .cancel(),
    restore: restore,
    startNew: startNew,
    handoff: handoff,
  );
}
