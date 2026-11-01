// 职责: 定义画布布局几何与边方向，计算初次摆位和按稳定顺序的全量网格排列。
// 关联文件:
//   lib/shared/services/ai/tools_canvas.dart
//   lib/shared/services/canvas_service.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart

import 'dart:ui';

/// 便签节点默认尺寸。
///
/// 宽 280 给 14px 中文约 20 字的空间,3 行内容基本不截;高 168 容得下
/// 标题 + 3 行正文 + 留白。UI 层与 AI 工具层共用同一份数字 —— 早先两边
/// 各写一套,AI 按 260 排布便签而 UI 按 280 渲染,于是每张卡压后一张 20px。
const double canvasStickyDefaultWidth = 280;
const double canvasStickyDefaultHeight = 168;
const Size canvasStickyDefaultSize = Size(
  canvasStickyDefaultWidth,
  canvasStickyDefaultHeight,
);

/// 引用节点默认尺寸(图标 + 双行标题)。
const double canvasReferenceDefaultWidth = 256;
const double canvasReferenceDefaultHeight = 62;
const Size canvasReferenceDefaultSize = Size(
  canvasReferenceDefaultWidth,
  canvasReferenceDefaultHeight,
);

/// 便签 resize 约束。
const Size canvasStickyMinSize = Size(180, 108);
const Size canvasStickyMaxSize = Size(420, 360);

// ---- 节点颜色 key ----
//
// 真源放在 model 层:AI 工具层(lib/shared)与画布 UI(lib/desktop)都要用它,
// 而具体色值仍由 `canvas_colors.dart` 派生 —— 这里只定 key。
//
// 颜色值有两种形态:预设 key(下列常量),或用户自定义的 `#RRGGBB`。

const String canvasStickyColorSand = 'sand';
const String canvasStickyColorSage = 'sage';
const String canvasStickyColorRose = 'rose';
const String canvasStickyColorStone = 'stone';

// 鲜艳色：固定色相，不随主题换色。
const String canvasNodeColorRed = 'red';
const String canvasNodeColorOrange = 'orange';
const String canvasNodeColorYellow = 'yellow';
const String canvasNodeColorGreen = 'green';
const String canvasNodeColorTeal = 'teal';
const String canvasNodeColorBlue = 'blue';
const String canvasNodeColorPurple = 'purple';
const String canvasNodeColorPink = 'pink';

/// 低饱和纸色(随主题 token 派生)。
const List<String> canvasStickyColorKeys = <String>[
  canvasStickyColorSand,
  canvasStickyColorSage,
  canvasStickyColorRose,
  canvasStickyColorStone,
];

/// 鲜艳色。
const List<String> canvasNodeVividColorKeys = <String>[
  canvasNodeColorRed,
  canvasNodeColorOrange,
  canvasNodeColorYellow,
  canvasNodeColorGreen,
  canvasNodeColorTeal,
  canvasNodeColorBlue,
  canvasNodeColorPurple,
  canvasNodeColorPink,
];

/// 全部预设颜色(选择器渲染顺序,也是 AI 工具的合法取值集合)。
const List<String> canvasNodeColorKeys = <String>[
  ...canvasStickyColorKeys,
  ...canvasNodeVividColorKeys,
];

/// 新建便签的默认纸色。引用节点没有默认色(不着色)。
const String canvasStickyColorDefault = canvasStickyColorSand;

/// `CanvasNodes.style` 中存放节点颜色的字段名。
const String canvasNodeColorStyleKey = 'color';

/// 自定义颜色 `#RRGGBB` 的正则。
const String canvasNodeCustomColorPattern = r'^#[0-9A-Fa-f]{6}$';

final RegExp _canvasCustomColorPattern = RegExp(canvasNodeCustomColorPattern);

/// [value] 是否为合法颜色值(预设 key 或 `#RRGGBB`)。
bool isCanvasNodeColorValue(Object? value) =>
    value is String &&
    (canvasNodeColorKeys.contains(value) ||
        _canvasCustomColorPattern.hasMatch(value));

