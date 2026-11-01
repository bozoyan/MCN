// 职责: 单大纲架构视图 — 展示节拍卡片的交错/单列自适应布局，支持编辑、删除与拖拽排序。
// 关联文件:
//   lib/desktop/widgets/workspace/outline_global_view.dart
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/desktop/widgets/workspace/outline_editor.dart
//   lib/desktop/widgets/workspace/outline_beat_dialog.dart
//   lib/shared/models/ai_shortcut_action.dart
//   lib/shared/models/outline.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/agent_shortcut.json
//   assets/translations/zh-CN/agent_shortcut.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../shared/components/reveric_context_menu.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/ai_shortcut_action.dart';
import '../../../shared/models/outline.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';
import 'outline_beat_chips.dart';
import 'outline_beat_dialog.dart';

class OutlineArchitectureView extends StatelessWidget {
  const OutlineArchitectureView({
    super.key,
    required this.draft,
    required this.onAddBeat,
    required this.onEditBeat,
    required this.onDeleteBeat,
    this.beatShortcutActions = const <AiShortcutActionDefinition>[],
    this.onRunShortcutAction,
    required this.onReorderBeats,
  });

  final OutlineDraft draft;
  final VoidCallback onAddBeat;
  final ValueChanged<int> onEditBeat;
  final ValueChanged<int> onDeleteBeat;
  final List<AiShortcutActionDefinition> beatShortcutActions;
  final ValueChanged<AiShortcutActionDefinition>? onRunShortcutAction;
  final void Function(int oldIndex, int newIndex) onReorderBeats;

