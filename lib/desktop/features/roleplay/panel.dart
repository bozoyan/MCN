// 职责: 桌面端角色扮演面板 — 组装头部、选角区与对话区；运行状态与操作全部来自共享的 useRoleplayRun。
// 关联文件:
//   lib/shared/hooks/use_roleplay_run.dart
//   lib/desktop/features/roleplay/setup_section.dart
//   lib/desktop/features/roleplay/message_list.dart
//   lib/desktop/features/roleplay/composer.dart
//   lib/desktop/pages/novel_editor_agent_mode_area.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/roleplay.json
//   assets/translations/zh-CN/roleplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/directory-structure.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/agent/agent_run_state.dart';
import '../../../shared/hooks/use_roleplay_run.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/roleplay_providers.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/ai/agent_round_detail_dialog.dart';
import '../../../shared/widgets/app_background.dart';
import '../../widgets/ai/chat/config_hint.dart';
import '../../widgets/ai/chat/panel.dart';
import '../../widgets/ai/shared/ai_panel_header.dart';
import 'composer.dart';
import 'message_list.dart';
import 'setup_section.dart';

class RoleplayPanel extends HookConsumerWidget {
  final VoidCallback? onClose;
  final Future<void> Function(String sessionId)? onSwitchToWriteMode;
  final Future<void> Function(AiChatHandoffDraft draft)?
  onDraftHandoffToWriteMode;
  final String? novelId;
  final String? novelName;
  final String? chapterTitle;
  final String? workspaceContent;
  final String? databasePath;
  final String? initialCharacterId;
  final String? initialSessionId;
  final ValueChanged<String>? onActiveSessionIdChanged;

  const RoleplayPanel({
    super.key,
    this.onClose,
    this.onSwitchToWriteMode,
    this.onDraftHandoffToWriteMode,
    this.novelId,
    this.novelName,
    this.chapterTitle,
    this.workspaceContent,
    this.databasePath,
    this.initialCharacterId,
    this.initialSessionId,
    this.onActiveSessionIdChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final appBackgroundActive = ref.watch(appBackgroundActiveProvider);
    final isConfigured = ref.watch(isAiConfiguredProvider);
    final run = useRoleplayRun(
      ref,
      novelId: novelId,
      databasePath: databasePath,
      novelName: novelName,
      chapterTitle: chapterTitle,
      workspaceContent: workspaceContent,
      initialSessionId: initialSessionId,
      initialCharacterId: initialCharacterId,

      onActiveSessionIdChanged: onActiveSessionIdChanged,
    );
    final session = run.session;

    Future<void> switchToWriteMode() async {
      final draftHandoff = onDraftHandoffToWriteMode;
      final handoff = await run.handoff(
        createTargetSession: draftHandoff == null,
      );
      if (handoff == null || !context.mounted) return;
      if (draftHandoff != null) {
        await draftHandoff(
          AiChatHandoffDraft(
            id: '__handoff_draft__${handoff.sourceSessionId}_${DateTime.now().microsecondsSinceEpoch}',
            label: handoff.sourceTitle,
            content: handoff.context.toMessageContent(),
            title: handoff.chatTitle,
          ),
        );
        return;
      }
      final targetSessionId = handoff.targetSessionId;
      if (targetSessionId != null) {
        await onSwitchToWriteMode?.call(targetSessionId);
      }
    }

    Future<void> showActiveRunDetailDialog(String title) async {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Consumer(
          builder: (dialogContext, ref, _) {
            final liveRun = ref.watch(roleplayActiveRunProvider(run.sessionId));
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
        ),
      );
    }

    return Container(
      color: appChromeBackgroundColor(
        colors,
        appBackgroundActive,
        colors.surfaceContainerHigh,
      ),
      child: Column(
        children: [
          AiPanelHeader(
            icon: RevericIcons.mask_happy_rounded,
            title: context.t(LocaleKeys.aiSessionModeRoleplay),
            subtitle: session?.character.name,
            gradientColors: [colors.accentWarm, colors.accent],
            onNewSession: session != null && session.messages.isNotEmpty
                ? run.startNew
                : null,
            newSessionTooltip: context.t(LocaleKeys.roleplayNew),
            onClose: onClose,
          ),
          Divider(height: 1, color: colors.border),
          if (!isConfigured)
            const ChatConfigHint()
          else
            Expanded(
              child: session == null
                  ? RoleplaySetupSection(run: run)
                  : Column(
                      children: [
                        Expanded(
                          child: RoleplayMessageList(
                            session: session,
                            activeRun: run.activeRun,
                            runHistory: run.runHistory,
                            userName: run.userName,
                            userAvatarPath: run.userAvatarPath,
                            onOpenActiveRunDetail: showActiveRunDetailDialog,
                            databasePath: databasePath,
                            novelId: novelId,
                          ),
                        ),
                        RoleplayComposer(
                          run: run,
                          characterName: session.character.name,
                          onSwitchToWriteMode: session.messages.isNotEmpty
                              ? switchToWriteMode
                              : null,
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
