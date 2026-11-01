// 职责: 实体关系图布局与渲染常量 — 节点尺寸、间距、碰撞阈值、画布背景、缩放控件与 PNG 导出。
// 关联文件:
//   lib/shared/entity_graph/layout.dart
//   lib/shared/entity_graph/graph_widget.dart
//   lib/shared/entity_graph/edge_painter.dart
//   lib/shared/entity_graph/png_export.dart
//   lib/shared/entity_graph/overview.dart

const double kEntityGraphNodeAvatarSize = 52.0;
const double kEntityGraphNodeRingWidth = 3.0;
const double kEntityGraphNodeTotalSize =
    kEntityGraphNodeAvatarSize + kEntityGraphNodeRingWidth * 2;
const double kEntityGraphNodeWidgetWidth = 100.0;

/// 中心节点头像尺寸（大于普通节点，强调焦点）。
const double kEntityGraphCenterNodeAvatarSize = 64.0;
const double kEntityGraphCenterNodeRingWidth = 3.5;
const double kEntityGraphCenterNodeTotalSize =
    kEntityGraphCenterNodeAvatarSize + kEntityGraphCenterNodeRingWidth * 2;
const double kEntityGraphCenterNodeWidgetWidth = 124.0;
const double kEntityGraphCenterNodeHaloSpread = 4.0;

/// 力导向理想边长与层间半径基准。
const double kEntityGraphNodeSpacing = 200.0;

/// 节点中心之间的最小距离（含标签占位）。
const double kEntityGraphMinNodeDistance = 185.0;

/// 节点中心到下方标签区域的半高（用于包围盒与边裁剪）。
const double kEntityGraphNodeLabelExtent = 42.0;

const double kEntityGraphHoverCardWidth = 260.0;
const double kEntityGraphHoverCardEstimatedHeight = 156.0;

/// 无头像角色在关系图节点上展示的回退字数。
const int kEntityGraphAvatarFallbackMaxChars = 2;

/// 画布点阵背景的网格间距与点半径。
const double kEntityGraphDotGridSpacing = 22.0;
const double kEntityGraphDotGridDotRadius = 1.0;

/// 中心节点统计药丸（直接/间接关系数）。
const double kEntityGraphStatPillHeight = 18.0;

/// 画布缩放控件。
const double kEntityGraphZoomMin = 0.3;
const double kEntityGraphZoomMax = 2.6;
const double kEntityGraphZoomStep = 1.2;
const double kEntityGraphZoomButtonSize = 30.0;

/// 概览环形图尺寸。
const double kEntityGraphDonutSize = 72.0;
const double kEntityGraphDonutStrokeWidth = 10.0;
const double kEntityGraphDonutRadius =
    (kEntityGraphDonutSize - kEntityGraphDonutStrokeWidth) / 2;

/// PNG 导出：内容边界四周留白、水印行与图例带尺寸。
const double kEntityGraphExportPadding = 48.0;
const double kEntityGraphExportTitleBandHeight = 40.0;
const double kEntityGraphExportLegendRowHeight = 20.0;
const double kEntityGraphExportLegendSwatchWidth = 16.0;
const double kEntityGraphExportLegendSwatchHeight = 3.0;

/// PNG 导出分辨率上限：默认 2 倍，长边超过 6000px 时按比例下调。
const double kEntityGraphExportMaxPixelRatio = 2.0;
const double kEntityGraphExportMaxDimension = 6000.0;
