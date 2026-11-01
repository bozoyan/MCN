// 职责: 移动端作品内 AI 五模式定义与跨模式 pushReplacement 导航（对话/圆桌/独白/小剧场/角色扮演）。
// 关联文件:
//   lib/mobile/providers/ai_mode_session_memory_provider.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/mobile/features/council/page.dart
//   lib/mobile/features/monologue/page.dart
//   lib/mobile/features/theater/page.dart
//   lib/mobile/features/roleplay/page.dart
//   lib/mobile/widgets/mobile_ai_mode_switch_strip.dart
//   lib/shared/models/ai_session_mode.dart
//   lib/shared/localization/locale_keys.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/ai_session_mode.dart';
import '../../shared/models/content_kind.dart';
import '../../shared/providers/novel_providers.dart';
import '../../shared/theme/theme.dart';
import '../features/council/page.dart';
import '../features/monologue/page.dart';
import '../pages/novel_chat_page.dart';
import '../features/roleplay/page.dart';
import '../features/theater/page.dart';
import '../providers/ai_mode_session_memory_provider.dart';

/// 作品内 AI 页共享上下文，供模式切换条跨页 [pushReplacementMobileAiModePage] 使用。
class MobileAiNovelContext {
  const MobileAiNovelContext({
    required this.novelId,
    required this.novelName,
    required this.databasePath,
    this.novelDescription,
    this.novelDraft = false,
    this.chapterId,
    this.chapterTitle,
    this.chapterNumber,
    this.workspaceContent,
    this.contentKind = contentKindNovel,
    this.currentSeasonId,
    this.currentEpisodeId,
    this.hasMultipleSeasons = false,
  });

  final String novelId;
  final String novelName;
  final String databasePath;
  final String? novelDescription;

  /// 「快速开书」草稿(未收入书库)。仅 chat 模式据此注入 novel_draft remind。
  final bool novelDraft;
  final String? chapterId;
  final String? chapterTitle;
  final int? chapterNumber;
  final String? workspaceContent;
  final String contentKind;
  final String? currentSeasonId;
  final String? currentEpisodeId;
  final bool hasMultipleSeasons;
}

class MobileAiModeEntry {
  const MobileAiModeEntry({
    required this.mode,
    required this.icon,
    required this.labelKey,
  });

  final AiSessionMode mode;
  final String icon;
  final String labelKey;
}

/// 作品内 AI 页横向模式切换条使用的五个模式（含 chat）。
const List<MobileAiModeEntry> mobileAiModes = [
  MobileAiModeEntry(
    mode: AiSessionMode.chat,
    icon: RevericIcons.chat_rounded,
    labelKey: LocaleKeys.aiSessionModeChat,
  ),
  MobileAiModeEntry(
    mode: AiSessionMode.council,
    icon: RevericIcons.groups_rounded,
    labelKey: LocaleKeys.aiSessionModeCouncil,
  ),
  MobileAiModeEntry(
    mode: AiSessionMode.monologue,
    icon: RevericIcons.person_rounded,
    labelKey: LocaleKeys.aiSessionModeMonologue,
  ),
  MobileAiModeEntry(
    mode: AiSessionMode.theater,
    icon: RevericIcons.theater_comedy_rounded,
    labelKey: LocaleKeys.aiSessionModeTheater,
  ),
  MobileAiModeEntry(
    mode: AiSessionMode.roleplay,
    icon: RevericIcons.add_comment_outlined,
    labelKey: LocaleKeys.aiSessionModeRoleplay,
  ),
];

String mobileAiModeLabel(BuildContext context, AiSessionMode mode) {
  final entry = mobileAiModes.firstWhere(
    (item) => item.mode == mode,
    orElse: () => mobileAiModes.first,
  );
  return context.t(entry.labelKey);
}

/// 解析切到 [targetMode] 时应打开的会话 id。
///
/// 优先级：显式 [existingSessionId] → 进程内记忆 → chat 的 preferred session。
/// [rememberedSessionId] / [preferredChatSessionId] 由调用方解析后传入，便于单测。
String? resolveMobileAiModeTargetSessionId({
  required AiSessionMode targetMode,
  String? existingSessionId,
  String? rememberedSessionId,
  String? preferredChatSessionId,
  bool restoreRemembered = true,
  bool useChatPreferredFallback = true,
}) {
  if (existingSessionId != null && existingSessionId.isNotEmpty) {
    return existingSessionId;
  }
  if (restoreRemembered &&
      rememberedSessionId != null &&
      rememberedSessionId.isNotEmpty) {
    return rememberedSessionId;
  }
  if (useChatPreferredFallback &&
      targetMode == AiSessionMode.chat &&
      preferredChatSessionId != null &&
      preferredChatSessionId.isNotEmpty) {
    return preferredChatSessionId;
  }
  return null;
}

