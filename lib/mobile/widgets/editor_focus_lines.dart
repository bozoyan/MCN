// 职责: 移动端正文参考划线层 — 读取 TextField 内 RenderEditable 的真实行几何，在每个可视行底边绘制稿纸线。
// 关联文件:
//   lib/mobile/pages/chapter_editor_page.dart
//   lib/shared/providers/settings_providers.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../shared/providers/settings_providers.dart';

Color parseMobileEditorLineColorHex(
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

/// 叠在移动端正文 [TextField] 上的稿纸参考线层（需置于 [Stack] 内）。
///
/// 与桌面端不同：移动端**不**用独立 [TextPainter] 预测排版。真机上系统字体、
/// 字形度量与 Flutter 预测排版之间存在固定纵向偏移，会让预测出的划线整体上移
/// 穿过字形。这里改为直接从 [TextField] 内部的 [RenderEditable] 读取每个可视行
/// 的真实行框底边——与屏幕上文字 100% 对齐，与字体/缩放无关。
///
/// [fieldKey] 必须挂在目标 [TextField] 上，用于定位其 [RenderEditable]。
/// [TextField] 使用 [expands] 在内部滚动时，行底边为内容坐标，按
/// [scrollController].offset 反向平移与正文同步。
class MobileEditorFocusLines extends StatefulWidget {
  const MobileEditorFocusLines({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.scrollController,
    required this.lineStyle,
    required this.lineColor,
  });

  final GlobalKey fieldKey;
  final TextEditingController controller;
  final ScrollController scrollController;
  final EditorLineStyle lineStyle;
  final Color lineColor;

  @override
  State<MobileEditorFocusLines> createState() => _MobileEditorFocusLinesState();
}

class _MobileEditorFocusLinesState extends State<MobileEditorFocusLines> {
  List<double> _lineBottoms = const [];
  // 画线层原点 → RenderEditable 内容原点的常量纵向内缩（真机 TextField 顶部存在
  // 一段内缩，与画线层坐标系不重合）。从真实渲染几何实测，避免硬编码或假设为 0。
  double _contentInset = 0;
  Timer? _recomputeDebounce;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleRecompute);
    _scheduleRecompute();
  }

  @override
  void didUpdateWidget(covariant MobileEditorFocusLines oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleRecompute);
      widget.controller.addListener(_scheduleRecompute);
    }
    // 字号/行高/宽度变化会改变排版，重新读取真实行几何。
    _scheduleRecompute();
  }

  @override
  void dispose() {
    _recomputeDebounce?.cancel();
    widget.controller.removeListener(_scheduleRecompute);
    super.dispose();
  }

  // 行枚举需遍历全文（长章节较重），与高亮一致用防抖：停顿后按最新排版重算。
  void _scheduleRecompute() {
    _recomputeDebounce?.cancel();
    _recomputeDebounce = Timer(const Duration(milliseconds: 180), _recompute);
  }

  void _recompute() {
    if (!mounted) {
      return;
    }
    final renderEditable = _findRenderEditable();
    final length = widget.controller.text.length;
    final inset = _measureContentInset(renderEditable) ?? _contentInset;
    final next = (renderEditable == null || length == 0)
        ? const <double>[]
        : _lineBottomsFrom(renderEditable, length);
    if (inset != _contentInset || !listEquals(_lineBottoms, next)) {
      setState(() {
        _contentInset = inset;
        _lineBottoms = next;
      });
    }
  }

  /// 实测画线层原点到 [RenderEditable] 内容原点的常量纵向内缩。
  ///
  /// `reTop - layerTop` 随滚动变化（内容上移），加回当前 `scroll` 即得到与滚动
  /// 无关的常量内缩。绘制时再 `inset - scroll` 还原，既修正内缩又保持滚动平滑。
  double? _measureContentInset(RenderEditable? renderEditable) {
    if (renderEditable == null || !renderEditable.attached) {
      return null;
    }
    final layerBox = context.findRenderObject() as RenderBox?;
    if (layerBox == null || !layerBox.hasSize) {
      return null;
    }
    final scroll = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    final reTop = renderEditable.localToGlobal(Offset.zero).dy;
    final layerTop = layerBox.localToGlobal(Offset.zero).dy;
    return (reTop - layerTop) + scroll;
  }

  RenderEditable? _findRenderEditable() {
    final root = widget.fieldKey.currentContext?.findRenderObject();
    if (root == null) {
      return null;
    }
    RenderEditable? found;
    void visit(RenderObject node) {
      if (found != null) {
        return;
      }
      if (node is RenderEditable) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  /// 枚举每个可视行的行框底边（[RenderEditable] 内容坐标）。
  ///
  /// 逐行用 [RenderEditable.getLineAtOffset] 跳进下一行，按光标矩形 `top` 去重——
  /// 软换行、硬换行（`\n`）、空行、行尾换行都能精确得到一行一条，不漏不重。
  List<double> _lineBottomsFrom(RenderEditable renderEditable, int length) {
    final seenTops = <double>{};
    final bottoms = <double>[];
    var offset = 0;
    var guard = 0;
    while (offset <= length && guard++ < 100000) {
      final position = TextPosition(offset: offset);
      final caret = renderEditable.getLocalRectForCaret(position);
      if (seenTops.add(caret.top.roundToDouble())) {
        bottoms.add(caret.bottom);
      }
      final line = renderEditable.getLineAtOffset(position);
      offset = line.end > offset ? line.end : offset + 1;
    }
    return bottoms;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRect(
          child: ListenableBuilder(
            listenable: widget.scrollController,
            builder: (context, _) {
              final scrollOffset = widget.scrollController.hasClients
                  ? widget.scrollController.offset
                  : 0.0;
              return Transform.translate(
                offset: Offset(0, _contentInset - scrollOffset),
                child: CustomPaint(
                  painter: MobileFocusLinePainter(
                    lineStyle: widget.lineStyle,
                    lineColor: widget.lineColor,
                    lineBottoms: _lineBottoms,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class MobileFocusLinePainter extends CustomPainter {
  MobileFocusLinePainter({
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
  bool shouldRepaint(MobileFocusLinePainter oldDelegate) {
    return oldDelegate.lineStyle != lineStyle ||
        oldDelegate.lineColor != lineColor ||
        !listEquals(oldDelegate.lineBottoms, lineBottoms);
  }
}
