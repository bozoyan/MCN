// 职责: 验证制作画布按场竖排片段时，场与场的色带不会互相压住。
// 关联文件:
//   lib/desktop/features/production/board.dart
//   lib/desktop/features/production/node_card.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/board.dart';
import 'package:reveric/desktop/features/production/node_card.dart';
import 'package:reveric/shared/database/novel_content_database.dart';

void main() {
  final at = DateTime(2026);
  const size = Size(260, 146);

  CanvasNode node(String clipId, double x, double y) => CanvasNode(
    id: 'node_$clipId',
    canvasId: 'canvas',
    type: canvasNodeTypeVideo,
    refType: canvasNodeRefTypeProductionClip,
    refId: clipId,
    title: clipId,
    content: '',
    x: x,
    y: y,
    zIndex: 0,
    sortOrder: 0,
    createdAt: at,
    updatedAt: at,
    deletedAt: at,
  );

  ProductionClipRow clip(String id, String sceneId) => ProductionClipRow(
    inputs: const [],
    id: id,
    episodeId: 'episode',
    kind: canvasNodeTypeVideo,
    sceneId: sceneId,
    title: id,
    prompt: '',
    errorDismissed: false,
    referenceMode: '',
    ratio: '16:9',
    resolution: '',
    createdAt: at,
    updatedAt: at,
    deletedAt: at,
  );

  test('long scene pushes the scene below it down instead of overlapping', () {
    // 库里按「每场一行」存：第 1 场 5 段横排，第 2 场在下方 620 处。
    final nodes = [
      for (var i = 0; i < 5; i++) node('a$i', 700 + i * 340.0, 0),
      for (var i = 0; i < 2; i++) node('b$i', 700 + i * 340.0, 620),
    ];
    final segments = [
      for (var i = 0; i < 5; i++) clip('a$i', 'scene_a'),
      for (var i = 0; i < 2; i++) clip('b$i', 'scene_b'),
    ];

    final positions = productionScenePositions(nodes, segments, (_) => size);

    const step = 146 + 24 + productionNodeHeaderExtent;
    for (var i = 0; i < 5; i++) {
      expect(positions['node_a$i'], Offset(700, i * step));
    }
    final lastA = positions['node_a4']!.dy + size.height;
    final firstB = positions['node_b0']!;
    expect(firstB.dx, 700);
    // 上一场色带底边 + 间距 + 下一场色带顶部留白。
    expect(firstB.dy, lastA + 24 + 24 + 40 + productionNodeHeaderExtent);
    expect(positions['node_b1'], Offset(700, firstB.dy + step));
  });

  test('scenes that do not overlap keep their stored corner', () {
    final nodes = [node('a0', 0, 0), node('b0', 600, 0)];
    final segments = [clip('a0', 'scene_a'), clip('b0', 'scene_b')];

    final positions = productionScenePositions(nodes, segments, (_) => size);

    expect(positions['node_a0'], Offset.zero);
    expect(positions['node_b0'], const Offset(600, 0));
  });
}