/// 切换到目标模式页；同模式 no-op。默认 [pushReplacement] 避免栈上堆叠多个模式页。
///
/// [seedText] 由 chat 的下一步建议带入，预填圆桌议题 / 小剧场场景；角色扮演的
/// seed 语义是角色名（入口是「和谁演」而不是「演什么」），由目标页解析成角色卡。
///
/// 切走前把 [currentSessionId] 写入进程内记忆；进入时优先恢复目标模式记忆的
/// 会话，chat 无记忆时再回落 [getPreferredSession]。显式「新建」应传
/// `restoreRemembered: false` 与 `useChatPreferredFallback: false`，并先 clear 记忆。
Future<void> pushReplacementMobileAiModePage(
  BuildContext context, {
  required AiSessionMode mode,
  required MobileAiNovelContext novel,
  AiSessionMode? currentMode,
  String? currentSessionId,
  String? existingSessionId,
  bool rememberCurrent = true,
  bool restoreRemembered = true,
  bool useChatPreferredFallback = true,
  String? seedText,
}) async {
  if (currentMode != null && currentMode == mode) {
    return;
  }

  final container = ProviderScope.containerOf(context, listen: false);
  final memory = container.read(
    mobileAiModeSessionMemoryProvider(novel.novelId).notifier,
  );

  if (rememberCurrent && currentMode != null) {
    memory.remember(currentMode, currentSessionId);
  }

  var targetSessionId = resolveMobileAiModeTargetSessionId(
    targetMode: mode,
    existingSessionId: existingSessionId,
    rememberedSessionId: restoreRemembered ? memory.sessionIdFor(mode) : null,
    restoreRemembered: restoreRemembered,
    useChatPreferredFallback: false,
  );

  if (targetSessionId == null &&
      useChatPreferredFallback &&
      mode == AiSessionMode.chat &&
      novel.databasePath.isNotEmpty) {
    try {
      final persistence = container.read(
        aiSessionPersistenceServiceProvider(
          novelId: novel.novelId,
          databasePath: novel.databasePath,
        ),
      );
      final preferred = await persistence.getPreferredSession();
      targetSessionId = resolveMobileAiModeTargetSessionId(
        targetMode: mode,
        preferredChatSessionId: preferred?.id,
        restoreRemembered: false,
        useChatPreferredFallback: true,
      );
    } catch (_) {
      // preferred 读取失败时退回空草稿，不阻断模式切换。
    }
  }

  if (targetSessionId != null &&
      novel.databasePath.isNotEmpty &&
      existingSessionId == null) {
    try {
      final persistence = container.read(
        aiSessionPersistenceServiceProvider(
          novelId: novel.novelId,
          databasePath: novel.databasePath,
        ),
      );
      final session = await persistence.getSession(targetSessionId);
      if (session == null) {
        memory.clear(mode);
        targetSessionId = null;
      }
    } catch (_) {
      memory.clear(mode);
      targetSessionId = null;
    }
  }

  if (!context.mounted) {
    return;
  }

  final page = _mobileAiModePage(
    mode: mode,
    novel: novel,
    sessionId: targetSessionId,
    seedText: seedText,
  );

  Navigator.of(
    context,
  ).pushReplacement(MaterialPageRoute<void>(builder: (_) => page));
}

Widget _mobileAiModePage({
  required AiSessionMode mode,
  required MobileAiNovelContext novel,
  String? sessionId,
  String? seedText,
}) {
  return switch (mode) {
    AiSessionMode.chat => MobileNovelChatPage(
      novelId: novel.novelId,
      databasePath: novel.databasePath,
      chapterId: novel.chapterId,
      chapterTitle: novel.chapterTitle,
      chapterNumber: novel.chapterNumber,
      currentSeasonId: novel.currentSeasonId,
      currentEpisodeId: novel.currentEpisodeId,
      hasMultipleSeasons: novel.hasMultipleSeasons,
      existingSessionId: sessionId,
    ),
    AiSessionMode.council => MobileCouncilPage(
      novelId: novel.novelId,
      novelName: novel.novelName,
      databasePath: novel.databasePath,
      novelDescription: novel.novelDescription,
      chapterTitle: novel.chapterTitle,
      workspaceContent: novel.workspaceContent,
      initialSessionId: sessionId,
      initialTopic: seedText,
    ),
    AiSessionMode.monologue => MobileMonologuePage(
      novelId: novel.novelId,
      novelName: novel.novelName,
      databasePath: novel.databasePath,
      novelDescription: novel.novelDescription,
      chapterTitle: novel.chapterTitle,
      workspaceContent: novel.workspaceContent,
      initialSessionId: sessionId,
    ),
    AiSessionMode.theater => MobileTheaterPage(
      novelId: novel.novelId,
      novelName: novel.novelName,
      databasePath: novel.databasePath,
      novelDescription: novel.novelDescription,
      chapterTitle: novel.chapterTitle,
      workspaceContent: novel.workspaceContent,
      initialSessionId: sessionId,
      initialScene: seedText,
    ),
    AiSessionMode.roleplay => MobileRoleplayPage(
      novelId: novel.novelId,
      novelName: novel.novelName,
      databasePath: novel.databasePath,
      novelDescription: novel.novelDescription,
      chapterTitle: novel.chapterTitle,
      workspaceContent: novel.workspaceContent,
      initialSessionId: sessionId,
      // 角色扮演的 seed 是角色名，不是议题 / 场景那样的自由文本。
      initialCharacterName: seedText,
    ),
  };
}
