// 职责: 移动端「角色扮演」页 — 选定单个角色后与之一对一对话、实时流式展示、切换写作模式与历史恢复。
// 关联文件:
//   lib/shared/widgets/novel_open_boundary.dart
//   lib/shared/hooks/use_roleplay_run.dart
//   lib/shared/providers/roleplay_providers.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/mobile/providers/ai_mode_session_memory_provider.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/roleplay.json
//   assets/translations/zh-CN/roleplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/widgets/novel_open_boundary.dart';
import '../../../shared/agent/agent_run_state.dart';
import '../../../shared/database/app_database.dart' show AiChatSession;
import '../../../shared/hooks/use_roleplay_run.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/ai_provider.dart';
import '../../../shared/models/ai_session_mode.dart';
import '../../../shared/models/roleplay_models.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/providers/roleplay_providers.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/services/ai/roleplay_session_codec.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/ai/agent_message_card.dart';
import '../../../shared/widgets/ai/agent_round_detail_dialog.dart';
import '../../../shared/widgets/ai/roleplay_message_card.dart';
import '../../../shared/widgets/character/picker.dart';
import '../../../shared/widgets/ai/user_respecting_auto_scroll_controller.dart';
import '../../../shared/widgets/ai/ai_mode_error_notice.dart';
import '../../providers/ai_mode_session_memory_provider.dart';
import '../../providers/chat_providers.dart';
import '../../widgets/ai_session_history_sheet.dart';
import '../../widgets/mobile_ai_mode.dart';
import '../../widgets/mobile_ai_session_app_bar.dart';
import '../../widgets/model_selector.dart';
import '../../pages/ai_providers_settings_page.dart';
import '../../pages/novel_chat_page.dart';

part 'page_sections.dart';
part 'page_widgets.dart';

/// 移动端角色扮演页：从「助手」Hub 的角色扮演卡片进入。
/// 复用桌面共享的 roleplay 编排器与 Provider，仅 UI 为移动端布局。
class MobileRoleplayPage extends HookConsumerWidget {
  const MobileRoleplayPage({
    super.key,
    required this.novelId,
    required this.novelName,
    required this.databasePath,
    this.novelDescription,
    this.chapterTitle,
    this.workspaceContent,
    this.initialSessionId,
    this.initialCharacterName,
  });

  final String novelId;
  final String novelName;
  final String databasePath;
  final String? novelDescription;
  final String? chapterTitle;
  final String? workspaceContent;

  /// 非空表示从「最近对话」打开一条已存在的角色扮演会话：进入后从持久化恢复对话历史。
  final String? initialSessionId;

  /// chat 的下一步建议带入的角色名。角色扮演的入口是「和谁演」而不是「演什么」，
  /// 所以 seed 是角色名，进入时解析成角色卡预选；解析不到就停在选择器。
  final String? initialCharacterName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NovelOpenBoundary(
      novelId: novelId,
      child: HookConsumer(
        builder: (context, ref, _) => _buildContent(context, ref),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isConfigured = ref.watch(isAiConfiguredProvider);

    final run = useRoleplayRun(
      ref,
      novelId: novelId,
      databasePath: databasePath,
      novelName: novelName,
      chapterTitle: chapterTitle,
      workspaceContent: workspaceContent,
      initialSessionId: initialSessionId,
      initialCharacterName: initialCharacterName,
    );
    final session = run.session;

    Future<void> startNewSession() async {
      await run.startNew();
      ref
          .read(mobileAiModeSessionMemoryProvider(novelId).notifier)
          .clear(AiSessionMode.roleplay);
    }

    final roleplaySessions =
        ref
            .watch(
              mobileNovelModeSessionsProvider((
                novelId: novelId,
                mode: AiSessionMode.roleplay,
              )),
            )
            .asData
            ?.value ??
        const <AiChatSession>[];

    Future<void> openHistory() async {
      final picked = await showAiSessionHistorySheet(
        context,
        sessions: roleplaySessions,
        currentSessionId: run.sessionId,
        mode: AiSessionMode.roleplay,
        modeLabel: mobileAiModeLabel(context, AiSessionMode.roleplay),
        onDelete: (session) async {
          final service = ref.read(
            aiSessionPersistenceServiceProvider(
              novelId: novelId,
              databasePath: databasePath,
            ),
          );
          await service.deleteSession(session.id);
        },
      );
      if (picked == null || !context.mounted) return;
      if (picked.id == run.sessionId) return;
      ref
          .read(mobileAiModeSessionMemoryProvider(novelId).notifier)
          .remember(AiSessionMode.roleplay, picked.id);
      await run.restore(picked.id);
    }

    Future<void> switchToWriteMode() async {
      final handoff = await run.handoff(createTargetSession: true);
      final targetSessionId = handoff?.targetSessionId;
      if (targetSessionId == null || !context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MobileNovelChatPage(
            novelId: novelId,
            databasePath: databasePath,
            existingSessionId: targetSessionId,
          ),
        ),
      );
    }

    Future<void> showActiveRunDetailDialog(String title) async {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Consumer(
            builder: (dialogContext, ref, _) {
              final liveRun = ref.watch(
                roleplayActiveRunProvider(run.sessionId),
              );
              return AgentRoundDetailDialog(
                runState:
                    liveRun ??
                    AgentRunState(
                      agentId: '',
                      agentName: title,
                      round: 0,
                      isComplete: true,
                    ),
                title: title,
                databasePath: databasePath,
                novelId: novelId,
              );
            },
          );
        },
      );
    }

    final roleplaySubtitle = session?.character.name.trim();
    final novelContext = MobileAiNovelContext(
      novelId: novelId,
      novelName: novelName,
      databasePath: databasePath,
      novelDescription: novelDescription,
      chapterTitle: chapterTitle,
      workspaceContent: workspaceContent,
    );

    return MobileAiSessionScaffold(
      title: context.t(LocaleKeys.aiSessionModeRoleplay),
      subtitle: roleplaySubtitle != null && roleplaySubtitle.isNotEmpty
          ? roleplaySubtitle
          : null,
      currentMode: AiSessionMode.roleplay,
      novelContext: novelContext,
      currentSessionId: run.sessionId,
      historyTooltip: context.t(LocaleKeys.aiSessionHistoryTitle),
      newSessionTooltip: context.t(LocaleKeys.roleplayNew),
      onHistory: openHistory,
      onNew: startNewSession,
      body: !isConfigured
          ? _buildConfigHint(context, colors, typo)
          : session == null
          ? _buildSetup(context, colors, typo, run: run)
          : _buildChat(
              context,
              run: run,
              session: session,
              onOpenActiveRunDetail: showActiveRunDetailDialog,
              onSwitchToWriteMode: session.messages.isNotEmpty
                  ? switchToWriteMode
                  : null,
            ),
    );
  }
}
