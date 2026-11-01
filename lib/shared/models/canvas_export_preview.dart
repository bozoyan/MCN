// 职责: 导出预览 SVG 的视觉输入 —— 主 isolate 按画布主题、文案与文字排版预先算好的纯值，
//       编码 isolate 只负责按卡片几何 token 把它们画成矢量。
// 关联文件:
//   lib/desktop/features/canvas/export_preview.dart
//   lib/shared/services/canvas_export/svg.dart
//   lib/shared/theme/canvas_card_metrics.dart
//   lib/shared/theme/canvas_colors.dart

import 'dart:ui';

/// 一种文字样式。[lineHeight] 与 [ascent] 取自 Flutter 排版的实际行度量，
/// SVG 按它们逐行摆放基线，行距与画布一致。
class CanvasExportTextStyle {
  const CanvasExportTextStyle({
    required this.fontSize,
    required this.fontWeight,
    required this.color,
    required this.lineHeight,
    required this.ascent,
    this.fontFamily,
    this.letterSpacing = 0,
    this.lineThroughColor,
  });

  final String? fontFamily;
  final double fontSize;

  /// 100–900。
  final int fontWeight;
  final Color color;
  final double lineHeight;
  final double ascent;
  final double letterSpacing;

  /// 非 null 时画删除线（失效引用的标题）。
  final Color? lineThroughColor;
}

/// 已按画布同样的宽度、最大行数与省略规则断好行的文字。
class CanvasExportText {
  const CanvasExportText({required this.lines, required this.style});

  final List<String> lines;
  final CanvasExportTextStyle style;

  double get height => lines.length * style.lineHeight;
}

/// 卡片投影的一层。
class CanvasExportShadow {
  const CanvasExportShadow({
    required this.color,
    required this.blur,
    required this.offset,
  });

  final Color color;
  final double blur;
  final Offset offset;
}

sealed class CanvasExportNodeFace {
  const CanvasExportNodeFace({required this.fill, required this.border});

  final Color fill;
  final Color border;
}

/// 引用卡片：左侧类型 chip + 垂直居中的标题与副标题。
class CanvasExportReferenceFace extends CanvasExportNodeFace {
  const CanvasExportReferenceFace({
    required super.fill,
    required super.border,
    required this.chipFill,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.chipBorder,
  });

  final Color chipFill;
  final Color? chipBorder;

  /// [CanvasExportPreview.icons] 的键。
  final String icon;
  final Color iconColor;
  final CanvasExportText title;
  final CanvasExportText subtitle;
}

/// 便签卡片：纸色底、图标 + 标签行、正文按可用高度截断。
class CanvasExportStickyFace extends CanvasExportNodeFace {
  const CanvasExportStickyFace({
    required super.fill,
    required super.border,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.body,
  });

  final String icon;
  final Color iconColor;
  final CanvasExportText label;
  final CanvasExportText body;
}

/// 连线的颜色、线型与标签。
class CanvasExportEdgeFace {
  const CanvasExportEdgeFace({
    required this.color,
    this.dash,
    this.label,
    this.labelWidth = 0,
  });

  final Color color;
  final List<double>? dash;
  final CanvasExportText? label;

  /// 标签文字最宽一行的排版宽度，不含内边距。
  final double labelWidth;
}

class CanvasExportPreview {
  const CanvasExportPreview({
    required this.background,
    required this.strokeWidth,
    required this.labelBackground,
    required this.labelRadius,
    required this.labelPaddingX,
    required this.labelPaddingY,
    required this.shadows,
    required this.icons,
    required this.nodes,
    required this.edges,
  });

  final Color background;
  final double strokeWidth;
  final Color labelBackground;
  final double labelRadius;
  final double labelPaddingX;
  final double labelPaddingY;
  final List<CanvasExportShadow> shadows;

  /// 图标键 → SVG 源码（用 currentColor 着色）。
  final Map<String, String> icons;

  /// 节点 id → 卡片外观。
  final Map<String, CanvasExportNodeFace> nodes;

  /// 连线 id → 连线外观。
  final Map<String, CanvasExportEdgeFace> edges;
}
