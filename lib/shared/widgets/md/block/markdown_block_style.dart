// 职责: Markdown 分块渲染配置 — 统一可见块、光标绘制与几何命中使用的排版参数
// 关联文件:
//   lib/shared/widgets/md/block/markdown_readonly_block.dart
//   lib/shared/widgets/md/block/markdown_block_list_view.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

/// 同一份实例传给显示、命中与光标 painter，保证只存在一套文本几何。
class MarkdownBlockStyle {
  const MarkdownBlockStyle({
    required this.textStyle,
    required this.hintStyle,
    required this.strutStyle,
    required this.textHeightBehavior,
  });

  final TextStyle textStyle;
  final TextStyle hintStyle;
  final StrutStyle strutStyle;
  final TextHeightBehavior textHeightBehavior;

  /// 尾距为最后一列光标保留绘制空间，不因是否聚焦改变段落可用宽度。
  static const double cursorWidth = 2;
  static const double textEndInset = 1 + cursorWidth;

  double effectiveTextWidth(double maxWidth) {
    return (maxWidth - textEndInset).clamp(1.0, double.infinity);
  }

  double preferredLineHeight(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      strutStyle: strutStyle,
      textHeightBehavior: textHeightBehavior,
    );
    final height = painter.preferredLineHeight;
    painter.dispose();
    return height;
  }
}
