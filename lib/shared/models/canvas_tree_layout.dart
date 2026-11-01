// 职责: 按有向图强连通分量与最长路径生成稳定、无节点重叠的横向或纵向层级坐标，
//       并为跨多层的有向边给出贴着自留通道走的路点。
// 关联文件:
//   lib/shared/models/canvas_layout.dart
//   lib/shared/services/canvas_service.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'canvas_layout.dart';

enum CanvasTreeDirection { left_to_right, top_to_bottom }

/// 走线占位总数上限。每条边按跨过的层数占位，病态大图（上万条长边）会把排序
/// 撑到秒级；超出后剩余的长边不留通道、不给路点，节点坐标照常。
const int _maxRouteLanes = 20000;

/// 树形布局结果。[waypoints] 以 (source, target) 节点 id 为键，只收跨多层的有向边；
/// 同一对节点间不同类型的边共用一条通道。
typedef CanvasTreeRouting = ({
  Map<String, Offset> positions,
  Map<(String, String), List<Offset>> waypoints,
});

Map<String, Offset> resolveCanvasTreeLayout({
  required Iterable<CanvasArrangeNode> nodes,
  required Iterable<CanvasArrangeEdge> edges,
  CanvasTreeDirection direction = CanvasTreeDirection.left_to_right,
}) {
  return resolveCanvasTreeRouting(
    nodes: nodes,
    edges: edges,
    direction: direction,
  ).positions;
}