/// 从节点 style 读颜色值；未设置或非法时返回 null。
String? canvasNodeColorValueOf(Map<String, dynamic>? style) {
  final value = style?[canvasNodeColorStyleKey];
  if (isCanvasNodeColorValue(value)) {
    return value as String;
  }
  return null;
}

/// 在原 style 上写入颜色；[value] 为 null 表示清除颜色。
Map<String, dynamic> canvasStyleWithColor(
  Map<String, dynamic>? style,
  String? value,
) {
  final next = <String, dynamic>{...?style}..remove(canvasNodeColorStyleKey);
  if (value != null) {
    next[canvasNodeColorStyleKey] = value;
  }
  return next;
}

/// 网格相邻两格之间的空隙。步长 = 默认尺寸 + 空隙,因此按网格摆放的节点
/// 天然带留白,不可能重叠。
///
/// 横向留 120 是被边标签逼出来的：连线中点会压一枚不透明的标签小字条
/// (设计稿 .cv-edge-label),「第11章起」这类五字标签就有 ~67px 宽。空隙小于
/// 它时整段连线会被字条盖死，画布上只剩标签、看不见线。设计稿 demo 同样把
/// 列间距留到 ~114px。
const double canvasGridGapX = 120;
const double canvasGridGapY = 80;

/// 网格步长:列距 400 / 行距 248。
const double canvasGridPitchX = canvasStickyDefaultWidth + canvasGridGapX;
const double canvasGridPitchY = canvasStickyDefaultHeight + canvasGridGapY;

/// 自动追加时每行最多排几列,超出换行。
const int canvasGridColumnsPerRow = 6;

/// 避让判定时给候选矩形留的最小呼吸量。
///
/// 只靠 `Rect.overlaps` 会把「刚好贴边」判成不重叠,视觉上仍是糊在一起。
const double _canvasNodeMinGap = 8;

/// 避让最多推进多少格,防御性上限(正常画布远达不到)。
const int _maxAvoidSteps = 64;

/// 相对已有节点的摆放方位。
enum CanvasPlaceDirection { right, left, above, below }

/// 摆位结果。[adjusted] 为 true 表示原始落点与已有节点重叠,已自动推开。
typedef CanvasPlacement = ({Offset position, bool adjusted});

/// 把「网格位 / 相对方位 / 精确坐标」解析成最终画布坐标。
///
/// 优先级 [explicit] > [anchor]+[direction] > [col]/[row] > 自动追加到下一个空格。
///
/// - [explicit] 是逃生口(用户手拖、精确摆位),**原样返回、不做避让**：调用方
///   既然给了确切坐标,就不该被算法挪走。
/// - 其余路径最后统一过一次确定性避让：与 [occupied] 任一矩形相交就沿 +x
///   推进一格,直到不相交。
///
/// [occupied] 是同一张画布上已有节点的矩形(不含待摆放的这个)。
CanvasPlacement resolveCanvasNodePlacement({
  required Size size,
  required List<Rect> occupied,
  Offset? explicit,
  Rect? anchor,
  CanvasPlaceDirection? direction,
  int? col,
  int? row,
}) {
  if (explicit != null) {
    return (position: explicit, adjusted: false);
  }

  final Offset base;
  if (anchor != null && direction != null) {
    base = _anchoredOrigin(anchor, direction, size);
  } else if (col != null || row != null) {
    base = canvasGridOrigin(col ?? 0, row ?? 0);
  } else {
    base = _nextFreeCell(size, occupied);
  }

  return _avoidOverlap(base, size, occupied);
}

/// 网格位 → 画布坐标。负数网格位合法(画布向左/上无限延伸)。
Offset canvasGridOrigin(int col, int row) {
  return Offset(col * canvasGridPitchX, row * canvasGridPitchY);
}

/// 画布坐标 → 最接近的网格位(工具返回值里回报给 AI,便于它接着往后排)。
(int col, int row) canvasGridCellOf(Offset position) {
  return (
    (position.dx / canvasGridPitchX).round(),
    (position.dy / canvasGridPitchY).round(),
  );
}

