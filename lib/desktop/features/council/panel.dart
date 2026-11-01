// 职责: 桌面端议会面板 — 组装头部、议题与成员设置、讨论区；运行状态与操作全部来自共享的 useCouncilRun。
// 关联文件:
//   lib/shared/hooks/use_council_run.dart
//   lib/desktop/features/council/setup_section.dart
//   lib/desktop/features/council/discussion_section.dart
//   lib/desktop/widgets/ai/shared/ai_panel_header.dart
//   lib/desktop/pages/novel_editor_agent_mode_area.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/directory-structure.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/agent/agent_run_state.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/database/app_database.dart' show Novel;
import '../../../shared/hooks/use_council_run.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/agent_council_models.dart';
import '../../../shared/providers/agent_council_providers.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/ai/agent_round_detail_dialog.dart';
import '../../../shared/widgets/app_background.dart';
import '../../widgets/ai/chat/config_hint.dart';
import '../../widgets/ai/chat/panel.dart';
import '../../widgets/ai/model/mode_model_selector.dart';
import '../../widgets/ai/shared/ai_panel_header.dart';
import 'discussion_section.dart';
import 'setup_section.dart';

String? _phaseSubtitle(BuildContext context, AgentCouncilSession? session) {
  if (session == null) return null;
  return switch (session.phase) {
    CouncilPhase.idle => context.t(LocaleKeys.councilPhasePreparing),
    CouncilPhase.discussing => context.t(
      LocaleKeys.councilPhaseDiscussingFmt,
      namedArgs: {
        'round': '${session.rounds.length}',
        'count': '${session.participants.length}',
      },
    ),
    CouncilPhase.summarizing => context.t(LocaleKeys.councilPhaseSummarizing),
    CouncilPhase.completed => context.t(
      LocaleKeys.councilPhaseCompletedFmt,
      namedArgs: {'count': '${session.rounds.length}'},
    ),
    CouncilPhase.cancelled => context.t(LocaleKeys.councilPhaseCancelled),
    CouncilPhase.error => context.t(LocaleKeys.councilPhaseError),
  };
}

class AgentCouncilPanel extends HookConsumerWidget {
  final VoidCallback? onClose;
  final Future<void> Function(String sessionId)? onSwitchToWriteMode;
  final Future<void> Function(AiChatHandoffDraft draft)?
  onDraftHandoffToWriteMode;
  final Novel novel;
  final String? databasePath;
  final String? initialSessionId;

  /// 由 chat 的下一步建议跳转带入的议题种子，用于预填议题输入框。
  final String? initialTopic;
  final ValueChanged<String?>? onActiveSessionIdChanged;

  const AgentCouncilPanel({
    super.key,
    this.onClose,
    this.onSwitchToWriteMode,
    this.onDraftHandoffToWriteMode,
    required this.novel,
    this.databasePath,
    this.initialSessionId,
    this.initialTopic,
    this.onActiveSessionIdChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final appBackgroundActive = ref.watch(appBackgroundActiveProvider);
    final isConfigured = ref.watch(isAiConfiguredProvider);
    final run = useCouncilRun(
      ref,
      novel: novel,
      databasePath: databasePath,
      initialSessionId: initialSessionId,
      initialTopic: initialTopic,

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

    void showActiveRunDetailDialog(String title) {
      showRevericDialog<void>(
        context: context,
        builder: (dialogContext) => Consumer(
          builder: (dialogContext, ref, _) {
            final liveRun = ref.watch(
              agentCouncilActiveRunProvider(run.sessionId),
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
              novelId: novel.id,
            );
          },
        ),
      );
    }

    final modelSelector = AiModeModelSelector(models: run.models);

    return Container(
      color: appChromeBackgroundColor(
        colors,
        appBackgroundActive,
        colors.surfaceContainerHigh,
      ),
      child: Column(
        children: [
          AiPanelHeader(
            icon: RevericIcons.groups_outlined,
            title: context.t(LocaleKeys.aiSessionModeCouncil),
            subtitle: _phaseSubtitle(context, session),
            onNewSession: session != null && session.rounds.isNotEmpty
                ? run.startNew
                : null,
            newSessionTooltip: context.t(LocaleKeys.councilNewDiscussion),
            onClose: onClose,
          ),
          Divider(height: 1, color: colors.border),
          if (!isConfigured)
            const ChatConfigHint()
          else
            Expanded(
              child: session == null
                  ? CouncilSetupSection(run: run, modelSelector: modelSelector)
                  : CouncilDiscussionSection(
                      run: run,
                      session: session,
                      modelSelector: modelSelector,
                      databasePath: databasePath,
                      novelId: novel.id,
                      onOpenActiveRunDetail: showActiveRunDetailDialog,
                      onSwitchToWriteMode: session.rounds.isNotEmpty
                          ? switchToWriteMode
                          : null,
                    ),
            ),
        ],
      ),
    );
  }
}