CanvasTreeRouting resolveCanvasTreeRouting({
  required Iterable<CanvasArrangeNode> nodes,
  required Iterable<CanvasArrangeEdge> edges,
  CanvasTreeDirection direction = CanvasTreeDirection.left_to_right,
}) {
  final ordered = nodes.toList()..sort(compareCanvasArrangeNodes);
  final byId = {for (var i = 0; i < ordered.length; i++) ordered[i].id: i};
  if (byId.length != ordered.length) {
    throw ArgumentError('Canvas node IDs must be unique.');
  }
  final vertical = direction == CanvasTreeDirection.top_to_bottom;
  final sizes = [
    for (final node in ordered)
      vertical ? Size(node.size.height, node.size.width) : node.size,
  ];
  for (final size in sizes) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      throw ArgumentError('Canvas node size must be positive and finite.');
    }
  }
  final outgoing = List.generate(ordered.length, (_) => <int>{});
  final incoming = List.generate(ordered.length, (_) => <int>{});
  for (final edge in edges) {
    final source = byId[edge.sourceNodeId];
    final target = byId[edge.targetNodeId];
    if (source != null && target != null && isCanvasEdgeDirected(edge.type)) {
      outgoing[source].add(target);
      incoming[target].add(source);
    }
  }
  final next = [for (final ids in outgoing) ids.toList()..sort()];
  final previous = [for (final ids in incoming) ids.toList()..sort()];
  // 非递归 Kosaraju：深链和大循环不会耗尽调用栈。
  final seen = <int>{};
  final finished = <int>[];
  for (var start = 0; start < ordered.length; start++) {
    if (!seen.add(start)) {
      continue;
    }
    final stack = <(int, int)>[(start, 0)];
    while (stack.isNotEmpty) {
      final (node, index) = stack.last;
      if (index == next[node].length) {
        finished.add(node);
        stack.removeLast();
      } else {
        stack[stack.length - 1] = (node, index + 1);
        final child = next[node][index];
        if (seen.add(child)) {
          stack.add((child, 0));
        }
      }
    }
  }
  final componentOf = List<int>.filled(ordered.length, -1);
  final members = <List<int>>[];
  for (final start in finished.reversed) {
    if (componentOf[start] != -1) {
      continue;
    }
    final component = members.length;
    final group = <int>[];
    final stack = <int>[start];
    componentOf[start] = component;
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      group.add(node);
      for (final parent in previous[node]) {
        if (componentOf[parent] == -1) {
          componentOf[parent] = component;
          stack.add(parent);
        }
      }
    }
    group.sort();
    members.add(group);
  }
  final children = List.generate(members.length, (_) => <int>{});
  final parents = List.generate(members.length, (_) => <int>{});
  for (var node = 0; node < ordered.length; node++) {
    final source = componentOf[node];
    for (final child in next[node]) {
      final target = componentOf[child];
      if (source != target) {
        children[source].add(target);
        parents[target].add(source);
      }
    }
  }
  // 走线占位没有成员，排序键借用它终点分组的键，同键再按创建顺序。
  final groupKeys = [for (final group in members) group.first];
  int compareGroups(int a, int b) {
    final order = groupKeys[a].compareTo(groupKeys[b]);
    return order == 0 ? a.compareTo(b) : order;
  }

  final groupSizes = [
    for (final group in members)
      Size(
        group.map((node) => sizes[node].width).fold(0.0, math.max),
        group.map((node) => sizes[node].height).fold(0.0, (sum, h) => sum + h) +
            canvasGridGapY * (group.length - 1),
      ),
  ];
  final participating = <int>{
    for (var node = 0; node < ordered.length; node++)
      if (next[node].isNotEmpty || previous[node].isNotEmpty) componentOf[node],
  };
  final componentOrder = participating.toList()..sort(compareGroups);
  final visited = <int>{};
  final positions = <String, Offset>{};
  var secondaryOffset = 0.0;
  Offset point(double primary, double secondary) => vertical
      ? Offset(56 + secondary, 44 + primary)
      : Offset(56 + primary, 44 + secondary);
  void place(int node, double primary, double secondary) {
    positions[ordered[node].id] = point(primary, secondary);
  }

  final chains = <(int, int), List<int>>{};
  final laneRoutes = <int, List<Offset>>{};
  final laneAt = <int, double>{};
  final laneBand = <int, (double, double)>{};
  var laneBudget = _maxRouteLanes;

  for (final start in componentOrder) {
    if (!visited.add(start)) {
      continue;
    }
    final connected = <int>[];
    final pending = Queue<int>()..add(start);
    while (pending.isNotEmpty) {
      final group = pending.removeFirst();
      connected.add(group);
      for (final neighbor in {...children[group], ...parents[group]}) {
        if (visited.add(neighbor)) {
          pending.add(neighbor);
        }
      }
    }
    connected.sort(compareGroups);
    final indegree = {
      for (final group in connected) group: parents[group].length,
    };
    final levels = {for (final group in connected) group: 0};
    final ready = Queue<int>()
      ..addAll(connected.where((group) => indegree[group] == 0));
    while (ready.isNotEmpty) {
      final group = ready.removeFirst();
      for (final child in children[group]) {
        levels[child] = math.max(levels[child]!, levels[group]! + 1);
        indegree[child] = indegree[child]! - 1;
        if (indegree[child] == 0) {
          ready.add(child);
        }
      }
    }
    // 状态、暗线这类侧挂的根只在中途汇入主干，钉在第 0 层会让它的边纵贯全图；
    // 沉到最早目标的上一层。主干起点的子节点就在第 1 层，所以第 0 层不会被搬空。
    for (final group in connected) {
      if (parents[group].isEmpty && children[group].isNotEmpty) {
        levels[group] =
            children[group].map((child) => levels[child]!).reduce(math.min) - 1;
      }
    }
    final componentChains = <List<int>>[];
    // 跨多层的边拆成逐层的走线占位，和真节点一起排序、分位置：长边于是有自己的
    // 通道，不再斜穿中间层的卡片。
    for (final group in connected.toList()) {
      for (final child in children[group].toList()..sort(compareGroups)) {
        final lanes = levels[child]! - levels[group]! - 1;
        if (lanes < 1 || lanes > laneBudget) {
          continue;
        }
        laneBudget -= lanes;
        final chain = <int>[];
        var from = group;
        for (var level = levels[group]! + 1; level < levels[child]!; level++) {
          final lane = members.length;
          members.add(const []);
          groupKeys.add(groupKeys[child]);
          groupSizes.add(Size.zero);
          children.add({});
          parents.add({});
          levels[lane] = level;
          children[from]
            ..remove(child)
            ..add(lane);
          parents[lane].add(from);
          chain.add(lane);
          connected.add(lane);
          from = lane;
        }
        children[from].add(child);
        parents[child]
          ..remove(group)
          ..add(from);
        chains[(group, child)] = chain;
        componentChains.add(chain);
      }
    }
    final layerCount = levels.values.fold(0, math.max) + 1;
    final layers = List.generate(layerCount, (_) => <int>[]);
    for (final group in connected) {
      layers[levels[group]!].add(group);
    }
    final orders = <int, int>{};
    void indexLayers() {
      for (final layer in layers) {
        for (var i = 0; i < layer.length; i++) {
          orders[layer[i]] = i;
        }
      }
    }

    indexLayers();
    void sortLayer(int level, List<Set<int>> neighbors) {
      final barycenters = <int, double>{};
      for (final group in layers[level]) {
        final adjacent = neighbors[group];
        barycenters[group] = adjacent.isEmpty
            ? orders[group]!.toDouble()
            : adjacent.fold(0.0, (sum, id) => sum + orders[id]!) /
                  adjacent.length;
      }
      layers[level].sort((a, b) {
        final order = barycenters[a]!.compareTo(barycenters[b]!);
        return order == 0 ? compareGroups(a, b) : order;
      });
      for (var i = 0; i < layers[level].length; i++) {
        orders[layers[level][i]] = i;
      }
    }

    for (var round = 0; round < 4; round++) {
      for (var level = 1; level < layerCount; level++) {
        sortLayer(level, parents);
      }
      for (var level = layerCount - 2; level >= 0; level--) {
        sortLayer(level, children);
      }
    }
    final layerHeights = [
      for (final layer in layers)
        layer.fold(0.0, (sum, group) => sum + groupSizes[group].height) +
            canvasGridGapY * (layer.length - 1),
    ];
    final height = layerHeights.fold(0.0, math.max);
    var primary = 0.0;
    for (var level = 0; level < layers.length; level++) {
      final starts = <int, double>{};
      var cursor = 0.0;
      double? realStart;
      var realEnd = 0.0;
      var width = 0.0;
      for (final group in layers[level]) {
        starts[group] = cursor;
        if (members[group].isNotEmpty) {
          realStart ??= cursor;
          realEnd = cursor + groupSizes[group].height;
        }
        cursor += groupSizes[group].height + canvasGridGapY;
        width = math.max(width, groupSizes[group].width);
      }
      // 各层按真节点的跨度围绕同一中线展开，让选择与汇合位于分支中央；走线占位
      // 不参与居中，否则只多一条通道的那层主干会被挤偏，主干不再是一条直线。
      final shift = (height - (realStart ?? 0) - realEnd) / 2;
      for (final group in layers[level]) {
        var within = secondaryOffset + shift + starts[group]!;
        if (members[group].isEmpty) {
          laneAt[group] = within;
          laneBand[group] = (primary, primary + width);
        }
        for (final node in members[group]) {
          place(node, primary, within);
          within += sizes[node].height + canvasGridGapY;
        }
      }
      primary += width + canvasGridGapX;
    }
    // 每层的占位只贴着本层最外侧的卡片，窄层离中轴近、宽层离得远，连起来是一条
    // 左右摆动的波浪线。若整条通道在它经过的每一层都是最外侧，就统一推到最外的
    // 那个位置：本来外面就没有卡片，推出去不会压到任何东西。
    for (final chain in componentChains) {
      final outer = [for (final lane in chain) layers[levels[lane]!]];
      if (chain.indexed.every((entry) => outer[entry.$1].first == entry.$2)) {
        final at = chain.map((lane) => laneAt[lane]!).reduce(math.min);
        for (final lane in chain) {
          laneAt[lane] = at;
        }
      } else if (chain.indexed.every(
        (entry) => outer[entry.$1].last == entry.$2,
      )) {
        final at = chain.map((lane) => laneAt[lane]!).reduce(math.max);
        for (final lane in chain) {
          laneAt[lane] = at;
        }
      }
      // 占位在本层的进出两端各给一个路点，线在层内笔直穿过自己的通道。
      for (final lane in chain) {
        final (from, to) = laneBand[lane]!;
        final at = laneAt[lane]!;
        laneRoutes[lane] = [point(from, at), point(to, at)];
      }
    }
    secondaryOffset += height + canvasGridGapY;
  }
  // 没有有向边的节点作为独立参考区，依旧按身份顺序，和所有图分量分开。
  final isolated = [
    for (var node = 0; node < ordered.length; node++)
      if (!participating.contains(componentOf[node])) node,
  ];
  final referenceGrid = resolveCanvasGridLayout([
    for (final node in isolated)
      CanvasArrangeNode(
        id: ordered[node].id,
        sortOrder: ordered[node].sortOrder,
        size: sizes[node],
      ),
  ]);
  for (final node in isolated) {
    final position = referenceGrid[ordered[node].id]!;
    place(node, position.dx - 56, secondaryOffset + position.dy - 44);
  }
  final waypoints = <(String, String), List<Offset>>{};
  for (var node = 0; node < ordered.length; node++) {
    for (final child in next[node]) {
      final chain = chains[(componentOf[node], componentOf[child])];
      if (chain != null) {
        waypoints[(ordered[node].id, ordered[child].id)] = [
          for (final lane in chain) ...laneRoutes[lane]!,
        ];
      }
    }
  }
  return (positions: positions, waypoints: waypoints);
}

