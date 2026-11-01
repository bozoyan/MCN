// 职责: 全局多大纲只读对齐时间轴 — 共享章节刻度、每大纲一列，按绝对章节坐标横向对齐对比。
// 关联文件:
//   lib/desktop/widgets/workspace/outline_architecture_view.dart
//   lib/desktop/widgets/workspace/outline_beat_chips.dart
//   lib/desktop/widgets/workspace/outline_beat_dialog.dart
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/shared/models/outline.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/outline.dart';
import '../../../shared/theme/theme.dart';
import 'outline_beat_chips.dart';
import 'outline_beat_dialog.dart';

/// 达到该宽度后各大纲列并排铺满；否则固定列宽横向滚动。
const double _globalSideBySideBreakpoint = 960.0;

/// 窄屏横向滚动时每列的固定宽度。
const double _minColumnWidth = 208.0;

/// 左侧章节刻度栏宽度。
const double _chapterGutterWidth = 60.0;

/// 列头（圆点 + 大纲标题）高度，各列与刻度栏共享以保证 spine 顶部对齐。
const double _columnHeaderHeight = 40.0;

/// 相邻节拍条的视觉间隙（上下各 1/2，只缩块高、不动顶点，故不破坏对齐）。
const double _barGap = 2.0;

/// 刻度目标：让「最短节拍（1 章）」达到此可读高度 —— 即「一章 = 一格」的格高。
/// 据此定「每章等高」的 px/章：最短节拍也能干净显示标题，长节拍按章节数等比占多格。刻度越大越可读、时间轴越长。
const double _readableBarHeight = 26.0;

/// 共享刻度取值边界（px/章）。
const double _minPixelsPerChapter = 6.0;
const double _maxPixelsPerChapter = 40.0;

class AllOutlinesArchitectureView extends StatelessWidget {
  const AllOutlinesArchitectureView({super.key, required this.outlines});

  final List<OutlineDraft> outlines;

  @override
  Widget build(BuildContext context) {
    final visibleOutlines = outlines
        .where((outline) {
          return outline.beats.isNotEmpty;
        })
        .toList(growable: false);

    if (visibleOutlines.isEmpty) {
      return const _GlobalOutlinesEmptyState();
    }

    final maxChapters = _maxGlobalChapterCount(visibleOutlines);
    final pixelsPerChapter = _resolvePixelsPerChapter(visibleOutlines);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        final expand =
            constraints.maxWidth >= _globalSideBySideBreakpoint ||
            visibleOutlines.length == 1;
        final horizontalPadding = compact
            ? RevericSpacing.x2l
            : RevericSpacing.x4l;
        final contentWidth = constraints.maxWidth.clamp(0.0, 1288.0).toDouble();

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            RevericSpacing.x4l,
            horizontalPadding,
            RevericSpacing.x5l,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _GlobalOutlinesIntro(),
                  const SizedBox(height: RevericSpacing.x4l),
                  _GlobalOutlinesSummary(outlines: visibleOutlines),
                  const SizedBox(height: RevericSpacing.x5l),
                  _GlobalComparisonBoard(
                    outlines: visibleOutlines,
                    maxChapters: maxChapters,
                    pixelsPerChapter: pixelsPerChapter,
                    expand: expand,
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

class _GlobalOutlinesSummary extends StatelessWidget {
  const _GlobalOutlinesSummary({required this.outlines});

  final List<OutlineDraft> outlines;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final outlineCount = outlines.length;
    final beats = outlines.expand((outline) => outline.beats).toList();
    final chapters = beats.fold<int>(0, (sum, beat) => sum + beat.chapterCount);

    return Container(
      padding: const EdgeInsets.all(RevericSpacing.x3l),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Wrap(
        spacing: RevericSpacing.x2l,
        runSpacing: RevericSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _SummaryLegend(
            color: colors.accent,
            label: context.t(LocaleKeys.workspaceOutlines),
            value: outlineCount,
          ),
          _SummaryLegend(
            color: colors.accentWarm,
            label: context.t(LocaleKeys.workspaceOutlineTimelineTitle),
            value: beats.length,
          ),
          _SummaryLegend(
            color: colors.textSubtle,
            label: context.t(LocaleKeys.workspaceOutlineArchitectureChapters),
            value: chapters,
          ),
        ],
      ),
    );
  }
}

class _GlobalOutlinesIntro extends StatelessWidget {
  const _GlobalOutlinesIntro();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t(LocaleKeys.workspaceOutlineGlobalTitle),
          style: typo.display.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: RevericSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            context.t(LocaleKeys.workspaceOutlineGlobalHint),
            style: typo.ui.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// 章节对齐对比板：左侧刻度栏 + 每大纲一列，全列共用同一刻度与总高。
/// 每个节拍条 top = (起始章-1)×刻度、高 = 章节数×刻度 —— 同一章节在所有列处于同一 Y、精确对齐。
class _GlobalComparisonBoard extends StatelessWidget {
  const _GlobalComparisonBoard({
    required this.outlines,
    required this.maxChapters,
    required this.pixelsPerChapter,
    required this.expand,
  });

