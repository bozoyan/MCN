// 职责: 桌面端小剧场台词流 — 已完成台词、导演指令、流式生成中的台词与中断错误，跟随滚动但尊重用户手动上滑。
// 关联文件:
//   lib/desktop/features/theater/performance_section.dart
//   lib/desktop/features/theater/line_card.dart
//   lib/shared/widgets/ai/theater_direction_note.dart
//   lib/shared/widgets/ai/user_respecting_auto_scroll_controller.dart
import 'package:flutter/material.dart';

import '../../../shared/agent/agent_run_state.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/theater_models.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/ai/ai_mode_error_notice.dart';
import '../../../shared/widgets/ai/theater_direction_note.dart';
import '../../../shared/widgets/ai/user_respecting_auto_scroll_controller.dart';
import 'line_card.dart';

class TheaterLineList extends StatefulWidget {
  final TheaterSession session;
  final AgentRunState? activeRun;
  final Map<String, AgentRunState> runHistory;
  final Future<void> Function(String title) onOpenActiveRunDetail;

  /// 改写历史的操作；表演进行中为 null。
  final void Function(TheaterLine line)? onRegenerate;
  final void Function(String lineId)? onRewindAfter;
  final void Function(String lineId)? onRemoveDirection;

  const TheaterLineList({
    super.key,
    required this.session,
    required this.activeRun,
    required this.runHistory,
    required this.onOpenActiveRunDetail,
    this.onRegenerate,
    this.onRewindAfter,
    this.onRemoveDirection,
  });

  @override
  State<TheaterLineList> createState() => _TheaterLineListState();
}

class _TheaterLineListState extends State<TheaterLineList> {
  final _autoScroll = UserRespectingAutoScrollController();

  @override
  void didUpdateWidget(covariant TheaterLineList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _autoScroll.resumeFollow();
    }
    // 用户点「开演」→ 恢复跟随。phase 在整场演出期间保持 performing，
    // 不会在逐条台词生成时反复触发。
    if (!oldWidget.session.isActive && widget.session.isActive) {
      _autoScroll.resumeFollow();
    }
    final countChanged =
        oldWidget.session.lines.length != widget.session.lines.length;
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

  TheaterParticipant _participantFor(String characterId, String name) {
    return widget.session.participants.firstWhere(
      (p) => p.characterId == characterId,
      orElse: () => TheaterParticipant(
        characterId: characterId,
        name: name,
        role: '',
        biography: '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.session.lines;
    final run = widget.activeRun;
    final failure = widget.session.failure;
    final hasError =
        widget.session.phase == TheaterPhase.error && failure != null;
    final removeDirection = widget.onRemoveDirection;
    final regenerate = widget.onRegenerate;
    final rewindAfter = widget.onRewindAfter;

    return NotificationListener<ScrollNotification>(
      onNotification: _autoScroll.handleScrollNotification,
      child: ListView.builder(
        controller: _autoScroll.scrollController,
        padding: const EdgeInsets.all(RevericSpacing.lg),
        itemCount: lines.length + (run != null ? 1 : 0) + (hasError ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < lines.length) {
            final line = lines[index];
            if (line.isDirection) {
              return TheaterDirectionNote(
                line: line,
                onRemove: removeDirection == null
                    ? null
                    : () => removeDirection(line.id),
              );
            }
            return TheaterLineCard(
              line: line,
              participant: _participantFor(
                line.characterId,
                line.characterName,
              ),
              completedRun: widget.runHistory[line.id],
              onRegenerate: regenerate == null ? null : () => regenerate(line),
              onRewindAfter: rewindAfter == null || index == lines.length - 1
                  ? null
                  : () => rewindAfter(line.id),
            );
          }
          if (run != null && index == lines.length) {
            final participant = _participantFor(run.agentId, run.agentName);
            return TheaterStreamingLineCard(
              run: run,
              participant: participant,
              onOpenDetail: () =>
                  widget.onOpenActiveRunDetail(participant.name),
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
