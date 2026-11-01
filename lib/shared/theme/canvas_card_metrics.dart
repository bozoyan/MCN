// 职责: 画布卡片的几何 token，画布卡片 widget 与导出预览 SVG 共用同一份间距与尺寸。
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_node_widget.dart
//   lib/desktop/features/canvas/export_preview.dart
//   lib/shared/services/canvas_export/svg.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'reveric_spacing.dart';

/// 引用卡片：左右内边距、类型 chip、chip 与文字的间距；文字列垂直居中。
abstract final class CanvasReferenceCardMetrics {
  static const double paddingX = RevericSpacing.lg;
  static const double chipSize = 28;
  static const double chipRadius = RevericRadius.medium;
  static const double iconSize = 15;
  static const double chipGap = RevericSpacing.md;
  static const double radius = RevericRadius.large;
  static const int titleMaxLines = 2;
}

/// 便签卡片：内边距、标签行图标与间距、正文行高。
abstract final class CanvasStickyCardMetrics {
  static const double paddingLeft = RevericSpacing.lg;
  static const double paddingTop = RevericSpacing.md;
  static const double paddingRight = RevericSpacing.lg;
  static const double paddingBottom = RevericSpacing.lg;
  static const double iconSize = 12;
  static const double iconGap = RevericSpacing.xxs;
  static const double bodyGap = RevericSpacing.xs;
  static const double bodyHeight = 1.75;
  static const double labelLetterSpacing = 0.6;
  static const double radius = RevericRadius.large;
}
