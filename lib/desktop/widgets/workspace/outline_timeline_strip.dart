// 职责: 横向 timeline beats 条 — 展示底部节拍刻度尺、横向节拍卡片、空状态与拖拽重排。
// 关联文件:
//   lib/desktop/widgets/workspace/outline_editor.dart
//   lib/desktop/widgets/workspace/outline_beat_dialog.dart
//   lib/shared/components/horizontal_wheel_scroll.dart
//   lib/shared/models/ai_shortcut_action.dart
//   lib/shared/models/outline.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/agent_shortcut.json
//   assets/translations/zh-CN/agent_shortcut.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../shared/components/reveric_context_menu.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/components/horizontal_wheel_scroll.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/ai_shortcut_action.dart';
import '../../../shared/models/outline.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';
import 'outline_beat_dialog.dart';

class OutlineTimelineBeatsToolbar extends StatelessWidget {
  const OutlineTimelineBeatsToolbar({
    super.key,
    required this.beatsExpanded,
    required this.onToggleBeatsExpanded,
    required this.onAddBeat,
    this.timelineCollapsed,
    this.onToggleCollapsed,
  });

  final bool beatsExpanded;
  final VoidCallback onToggleBeatsExpanded;
  final VoidCallback onAddBeat;
  final bool? timelineCollapsed;
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            context.t(LocaleKeys.workspaceOutlineTimelineTitle),
            style: typo.heading2.copyWith(color: colors.textPrimary),
          ),
        ),
        if (onToggleCollapsed != null)
          IconButton(
            tooltip: timelineCollapsed!
                ? context.t(LocaleKeys.workspaceOutlineTimelineShow)
                : context.t(LocaleKeys.workspaceOutlineTimelineHide),
            onPressed: onToggleCollapsed,
            icon: RevericIcon(
              timelineCollapsed!
                  ? RevericIcons.arrow_downward_rounded
                  : RevericIcons.arrow_upward_rounded,
              size: 18,
              color: colors.textMuted,
            ),
          ),
        IconButton(
          tooltip: beatsExpanded
              ? context.t(LocaleKeys.workspaceOutlineTimelineCollapse)
              : context.t(LocaleKeys.workspaceOutlineTimelineExpand),
          onPressed: onToggleBeatsExpanded,
          icon: RevericIcon(
            beatsExpanded
                ? RevericIcons.close_fullscreen_rounded
                : RevericIcons.open_in_full_rounded,
            size: 18,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(width: RevericSpacing.xs),
        FilledButton.icon(
          onPressed: onAddBeat,
          icon: const RevericIcon(RevericIcons.add, size: 16),
          label: Text(context.t(LocaleKeys.workspaceOutlineAddBeat)),
        ),
      ],
    );
  }
}

enum _TimelineDensity { full, compact, dense }

class OutlineTimelineStrip extends StatelessWidget {
  const OutlineTimelineStrip({
    super.key,
    required this.draft,
    required this.isCollapsed,
    this.expandedHeight,
    required this.onAddBeat,
    required this.onEditBeat,
    required this.onDeleteBeat,
    this.beatShortcutActions = const <AiShortcutActionDefinition>[],
    this.onRunShortcutAction,
    required this.onReorderBeats,
    required this.onToggleBeatsExpanded,
    required this.onToggleCollapsed,
  });

  final OutlineDraft draft;
  final bool isCollapsed;
  final double? expandedHeight;
  final VoidCallback onAddBeat;
  final ValueChanged<int> onEditBeat;
  final ValueChanged<int> onDeleteBeat;
  final List<AiShortcutActionDefinition> beatShortcutActions;
  final ValueChanged<AiShortcutActionDefinition>? onRunShortcutAction;
  final void Function(int oldIndex, int newIndex) onReorderBeats;
  final VoidCallback onToggleBeatsExpanded;
  final VoidCallback onToggleCollapsed;

  /// 收起态高度（仅 toolbar）。
  static const double collapsedHeight = 64;

  /// dense 档固有高度（toolbar + ruler + 单行卡片）。
  static const double denseExpandedHeight = 168;