/// 层级排列下跨多层有向边的路点，键为 (source, target) 节点 id。
///
/// 路点不落库：按当前节点与边重跑一次层级排列，只有两端节点都还停在排列给出的
/// 位置上（[CanvasArrangeNode.position]）时才采用 —— 用户拖动过端点、或排列之后
/// 又加了节点/边，这条边就退回默认曲线，不会被一组过期的通道拽着走。
/// 画布连线与导出的 SVG 共用。
Map<(String, String), List<Offset>> resolveCanvasTreeEdgeWaypoints({
  required List<CanvasArrangeNode> nodes,
  required Iterable<CanvasArrangeEdge> edges,
  String? layout,
}) {
  if (layout != canvasLayoutTreeLr && layout != canvasLayoutTreeTb) {
    return const {};
  }
  final routing = resolveCanvasTreeRouting(
    nodes: nodes,
    edges: edges,
    direction: layout == canvasLayoutTreeTb
        ? CanvasTreeDirection.top_to_bottom
        : CanvasTreeDirection.left_to_right,
  );
  final byId = {for (final node in nodes) node.id: node};
  bool arranged(String id) {
    final node = byId[id];
    final position = routing.positions[id];
    return node != null &&
        position != null &&
        (node.position - position).distance < 0.5;
  }

  return {
    for (final entry in routing.waypoints.entries)
      if (arranged(entry.key.$1) && arranged(entry.key.$2))
        entry.key: entry.value,
  };
}
