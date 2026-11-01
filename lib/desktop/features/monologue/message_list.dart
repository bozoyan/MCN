// 职责: 桌面端独白消息流 — 逐条渲染已生成独白，生成中在末尾挂同款卡片，出错时追加中断提示，并跟随滚动。
// 关联文件:
//   lib/desktop/features/monologue/session_section.dart
//   lib/shared/widgets/ai/agent_message_card.dart
//   lib/shared/widgets/ai/monologue_body.dart
//   lib/shared/widgets/ai/user_respecting_auto_scroll_controller.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'package:flutter/material.dart';

import '../../../shared/agent/agent_run_state.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/monologue_models.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/ai/agent_message_card.dart';
import '../../../shared/widgets/ai/agent_round_detail_dialog.dart';
import '../../../shared/widgets/ai/ai_mode_error_notice.dart';
import '../../../shared/widgets/ai/monologue_body.dart';
import '../../../shared/widgets/ai/user_respecting_auto_scroll_controller.dart';
import '../../../shared/widgets/character_avatar.dart';

const _density = AgentMessageDensity.panel;

class MonologueMessageList extends StatefulWidget {
  const MonologueMessageList({
    super.key,
    required this.session,
    required this.activeRun,
    required this.runHistory,
    required this.onOpenActiveRunDetail,
  });

  final MonologueSession session;
  final AgentRunState? activeRun;
  final Map<String, AgentRunState> runHistory;
  final Future<void> Function(String title) onOpenActiveRunDetail;

  @override
  State<MonologueMessageList> createState() => _MonologueMessageListState();
}

class _MonologueMessageListState extends State<MonologueMessageList> {
  final _autoScroll = UserRespectingAutoScrollController();

  @override
  void didUpdateWidget(covariant MonologueMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _autoScroll.resumeFollow();
    }
    // 用户点「生成」→ 恢复跟随。phase 在整段生成期间保持 generating，
    // 不会在流式过程中反复触发。
    if (!oldWidget.session.isActive && widget.session.isActive) {
      _autoScroll.resumeFollow();
    }
    final countChanged =
        oldWidget.session.monologues.length != widget.session.monologues.length;
    final streamingChanged =
        oldWidget.activeRun?.accumulatedText !=
            widget.activeRun?.accumulatedText ||
        oldWidget.activeRun?.blocks.length != widget.activeRun?.blocks.length ||
        (oldWidget.activeRun == null) != (widget.activeRun == null);
    final errorChanged = oldWidget.session.failure != widget.session.failure;
    if (countChanged || streamingChanged || errorChanged) {
      _autoScroll.scheduleScrollToBottom(streaming: widget.activeRun != null);
    }
  }

  @override
  void dispose() {
    _autoScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monologues = widget.session.monologues;
    // 生成中但还没收到首个 delta 时也显示同一张卡片（跳动三点），不另起占位组件。
    final showPending =
        widget.activeRun != null ||
        widget.session.phase == MonologuePhase.generating;
    final failure = widget.session.failure;
    final hasError =
        widget.session.phase == MonologuePhase.error && failure != null;

    return NotificationListener<ScrollNotification>(
      onNotification: _autoScroll.handleScrollNotification,
      child: ListView.builder(
        controller: _autoScroll.scrollController,
        padding: const EdgeInsets.all(RevericSpacing.lg),
        itemCount:
            monologues.length + (showPending ? 1 : 0) + (hasError ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < monologues.length) {
            final monologue = monologues[index];
            return _MonologueCard(
              monologue: monologue,
              character: widget.session.character,
              completedRun: widget.runHistory[monologue.id],
            );
          }
          if (showPending && index == monologues.length) {
            final run = widget.activeRun;
            final character = widget.session.character;
            return _MonologueMessageCard(
              character: character,
              thinking: run?.accumulatedThinking ?? '',
              streaming: true,
              onOpenDetail: run == null
                  ? null
                  : () => widget.onOpenActiveRunDetail(character.name),
              body: run == null
                  ? null
                  : MonologueBody.streaming(run.accumulatedText, _density),
            );
          }
          return AiModeErrorNotice(
            title: context.t(LocaleKeys.aiRunInterrupted),
            failure: failure!,
          );
        },
      ),
    );
  }
}

/// 独白卡片外壳：生成中与生成完成共用，避免完成瞬间排版跳变。
class _MonologueMessageCard extends StatelessWidget {
  const _MonologueMessageCard({
    required this.character,
    required this.thinking,
    required this.body,
    this.streaming = false,
    this.onOpenDetail,
  });

  final MonologueParticipant character;
  final String thinking;
  final Widget? body;
  final bool streaming;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return AgentMessageCard(
      avatar: CharacterAvatar(
        avatarAssetId: character.avatarAssetId,
        fallbackName: character.name,
        size: AgentMessageCard.avatarSize(_density),
        backgroundColor: colors.accent.withValues(alpha: 0.15),
      ),
      name: character.name,
      accentColor: colors.accent,
      density: _density,
      thinking: thinking,
      streaming: streaming,
      onOpenDetail: onOpenDetail,
      body: body,
    );
  }
}

class _MonologueCard extends StatelessWidget {
  const _MonologueCard({
    required this.monologue,
    required this.character,
    this.completedRun,
  });

  final MonologueEntry monologue;
  final MonologueParticipant character;
  final AgentRunState? completedRun;

  @override
  Widget build(BuildContext context) {
    final detailRun =
        completedRun ??
        AgentRunState(
          agentId: monologue.characterId,
          agentName: monologue.characterName,
          round: 1,
          accumulatedText: [
            if (monologue.innerThoughts.isNotEmpty) monologue.innerThoughts,
            if (monologue.plannedActions.isNotEmpty) monologue.plannedActions,
          ].join('\n\n'),
          isComplete: true,
        );
    return _MonologueMessageCard(
      character: character,
      thinking: completedRun?.accumulatedThinking ?? '',
      onOpenDetail: () => AgentRoundDetailDialog.show(
        context,
        runState: detailRun,
        title: character.name,
      ),
      body: MonologueBody(
        innerThoughts: monologue.innerThoughts,
        plannedActions: monologue.plannedActions,
        density: _density,
      ),
    );
  }
}