  /// compact 档固有高度（toolbar + ruler + 无预览卡片）。
  static const double compactExpandedHeight = 240;

  /// full 档固有高度（含正文预览）。
  static const double defaultExpandedHeight = 316;

  /// 时间线刻度尺的总高度（含标签 + 刻度线）。
  static const double rulerHeight = 28;

  /// 每个 beat 起点在刻度线上的指示圆点直径。
  static const double indicatorSize = 14;

  /// 在 [maxBudget] 内选最大可放下的密度档固有高度；绝不撑满预算留白。
  static double resolveExpandedHeight(double maxBudget) {
    if (maxBudget >= defaultExpandedHeight) {
      return defaultExpandedHeight;
    }
    if (maxBudget >= compactExpandedHeight) {
      return compactExpandedHeight;
    }
    if (maxBudget >= denseExpandedHeight) {
      return denseExpandedHeight;
    }
    return math.max(0.0, maxBudget);
  }

  static _TimelineDensity _densityForHeight(double height) {
    if (height >= defaultExpandedHeight) {
      return _TimelineDensity.full;
    }
    if (height >= compactExpandedHeight) {
      return _TimelineDensity.compact;
    }
    return _TimelineDensity.dense;
  }

  @override
  Widget build(BuildContext context) {
    final beats = draft.beats;
    final panelHeight = isCollapsed
        ? collapsedHeight
        : (expandedHeight ?? defaultExpandedHeight);
    final density = isCollapsed
        ? _TimelineDensity.full
        : _densityForHeight(panelHeight);

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 900
            ? RevericSpacing.x4l
            : RevericSpacing.x6l;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            0,
            horizontalPadding,
            RevericSpacing.x3l,
          ),
          child: _TimelinePanelFrame(
            height: panelHeight,
            child: isCollapsed
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RevericSpacing.x3l,
                    ),
                    child: OutlineTimelineBeatsToolbar(
                      beatsExpanded: false,
                      timelineCollapsed: true,
                      onToggleBeatsExpanded: onToggleBeatsExpanded,
                      onToggleCollapsed: onToggleCollapsed,
                      onAddBeat: onAddBeat,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          RevericSpacing.x3l,
                          density == _TimelineDensity.dense
                              ? RevericSpacing.sm
                              : RevericSpacing.lg,
                          RevericSpacing.x3l,
                          RevericSpacing.sm,
                        ),
                        child: OutlineTimelineBeatsToolbar(
                          beatsExpanded: false,
                          timelineCollapsed: false,
                          onToggleBeatsExpanded: onToggleBeatsExpanded,
                          onToggleCollapsed: onToggleCollapsed,
                          onAddBeat: onAddBeat,
                        ),
                      ),
                      Expanded(
                        child: beats.isEmpty
                            ? _TimelineEmptyState(onAdd: onAddBeat)
                            : _BeatsTrack(
                                beats: beats,
                                startChapterNum: draft.startChapterNum,
                                rulerHeight: rulerHeight,
                                indicatorSize: indicatorSize,
                                onEdit: onEditBeat,
                                onDelete: onDeleteBeat,
                                beatShortcutActions: beatShortcutActions,
                                onRunShortcutAction: onRunShortcutAction,
                                onReorder: onReorderBeats,
                                density: density,
                              ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _TimelinePanelFrame extends StatelessWidget {
  const _TimelinePanelFrame({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _BeatsTrack extends StatelessWidget {
  const _BeatsTrack({
    required this.beats,
    required this.startChapterNum,
    required this.rulerHeight,
    required this.indicatorSize,
    required this.onEdit,
    required this.onDelete,
    required this.beatShortcutActions,
    this.onRunShortcutAction,
    required this.onReorder,
    required this.density,
  });

  final List<OutlineBeatDraft> beats;
  final int startChapterNum;
  final double rulerHeight;
  final double indicatorSize;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;
  final List<AiShortcutActionDefinition> beatShortcutActions;
  final ValueChanged<AiShortcutActionDefinition>? onRunShortcutAction;
  final void Function(int oldIndex, int newIndex) onReorder;
  final _TimelineDensity density;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final totalChapters = beats.fold<int>(0, (sum, b) => sum + b.chapterCount);
    if (totalChapters <= 0) {
      return const SizedBox.shrink();
    }

    // 累计起点：第 i 个 beat 的起点（章数）。
    final beatStartChapter = <int>[0];
    for (final b in beats) {
      beatStartChapter.add(beatStartChapter.last + b.chapterCount);
    }
    final chapterOffset = math.max(1, startChapterNum) - 1;

    final pixelsPerChapter = _TimelineLayout.pixelsPerChapter(totalChapters);
    final trackWidth = totalChapters * pixelsPerChapter;
    final cardWidths = [
      for (final beat in beats)
        _TimelineLayout.beatCardWidth(beat.chapterCount, pixelsPerChapter),
    ];
    final cardsRowWidth = cardWidths.fold<double>(0, (sum, w) => sum + w);
    final scrollWidth = math.max(trackWidth, cardsRowWidth) + indicatorSize;
    // 圆点中心要落在刻度线最底部（baseline）。刻度线 baseline 距 ruler 顶部 = rulerHeight - 1。
    final indicatorTop = rulerHeight - indicatorSize / 2 - 1;

    final trackBottomPadding = density == _TimelineDensity.dense
        ? RevericSpacing.xs
        : RevericSpacing.x2l;
    final rulerToCardsGap = density == _TimelineDensity.dense
        ? RevericSpacing.xs
        : RevericSpacing.md;

    return HorizontalWheelScroll(
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(
          RevericSpacing.x4l,
          0,
          RevericSpacing.x4l,
          trackBottomPadding,
        ),
        child: SizedBox(
          width: scrollWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 刻度尺 + 起点指示圆点（通过 Stack 叠在刻度线上）。
              SizedBox(
                height: rulerHeight + indicatorSize / 2,
                width: trackWidth + indicatorSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: indicatorSize / 2,
                      top: 0,
                      child: SizedBox(
                        width: trackWidth,
                        height: rulerHeight,
                        child: CustomPaint(
                          painter: _ChapterRulerPainter(
                            totalChapters: totalChapters,
                            chapterOffset: chapterOffset,
                            pixelsPerChapter: pixelsPerChapter,
                            baselineColor: colors.border,
                            minorTickColor: colors.border,
                            majorTickColor: colors.textMuted,
                            labelStyle: typo.uiTiny.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    for (int i = 0; i < beats.length; i++)
                      Positioned(
                        left:
                            indicatorSize / 2 +
                            beatStartChapter[i] * pixelsPerChapter -
                            indicatorSize / 2,
                        top: indicatorTop,
                        child: Container(
                          width: indicatorSize,
                          height: indicatorSize,
                          decoration: BoxDecoration(
                            color: statusColor(context, beats[i].status),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.surfaceContainer,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: rulerToCardsGap),
              // beat 卡片行：宽度为 max(章数比例, 最小卡片宽)，刻度尺仍按章数比例。
              Padding(
                padding: EdgeInsets.only(left: indicatorSize / 2),
                child: SizedBox(
                  width: cardsRowWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < beats.length; i++)
                        SizedBox(
                          width: cardWidths[i],
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: i == beats.length - 1
                                  ? 0
                                  : RevericSpacing.sm,
                            ),
                            child: _DraggableBeatSlot(
                              index: i,
                              onReorder: onReorder,
                              child: _TimelineBeatCard(
                                beat: beats[i],
                                beatIndex: i,
                                chapterStart:
                                    chapterOffset + beatStartChapter[i] + 1,
                                chapterEnd:
                                    chapterOffset + beatStartChapter[i + 1],
                                onEdit: () => onEdit(i),
                                onDelete: () {
                                  onDelete(i);
                                },
                                shortcutActions: beatShortcutActions,
                                onRunShortcutAction: onRunShortcutAction,
                                density: density,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterRulerPainter extends CustomPainter {
  _ChapterRulerPainter({
    required this.totalChapters,
    required this.chapterOffset,
    required this.pixelsPerChapter,
    required this.baselineColor,
    required this.minorTickColor,
    required this.majorTickColor,
    required this.labelStyle,
  });

  final int totalChapters;
  final int chapterOffset;
  final double pixelsPerChapter;
  final Color baselineColor;
  final Color minorTickColor;
  final Color majorTickColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final baselineY = size.height - 1;
    const majorTickHeight = 9.0;
    const minorTickHeight = 5.0;

    // 最小刻度固定为每 5 章一格；主刻度在更大的章数间隔上标注数字。
    const int minorStep = 5;
    final int majorInterval = totalChapters <= 50
        ? 10
        : (totalChapters <= 150 ? 25 : 50);

    final baselinePaint = Paint()
      ..color = baselineColor
      ..strokeWidth = 1;
    final minorPaint = Paint()
      ..color = minorTickColor
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = majorTickColor
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(0, baselineY),
      Offset(size.width, baselineY),
      baselinePaint,
    );

    void drawTick(int chapter, {required bool major}) {
      final x = chapter * pixelsPerChapter;
      final tickHeight = major ? majorTickHeight : minorTickHeight;
      final paint = major ? majorPaint : minorPaint;
      canvas.drawLine(
        Offset(x, baselineY - tickHeight),
        Offset(x, baselineY),
        paint,
      );
      if (major && chapter > 0) {
        final tp = TextPainter(
          text: TextSpan(text: '${chapterOffset + chapter}', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(x - tp.width / 2, baselineY - tickHeight - tp.height - 2),
        );
      }
    }

    // 起点 (0) 始终画一个主刻度（不带标签）。
    drawTick(0, major: true);

    // 每 5 章一个最小刻度；主刻度按 majorInterval 标注。
    for (int i = minorStep; i <= totalChapters; i += minorStep) {
      drawTick(i, major: i % majorInterval == 0);
    }

    // 终点若不在 5 章倍数上，补一个主刻度（带标签），便于看到结尾位置。
    if (totalChapters % minorStep != 0) {
      drawTick(totalChapters, major: true);
    }
  }

  @override
  bool shouldRepaint(_ChapterRulerPainter oldDelegate) {
    return oldDelegate.totalChapters != totalChapters ||
        oldDelegate.chapterOffset != chapterOffset ||
        oldDelegate.pixelsPerChapter != pixelsPerChapter ||
        oldDelegate.baselineColor != baselineColor ||
        oldDelegate.minorTickColor != minorTickColor ||
        oldDelegate.majorTickColor != majorTickColor ||
        oldDelegate.labelStyle != labelStyle;
  }
}

class _TimelineLayout {
  _TimelineLayout._();

  static const double maxPixelsPerChapter = 48;
  static const double maxTimelineTrackWidth = 3600;
  static const double minBeatCardWidth = 280;
  static const double maxBeatCardWidth = 520;

  static double pixelsPerChapter(int totalChapters) {
    if (totalChapters <= 0) {
      return maxPixelsPerChapter;
    }
    final uncapped = totalChapters * maxPixelsPerChapter;
    if (uncapped <= maxTimelineTrackWidth) {
      return maxPixelsPerChapter;
    }
    return maxTimelineTrackWidth / totalChapters;
  }

  static double beatCardWidth(int chapterCount, double pixelsPerChapter) {
    return math
        .max(chapterCount * pixelsPerChapter, minBeatCardWidth)
        .clamp(minBeatCardWidth, maxBeatCardWidth);
  }
}

class _TimelineBeatCard extends HookWidget {
  const _TimelineBeatCard({
    required this.beat,
    required this.beatIndex,
    required this.chapterStart,
    required this.chapterEnd,
    required this.onEdit,
    required this.onDelete,
    required this.shortcutActions,
    this.onRunShortcutAction,
    required this.density,
  });

  final OutlineBeatDraft beat;
  final int beatIndex;
  final int chapterStart;
  final int chapterEnd;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final List<AiShortcutActionDefinition> shortcutActions;
  final ValueChanged<AiShortcutActionDefinition>? onRunShortcutAction;
  final _TimelineDensity density;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final hovered = useState(false);
    final menuOpen = useState(false);
    final rawTitle = beat.title.trim();
    final fallbackTitle = rawTitle.isEmpty
        ? context.t(LocaleKeys.workspaceOutlineUntitledBeat)
        : rawTitle;
    final shortenedTitle = shortOutlineBeatTitle(rawTitle);
    final displayTitle = shortenedTitle.isEmpty
        ? fallbackTitle
        : shortenedTitle;
    final sequenceColor = _beatSequenceColor(context, beatIndex);
    final chapterRangeLabel = context.t(
      LocaleKeys.workspaceOutlineBeatChapterRange,
      namedArgs: {'start': '$chapterStart', 'end': '$chapterEnd'},
    );
    final contentPadding = density == _TimelineDensity.dense
        ? const EdgeInsets.fromLTRB(
            RevericSpacing.md,
            RevericSpacing.xs,
            RevericSpacing.lg,
            RevericSpacing.xs,
          )
        : const EdgeInsets.fromLTRB(
            RevericSpacing.lg,
            RevericSpacing.lg,
            RevericSpacing.x3l,
            RevericSpacing.lg,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 160;
        final effectiveDensity = isNarrow && density == _TimelineDensity.full
            ? _TimelineDensity.compact
            : density;
        return Tooltip(
          message: isNarrow ? fallbackTitle : '',
          waitDuration: const Duration(milliseconds: 400),
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
                      ? sequenceColor.withValues(alpha: 0.42)
                      : colors.borderSubtle,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onEdit,
                hoverColor: colors.hover,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Padding(
                      padding: contentPadding,
                      child: _TimelineBeatCardContent(
                        beat: beat,
                        beatIndex: beatIndex,
                        displayTitle: displayTitle,
                        chapterRangeLabel: chapterRangeLabel,
                        density: effectiveDensity,
                      ),
                    ),
                    if (hovered.value || menuOpen.value)
                      Positioned(
                        top: RevericSpacing.xs,
                        right: RevericSpacing.xs,
                        child: Material(
                          color: colors.surfaceContainerHigh,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              RevericRadius.pill,
                            ),
                            side: BorderSide(color: colors.borderSubtle),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _TimelineBeatCardMenu(
                            shortcutActions: shortcutActions,
                            onRunShortcutAction: onRunShortcutAction,
                            onDelete: onDelete,
                            onMenuOpenChanged: (open) {
                              menuOpen.value = open;
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimelineBeatCardMenu extends StatelessWidget {
  const _TimelineBeatCardMenu({
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

class _TimelineBeatCardContent extends StatelessWidget {
  const _TimelineBeatCardContent({
    required this.beat,
    required this.beatIndex,
    required this.displayTitle,
    required this.chapterRangeLabel,
    required this.density,
  });

  final OutlineBeatDraft beat;
  final int beatIndex;
  final String displayTitle;
  final String chapterRangeLabel;
  final _TimelineDensity density;

  static const double _fullContentHeight = 156;
  static const double _compactContentHeight = 88;
  static const double _denseContentHeight = 48;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final sequenceColor = _beatSequenceColor(context, beatIndex);
    final isDense = density == _TimelineDensity.dense;
    final showContentPreview = density == _TimelineDensity.full;
    final contentHeight = switch (density) {
      _TimelineDensity.full => _fullContentHeight,
      _TimelineDensity.compact => _compactContentHeight,
      _TimelineDensity.dense => _denseContentHeight,
    };

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: [
        Row(
          children: [
            _BeatSequenceLabel(index: beatIndex + 1, color: sequenceColor),
            const SizedBox(width: RevericSpacing.sm),
            Flexible(child: _BeatStatusBadge(status: beat.status)),
            const SizedBox(width: RevericSpacing.xs),
            _ChapterCountBadge(count: beat.chapterCount),
            const Spacer(),
            const _BeatDragHandle(),
          ],
        ),
        SizedBox(height: isDense ? RevericSpacing.xs : RevericSpacing.md),
        Text(
          displayTitle,
          style: typo.uiSemibold.copyWith(color: colors.textPrimary),
          maxLines: isDense ? 1 : 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (!isDense) ...[
          const SizedBox(height: RevericSpacing.xs),
          Text(
            chapterRangeLabel,
            style: typo.uiTiny.copyWith(color: colors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (showContentPreview) ...[
            const SizedBox(height: RevericSpacing.sm),
            Expanded(
              child: RevericMarkdownPreview(
                data: beat.content,
                style: typo.uiSmall.copyWith(color: colors.textSecondary),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            const Spacer(),
          ],
        ] else ...[
          const Spacer(),
        ],
      ],
    );

    return SizedBox(height: contentHeight, child: content);
  }
}

class _BeatSequenceLabel extends StatelessWidget {
  const _BeatSequenceLabel({required this.index, required this.color});

  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        context.t(
          LocaleKeys.workspaceOutlineBeatSequenceLabel,
          namedArgs: {'index': '$index'},
        ),
        style: typo.uiTinySemibold.copyWith(color: color),
      ),
    );
  }
}

class _ChapterCountBadge extends StatelessWidget {
  const _ChapterCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Text(
        context.t(
          LocaleKeys.workspaceOutlineBeatChapterCountValue,
          namedArgs: {'count': '$count'},
        ),
        style: typo.uiTiny.copyWith(color: colors.textMuted),
      ),
    );
  }
}

class _BeatDragHandle extends StatelessWidget {
  const _BeatDragHandle();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Tooltip(
      message: context.t(LocaleKeys.workspaceOutlineBeatDragHandle),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(
          padding: const EdgeInsets.only(left: RevericSpacing.xs),
          child: RevericIcon(
            RevericIcons.more_vert,
            size: 14,
            color: colors.textSubtle,
          ),
        ),
      ),
    );
  }
}

class _DraggableBeatSlot extends StatelessWidget {
  const _DraggableBeatSlot({
    required this.index,
    required this.onReorder,
    required this.child,
  });

  final int index;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return LongPressDraggable<int>(
      data: index,
      delay: const Duration(milliseconds: 200),
      hapticFeedbackOnStart: true,
      feedback: Opacity(
        opacity: 0.85,
        child: Material(
          color: colors.surface.withValues(alpha: 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: child,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: _BeatDropZone(
                    selfIndex: index,
                    alignment: Alignment.centerLeft,
                    accentColor: colors.accent,
                    onAccept: (from) => onReorder(from, index),
                  ),
                ),
                Expanded(
                  child: _BeatDropZone(
                    selfIndex: index,
                    alignment: Alignment.centerRight,
                    accentColor: colors.accent,
                    onAccept: (from) => onReorder(from, index + 1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BeatDropZone extends StatelessWidget {
  const _BeatDropZone({
    required this.selfIndex,
    required this.alignment,
    required this.accentColor,
    required this.onAccept,
  });

  final int selfIndex;
  final Alignment alignment;
  final Color accentColor;
  final ValueChanged<int> onAccept;

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != selfIndex,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return IgnorePointer(
          child: Align(
            alignment: alignment,
            child: Container(
              width: active ? 3 : 0,
              height: double.infinity,
              color: active ? accentColor : accentColor.withValues(alpha: 0),
            ),
          ),
        );
      },
    );
  }
}

class _BeatStatusBadge extends StatelessWidget {
  const _BeatStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    final color = statusColor(context, status);
    final label = statusLabel(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: RevericSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typo.uiTinySemibold.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEmptyState extends StatelessWidget {
  const _TimelineEmptyState({required this.onAdd});

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

Color _beatSequenceColor(BuildContext context, int index) {
  final colors = RevericTheme.colorsOf(context);
  final palette = <Color>[
    colors.accent,
    colors.accentWarm,
    colors.accentAmber,
    colors.success,
    colors.warningText,
  ];
  return palette[index % palette.length];
}