Offset _anchoredOrigin(Rect anchor, CanvasPlaceDirection direction, Size size) {
  return switch (direction) {
    CanvasPlaceDirection.right => Offset(
      anchor.right + canvasGridGapX,
      anchor.top,
    ),
    CanvasPlaceDirection.left => Offset(
      anchor.left - canvasGridGapX - size.width,
      anchor.top,
    ),
    CanvasPlaceDirection.below => Offset(
      anchor.left,
      anchor.bottom + canvasGridGapY,
    ),
    CanvasPlaceDirection.above => Offset(
      anchor.left,
      anchor.top - canvasGridGapY - size.height,
    ),
  };
}

/// 行优先扫描第一个空网格位。没有任何已有节点时就是 (0,0)。
Offset _nextFreeCell(Size size, List<Rect> occupied) {
  for (var row = 0; row < _maxAvoidSteps; row++) {
    for (var col = 0; col < canvasGridColumnsPerRow; col++) {
      final origin = canvasGridOrigin(col, row);
      if (!_intersectsAny(origin, size, occupied)) {
        return origin;
      }
    }
  }
  return canvasGridOrigin(0, _maxAvoidSteps);
}

CanvasPlacement _avoidOverlap(Offset base, Size size, List<Rect> occupied) {
  var origin = base;
  for (var step = 0; step < _maxAvoidSteps; step++) {
    if (!_intersectsAny(origin, size, occupied)) {
      return (position: origin, adjusted: origin != base);
    }
    origin = Offset(origin.dx + canvasGridPitchX, origin.dy);
  }
  return (position: origin, adjusted: true);
}

bool _intersectsAny(Offset origin, Size size, List<Rect> occupied) {
  return canvasNodeOverlaps(origin: origin, size: size, occupied: occupied);
}

/// 落在 [origin] 的 [size] 大小节点是否与 [occupied] 任一矩形挨得太近。
///
/// public 供 `canvas_auto_layout.dart` 复用 —— 两处若各写一份「多近算重叠」,
/// 重排摆出来的间距会和新增节点的避让间距对不上。
bool canvasNodeOverlaps({
  required Offset origin,
  required Size size,
  required List<Rect> occupied,
}) {
  final candidate = (origin & size).inflate(_canvasNodeMinGap);
  for (final rect in occupied) {
    if (candidate.overlaps(rect)) {
      return true;
    }
  }
  return false;
}

/// 自由画布：按行追加，整理时只按连线调列，手动摆过的节点不动。
const String canvasLayoutAuto = 'auto';
const String canvasLayoutTreeLr = 'tree_lr';
const String canvasLayoutTreeTb = 'tree_tb';
const String canvasLayoutGrid = 'grid';

/// 整理现有布局：按画布已保存的布局重跑一次，不是一种布局，不落库。
const String canvasLayoutTidy = 'tidy';

/// 可保存为画布布局的取值。
const List<String> canvasLayoutSavedModes = [
  canvasLayoutAuto,
  canvasLayoutTreeLr,
  canvasLayoutTreeTb,
  canvasLayoutGrid,
];

/// 可执行的排列操作，也是菜单顺序。
const List<String> canvasLayoutModes = [
  canvasLayoutTidy,
  ...canvasLayoutSavedModes,
];

/// 有向语义属于共享图契约，不能把关系边的存储端点顺序解释为先后。
bool isCanvasEdgeDirected(String type) => switch (type) {
  'timeline' || 'causal' || 'foreshadow_payoff' => true,
  _ => false,
};

/// 连线在节点上的出入边，落在该边中点。
enum CanvasAnchorSide { top, right, bottom, left }

