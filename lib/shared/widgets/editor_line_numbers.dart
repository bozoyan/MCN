// 职责: 在可编辑正文旁绘制跟随文本滚动的行号栏。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/mobile/pages/chapter_editor_page.dart
//   lib/shared/theme/theme.dart

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// 可复用的编辑器行号栏。
///
/// 行号按逻辑行绘制，并按正文可用宽度测量换行后的实际高度；移动端传入
/// [scrollController] 后，行号会与 TextField 的内部滚动同步。
const editorLineNumbersGutterWidth = 40.0;

class EditorLineNumbers extends StatelessWidget {
  const EditorLineNumbers({
    super.key,
    required this.controller,
    required this.contentStyle,
    required this.numberStyle,
    required this.lineHeight,
    this.scrollController,
    this.width = editorLineNumbersGutterWidth,
    this.contentWidth,
    this.textDirection,
  });

  final TextEditingController controller;
  final TextStyle contentStyle;
  final TextStyle numberStyle;
  final double lineHeight;
  final ScrollController? scrollController;
  final double width;
  final double? contentWidth;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final direction = textDirection ?? Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([controller, ?scrollController]),
        builder: (context, _) {
          final scrollOffset = scrollController?.hasClients == true
              ? scrollController!.offset
              : 0.0;
          return CustomPaint(
            painter: _EditorLineNumbersPainter(
              text: controller.text,
              contentStyle: contentStyle,
              numberStyle: numberStyle,
              lineHeight: lineHeight,
              scrollOffset: scrollOffset,
              gutterWidth: width,
              contentWidth: contentWidth,
              textDirection: direction,
              textScaler: textScaler,
              color: RevericTheme.colorsOf(context).textSubtle,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _EditorLineNumbersPainter extends CustomPainter {
  const _EditorLineNumbersPainter({
    required this.text,
    required this.contentStyle,
    required this.numberStyle,
    required this.lineHeight,
    required this.scrollOffset,
    required this.gutterWidth,
    required this.contentWidth,
    required this.textDirection,
    required this.textScaler,
    required this.color,
  });

  final String text;
  final TextStyle contentStyle;
  final TextStyle numberStyle;
  final double lineHeight;
  final double scrollOffset;
  final double gutterWidth;
  final double? contentWidth;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final availableWidth = (contentWidth ?? size.width - gutterWidth).clamp(
      1.0,
      double.infinity,
    );
    final measuredText = text.isEmpty ? ' ' : text;
    final contentPainter = TextPainter(
      text: TextSpan(text: measuredText, style: contentStyle),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: null,
    )..layout(maxWidth: availableWidth);
    final lineStarts = <int>[0];
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) == 0x0A) {
        lineStarts.add(index + 1);
      }
    }
    final lineExtent =
        textScaler.scale(contentStyle.fontSize ?? numberStyle.fontSize ?? 0) *
        lineHeight;
    for (var index = 0; index < lineStarts.length; index++) {
      final y =
          contentPainter
              .getOffsetForCaret(
                TextPosition(offset: lineStarts[index]),
                Rect.zero,
              )
              .dy -
          scrollOffset;
      if (y + lineExtent >= 0 && y <= size.height) {
        final numberPainter = TextPainter(
          text: TextSpan(
            text: '${index + 1}',
            style: numberStyle.copyWith(color: color),
          ),
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(maxWidth: gutterWidth);
        final numberY = y + (lineExtent - numberPainter.height) / 2;
        numberPainter.paint(
          canvas,
          Offset((gutterWidth - numberPainter.width) / 2, numberY),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EditorLineNumbersPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.contentStyle != contentStyle ||
        oldDelegate.numberStyle != numberStyle ||
        oldDelegate.lineHeight != lineHeight ||
        oldDelegate.scrollOffset != scrollOffset ||
        oldDelegate.gutterWidth != gutterWidth ||
        oldDelegate.contentWidth != contentWidth ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.color != color;
  }
}
