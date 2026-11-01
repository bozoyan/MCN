// 职责: 角色扮演运行内核 hook — 会话可见性、角色选择与输入、发送/暂停/取消、历史恢复、交接到 chat，桌面面板与移动页共用。
// 关联文件:
//   lib/shared/hooks/use_ai_mode_model_selection.dart
//   lib/shared/services/ai/mode_run_resources.dart
//   lib/shared/providers/roleplay_providers.dart
//   lib/shared/services/ai/roleplay_session_codec.dart
//   lib/shared/services/ai/handoff_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/roleplay.json
//   assets/translations/zh-CN/roleplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../agent/agent_run_state.dart';
import '../database/novel_content_database.dart';
import '../heuristic/chat_next_action.dart' show resolveNextActionCharacterId;
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../models/agent_profile.dart';
import '../models/ai_chat_models.dart';
import '../models/ai_provider.dart';
import '../models/ai_session_mode.dart';
import '../models/roleplay_models.dart';
import '../providers/ai_mode_processing.dart';
import '../providers/novel_providers.dart';
import '../providers/roleplay_providers.dart';
import '../providers/settings_providers.dart';
import '../services/ai/handoff_service.dart';
import '../services/ai/roleplay_orchestrator.dart';
import '../services/ai/roleplay_session_codec.dart';
import '../services/ai/session_persistence.dart';
import '../utils/random_id.dart';
import '../services/ai/mode_run_resources.dart';
import 'use_ai_mode_model_selection.dart';

/// 角色扮演页面的状态与操作。
class RoleplayRun {
  const RoleplayRun({
    required this.sessionId,
    required this.session,
    required this.activeRun,
    required this.runHistory,
    required this.characters,
    required this.selectedCharacter,
    required this.inputController,
    required this.isSending,
    required this.models,
    required this.userName,
    required this.userAvatarPath,
    required this.toggleCharacter,
    required this.send,
    required this.restore,
    required this.startNew,
    required this.handoff,
  });

  final String? sessionId;
  final RoleplaySession? session;
  final AgentRunState? activeRun;
  final Map<String, AgentRunState> runHistory;
  final List<CharacterProfile> characters;

  /// 当前选中且仍在角色卡列表里的角色。
  final CharacterProfile? selectedCharacter;
  final TextEditingController inputController;
  final bool isSending;
  final AiModeModelSelection models;

  /// 作者在设置里的名字与头像，用于作者发言气泡。
  final String userName;
  final String userAvatarPath;

  /// 会话开始前要先选角色；之后角色由会话决定。
  bool get canCompose => (session != null || selectedCharacter != null);

  /// 单选：再次点击已选角色取消选择。
  final void Function(String characterId) toggleCharacter;
  final Future<void> Function() send;
  final Future<void> Function(String sessionId) restore;

  /// 保存并清空当前会话，回到选角界面。
  final Future<void> Function() startNew;

  /// 保存当前会话并生成交接上下文，随后清空本会话。
  /// [createTargetSession] 为 true 时同时创建 chat 目标会话。
  final Future<AiModeHandoff?> Function({required bool createTargetSession})
  handoff;
}

