// 职责: 议会讨论时间线 — 按轮次分组的发言、正在生成的发言、总结与失败提示，带尊重用户回看的自动跟随，桌面面板与移动页共用。
// 关联文件:
//   lib/shared/widgets/ai/council/message_card.dart
//   lib/shared/widgets/ai/council/summary_card.dart
//   lib/shared/widgets/ai/council/participant.dart
//   lib/shared/widgets/ai/user_respecting_auto_scroll_controller.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'package:flutter/material.dart';

import '../../../agent/agent_run_state.dart';
import '../../../components/reveric_surfaces.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../models/agent_council_models.dart';
import '../../../theme/theme.dart';
import '../agent_message_card.dart';
import '../ai_mode_error_notice.dart';
import '../user_respecting_auto_scroll_controller.dart';
import 'message_card.dart';
import 'participant.dart';
import 'summary_card.dart';

class CouncilTimeline extends StatefulWidget {
  const CouncilTimeline({
    super.key,
    required this.session,
    required this.activeRun,
    required this.runHistory,
    required this.density,
    required this.onOpenActiveRunDetail,
    this.queuedMessageIds = const {},
    this.databasePath,
    this.novelId,
    this.onRegenerate,
    this.onRewindAfter,
    this.onRemove,
  });

  final AgentCouncilSession session;
  final AgentRunState? activeRun;
  final Map<String, AgentRunState> runHistory;
  final AgentMessageDensity density;
  final void Function(String title) onOpenActiveRunDetail;

  /// 讨论中插入、还没并入的插话，排在正在生成的发言之后，与最终落盘顺序一致。
  final Set<String> queuedMessageIds;
  final String? databasePath;
  final String? novelId;

  /// 改写历史；讨论进行中传 null。
  final void Function(CouncilMessage message)? onRegenerate;
  final void Function(String messageId)? onRewindAfter;
  final void Function(String messageId)? onRemove;

  @override
  State<CouncilTimeline> createState() => _CouncilTimelineState();
}

int _messageCount(AgentCouncilSession session) =>
    session.rounds.fold(0, (sum, r) => sum + r.messages.length);

class _CouncilTimelineState extends State<CouncilTimeline> {
  final _autoScroll = UserRespectingAutoScrollController();

  @override
  void didUpdateWidget(covariant CouncilTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final session = widget.session;
    final old = oldWidget.session;
    if (old.id != session.id) {
      _autoScroll.resumeFollow();
    }
    final messageCountChanged = _messageCount(old) != _messageCount(session);
    // 用户发起新一轮 / 自己插话 → 恢复跟随，否则回看历史时看不到自己触发的内容。
    // phase 在整轮讨论期间保持 active，不会在轮内逐个成员发言时反复触发。
    if ((!old.isActive && session.isActive) ||
        (messageCountChanged &&
            session.rounds.lastOrNull?.messages.lastOrNull?.isUser == true)) {
      _autoScroll.resumeFollow();
    }
    final streamingChanged =
        oldWidget.activeRun?.accumulatedText !=
            widget.activeRun?.accumulatedText ||
        oldWidget.activeRun?.blocks.length != widget.activeRun?.blocks.length;
    final phaseChanged =
        old.phase != session.phase ||
        old.summary != session.summary ||
        old.failure != session.failure;
    if (messageCountChanged || streamingChanged || phaseChanged) {
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
    final session = widget.session;
    final density = widget.density;
    final isSummarizing = session.phase == CouncilPhase.summarizing;
    // 总结阶段不再展示发言卡片（成员已结束发言）。
    final run = isSummarizing ? null : widget.activeRun;
    final rounds = session.rounds;
    final summary = session.summary;
    final lastRoundNumber = rounds.lastOrNull?.roundNumber ?? 0;
    // 一轮的 CouncilRound 要等首位成员说完才创建；在那之前流式卡片单独成一轮，
    // 否则首位成员说完前面板一片空白，用户以为卡住了。
    final streamingInNewRound = run != null && run.round > lastRoundNumber;

    Widget streamingCard(AgentRunState run) {
      final participant = councilParticipantFor(
        session,
        run.agentId,
        run.agentName,
      );
      return CouncilStreamingCard(
        run: run,
        participant: participant,
        density: density,
        onOpenDetail: () =>
            widget.onOpenActiveRunDetail(participant.resolveName(context.t)),
      );
    }

    Widget roundSection(CouncilRound round, {Widget? streaming}) {
      return _RoundSection(
        round: round,
        session: session,
        runHistory: widget.runHistory,
        density: density,
        databasePath: widget.databasePath,
        novelId: widget.novelId,
        streaming: streaming,
        queuedMessageIds: widget.queuedMessageIds,
        onRegenerate: widget.onRegenerate,
        onRewindAfter: widget.onRewindAfter,
        onRemove: widget.onRemove,
      );
    }

    final summaryCard = summary == null
        ? null
        : CouncilSummaryCard(
            summary: summary,
            isOutdated: session.hasOutdatedSummary,
          );
    // 总结跟在它覆盖到的那一轮后面；对应轮次不在了（旧数据）就放到最后。
    final summaryRoundShown = rounds.any(
      (r) => r.roundNumber == summary?.coveredThroughRound,
    );
    final children = <Widget>[
      for (final round in rounds) ...[
        roundSection(
          round,
          streaming: run != null && !streamingInNewRound && round == rounds.last
              ? streamingCard(run)
              : null,
        ),
        if (round.roundNumber == summary?.coveredThroughRound) ?summaryCard,
      ],
      if (run != null && streamingInNewRound)
        roundSection(
          CouncilRound(roundNumber: run.round, messages: const []),
          streaming: streamingCard(run),
        ),
      if (isSummarizing) const CouncilSummaryPending(),
      if (!summaryRoundShown) ?summaryCard,
    ];
    final failure = session.failure;
    if (failure != null) {
      children.add(
        AiModeErrorNotice(
          title: context.t(LocaleKeys.aiRunInterrupted),
          failure: failure,
        ),
      );
    }

    final mobile = density == AgentMessageDensity.mobile;
    return NotificationListener<ScrollNotification>(
      onNotification: _autoScroll.handleScrollNotification,
      child: ListView(
        controller: _autoScroll.scrollController,
        padding: EdgeInsets.fromLTRB(
          mobile ? RevericSpacing.lg : RevericSpacing.x2l,
          RevericSpacing.lg,
          mobile ? RevericSpacing.lg : RevericSpacing.x2l,
          RevericSpacing.x2l,
        ),
        children: children,
      ),
    );
  }
}

/// 一轮的卡片：轮次标签 + 本轮发言者头像 + 各条发言，末尾挂正在生成的发言。
class _RoundSection extends StatelessWidget {
  const _RoundSection({
    required this.round,
    required this.session,
    required this.runHistory,
    required this.density,
    this.databasePath,
    this.novelId,
    this.streaming,
    this.queuedMessageIds = const {},
    this.onRegenerate,
    this.onRewindAfter,
    this.onRemove,
  });