  @override
  Widget build(BuildContext context) {
    final beats = draft.beats;
    if (beats.isEmpty) {
      return _ArchitectureEmptyState(onAdd: onAddBeat);
    }

    final chapterStarts = <int>[0];
    for (final beat in beats) {
      chapterStarts.add(chapterStarts.last + beat.chapterCount);
    }
    // 大纲轨道可从任意绝对章节起始，节拍章节区间需整体偏移。
    final chapterOffset =
        (draft.startChapterNum < 1 ? 1 : draft.startChapterNum) - 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 交错双栏下单卡宽 ≈ (width - 内边距 32 - rail 40) / 2；600 时约 264，
        // 是 chip 行 + 两行标题仍可读的下限，再窄才退回单列。
        final singleColumn = width < 600;
        final compact = width < 840;
        final contentWidth = width.clamp(0.0, 1288.0).toDouble();
        final horizontalPadding = singleColumn
            ? RevericSpacing.xl
            : compact
            ? RevericSpacing.x2l
            : RevericSpacing.x3l;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            RevericSpacing.x4l,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ArchitectureSummary(beats: beats),
                  const SizedBox(height: RevericSpacing.x3l),
                  _ArchitectureIntro(beats: beats),
                  const SizedBox(height: RevericSpacing.x3l),
                  _ArchitectureSpine(
                    beats: beats,
                    chapterStarts: chapterStarts,
                    chapterOffset: chapterOffset,
                    singleColumn: singleColumn,
                    compact: compact,
                    onEditBeat: onEditBeat,
                    onDeleteBeat: onDeleteBeat,
                    beatShortcutActions: beatShortcutActions,
                    onRunShortcutAction: onRunShortcutAction,
                    onReorderBeats: onReorderBeats,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ArchitectureSummary extends StatelessWidget {
  const _ArchitectureSummary({required this.beats});

  final List<OutlineBeatDraft> beats;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final total = beats.length;
    final finished = _countStatus(beats, outlineStatusFinished);
    final writing = _countStatus(beats, outlineStatusInProgress);
    final pending = _countStatus(beats, outlineStatusPending);
    final chapters = beats.fold<int>(0, (sum, beat) => sum + beat.chapterCount);
    final finishedFraction = total == 0 ? 0.0 : finished / total;
    final writingFraction = total == 0 ? 0.0 : writing / total;
    final pendingFraction = total == 0 ? 0.0 : pending / total;

    return Container(
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(RevericRadius.pill),
            child: SizedBox(
              height: RevericSpacing.xs,
              child: Row(
                children: [
                  if (finished > 0)
                    Expanded(
                      flex: _mathFlex(finishedFraction),
                      child: ColoredBox(color: colors.accentWarm),
                    ),
                  if (writing > 0)
                    Expanded(
                      flex: _mathFlex(writingFraction),
                      child: ColoredBox(color: colors.accent),
                    ),
                  if (pending > 0)
                    Expanded(
                      flex: _mathFlex(pendingFraction),
                      child: ColoredBox(color: colors.border),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: RevericSpacing.lg),
          Wrap(
            spacing: RevericSpacing.lg,
            runSpacing: RevericSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SummaryLegend(
                color: statusColor(context, outlineStatusFinished),
                label: statusLabel(context, outlineStatusFinished),
                value: finished,
              ),
              _SummaryLegend(
                color: statusColor(context, outlineStatusInProgress),
                label: statusLabel(context, outlineStatusInProgress),
                value: writing,
              ),
              _SummaryLegend(
                color: statusColor(context, outlineStatusPending),
                label: statusLabel(context, outlineStatusPending),
                value: pending,
              ),
              _SummaryLegend(
                color: colors.textSubtle,
                label: context.t(
                  LocaleKeys.workspaceOutlineArchitectureChapters,
                ),
                value: chapters,
              ),
              _SummaryTotal(total: total),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryLegend extends StatelessWidget {
  const _SummaryLegend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: RevericSpacing.md,
          height: RevericSpacing.md,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: RevericSpacing.xs),
        Text(
          '$label $value',
          style: typo.ui.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _SummaryTotal extends StatelessWidget {
  const _SummaryTotal({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Text(
      context.t(
        LocaleKeys.workspaceOutlineArchitectureTotal,
        namedArgs: {'count': '$total'},
      ),
      style: typo.uiSmallSemibold.copyWith(color: colors.textMuted),
    );
  }
}

class _ArchitectureIntro extends StatelessWidget {
  const _ArchitectureIntro({required this.beats});

  final List<OutlineBeatDraft> beats;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t(LocaleKeys.workspaceOutlineArchitectureTitle),
          style: typo.heading2.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: RevericSpacing.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            context.t(LocaleKeys.workspaceOutlineArchitectureHint),
            style: typo.uiSmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ArchitectureSpine extends StatelessWidget {
  const _ArchitectureSpine({
    required this.beats,
    required this.chapterStarts,
    required this.chapterOffset,
    required this.singleColumn,
    required this.compact,
    required this.onEditBeat,
    required this.onDeleteBeat,
    required this.beatShortcutActions,
    this.onRunShortcutAction,
    required this.onReorderBeats,
  });

  final List<OutlineBeatDraft> beats;
  final List<int> chapterStarts;
  final int chapterOffset;
  final bool singleColumn;
  final bool compact;
  final ValueChanged<int> onEditBeat;
  final ValueChanged<int> onDeleteBeat;
  final List<AiShortcutActionDefinition> beatShortcutActions;
  final ValueChanged<AiShortcutActionDefinition>? onRunShortcutAction;
  final void Function(int oldIndex, int newIndex) onReorderBeats;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final spineAlignment = singleColumn
        ? Alignment.topLeft
        : Alignment.topCenter;
    // 单列模式下 rail 居于左侧（rail 宽度 = x5l=28），其 marker 中心约 14px
    final spineLeftOffset = singleColumn ? RevericSpacing.xl : 0.0;

    return Stack(
      alignment: spineAlignment,
      children: [
        Positioned(
          top: 0,
          bottom: 0,
          left: singleColumn ? spineLeftOffset : null,
          child: Container(
            width: RevericSizes.dividerThickness,
            color: colors.border,
          ),
        ),
        Column(
          children: [
            for (var i = 0; i < beats.length; i++)
              _ArchitectureNode(
                key: ValueKey('${beats[i].id}-$i'),
                beat: beats[i],
                index: i,
                chapterStart: chapterOffset + chapterStarts[i] + 1,
                chapterEnd: chapterOffset + chapterStarts[i + 1],
                alignRight: !singleColumn && i.isOdd,
                singleColumn: singleColumn,
                compact: compact,
                onEdit: () => onEditBeat(i),
                onDelete: () {
                  onDeleteBeat(i);
                },
                shortcutActions: beatShortcutActions,
                onRunShortcutAction: onRunShortcutAction,
                onDropBefore: (from) => onReorderBeats(from, i),
                onDropAfter: (from) => onReorderBeats(from, i + 1),
              ),
          ],
        ),
      ],
    );
  }
}

class _ArchitectureNode extends StatelessWidget {
  const _ArchitectureNode({
    super.key,
    required this.beat,
    required this.index,
    required this.chapterStart,
    required this.chapterEnd,
    required this.alignRight,
    required this.singleColumn,
    required this.compact,
    required this.onEdit,
    required this.onDelete,
    required this.shortcutActions,
    this.onRunShortcutAction,
    required this.onDropBefore,
    required this.onDropAfter,
  });

  final OutlineBeatDraft beat;
  final int index;
  final int chapterStart;
  final int chapterEnd;
  final bool alignRight;
  final bool singleColumn;
  final bool compact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final List<AiShortcutActionDefinition> shortcutActions;
  final ValueChanged<AiShortcutActionDefinition>? onRunShortcutAction;
  final ValueChanged<int> onDropBefore;
  final ValueChanged<int> onDropAfter;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final beatColor = beatSequenceColor(context, index);
    final card = _DraggableArchitectureCard(
      index: index,
      child: _ArchitectureBeatCard(
        beat: beat,
        index: index,
        chapterStart: chapterStart,
        chapterEnd: chapterEnd,
        compact: compact,
        onEdit: onEdit,
        onDelete: onDelete,
        shortcutActions: shortcutActions,
        onRunShortcutAction: onRunShortcutAction,
      ),
    );

    final markerOuter = singleColumn
        ? RevericSpacing.x3l
        : RevericSpacing.x4l;
    final markerInner = singleColumn ? RevericSpacing.sm : RevericSpacing.md;
    final railWidth = singleColumn ? RevericSpacing.x5l : RevericSpacing.x6l;

    final marker = SizedBox(
      width: railWidth,
      child: Center(
        child: Container(
          width: markerOuter,
          height: markerOuter,
          decoration: BoxDecoration(
            color: colors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: beatColor, width: 2),
          ),
          child: Center(
            child: Container(
              width: markerInner,
              height: markerInner,
              decoration: BoxDecoration(
                color: beatColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );

    final Row row;
    if (singleColumn) {
      row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          marker,
          const SizedBox(width: RevericSpacing.sm),
          Expanded(child: card),
        ],
      );
    } else {
      row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!alignRight) Expanded(child: card) else const Spacer(),
          marker,
          if (alignRight) Expanded(child: card) else const Spacer(),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: singleColumn ? RevericSpacing.xxs : RevericSpacing.sm,
      ),
      child: Column(
        children: [
          _DropBand(onAccept: onDropBefore),
          row,
          _DropBand(onAccept: onDropAfter),
        ],
      ),
    );
  }
}

class _ArchitectureBeatCard extends HookWidget {
  const _ArchitectureBeatCard({
    required this.beat,
    required this.index,
    required this.chapterStart,
    required this.chapterEnd,
    required this.compact,
    required this.onEdit,
    required this.onDelete,
    required this.shortcutActions,
    this.onRunShortcutAction,
  });

  final OutlineBeatDraft beat;
  final int index;
  final int chapterStart;
  final int chapterEnd;
  final bool compact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final List<AiShortcutActionDefinition> shortcutActions;
  final ValueChanged<AiShortcutActionDefinition>? onRunShortcutAction;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final hovered = useState(false);
    final menuOpen = useState(false);
    final title = shortOutlineBeatTitle(beat.title).isEmpty
        ? context.t(LocaleKeys.workspaceOutlineUntitledBeat)
        : shortOutlineBeatTitle(beat.title);
    final chapterRange = context.t(
      LocaleKeys.workspaceOutlineBeatChapterRange,
      namedArgs: {'start': '$chapterStart', 'end': '$chapterEnd'},
    );

    final cardPadding = compact ? RevericSpacing.x2l : RevericSpacing.x3l;

    return Tooltip(
      message: context.t(LocaleKeys.commonEdit),
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) {
          hovered.value = true;
        },
        onExit: (_) {
          hovered.value = false;
        },
        child: Material(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RevericRadius.large),
            side: BorderSide(
              color: hovered.value || menuOpen.value
                  ? colors.accent
                  : colors.borderSubtle,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onEdit,
            hoverColor: colors.hover,
            child: Padding(
              padding: EdgeInsets.all(cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: RevericSpacing.xs,
                          runSpacing: RevericSpacing.xs,
                          children: [
                            OutlineBeatSequenceChip(
                              index: index + 1,
                              color: beatSequenceColor(context, index),
                            ),
                            OutlineBeatStatusChip(status: beat.status),
                            OutlineBeatChapterChip(count: beat.chapterCount),
                          ],
                        ),
                      ),
                      const SizedBox(width: RevericSpacing.xs),
                      _CardMenu(
                        shortcutActions: shortcutActions,
                        onRunShortcutAction: onRunShortcutAction,
                        onDelete: onDelete,
                        onMenuOpenChanged: (open) {
                          menuOpen.value = open;
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: RevericSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: typo.uiSemibold.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: RevericSpacing.md),
                      Flexible(
                        child: Text(
                          chapterRange,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: typo.uiTiny.copyWith(color: colors.textMuted),
                        ),
                      ),
                    ],
                  ),
                  if (beat.content.trim().isNotEmpty) ...[
                    const SizedBox(height: RevericSpacing.md),
                    Container(height: 1, color: colors.borderSubtle),
                    const SizedBox(height: RevericSpacing.md),
                    RevericMarkdownPreview(
                      data: beat.content,
                      style: typo.uiSmall.copyWith(color: colors.textSecondary),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DraggableArchitectureCard extends StatelessWidget {
  const _DraggableArchitectureCard({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final feedbackWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(240.0, 420.0).toDouble()
            : 360.0;
        return LongPressDraggable<int>(
          data: index,
          delay: const Duration(milliseconds: 180),
          feedback: Material(
            color: colors.surface.withValues(alpha: 0),
            child: SizedBox(
              width: feedbackWidth,
              child: Opacity(opacity: 0.86, child: child),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.38, child: child),
          child: child,
        );
      },
    );
  }
}

class _DropBand extends StatelessWidget {
  const _DropBand({required this.onAccept});

  final ValueChanged<int> onAccept;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: active ? RevericSpacing.x2l : RevericSpacing.xs,
          margin: const EdgeInsets.symmetric(vertical: RevericSpacing.xxs),
          decoration: BoxDecoration(
            color: active
                ? colors.accent.withValues(alpha: 0.12)
                : colors.surface.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(RevericRadius.pill),
          ),
        );
      },
    );
  }
}

class _CardMenu extends StatelessWidget {
  const _CardMenu({
    required this.shortcutActions,
    required this.onRunShortcutAction,
    required this.onDelete,
    required this.onMenuOpenChanged,
  });

  final List<AiShortcutActionDefinition> shortcutActions;
  final ValueChanged<AiShortcutActionDefinition>? onRunShortcutAction;
  final VoidCallback onDelete;
  final ValueChanged<bool> onMenuOpenChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return RevericIconButton(
      icon: RevericIcons.more_horiz,
      tooltip: context.t(LocaleKeys.commonMoreActions),
      onPressed: () async {
        final box = context.findRenderObject()! as RenderBox;
        onMenuOpenChanged(true);
        try {
          await showRevericContextMenu(
            context: context,
            position: box.localToGlobal(Offset(0, box.size.height)),
            entries: [
              for (final shortcut in shortcutActions)
                RevericMenuItem(
                  label: shortcut.name,
                  icon: RevericIcons.rocket_launch_outlined,
                  enabled: onRunShortcutAction != null,
                  onTap: () => onRunShortcutAction?.call(shortcut),
                ),
              RevericMenuItem(
                label: context.t(LocaleKeys.commonDelete),
                icon: RevericIcons.delete_outline,
                iconColor: colors.warningText,
                labelColor: colors.warningText,
                onTap: onDelete,
              ),
            ],
          );
        } finally {
          if (context.mounted) {
            onMenuOpenChanged(false);
          }
        }
      },
    );
  }
}

class _ArchitectureEmptyState extends StatelessWidget {
  const _ArchitectureEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RevericIcon(
            RevericIcons.linear_scale,
            color: colors.textSubtle,
            size: 28,
          ),
          const SizedBox(height: RevericSpacing.md),
          Text(
            context.t(LocaleKeys.workspaceOutlineTimelineEmptyTitle),
            style: typo.uiSemibold.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.xs),
          Text(
            context.t(LocaleKeys.workspaceOutlineTimelineEmptyHint),
            style: typo.ui.copyWith(color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RevericSpacing.lg),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const RevericIcon(RevericIcons.add, size: 16),
            label: Text(context.t(LocaleKeys.workspaceOutlineAddBeat)),
          ),
        ],
      ),
    );
  }
}

int _countStatus(List<OutlineBeatDraft> beats, String status) {
  return beats.where((beat) => beat.status == status).length;
}

int _mathFlex(double value) {
  return (value.clamp(0.02, 1) * 1000).round();
}
