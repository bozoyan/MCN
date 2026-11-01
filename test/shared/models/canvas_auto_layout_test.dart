// 职责: 画布连边感知重排测试 — 覆盖主干层保序、barycenter 分列、手动位置保护与幂等
// 关联文件:
//   lib/shared/models/canvas_auto_layout.dart
//   lib/shared/models/canvas_layout.dart
//   lib/shared/services/canvas_service.dart

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/canvas_auto_layout.dart';
import 'package:reveric/shared/models/canvas_layout.dart';

CanvasLayoutNode _at(String id, int col, int row, {Size? size}) {
  return (
    id: id,
    position: canvasGridOrigin(col, row),
    size: size ?? canvasReferenceDefaultSize,
  );
}

CanvasLayoutEdge _edge(String source, String target) {
  return (sourceNodeId: source, targetNodeId: target);
}

/// 截图那张画布的同构数据：14 个章节排 row 0、14 个伏笔排 row 1，
/// 伏笔在行内的顺序与其指向的章节毫无关系，于是 21 条边全是横穿画布的长线。
({List<CanvasLayoutNode> nodes, List<CanvasLayoutEdge> edges}) _spaghetti() {
  final nodes = <CanvasLayoutNode>[
    for (var i = 0; i < 14; i++) _at('c$i', i, 0),
    for (var i = 0; i < 14; i++) _at('f$i', i, 1),
  ];
  // (伏笔序号, 章节序号)，逐条抄自真实数据。
  const links = <(int, int)>[
    (0, 4), (0, 13),
    (1, 13), (1, 9),
    (2, 1),
    (3, 1),
    (4, 12), (4, 2),
    (5, 3),
    (6, 11), (6, 8),
    (7, 12), (7, 9),
    (8, 11),
    (9, 4), (9, 7),
    (10, 5),
    (11, 7), (11, 6),
    (12, 7),
    (13, 11),
  ];
  return (
    nodes: nodes,
    edges: [for (final (f, c) in links) _edge('f$f', 'c$c')],
  );
}

/// 每条边的水平跨度（以列为单位），用来衡量「长横线」被压短了多少。
List<double> _spansInColumns(
  List<CanvasLayoutNode> nodes,
  List<CanvasLayoutEdge> edges,
  Map<String, Offset> moved,
) {
  Offset positionOf(String id) {
    return moved[id] ?? nodes.firstWhere((n) => n.id == id).position;
  }

  return [
    for (final edge in edges)
      (positionOf(edge.sourceNodeId).dx - positionOf(edge.targetNodeId).dx)
              .abs() /
          canvasGridPitchX,
  ];
}

double _sum(List<double> values) => values.fold(0.0, (a, b) => a + b);

double _max(List<double> values) => values.reduce((a, b) => a > b ? a : b);

