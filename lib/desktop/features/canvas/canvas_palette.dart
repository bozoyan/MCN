// 职责: 画布 flow 主题（节点、连线、端口、点网格、边标签）；专用色的派生函数在 shared/theme/canvas_colors.dart
// 关联文件:
//   lib/shared/theme/reveric_colors.dart
//   lib/shared/database/novel_content_database.dart
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
//   lib/desktop/features/screenplay/board.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../../shared/models/canvas_connection_path.dart';
import '../../../shared/theme/canvas_colors.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/app_background.dart';
import '../../../third/flow/vyuh_node_flow.dart' as flow;

// 节点颜色 key 的真源在 `lib/shared/models/canvas_layout.dart`(AI 工具层也要用);
// 此处 re-export 保持既有 import canvas_palette.dart 的调用点不变。
export '../../../shared/models/canvas_layout.dart'
    show
        canvasStickyColorSand,
        canvasStickyColorSage,
        canvasStickyColorRose,
        canvasStickyColorStone,
        canvasStickyColorKeys,
        canvasStickyColorDefault,
        canvasNodeColorRed,
        canvasNodeColorOrange,
        canvasNodeColorYellow,
        canvasNodeColorGreen,
        canvasNodeColorTeal,
        canvasNodeColorBlue,
        canvasNodeColorPurple,
        canvasNodeColorPink,
        canvasNodeVividColorKeys,
        canvasNodeColorKeys,
        canvasNodeColorStyleKey,
        isCanvasNodeColorValue,
        canvasNodeColorValueOf,
        canvasStyleWithColor;
// 色值从主题 token 派生的函数与导出预览共用，真源在 shared。
export '../../../shared/theme/canvas_colors.dart';

/// 画布的 flow 主题。
///
/// [typography] / [fontFamily] 只为边标签服务：标签由 CustomPainter 直接绘制，
/// 不走 widget 树，因此拿不到 DefaultTextStyle —— 不显式给字体，中文标签会渲染成
/// 一排缺字方块。
flow.NodeFlowTheme canvasFlowTheme(
  RevericColors colors,
  RevericTypography typography,
  bool appBackgroundActive, {
  String? fontFamily,
}) {
  return flow.NodeFlowTheme.light.copyWith(
    backgroundColor: appChromeBackgroundColor(
      colors,
      appBackgroundActive,
      colors.canvas,
    ),
    nodeTheme: flow.NodeFlowTheme.light.nodeTheme.copyWith(
      backgroundColor: Colors.transparent,
      selectedBackgroundColor: Colors.transparent,
      highlightBackgroundColor: Colors.transparent,
      borderColor: Colors.transparent,
      borderWidth: 0,
      selectedBorderColor: Colors.transparent,
      selectedBorderWidth: 0,
      borderRadius: BorderRadius.circular(RevericRadius.x2l),
    ),
    connectionTheme: canvasConnectionGeometryTheme.copyWith(
      color: colors.textMuted.withValues(alpha: 0.42),
      selectedColor: colors.accent,
      // 设计稿 strokeWidth={on ? 3 : 1.8}：连线是画布上唯一表达结构的图形，
      // 1.4 在点网格底上偏细，缩放到 0.7 左右几乎糊掉。
      strokeWidth: 1.8,
      selectedStrokeWidth: 3,
    ),
    temporaryConnectionTheme: flow.NodeFlowTheme.light.temporaryConnectionTheme
        .copyWith(
          style: flow.ConnectionStyles.bezier,
          color: colors.accent,
          strokeWidth: 2,
        ),
    portTheme: flow.NodeFlowTheme.light.portTheme.copyWith(
      size: const Size(8, 8),
      shape: flow.MarkerShapes.circle,
      color: Colors.transparent,
      connectedColor: Colors.transparent,
      highlightColor: Colors.transparent,
      borderColor: Colors.transparent,
      highlightBorderColor: colors.accent,
      borderWidth: 0,
    ),
    gridTheme: flow.GridTheme.light.copyWith(
      // 点网格只做空间参照，压低对比让节点靠自身描边浮出。
      color: canvasGridDotColor(colors),
      size: 24,
      thickness: 1,
      style: flow.GridStyles.dots,
    ),
    // 边标签是"骑在连线上"的小字条(设计稿 .cv-edge-label)：用画布底色遮断
    // 线条、不描边、圆角只取 small。之前用 surface + 描边 + pill，在浅色画布上
    // 反而像一枚独立的按钮，抢连线的视线。
    // 整体重建而非 copyWith：LabelTheme.copyWith 是 `border ?? this.border`，
    // 传 null 清不掉 light 预设自带的灰描边。
    labelTheme: flow.LabelTheme(
      textStyle: typography.uiTinySemibold.copyWith(
        height: 1.2,
        color: colors.textSecondary,
        fontFamily: fontFamily,
      ),
      backgroundColor: appChromeBackgroundColor(
        colors,
        appBackgroundActive,
        colors.canvas,
      ),
      borderRadius: BorderRadius.circular(RevericRadius.small),
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.xs,
        vertical: 1,
      ),
    ),
  );
}
