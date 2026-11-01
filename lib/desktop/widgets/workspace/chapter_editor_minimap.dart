// 职责: 桌面章节编辑器 minimap 区域 — 绘制正文缩略图并同步正文滚动与快速定位。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/performance.md

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

/// 编辑器滚动区域：正文与 minimap 共用同一 [ScrollController]。
class ChapterEditorScrollRegion extends HookWidget {
  const ChapterEditorScrollRegion({
    super.key,
    required this.textController,
    required this.minimapEnabled,
    required this.child,
  });

  final TextEditingController textController;
  final bool minimapEnabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scrollController = useScrollController();

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            key: const ValueKey('chapter-editor-scroll-view'),
            controller: scrollController,
            padding: EdgeInsets.only(
              right: minimapEnabled ? RevericSizes.editorMinimapWidth : 0,
            ),
            child: child,
          ),
        ),
        if (minimapEnabled)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: RevericSizes.editorMinimapWidth,
            child: _ChapterEditorMinimap(
              textController: textController,
              scrollController: scrollController,
            ),
          ),
      ],
    );
  }
}

class _ChapterEditorMinimap extends HookWidget {
  const _ChapterEditorMinimap({
    required this.textController,
    required this.scrollController,
  });

  final TextEditingController textController;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final text = useListenableSelector(
      textController,
      () => textController.text,
    );
    final lines = useMemoized(() => _buildVisualLines(text), [text]);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;

        void jumpTo(Offset localPosition) {
          _jumpToMinimapPosition(
            scrollController: scrollController,
            minimapHeight: size.height,
            localY: localPosition.dy,
          );
        }