void main() {
  group('resolveCanvasAutoLayout', () {
    test('把横穿画布的长线压短', () {
      final graph = _spaghetti();
      final before = _spansInColumns(graph.nodes, graph.edges, const {});
      expect(_max(before), 13, reason: '重排前最长一条边横跨 13 列（0 → 5200px）');

      final moved = resolveCanvasAutoLayout(
        nodes: graph.nodes,
        edges: graph.edges,
      );
      final after = _spansInColumns(graph.nodes, graph.edges, moved);

      expect(
        _sum(after),
        lessThan(_sum(before) * 0.4),
        reason: '21 条边的总跨度至少压掉六成',
      );
      // 剩下的长边是节点自身跨度大（如同时连第 2 章与第 12 章的伏笔），
      // 摆在哪都得拉一条长线，不是布局没做好。
      expect(_max(after), lessThanOrEqualTo(6));
    });

    test('主干层（节点最多的一层）原样不动，列序即故事顺序', () {
      final graph = _spaghetti();
      final moved = resolveCanvasAutoLayout(
        nodes: graph.nodes,
        edges: graph.edges,
      );

      for (var i = 0; i < 14; i++) {
        expect(moved.containsKey('c$i'), isFalse, reason: 'c$i 不该被挪走');
      }
    });

    test('只有一个邻居的节点落到邻居正下方', () {
      // f2 只连 c1、f5 只连 c3、f10 只连 c5，三者互不争抢同一列。
      final graph = _spaghetti();
      final moved = resolveCanvasAutoLayout(
        nodes: graph.nodes,
        edges: graph.edges,
      );

      expect(moved['f2'], canvasGridOrigin(1, 1));
      expect(moved['f5'], canvasGridOrigin(3, 1));
      expect(moved['f10'], canvasGridOrigin(5, 1));
    });

    test('抢同一列时挪开一格或沉一行，始终贴着目标列', () {
      final graph = _spaghetti();
      final moved = resolveCanvasAutoLayout(
        nodes: graph.nodes,
        edges: graph.edges,
      );

      // 单邻居伏笔（伏笔序号 → 章节列）：即便撞格也不该被挤出一列以外。
      const singleNeighbor = <String, int>{
        'f2': 1,
        'f3': 1,
        'f5': 3,
        'f8': 11,
        'f10': 5,
        'f12': 7,
        'f13': 11,
      };
      singleNeighbor.forEach((id, targetColumn) {
        final origin = moved[id] ?? graph.nodes.firstWhere((n) => n.id == id).position;
        final (column, row) = canvasGridCellOf(origin);
        expect((column - targetColumn).abs(), lessThanOrEqualTo(1), reason: id);
        expect(row, greaterThan(0), reason: '$id 不该跑进主干层');
      });
    });

    test('重排后没有两个节点落在同一格', () {
      final graph = _spaghetti();
      final moved = resolveCanvasAutoLayout(
        nodes: graph.nodes,
        edges: graph.edges,
      );

      final origins = <Offset>{};
      for (final node in graph.nodes) {
        final origin = moved[node.id] ?? node.position;
        expect(origins.add(origin), isTrue, reason: '${node.id} 与别人同格');
      }
    });

    test('结果只与输入有关，同一输入两次完全一致', () {
      final graph = _spaghetti();
      final first = resolveCanvasAutoLayout(
        nodes: graph.nodes,
        edges: graph.edges,
      );
      final second = resolveCanvasAutoLayout(
        nodes: graph.nodes,
        edges: graph.edges,
      );
      expect(second, equals(first));
    });

    test('重排幂等：把结果喂回去不再产生移动', () {
      final graph = _spaghetti();
      final moved = resolveCanvasAutoLayout(
        nodes: graph.nodes,
        edges: graph.edges,
      );
      final settled = [
        for (final node in graph.nodes)
          (
            id: node.id,
            position: moved[node.id] ?? node.position,
            size: node.size,
          ),
      ];

      expect(
        resolveCanvasAutoLayout(nodes: settled, edges: graph.edges),
        isEmpty,
      );
    });

    test('非网格点的节点是用户手摆的，不参与重排且不被压住', () {
      // 手拖到 (410, 300) 的伏笔：既不移动，也要挡住别人落在这。
      final nodes = <CanvasLayoutNode>[
        _at('c0', 0, 0),
        _at('c1', 1, 0),
        _at('c2', 2, 0),
        (
          id: 'pinned',
          position: const Offset(410, 300),
          size: canvasReferenceDefaultSize,
        ),
        _at('f0', 5, 1),
      ];
      final edges = [_edge('f0', 'c1'), _edge('pinned', 'c1')];

      final moved = resolveCanvasAutoLayout(nodes: nodes, edges: edges);

      expect(moved.containsKey('pinned'), isFalse);
      // f0 的目标列是 c1 所在的 1 列，但 (1,1) 被手摆节点占着，只能挪开。
      expect(moved['f0'], isNot(canvasGridOrigin(1, 1)));
      expect(moved['f0'], isNotNull);
    });

    test('无边 / 单层 / 单节点画布原样返回', () {
      final flat = [for (var i = 0; i < 3; i++) _at('n$i', i, 0)];
      expect(
        resolveCanvasAutoLayout(nodes: flat, edges: const []),
        isEmpty,
        reason: '没有边就没有「谁该挨着谁」的信息',
      );
      expect(
        resolveCanvasAutoLayout(
          nodes: flat,
          edges: [_edge('n0', 'n1')],
        ),
        isEmpty,
        reason: '所有节点同一层时没有可参照的另一层',
      );
      expect(
        resolveCanvasAutoLayout(nodes: [_at('n0', 0, 0)], edges: const []),
        isEmpty,
      );
    });

    test('端点不在画布上的边被忽略，不会算进 barycenter', () {
      final nodes = [_at('c0', 0, 0), _at('c1', 1, 0), _at('f0', 6, 1)];
      final moved = resolveCanvasAutoLayout(
        nodes: nodes,
        edges: [_edge('f0', 'ghost'), _edge('f0', 'c1')],
      );
      expect(moved['f0'], canvasGridOrigin(1, 1));
    });
  });
}
