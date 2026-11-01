// 职责: 桌面端正文参考划线层 — 按 TextPainter 排版结果在 TextField 下方绘制实线/虚线稿纸线。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/shared/providers/settings_providers.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/providers/settings_providers.dart';

/// 与 [RenderEditable] 内部 `_caretMargin = _kCaretGap(1.0) + cursorWidth(2.0)` 对齐。
///
/// TextField 在多行布局时会从可用宽度里预留这一段给行末光标显示，
/// 因此实际可用于文本排版的宽度 = `maxWidth - kEditableCaretMargin`。
const double kEditableCaretMargin = 3.0;

Color parseEditorLineColorHex(
  String hex, {
  Color fallback = const Color(0xFFFF0000),
}) {
  final normalized = hex.replaceFirst('#', '');
  final argb = normalized.length == 6 ? 'FF$normalized' : normalized;
  if (argb.length != 8) {
    return fallback;
  }
  final value = int.tryParse(argb, radix: 16);
  if (value == null) {
    return fallback;
  }
  return Color(value);
}

/// 参考线落在每行文本基线下方的偏移（与字号成比例）。
///
/// 取每行实际排版的 [LineMetrics.baseline]（而非「行框底边 `(i+1) * rowHeight`」）
/// 作为锚点：行框底边按行高累加，会忽略首行行框顶端的 leading 偏移，导致整体上移
/// 穿过字形；锚在每行自己的基线上则始终贴着该行文字。0.44 ≈ 字形下降量 0.22 +
/// 视觉呼吸间距 0.22，足以落在字形下方又不触及下一行。
const double _kEditorLineBelowBaselineRatio = 0.44;

/// 计算所有可视行的参考线 Y 位置（桌面端：TextField 不内部滚动，整页随外层滚动）。
///
/// 仅基于 [TextPainter] 的纯排版结果（不读 RenderEditable），保证在 IME 组合
/// 输入过程中位置稳定，不随 composing 帧抖动。每行参考线锚在该行基线下方
/// [_kEditorLineBelowBaselineRatio] × 字号处，逐行计算，不假设各行等高。
List<double> computeEditorLineYs({
  required InlineSpan span,
  required double maxWidth,
  required TextDirection textDirection,
  required StrutStyle strutStyle,
  required TextHeightBehavior textHeightBehavior,
  required double fontSize,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (span.toPlainText().isEmpty) {
    return const <double>[];
  }

  final painter = TextPainter(
    text: span,
    textDirection: textDirection,
    strutStyle: strutStyle,
    textHeightBehavior: textHeightBehavior,
    textScaler: textScaler,
    maxLines: null,
  )..layout(maxWidth: maxWidth);

  final metrics = painter.computeLineMetrics();
  // 偏移随 textScaler 缩放，保证与已被缩放的 baseline 同步。
  final belowBaseline =
      textScaler.scale(fontSize) * _kEditorLineBelowBaselineRatio;

  if (metrics.isEmpty) {
    // 极端排版退化：按字号估算首行基线（≈ ascent 0.78）再加同样的基线下偏移。
    return [textScaler.scale(fontSize) * 0.78 + belowBaseline];
  }

  return [for (final metric in metrics) metric.baseline + belowBaseline];
}

/// 叠在正文 [TextField] 上的稿纸参考线层（需置于 [Stack] 内，且 [IgnorePointer]）。
class EditorFocusLinesLayer extends StatefulWidget {
  const EditorFocusLinesLayer({
    super.key,
    required this.lineStyle,
    required this.lineColor,
    required this.fallbackSpan,
    required this.maxWidth,
    required this.textDirection,
    required this.strutStyle,
    required this.textHeightBehavior,
    required this.fontSize,
    this.textScaler = TextScaler.noScaling,
  });

  final EditorLineStyle lineStyle;
  final Color lineColor;
  final InlineSpan fallbackSpan;
  final double maxWidth;
  final TextDirection textDirection;
  final StrutStyle strutStyle;
  final TextHeightBehavior textHeightBehavior;
  final double fontSize;
  final TextScaler textScaler;

  @override
  State<EditorFocusLinesLayer> createState() => _EditorFocusLinesLayerState();
}

class _EditorFocusLinesLayerState extends State<EditorFocusLinesLayer> {
  List<double> _lineYs = const [];
  Timer? _recomputeDebounce;

  @override
  void initState() {
    super.initState();
    _lineYs = _computeLineYs();
  }

  @override
  void didUpdateWidget(covariant EditorFocusLinesLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fallbackSpan.toPlainText().isEmpty) {
      _recomputeDebounce?.cancel();
      if (_lineYs.isNotEmpty) {
        setState(() {
          _lineYs = const <double>[];
        });
      }
      return;
    }

    _recomputeDebounce?.cancel();
    _recomputeDebounce = Timer(
      const Duration(milliseconds: 200),
      _recomputeIfChanged,
    );
  }

  @override
  void dispose() {
    _recomputeDebounce?.cancel();
    super.dispose();
  }

  List<double> _computeLineYs() {
    return computeEditorLineYs(
      span: widget.fallbackSpan,
      maxWidth: widget.maxWidth,
      textDirection: widget.textDirection,
      strutStyle: widget.strutStyle,
      textHeightBehavior: widget.textHeightBehavior,
      fontSize: widget.fontSize,
      textScaler: widget.textScaler,
    );
  }

  void _recomputeIfChanged() {
    if (!mounted) {
      return;
    }
    final next = _computeLineYs();
    if (!listEquals(_lineYs, next)) {
      setState(() {
        _lineYs = next;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: ClipRect(
            child: CustomPaint(
              isComplex: true,
              willChange: false,
              painter: EditorFocusLinePainter(
                lineStyle: widget.lineStyle,
                lineColor: widget.lineColor,
                lineBottoms: _lineYs,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EditorFocusLinePainter extends CustomPainter {
  EditorFocusLinePainter({
    required this.lineStyle,
    required this.lineColor,
    required this.lineBottoms,
  });

  final EditorLineStyle lineStyle;
  final Color lineColor;
  final List<double> lineBottoms;

  @override
  void paint(Canvas canvas, Size size) {
    final (alpha, strokeWidth, dashWidth, gapWidth) = switch (lineStyle) {
      EditorLineStyle.solid => (0.30, 1.0, size.width, 0.0),
      EditorLineStyle.sparseDashed => (0.28, 1.0, 5.0, 5.0),
      EditorLineStyle.denseDashed => (0.30, 1.0, 3.0, 2.5),
    };

    final paint = Paint()
      ..color = lineColor.withValues(alpha: alpha)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (final y in lineBottoms) {
      double dx = 0;
      while (dx < size.width) {
        final endX = (dx + dashWidth).clamp(0.0, size.width);
        canvas.drawLine(Offset(dx, y), Offset(endX, y), paint);
        dx = endX + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(EditorFocusLinePainter oldDelegate) {
    return oldDelegate.lineStyle != lineStyle ||
        oldDelegate.lineColor != lineColor ||
        !listEquals(oldDelegate.lineBottoms, lineBottoms);
  }
}