  final CouncilRound round;
  final AgentCouncilSession session;
  final Map<String, AgentRunState> runHistory;
  final AgentMessageDensity density;
  final String? databasePath;
  final String? novelId;
  final Widget? streaming;
  final Set<String> queuedMessageIds;
  final void Function(CouncilMessage message)? onRegenerate;
  final void Function(String messageId)? onRewindAfter;
  final void Function(String messageId)? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final mobile = density == AgentMessageDensity.mobile;
    final speakers = <String, CouncilParticipant>{
      for (final m in round.messages)
        if (!m.isUser)
          m.participantId: councilParticipantFor(
            session,
            m.participantId,
            m.participantName,
          ),
    };

    // 只有正在生成时才需要把排队的插话挪到后面。
    bool queued(CouncilMessage message) =>
        streaming != null && queuedMessageIds.contains(message.id);
    Widget card(CouncilMessage message) => CouncilMessageCard(
      message: message,
      participant: councilParticipantFor(
        session,
        message.participantId,
        message.participantName,
      ),
      density: density,
      completedRun: runHistory[message.id],
      databasePath: databasePath,
      novelId: novelId,
      onRegenerate: message.isUser || onRegenerate == null
          ? null
          : () => onRegenerate!(message),
      onRewindAfter: onRewindAfter == null
          ? null
          : () => onRewindAfter!(message.id),
      onRemove: message.isUser && onRemove != null
          ? () => onRemove!(message.id)
          : null,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.md,
                vertical: RevericSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: mobile ? colors.surface : colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(RevericRadius.pill),
              ),
              child: Text(
                context.t(
                  LocaleKeys.councilRoundLabelFmt,
                  namedArgs: {'round': '${round.roundNumber}'},
                ),
                style: typo.uiTiny.copyWith(
                  color: colors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: RevericSpacing.xxs,
                runSpacing: RevericSpacing.xxs,
                children: [
                  for (final speaker in speakers.values)
                    CouncilParticipantAvatar(participant: speaker, size: 20),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.lg),
        for (final message in round.messages)
          if (!queued(message)) card(message),
        ?streaming,
        for (final message in round.messages)
          if (queued(message)) card(message),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.lg),
      child: mobile
          ? Container(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.lg,
                RevericSpacing.lg,
                RevericSpacing.lg,
                0,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceDim,
                borderRadius: BorderRadius.circular(RevericRadius.x2l),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: content,
            )
          : RevericElevatedCard(
              fallback: colors.surfaceDim,
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x2l,
                RevericSpacing.x2l,
                RevericSpacing.x2l,
                RevericSpacing.md,
              ),
              child: content,
            ),
    );
  }
}
