// 职责: 画布连边感知重排 — 保持主干层不动,按连边把其余层的节点重新分列,压短跨列连线
// 关联文件:
//   lib/shared/models/canvas_layout.dart
//   lib/shared/services/canvas_service.dart
//   lib/shared/services/ai/tools_canvas.dart

import 'dart:ui';

import 'canvas_layout.dart';

/// 参与重排的节点(几何 + id,不含业务字段)。
typedef CanvasLayoutNode = ({String id, Offset position, Size size});

/// 参与重排的边。只关心两端点,不区分边类型 —— 任何一条边都意味着
/// 「这两个节点应该挨近」,伏笔兑现与通用关联在布局上没有强弱之分。
typedef CanvasLayoutEdge = ({String sourceNodeId, String targetNodeId});

/// 坐标与网格点的最大允许偏差。超过即视为用户手动摆过。
const double _gridSnapTolerance = 1.0;

/// 找空列时最多左右各探多少格,防御性上限。
const int _maxColumnProbe = 64;

/// 按连边关系重算节点列位,返回**需要移动**的节点 → 新坐标。
///
/// [resolveCanvasNodePlacement] 解决的是「新节点摆哪不压别人」,它在摆位时只看得到
/// 已有节点的矩形；而边总是在节点全部落库之后才连,那一层原理上不知道谁该挨着谁。
/// 于是 AI 按资源类型分行(章节一行、伏笔一行)后,两行的列之间没有任何对应关系,
/// 每条边都成了横穿画布的长线。这里补上缺的那一步:边写完后按边重新分列。
///
/// 算法(确定性,无随机):
/// 1. 坐标不在网格点上的节点视为用户手拖 / UI 视口中心新建 —— 不移动,只当障碍物。
/// 2. 其余节点按 row 分层,保留调用方(模型或用户)给出的分层语义。
/// 3. 节点最多的那一层是**主干**(通常是章节 / 时间线,列序即故事顺序),原样不动。
/// 4. 其余层按到主干的距离依次处理:每个节点落到「已放置邻居列均值」最近的空列。
///    这是分层图布局的 barycenter 启发式 —— 单邻居节点会直接落到邻居正下方。
///
/// 层内不足以参考时(无已放置邻居)保留原列,因此无边画布、单层画布都原样返回空 map。
Map<String, Offset> resolveCanvasAutoLayout({
  required List<CanvasLayoutNode> nodes,
  required List<CanvasLayoutEdge> edges,
}) {
  if (nodes.length < 2) {
    return const <String, Offset>{};
  }

  final byId = {for (final node in nodes) node.id: node};
  final neighbors = _buildAdjacency(edges, byId);
  if (neighbors.isEmpty) {
    return const <String, Offset>{};
  }

  final rows = <int, List<CanvasLayoutNode>>{};
  final pinned = <CanvasLayoutNode>[];
  // 每个节点的参考列:on-grid 节点是精确列,pinned 节点取最近列(仅用于算均值)。
  final columnOf = <String, int>{};
  for (final node in nodes) {
    final (col, row) = canvasGridCellOf(node.position);
    columnOf[node.id] = col;
    if (_isOnGrid(node.position, col, row)) {
      (rows[row] ??= <CanvasLayoutNode>[]).add(node);
    } else {
      pinned.add(node);
    }
  }
  // 只有一层可动时没有任何跨层参照,重排无从谈起。
  if (rows.length < 2) {
    return const <String, Offset>{};
  }

  final anchorRow = _pickAnchorRow(rows);
  final occupied = <Rect>[
    for (final node in pinned) node.position & node.size,
    for (final node in rows[anchorRow]!) node.position & node.size,
  ];
  final placedColumns = <String, int>{
    for (final node in pinned) node.id: columnOf[node.id]!,
    for (final node in rows[anchorRow]!) node.id: columnOf[node.id]!,
  };

  final pending = rows.keys.where((row) => row != anchorRow).toList()
    ..sort((a, b) {
      final byDistance = (a - anchorRow).abs().compareTo((b - anchorRow).abs());
      return byDistance != 0 ? byDistance : a.compareTo(b);
    });

  final moved = <String, Offset>{};
  for (final row in pending) {
    // 快照:同层节点互不影响彼此的目标列,否则结果依赖遍历顺序。
    final reference = Map<String, int>.of(placedColumns);
    final targets =
        <({CanvasLayoutNode node, double target})>[
          for (final node in rows[row]!)
            (
              node: node,
              target:
                  _barycenter(neighbors[node.id], reference) ??
                  columnOf[node.id]!.toDouble(),
            ),
        ]..sort((a, b) {
          // 只按目标列与 id 排序,不掺入当前列 —— 掺入的话「重排一次」与「重排两次」
          // 的抢位顺序不同,同一张画布点两次按钮会得到两种布局。
          final byTarget = a.target.compareTo(b.target);
          return byTarget != 0 ? byTarget : a.node.id.compareTo(b.node.id);
        });

    for (final entry in targets) {
      final (column, cellRow) = _firstFreeCell(
        preferred: entry.target.round(),
        row: row,
        away: row > anchorRow ? 1 : -1,
        size: entry.node.size,
        occupied: occupied,
      );
      final origin = canvasGridOrigin(column, cellRow);
      occupied.add(origin & entry.node.size);
      placedColumns[entry.node.id] = column;
      if ((origin - entry.node.position).distance > _gridSnapTolerance) {
        moved[entry.node.id] = origin;
      }
    }
  }
  return moved;
}