  final List<OutlineDraft> outlines;
  final int maxChapters;
  final double pixelsPerChapter;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final ticks = _chapterTicks(maxChapters);
    final totalHeight = maxChapters * pixelsPerChapter;

    final rowChildren = <Widget>[
      _ChapterGutter(
        ticks: ticks,
        pixelsPerChapter: pixelsPerChapter,
        totalHeight: totalHeight,
      ),
    ];
    for (var index = 0; index < outlines.length; index++) {
      rowChildren.add(const SizedBox(width: RevericSpacing.x2l));
      final column = _GlobalOutlineColumn(
        outline: outlines[index],
        outlineIndex: index,
        pixelsPerChapter: pixelsPerChapter,
        totalHeight: totalHeight,
        ticks: ticks,
      );
      rowChildren.add(
        expand
            ? Expanded(child: column)
            : SizedBox(width: _minColumnWidth, child: column),
      );
    }

    final board = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rowChildren,
    );

    if (expand) {
      return board;
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: board,
    );
  }
}

class _ChapterGutter extends StatelessWidget {
  const _ChapterGutter({
    required this.ticks,
    required this.pixelsPerChapter,
    required this.totalHeight,
  });

  final List<int> ticks;
  final double pixelsPerChapter;
  final double totalHeight;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return SizedBox(
      width: _chapterGutterWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _columnHeaderHeight,
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(
                  right: RevericSpacing.sm,
                  bottom: RevericSpacing.xs,
                ),
                child: Text(
                  context.t(LocaleKeys.workspaceOutlineArchitectureChapters),
                  style: typo.uiTiny.copyWith(color: colors.textSubtle),
                ),
              ),
            ),
          ),
          SizedBox(
            height: totalHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final tick in ticks)
                  Positioned(
                    top: (tick - 1) * pixelsPerChapter,
                    right: RevericSpacing.sm,
                    child: Text(
                      context.t(
                        LocaleKeys.commonChapterNumber,
                        namedArgs: {'number': '$tick'},
                      ),
                      style: typo.uiTiny.copyWith(color: colors.textMuted),
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

class _GlobalOutlineColumn extends StatelessWidget {
  const _GlobalOutlineColumn({
    required this.outline,
    required this.outlineIndex,
    required this.pixelsPerChapter,
    required this.totalHeight,
    required this.ticks,
  });

  final OutlineDraft outline;
  final int outlineIndex;
  final double pixelsPerChapter;
  final double totalHeight;
  final List<int> ticks;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final accent = _beatVolumeColor(context, outlineIndex);
    final spans = _globalBeatSpans(outline);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _columnHeaderHeight,
          child: Row(
            children: [
              Container(
                width: RevericSpacing.md,
                height: RevericSpacing.md,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  _outlineLabel(context, outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final tick in ticks)
                Positioned(
                  top: (tick - 1) * pixelsPerChapter,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: RevericSizes.dividerThickness,
                    color: colors.borderSubtle,
                  ),
                ),
              for (var i = 0; i < spans.length; i++)
                _positionBeat(
                  span: spans[i],
                  index: i,
                  accent: accent,
                  ppc: pixelsPerChapter,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _positionBeat({
    required _GlobalBeatSpan span,
    required int index,
    required Color accent,
    required double ppc,
  }) {
    final count = span.end - span.start + 1;
    // top 精确落在起始章节坐标；间隙只从块高里扣，不动 top，故不破坏跨列对齐。
    final top = (span.start - 1) * ppc + _barGap / 2;
    final height = math.max(count * ppc - _barGap, 1.0);
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      height: height,
      child: _GlobalBeatBar(
        span: span,
        index: index,
        outlineIndex: outlineIndex,
        accent: accent,
        height: height,
      ),
    );
  }
}

/// 全局对比卡片：白底 surface + 描边，内容按可用高度分级降级
/// （矮格只放标题；随格高依次加 章节范围 → chip 行 → 描述），呼应单大纲架构视图的卡片观感。
class _GlobalBeatBar extends StatelessWidget {
  const _GlobalBeatBar({
    required this.span,
    required this.index,
    required this.outlineIndex,
    required this.accent,
    required this.height,
  });

  final _GlobalBeatSpan span;
  final int index;
  final int outlineIndex;
  final Color accent;

  /// 卡片可视高度（= 节拍占的槽位高度，∝ 章节数）。
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final title = _beatTitle(context, span.beat);
    final range = context.t(
      LocaleKeys.workspaceOutlineBeatChapterRange,
      namedArgs: {'start': '${span.start}', 'end': '${span.end}'},
    );
    final status = span.beat.status;
    final content = span.beat.content.trim();

    final verticalPadding = height >= 72
        ? RevericSpacing.md
        : height >= 40
        ? 4.0
        : 2.0;
    final contentArea = height - verticalPadding * 2;

    final showChips = contentArea >= 54;
    final titleStyle = height >= 64 ? typo.uiSemibold : typo.uiTinySemibold;

    // 预算：标题行(~22) + chip 行(~30) 之后，余量按行高(~18)折算描述行数。
    var used = 22.0;
    if (showChips) {
      used += 30;
    }
    final descLines = content.isEmpty
        ? 0
        : ((contentArea - used - 8) / 18).floor().clamp(0, 6);
    final showDesc = descLines >= 1;

    final children = <Widget>[
      if (showChips) ...[
        Wrap(
          spacing: RevericSpacing.xs,
          runSpacing: RevericSpacing.xs,
          children: [
            OutlineBeatSequenceChip(index: index + 1, color: accent),
            OutlineBeatStatusChip(status: status),
          ],
        ),
        const SizedBox(height: RevericSpacing.sm),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
          Text(
            range,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typo.uiTiny.copyWith(color: colors.textMuted),
          ),
        ],
      ),
      if (showDesc) ...[
        const SizedBox(height: RevericSpacing.sm),
        Text(
          content,
          maxLines: descLines,
          overflow: TextOverflow.ellipsis,
          style: typo.uiSmall.copyWith(color: colors.textSecondary),
        ),
      ],
    ];

    return Tooltip(
      message: '$title\n$range · ${statusLabel(context, status)}',
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        key: ValueKey('global-beat-$outlineIndex-$index'),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.topLeft,
        padding: EdgeInsets.symmetric(
          horizontal: RevericSpacing.lg,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(RevericRadius.large),
          border: Border.all(color: colors.borderSubtle),
        ),
        // 卡片高度被章节数锁死；用 OverflowBox 让内容按自然高度布局、超出部分由 Container 裁掉，
        // 避免最矮的一格（标题略高于可用高度）触发 RenderFlex 溢出报错。
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxHeight: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _GlobalOutlinesEmptyState extends StatelessWidget {
  const _GlobalOutlinesEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x6l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.timeline_outlined,
              color: colors.textSubtle,
              size: 28,
            ),
            const SizedBox(height: RevericSpacing.md),
            Text(
              context.t(LocaleKeys.workspaceOutlineGlobalTitle),
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                context.t(LocaleKeys.workspaceOutlineGlobalEmptyHint),
                style: typo.ui.copyWith(color: colors.textMuted),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalBeatSpan {
  const _GlobalBeatSpan({
    required this.beat,
    required this.start,
    required this.end,
  });

  final OutlineBeatDraft beat;
  final int start;
  final int end;
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

/// 共享刻度（px/章，每章等高）：取「最短节拍」达到 [_readableBarHeight] 所需的 px/章 ——
/// 于是最短节拍也够高显示标题，长节拍按章节数等比更高，且所有列共用同一刻度 → 同一章节精确对齐。
/// 代价：最短节拍越短、时间轴越长。
double _resolvePixelsPerChapter(List<OutlineDraft> outlines) {
  var minBeatChapters = 1 << 30;
  for (final outline in outlines) {
    for (final beat in outline.beats) {
      minBeatChapters = math.min(
        minBeatChapters,
        math.max(1, beat.chapterCount),
      );
    }
  }
  if (minBeatChapters == 1 << 30) {
    return _maxPixelsPerChapter;
  }
  return (_readableBarHeight / minBeatChapters).clamp(
    _minPixelsPerChapter,
    _maxPixelsPerChapter,
  );
}

int _maxGlobalChapterCount(List<OutlineDraft> outlines) {
  var maxChapters = 1;
  for (final outline in outlines) {
    final outlineChapters = outline.beats.fold<int>(
      0,
      (sum, beat) => sum + math.max(1, beat.chapterCount),
    );
    if (outlineChapters == 0) {
      continue;
    }
    final start = math.max(1, outline.startChapterNum);
    maxChapters = math.max(maxChapters, start + outlineChapters - 1);
  }
  return maxChapters;
}

List<_GlobalBeatSpan> _globalBeatSpans(OutlineDraft outline) {
  final spans = <_GlobalBeatSpan>[];
  var start = math.max(1, outline.startChapterNum);
  for (final beat in outline.beats) {
    final count = math.max(1, beat.chapterCount);
    final end = start + count - 1;
    spans.add(_GlobalBeatSpan(beat: beat, start: start, end: end));
    start = end + 1;
  }
  return spans;
}

List<int> _chapterTicks(int maxChapters) {
  if (maxChapters <= 1) {
    return const [1];
  }
  final tickCount = math.min(6, maxChapters);
  final ticks = <int>{1, maxChapters};
  for (var i = 1; i < tickCount - 1; i++) {
    final tick = 1 + ((maxChapters - 1) * i / (tickCount - 1)).round();
    ticks.add(tick);
  }
  return ticks.toList()..sort();
}

String _outlineLabel(BuildContext context, OutlineDraft outline) {
  final title = outline.title.trim();
  if (title.isNotEmpty) {
    return title;
  }
  return context.t(LocaleKeys.workspaceOutlines);
}

String _beatTitle(BuildContext context, OutlineBeatDraft beat) {
  final title = shortOutlineBeatTitle(beat.title);
  if (title.isNotEmpty) {
    return title;
  }
  return context.t(LocaleKeys.workspaceOutlineUntitledBeat);
}

Color _beatVolumeColor(BuildContext context, int index) {
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