        return Semantics(
          label: context.t(LocaleKeys.settingsEditorMinimap),
          button: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: const ValueKey('chapter-editor-minimap'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => jumpTo(details.localPosition),
              onVerticalDragStart: (details) => jumpTo(details.localPosition),
              onVerticalDragUpdate: (details) => jumpTo(details.localPosition),
              child: CustomPaint(
                painter: _ChapterMinimapPainter(
                  lines: lines,
                  scrollController: scrollController,
                  backgroundColor: colors.surfaceContainerHigh.withValues(
                    alpha: 0.94,
                  ),
                  borderColor: colors.borderSubtle,
                  textColor: colors.textMuted.withValues(alpha: 0.52),
                  viewportColor: colors.selected.withValues(alpha: 0.12),
                  viewportBorderColor: colors.accent.withValues(alpha: 0.42),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

void _jumpToMinimapPosition({
  required ScrollController scrollController,
  required double minimapHeight,
  required double localY,
}) {
  if (!scrollController.hasClients || minimapHeight <= 0) {
    return;
  }
  final position = scrollController.position;
  if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
    return;
  }

  final viewportHeight = _minimapViewportHeight(position, minimapHeight);
  final trackExtent = math.max(0.0, minimapHeight - viewportHeight);
  if (trackExtent <= 0) {
    return;
  }
  final normalized = ((localY - viewportHeight / 2) / trackExtent)
      .clamp(0.0, 1.0)
      .toDouble();
  scrollController.jumpTo(position.maxScrollExtent * normalized);
}

double _minimapViewportHeight(ScrollPosition position, double minimapHeight) {
  final contentExtent = position.maxScrollExtent + position.viewportDimension;
  if (contentExtent <= 0) {
    return minimapHeight;
  }
  return (minimapHeight * position.viewportDimension / contentExtent)
      .clamp(RevericSizes.editorMinimapMinimumViewportHeight, minimapHeight)
      .toDouble();
}

class _ChapterMinimapVisualLine {
  const _ChapterMinimapVisualLine({
    required this.leadingColumns,
    required this.contentColumns,
  });

  final int leadingColumns;
  final int contentColumns;
}

const _minimapColumns = 64;
const _minimapNaturalRowPitch = 2.2;

@visibleForTesting
double chapterEditorMinimapRowPitch({
  required int sampledLineCount,
  required double contentHeight,
  required bool stretchToTrack,
}) {
  if (sampledLineCount <= 1 || contentHeight <= 0) {
    return 0;
  }
  final naturalHeight = (sampledLineCount - 1) * _minimapNaturalRowPitch;
  if (stretchToTrack || naturalHeight > contentHeight) {
    return contentHeight / (sampledLineCount - 1);
  }
  return _minimapNaturalRowPitch;
}

List<_ChapterMinimapVisualLine> _buildVisualLines(String text) {
  if (text.isEmpty) {
    return const <_ChapterMinimapVisualLine>[];
  }

  final result = <_ChapterMinimapVisualLine>[];
  for (final hardLine in text.split('\n')) {
    if (hardLine.isEmpty) {
      result.add(
        const _ChapterMinimapVisualLine(leadingColumns: 0, contentColumns: 0),
      );
      continue;
    }

    var offset = 0;
    while (offset < hardLine.length) {
      final end = math.min(offset + _minimapColumns, hardLine.length);
      var leadingColumns = 0;
      while (offset + leadingColumns < end &&
          _isWhitespace(hardLine.codeUnitAt(offset + leadingColumns))) {
        leadingColumns += 1;
      }
      result.add(
        _ChapterMinimapVisualLine(
          leadingColumns: leadingColumns,
          contentColumns: end - offset - leadingColumns,
        ),
      );
      offset = end;
    }
  }
  return result;
}

bool _isWhitespace(int codeUnit) {
  return codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x3000;
}

class _ChapterMinimapPainter extends CustomPainter {
  _ChapterMinimapPainter({
    required this.lines,
    required this.scrollController,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.viewportColor,
    required this.viewportBorderColor,
  }) : super(repaint: scrollController);

  final List<_ChapterMinimapVisualLine> lines;
  final ScrollController scrollController;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final Color viewportColor;
  final Color viewportBorderColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    canvas.drawLine(
      Offset.zero,
      Offset(0, size.height),
      Paint()
        ..color = borderColor
        ..strokeWidth = RevericSizes.dividerThickness,
    );

    _paintDocument(canvas, size);
    _paintViewport(canvas, size);
  }

  void _paintDocument(Canvas canvas, Size size) {
    if (lines.isEmpty || size.isEmpty) {
      return;
    }

    const verticalPadding = RevericSpacing.sm;
    const horizontalPadding = RevericSpacing.xs;
    final contentHeight = math.max(0.0, size.height - verticalPadding * 2);
    final contentWidth = math.max(0.0, size.width - horizontalPadding * 2);
    if (contentHeight <= 0 || contentWidth <= 0) {
      return;
    }

    final maxPaintedLines = math.max(1, contentHeight.floor());
    final sampleStep = math.max(1, (lines.length / maxPaintedLines).ceil());
    final sampledLineCount = (lines.length / sampleStep).ceil();
    final stretchToTrack =
        scrollController.hasClients &&
        scrollController.position.hasContentDimensions &&
        scrollController.position.maxScrollExtent > 0;
    final rowPitch = chapterEditorMinimapRowPitch(
      sampledLineCount: sampledLineCount,
      contentHeight: contentHeight,
      stretchToTrack: stretchToTrack,
    );
    final strokeWidth = (rowPitch * 0.46).clamp(0.45, 0.9).toDouble();
    final columnWidth = contentWidth / _minimapColumns;
    final paint = Paint()
      ..color = textColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square;

    var paintedIndex = 0;
    for (
      var sourceIndex = 0;
      sourceIndex < lines.length;
      sourceIndex += sampleStep
    ) {
      final line = lines[sourceIndex];
      if (line.contentColumns > 0) {
        final y = verticalPadding + paintedIndex * rowPitch;
        _paintTextLikeLine(
          canvas: canvas,
          paint: paint,
          line: line,
          lineIndex: sourceIndex,
          y: y,
          horizontalPadding: horizontalPadding,
          columnWidth: columnWidth,
          maxX: size.width - horizontalPadding,
        );
      }
      paintedIndex += 1;
    }
  }

  void _paintTextLikeLine({
    required Canvas canvas,
    required Paint paint,
    required _ChapterMinimapVisualLine line,
    required int lineIndex,
    required double y,
    required double horizontalPadding,
    required double columnWidth,
    required double maxX,
  }) {
    var x = horizontalPadding + line.leadingColumns * columnWidth;
    var remainingColumns = line.contentColumns;
    var segmentIndex = 0;
    while (remainingColumns > 0 && x < maxX) {
      final segmentColumns = math.min(
        remainingColumns,
        4 + ((lineIndex * 7 + segmentIndex * 3) % 8),
      );
      final segmentEnd = math.min(maxX, x + segmentColumns * columnWidth);
      canvas.drawLine(Offset(x, y), Offset(segmentEnd, y), paint);
      remainingColumns -= segmentColumns;
      x = segmentEnd + columnWidth * 1.4;
      segmentIndex += 1;
    }
  }

  void _paintViewport(Canvas canvas, Size size) {
    if (!scrollController.hasClients || size.isEmpty) {
      return;
    }
    final position = scrollController.position;
    if (!position.hasContentDimensions) {
      return;
    }

    final height = _minimapViewportHeight(position, size.height);
    final trackExtent = math.max(0.0, size.height - height);
    final progress = position.maxScrollExtent <= 0
        ? 0.0
        : (position.pixels / position.maxScrollExtent)
              .clamp(0.0, 1.0)
              .toDouble();
    final rect = Rect.fromLTWH(0, trackExtent * progress, size.width, height);
    canvas.drawRect(rect, Paint()..color = viewportColor);
    canvas.drawRect(
      rect.deflate(RevericSizes.dividerThickness / 2),
      Paint()
        ..color = viewportBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = RevericSizes.dividerThickness,
    );
  }

  @override
  bool shouldRepaint(covariant _ChapterMinimapPainter oldDelegate) {
    return !identical(lines, oldDelegate.lines) ||
        scrollController != oldDelegate.scrollController ||
        backgroundColor != oldDelegate.backgroundColor ||
        borderColor != oldDelegate.borderColor ||
        textColor != oldDelegate.textColor ||
        viewportColor != oldDelegate.viewportColor ||
        viewportBorderColor != oldDelegate.viewportBorderColor;
  }
}