/// 无向邻接表。只保留两端都在画布上的边,自环无意义(布局上不提供信息)。
Map<String, List<String>> _buildAdjacency(
  List<CanvasLayoutEdge> edges,
  Map<String, CanvasLayoutNode> byId,
) {
  final neighbors = <String, List<String>>{};
  for (final edge in edges) {
    if (edge.sourceNodeId == edge.targetNodeId) continue;
    if (!byId.containsKey(edge.sourceNodeId) ||
        !byId.containsKey(edge.targetNodeId)) {
      continue;
    }
    (neighbors[edge.sourceNodeId] ??= <String>[]).add(edge.targetNodeId);
    (neighbors[edge.targetNodeId] ??= <String>[]).add(edge.sourceNodeId);
  }
  return neighbors;
}

/// 主干层:节点最多的一层,平手取最上面一层。
///
/// 主干的列序通常是故事顺序(章节 1→N),重排它等于打乱语义,因此只动其余层。
int _pickAnchorRow(Map<int, List<CanvasLayoutNode>> rows) {
  var anchor = rows.keys.first;
  for (final row in rows.keys) {
    final count = rows[row]!.length;
    final best = rows[anchor]!.length;
    if (count > best || (count == best && row < anchor)) {
      anchor = row;
    }
  }
  return anchor;
}

/// 已放置邻居的列均值;一个都没有时返回 null(调用方保留原列)。
double? _barycenter(List<String>? neighbors, Map<String, int> placedColumns) {
  if (neighbors == null || neighbors.isEmpty) return null;
  var sum = 0;
  var count = 0;
  for (final id in neighbors) {
    final column = placedColumns[id];
    if (column == null) continue;
    sum += column;
    count += 1;
  }
  return count == 0 ? null : sum / count;
}

/// 找离 (preferred, row) 最近的空格子。
///
/// 代价 = |Δ列| + |Δ行|,同代价下先横后纵、先右后左。目标列被占时优先左右挪一格,
/// 挪不动才往[away](远离主干的方向)沉一行 —— 直接沉在目标列正下方会让连线
/// 从上面那张卡片中间穿过去,看着像连在了别人身上。
(int col, int row) _firstFreeCell({
  required int preferred,
  required int row,
  required int away,
  required Size size,
  required List<Rect> occupied,
}) {
  for (var cost = 0; cost <= _maxColumnProbe; cost++) {
    // 同代价下按 |Δ列| 升序试，Δ列=0(正下方)放到最后。
    final steps = <int>[
      for (var columnStep = 1; columnStep <= cost; columnStep++) columnStep,
      0,
    ];
    for (final columnStep in steps) {
      final rowStep = cost - columnStep;
      final candidateRow = row + rowStep * away;
      final columns = columnStep == 0
          ? <int>[preferred]
          : <int>[preferred + columnStep, preferred - columnStep];
      for (final column in columns) {
        if (!canvasNodeOverlaps(
          origin: canvasGridOrigin(column, candidateRow),
          size: size,
          occupied: occupied,
        )) {
          return (column, candidateRow);
        }
      }
    }
  }
  return (preferred + _maxColumnProbe + 1, row);
}

/// 坐标是否严格落在网格点上(允许 [_gridSnapTolerance] 的浮点误差)。
///
/// AI 通过 col/row 摆的节点必然精确落点;用户手拖、或 UI 在视口中心新建的节点
/// 几乎不可能正好压在格点上 —— 以此区分「算法摆的」与「人摆的」,后者不动。
bool _isOnGrid(Offset position, int col, int row) {
  final origin = canvasGridOrigin(col, row);
  return (position.dx - origin.dx).abs() <= _gridSnapTolerance &&
      (position.dy - origin.dy).abs() <= _gridSnapTolerance;
}
