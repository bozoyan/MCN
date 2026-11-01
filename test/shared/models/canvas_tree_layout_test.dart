// 职责: 验证通用层级图的稳定身份、汇合、循环、变尺寸和大图终止性。
// 关联文件:
//   lib/shared/models/canvas_tree_layout.dart
//   lib/shared/models/canvas_layout.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/shared/models/canvas_tree_layout.dart';

CanvasArrangeNode node(
  String id,
  int order, [
  Size size = const Size(256, 62),
]) => CanvasArrangeNode(id: id, sortOrder: order, size: size);
CanvasArrangeEdge edge(String from, String to, [String type = 'timeline']) =>
    CanvasArrangeEdge(sourceNodeId: from, targetNodeId: to, type: type);

void noOverlap(List<CanvasArrangeNode> nodes, Map<String, Offset> positions) {
  for (var i = 0; i < nodes.length; i++) {
    for (var j = i + 1; j < nodes.length; j++) {
      expect(
        (positions[nodes[i].id]! & nodes[i].size).overlaps(
          positions[nodes[j].id]! & nodes[j].size,
        ),
        isFalse,
        reason: '${nodes[i].id} / ${nodes[j].id}',
      );
    }
  }
}

void main() {
  for (final direction in CanvasTreeDirection.values) {
    test('fork and merge stay centered across three branches: $direction', () {
      final nodes = [
        node('choice', 0, const Size(280, 168)),
        node('a', 1, const Size(280, 168)),
        node('b', 2, const Size(280, 168)),
        node('c', 3, const Size(280, 168)),
        node('merge', 4, const Size(280, 168)),
      ];
      final positions = resolveCanvasTreeLayout(
        nodes: nodes,
        edges: [
          for (final branch in ['a', 'b', 'c']) ...[
            edge('choice', branch),
            edge(branch, 'merge'),
          ],
        ],
        direction: direction,
      );
      double center(String id) => direction == CanvasTreeDirection.top_to_bottom
          ? positions[id]!.dx + 140
          : positions[id]!.dy + 84;
      final middle = (center('a') + center('c')) / 2;
      expect(center('choice'), middle);
      expect(center('merge'), middle);
      noOverlap(nodes, positions);
    });
    test(
      'diamond, multiple roots, components and variable dimensions: $direction',
      () {
        final nodes = [
          node('a', 0, const Size(180, 340)),
          node('b', 1),
          node('c', 2, const Size(420, 108)),
          node('d', 3),
          node('e', 4),
          node('f', 5),
          node('g', 6),
          node('ref', 7),
        ];
        final edges = [
          edge('a', 'b'),
          edge('a', 'c'),
          edge('b', 'd'),
          edge('c', 'd'),
          edge('e', 'd'),
          edge('f', 'g'),
          edge('ref', 'a', 'relationship'),
          edge('d', 'missing'),
        ];
        final result = resolveCanvasTreeLayout(
          nodes: nodes,
          edges: edges,
          direction: direction,
        );
        expect(result.keys.toSet(), nodes.map((n) => n.id).toSet());
        expect(
          resolveCanvasTreeLayout(
            nodes: nodes,
            edges: edges.take(edges.length - 1),
            direction: direction,
          ),
          result,
          reason: 'Dangling edges must not affect the layout.',
        );
        noOverlap(nodes, result);
        for (final e in edges.take(6)) {
          final before = result[e.sourceNodeId]!;
          final after = result[e.targetNodeId]!;
          expect(
            direction == CanvasTreeDirection.left_to_right
                ? after.dx > before.dx
                : after.dy > before.dy,
            isTrue,
          );
        }
        expect(
          resolveCanvasTreeLayout(
            nodes: nodes.reversed,
            edges: edges.reversed,
            direction: direction,
          ),
          result,
        );
      },
    );
    test('side roots sink next to their earliest target: $direction', () {
      final nodes = [
        node('start', 0),
        node('a', 1),
        node('b', 2),
        node('c', 3),
        node('end', 4),
        node('state', 5),
        node('hint', 6),
      ];
      final result = resolveCanvasTreeLayout(
        nodes: nodes,
        edges: [
          edge('start', 'a'),
          edge('a', 'b'),
          edge('b', 'c'),
          edge('c', 'end'),
          edge('state', 'c', 'causal'),
          edge('hint', 'b', 'causal'),
          edge('hint', 'end', 'causal'),
        ],
        direction: direction,
      );
      double primary(String id) =>
          direction == CanvasTreeDirection.left_to_right
          ? result[id]!.dx
          : result[id]!.dy;
      expect(primary('state'), primary('b'));
      expect(primary('hint'), primary('a'));
      noOverlap(nodes, result);
    });
    test('long edges route through their own lane: $direction', () {
      final nodes = [
        node('start', 0),
        node('a', 1),
        node('b', 2),
        node('c', 3),
        node('end', 4),
      ];
      final routing = resolveCanvasTreeRouting(
        nodes: nodes,
        edges: [
          edge('start', 'a'),
          edge('a', 'b'),
          edge('b', 'c'),
          edge('c', 'end'),
          edge('a', 'end', 'causal'),
          edge('a', 'end', 'timeline'),
          edge('start', 'c', 'relationship'),
        ],
        direction: direction,
      );
      expect(routing.waypoints.keys, [('a', 'end')]);
      final route = routing.waypoints[('a', 'end')]!;
      // 中间隔着 b、c 两层，每层进出各一个路点。
      expect(route, hasLength(4));
      double primary(Offset point) =>
          direction == CanvasTreeDirection.left_to_right ? point.dx : point.dy;
      for (var i = 1; i < route.length; i++) {
        expect(primary(route[i]), greaterThan(primary(route[i - 1])));
      }
      // 通道在每层都是最外侧，整条被拉成一条直线。
      final secondaries = route
          .map(
            (point) => direction == CanvasTreeDirection.left_to_right
                ? point.dy
                : point.dx,
          )
          .toSet();
      expect(secondaries, hasLength(1));
      for (var i = 0; i < route.length; i += 2) {
        final lane = Rect.fromPoints(route[i], route[i + 1]);
        for (final n in nodes) {
          final bounds = routing.positions[n.id]! & n.size;
          expect(bounds.overlaps(lane.inflate(0.5)), isFalse, reason: n.id);
        }
      }
      expect(
        resolveCanvasTreeLayout(
          nodes: nodes,
          edges: [
            edge('start', 'a'),
            edge('a', 'b'),
            edge('b', 'c'),
            edge('c', 'end'),
            edge('a', 'end', 'causal'),
          ],
          direction: direction,
        ),
        routing.positions,
      );
      noOverlap(nodes, routing.positions);
    });
    test(
      'cycles and duplicate edges keep all instances without overlap: $direction',
      () {
        final nodes = [
          for (var i = 0; i < 6; i++)
            node('$i', i, Size(200 + i * 20, 100 + i * 30)),
        ];
        final edges = [
          edge('0', '1'),
          edge('1', '2'),
          edge('2', '0'),
          edge('0', '1'),
          edge('2', '3'),
          edge('4', '4'),
          edge('5', '0', 'association'),
        ];
        final result = resolveCanvasTreeLayout(
          nodes: nodes,
          edges: edges,
          direction: direction,
        );
        expect(result, hasLength(6));
        noOverlap(nodes, result);
        double primary(String id) =>
            direction == CanvasTreeDirection.left_to_right
            ? result[id]!.dx
            : result[id]!.dy;
        expect(primary('1'), primary('0'));
        expect(primary('2'), primary('0'));
        expect(primary('3'), greaterThan(primary('2')));
        expect(
          resolveCanvasTreeLayout(
            nodes: nodes,
            edges: edges,
            direction: direction,
          ),
          result,
        );
      },
    );
  }
  for (final (count, edgeCount) in [(500, 1000), (5000, 10000)]) {
    test('$count nodes / $edgeCount edges terminate without dropping IDs', () {
      final nodes = [
        for (var i = 0; i < count; i++)
          node('$i', i, Size(180 + (i % 5) * 40, 62 + (i % 4) * 50)),
      ];
      final edges = [
        for (var i = 0; i < edgeCount; i++)
          edge('${i % count}', '${(i * 17 + 1) % count}'),
      ];
      final watch = Stopwatch()..start();
      final result = resolveCanvasTreeLayout(nodes: nodes, edges: edges);
      watch.stop();
      // CI 保存设备与实测时长；规模验收不以截断输入换取通过。
      stdout.writeln(
        'canvas-layout ${Platform.operatingSystem} ${Platform.version} processors=${Platform.numberOfProcessors} nodes=$count edges=$edgeCount elapsed_us=${watch.elapsedMicroseconds}',
      );
      expect(result.keys.toSet(), nodes.map((n) => n.id).toSet());
      expect(
        result.values.every((p) => p.dx.isFinite && p.dy.isFinite),
        isTrue,
      );
      if (count == 500) {
        expect(watch.elapsedMilliseconds, lessThan(1000));
        noOverlap(nodes, result);
      }
    });
  }
}