RoleplayRun useRoleplayRun(
  WidgetRef ref, {
  required String? novelId,
  required String? databasePath,
  required String? novelName,
  required String? chapterTitle,
  required String? workspaceContent,
  required String? initialSessionId,
  String? initialCharacterId,

  /// chat 的下一步建议带入的角色名；角色卡加载后解析成预选角色，解析不到就停在选择器。
  String? initialCharacterName,
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

  // 前台会话追踪：处理中徽章/通知在本页显示期间归属当前角色扮演会话。
  useEffect(() {
    final sid = visibleSessionId.value;
    if (sid == null || sid.isEmpty) return null;
    final tracker = ref.read(aiModeProcessingTrackerProvider.notifier);
    tracker.setForegroundSession(
      mode: AiSessionMode.roleplay,
      sessionId: sid,
      foreground: true,
    );
    return () => tracker.setForegroundSession(
      mode: AiSessionMode.roleplay,
      sessionId: sid,
      foreground: false,
    );
  }, [visibleSessionId.value]);

  final session = ref.watch(roleplaySessionProvider(visibleSessionId.value));
  final activeRun = ref.watch(
    roleplayActiveRunProvider(visibleSessionId.value),
  );
  final runHistory = ref.watch(
    roleplayRunHistoryStoreProvider(visibleSessionId.value),
  );
  final characters = path == null
      ? const <CharacterProfile>[]
      : ref.watch(characterProfilesProvider(path)).asData?.value ??
            const <CharacterProfile>[];
  final userSettings = ref.watch(appSettingsProvider).asData?.value;
  final models = useAiModeModelSelection(ref);
  final runtimeProcessing = ref.watch(
    roleplayRuntimeProvider(
      visibleSessionId.value,
    ).select((state) => state.isProcessing),
  );

  final inputController = useTextEditingController();
  final isSending = useState(false);
  final selectedCharacterId = useState<String?>(initialCharacterId);
  // 角色卡是异步加载的，跳进来那一帧还解析不出 id，所以等 characters 到齐后再
  // 解析一次。只在「从建议跳入的新会话」这条路上生效：带 initialSessionId 时
  // 角色由会话恢复决定，用户已经选过时也不覆盖。
  useEffect(() {
    if (initialCharacterName == null ||
        initialSessionId != null ||
        characters.isEmpty ||
        selectedCharacterId.value != null) {
      return null;
    }
    selectedCharacterId.value = resolveNextActionCharacterId(
      characters.map((c) => (id: c.id, name: c.name)),
      initialCharacterName,
    );
    return null;
  }, [initialCharacterName, initialSessionId, characters.length]);

  final selectedCharacter = characters
      .where((c) => c.id == selectedCharacterId.value)
      .firstOrNull;

  void showSession(String? sessionId) {
    visibleSessionId.value = sessionId;
    if (sessionId != null) onActiveSessionIdChanged?.call(sessionId);
  }

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
    final current = ref.read(roleplaySessionProvider(sessionId));
    final target = persistenceTarget();
    if (current == null || current.messages.isEmpty || target == null) {
      return;
    }
    await ref
        .read(roleplaySessionProvider(sessionId).notifier)
        .persistToChatSession(
          persistence: target.persistence,
          novelDatabase: target.database,
          databasePath: path,
        );
  }

  Future<void> send() async {
    if (isSending.value || runtimeProcessing) {
      return;
    }
    final draft = inputController.value;
    final text = draft.text.trim();
    // 会话进行中沿用会话角色；开局时用选择器里的角色。
    final character =
        session?.character ??
        (selectedCharacter == null
            ? null
            : roleplayParticipantFromCharacter(selectedCharacter));
    if (text.isEmpty || character == null) return;

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

    isSending.value = true;
    ProviderSubscription<RoleplaySession?>? acceptanceSubscription;
    try {
      final sessionId = visibleSessionId.value ?? buildRandomId('rp');
      showSession(sessionId);
      // 客户端初始化成功并追加用户消息后才清空草稿；订阅随页面卸载释放。
      var accepted = false;
      acceptanceSubscription = ref.listenManual(
        roleplaySessionProvider(sessionId),
        (previous, next) {
          if (accepted || next == null) {
            return;
          }
          final message = next.messages.lastOrNull;
          if (message == null ||
              message.speakerId != 'user' ||
              message.content != text ||
              (previous?.messages.any((m) => m.id == message.id) ?? false)) {
            return;
          }
          accepted = true;
          if (context.mounted &&
              visibleSessionId.value == sessionId &&
              inputController.text == draft.text) {
            inputController.clear();
          }
        },
      );
      await ref
          .read(roleplaySessionProvider(sessionId).notifier)
          .sendMessage(
            novelId: novelId ?? 'unknown',
            userMessage: text,
            character: character,
            selection: selection,
            context: AiSessionContext(
              workId: novelId,
              databasePath: path,
              novelName: novelName,
              chapterTitle: chapterTitle,
              workspaceContent: workspaceContent,
            ),
            preferredSessionId: sessionId,
            config: const RoleplayConfig(),
          );
    } on AiModeRunCancelled {
      // 取消由会话执行层处理，这里只释放界面执行态。
    } on AiModeClientUnavailable {
      // 模型初始化失败时结束本次操作，由 finally 释放界面执行态。
    } on RoleplayRunException {
      // 执行层已记录会话错误，这里只释放界面执行态。
    } finally {
      acceptanceSubscription?.close();
      if (context.mounted) isSending.value = false;
    }
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
    final targetProvider = roleplaySessionProvider(sessionId);
    if (ref.read(targetProvider) == null) {
      final restored = decodeRoleplaySession(
        aiSession,
        persisted.messages,
        characters,
      );
      if (restored == null) return;
      ref
          .read(targetProvider.notifier)
          .restorePersistedSessionIfAbsent(
            session: restored,
            runHistory: decodeRoleplayRunHistory(persisted.messages),
          );
    }
    final effective = ref.read(targetProvider);
    if (effective == null) return;
    showSession(sessionId);
    selectedCharacterId.value = effective.character.characterId;
    // 继续对话沿用该会话当时的模型；已不可用时保持当前选择。
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
    ref.read(roleplaySessionProvider(sessionId).notifier).clear();
    visibleSessionId.value = null;
    inputController.clear();
    selectedCharacterId.value = null;
  }

  Future<AiModeHandoff?> handoff({required bool createTargetSession}) async {
    final current = ref.read(roleplaySessionProvider(visibleSessionId.value));
    final target = persistenceTarget();
    if (current == null || current.messages.isEmpty || target == null) {
      return null;
    }
    final chatName = context.t(LocaleKeys.aiSessionModeChat);
    final roleplayName = context.t(LocaleKeys.aiSessionModeRoleplay);
    final characterLabel = context.t(LocaleKeys.roleplaySelectCharacter);
    final sourceTitle = current.title.trim().isEmpty
        ? '$roleplayName · ${current.character.name}'
        : current.title;
    final chatTitle = '$chatName · $sourceTitle';
    await persist(current.id);
    final handoffContext = AiHandoffContext(
      sourceSessionId: current.id,
      sourceTitle: sourceTitle,
      fromMode: AiSessionMode.roleplay,
      fromAgentName: roleplayName,
      target: AiHandoffTarget(
        mode: AiSessionMode.chat,
        agentSlug: builtinAgentSlugOrchestrator,
        agentName: chatName,
        providerId: current.providerId,
        model: current.model,
      ),
      summary: roleplayHandoffTranscript(current),
      constraints: ['$characterLabel: ${current.character.name}'],
    );
    final targetSessionId = createTargetSession
        ? await const AiHandoffService().createTargetSession(
            persistence: target.persistence,
            novelDatabase: target.database,
            title: chatTitle,
            context: handoffContext,
          )
        : null;
    ref.read(roleplaySessionProvider(current.id).notifier).clear();
    return AiModeHandoff(
      sourceSessionId: current.id,
      sourceTitle: sourceTitle,
      chatTitle: chatTitle,
      context: handoffContext,
      targetSessionId: targetSessionId,
    );
  }

  return RoleplayRun(
    sessionId: visibleSessionId.value,
    session: session,
    activeRun: activeRun,
    runHistory: runHistory,
    characters: characters,
    selectedCharacter: selectedCharacter,
    inputController: inputController,
    isSending: isSending.value || runtimeProcessing,
    models: models,
    userName: userSettings?.username ?? '',
    userAvatarPath: userSettings?.avatarPath ?? '',
    toggleCharacter: (id) =>
        selectedCharacterId.value = selectedCharacterId.value == id ? null : id,
    send: send,
    restore: restore,
    startNew: startNew,
    handoff: handoff,
  );
}
