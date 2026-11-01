// 职责: 桌面端小剧场面板 — 组装头部、选角配置与表演区；运行状态与操作全部来自共享的 useTheaterRun。
// 关联文件:
//   lib/shared/hooks/use_theater_run.dart
//   lib/desktop/features/theater/setup_section.dart
//   lib/desktop/features/theater/performance_section.dart
//   lib/desktop/widgets/ai/shared/ai_panel_header.dart
//   lib/desktop/pages/novel_editor_agent_mode_area.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/directory-structure.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/agent/agent_run_state.dart';
import '../../../shared/hooks/use_theater_run.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/providers/theater_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/ai/agent_round_detail_dialog.dart';
import '../../../shared/widgets/app_background.dart';
import '../../widgets/ai/chat/config_hint.dart';
import '../../widgets/ai/chat/panel.dart';
import '../../widgets/ai/model/mode_model_selector.dart';
import '../../widgets/ai/shared/ai_panel_header.dart';
import 'performance_section.dart';
import 'setup_section.dart';

class TheaterPanel extends HookConsumerWidget {
  final VoidCallback? onClose;
  final Future<void> Function(String sessionId)? onSwitchToWriteMode;
  final Future<void> Function(AiChatHandoffDraft draft)?
  onDraftHandoffToWriteMode;
  final String? novelId;
  final String? novelName;
  final String? chapterTitle;
  final String? workspaceContent;
  final String? databasePath;
  final String? initialSessionId;

  /// 由 chat 的下一步建议跳转带入的场景种子，用于预填场景输入框。
  final String? initialScene;
  final ValueChanged<String>? onActiveSessionIdChanged;

  const TheaterPanel({
    super.key,
    this.onClose,
    this.onSwitchToWriteMode,
    this.onDraftHandoffToWriteMode,
    this.novelId,
    this.novelName,
    this.chapterTitle,
    this.workspaceContent,
    this.databasePath,
    this.initialSessionId,
    this.initialScene,
    this.onActiveSessionIdChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final appBackgroundActive = ref.watch(appBackgroundActiveProvider);
    final isConfigured = ref.watch(isAiConfiguredProvider);
    final run = useTheaterRun(
      ref,
      novelId: novelId,
      databasePath: databasePath,
      novelName: novelName,
      chapterTitle: chapterTitle,
      workspaceContent: workspaceContent,
      initialSessionId: initialSessionId,
      initialScene: initialScene,

      onActiveSessionIdChanged: onActiveSessionIdChanged,
    );
    final session = run.session;

    /// [instruction] 为写成正文的指令，随交接自动发送；只带剧本时为 null。
    Future<void> switchToWriteMode(String? instruction) async {
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
            initialText: instruction,
            autoSend: instruction != null,
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
            final liveRun = ref.watch(theaterActiveRunProvider(run.sessionId));
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
            icon: RevericIcons.theater_comedy_rounded,
            title: context.t(LocaleKeys.aiSessionModeTheater),
            subtitle: session?.participants.map((p) => p.name).join('、'),
            gradientColors: [colors.accentWarm, colors.accent],
            onNewSession: session != null && session.lines.isNotEmpty
                ? run.startNew
                : null,
            newSessionTooltip: context.t(LocaleKeys.theaterNew),
            onClose: onClose,
          ),
          Divider(height: 1, color: colors.border),
          if (!isConfigured)
            const ChatConfigHint()
          else
            Expanded(
              child: session == null
                  ? TheaterSetupSection(run: run, modelSelector: modelSelector)
                  : TheaterPerformanceSection(
                      run: run,
                      session: session,
                      modelSelector: modelSelector,
                      onOpenActiveRunDetail: showActiveRunDetailDialog,
                      onSwitchToWriteMode: session.lines.isNotEmpty
                          ? switchToWriteMode
                          : null,
                    ),
            ),
        ],
      ),
    );
  }
}