/// 层级图沿阅读方向分开入口与出口；自由布局按中心相对位置选边界。
///
/// 层级图优先使用布局轴，同层循环或自由布局按 dx/dy 的绝对值大小挑选「主方向」：
/// - 水平差更大：源用 right/left，目标用相反侧
/// - 垂直差更大：源用 bottom/top，目标用相反侧
///
/// 画布连线与导出的 SVG 共用这一份口径，调用方只对有向边传 [layout]。
(CanvasAnchorSide source, CanvasAnchorSide target) canvasEdgeAnchorSides(
  Offset sourceCenter,
  Offset targetCenter, {
  String? layout,
}) {
  final dx = targetCenter.dx - sourceCenter.dx;
  final dy = targetCenter.dy - sourceCenter.dy;
  if (layout == canvasLayoutTreeTb && dy != 0) {
    return dy > 0
        ? (CanvasAnchorSide.bottom, CanvasAnchorSide.top)
        : (CanvasAnchorSide.top, CanvasAnchorSide.bottom);
  }
  if (layout == canvasLayoutTreeLr && dx != 0) {
    return dx > 0
        ? (CanvasAnchorSide.right, CanvasAnchorSide.left)
        : (CanvasAnchorSide.left, CanvasAnchorSide.right);
  }
  if (dx.abs() >= dy.abs()) {
    return dx >= 0
        ? (CanvasAnchorSide.right, CanvasAnchorSide.left)
        : (CanvasAnchorSide.left, CanvasAnchorSide.right);
  }
  return dy >= 0
      ? (CanvasAnchorSide.bottom, CanvasAnchorSide.top)
      : (CanvasAnchorSide.top, CanvasAnchorSide.bottom);
}

/// 布局计算只接收值对象，不携带数据库行、正文或 UI controller。
class CanvasArrangeNode {
  const CanvasArrangeNode({
    required this.id,
    required this.sortOrder,
    required this.size,
    this.position = Offset.zero,
  });

  final String id;
  final int sortOrder;
  final Size size;
  final Offset position;
}

class CanvasArrangeEdge {
  const CanvasArrangeEdge({
    required this.sourceNodeId,
    required this.targetNodeId,
    required this.type,
  });

  final String sourceNodeId;
  final String targetNodeId;
  final String type;
}

class CanvasLayoutRequest {
  CanvasLayoutRequest({
    required this.mode,
    required Iterable<CanvasArrangeNode> nodes,
    required Iterable<CanvasArrangeEdge> edges,
  }) : nodes = List.unmodifiable(nodes),
       edges = List.unmodifiable(edges);

  final String mode;
  final List<CanvasArrangeNode> nodes;
  final List<CanvasArrangeEdge> edges;
}

class CanvasLayoutSaveResult {
  const CanvasLayoutSaveResult({
    required this.moved,
    required this.modeChanged,
  });
  final int moved;
  final bool modeChanged;
}

int compareCanvasArrangeNodes(CanvasArrangeNode a, CanvasArrangeNode b) {
  final order = a.sortOrder.compareTo(b.sortOrder);
  return order == 0 ? a.id.compareTo(b.id) : order;
}

/// 全量网格按身份顺序排布，使用每列/行最大尺寸，不改变原有追加网格坐标系。
Map<String, Offset> resolveCanvasGridLayout(Iterable<CanvasArrangeNode> nodes) {
  final ordered = nodes.toList()..sort(compareCanvasArrangeNodes);
  final widths = List<double>.filled(canvasGridColumnsPerRow, 0);
  final heights = List<double>.filled(
    (ordered.length / canvasGridColumnsPerRow).ceil(),
    0,
  );
  for (var i = 0; i < ordered.length; i++) {
    final size = ordered[i].size;
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      throw ArgumentError('Canvas node size must be positive and finite.');
    }
    final col = i % canvasGridColumnsPerRow;
    final row = i ~/ canvasGridColumnsPerRow;
    if (size.width > widths[col]) {
      widths[col] = size.width;
    }
    if (size.height > heights[row]) {
      heights[row] = size.height;
    }
  }
  final xs = <double>[];
  var x = 56.0;
  for (final width in widths) {
    xs.add(x);
    x += width + canvasGridGapX;
  }
  final ys = <double>[];
  var y = 44.0;
  for (final height in heights) {
    ys.add(y);
    y += height + canvasGridGapY;
  }
  return {
    for (var i = 0; i < ordered.length; i++)
      ordered[i].id: Offset(
        xs[i % canvasGridColumnsPerRow],
        ys[i ~/ canvasGridColumnsPerRow],
      ),
  };
}
