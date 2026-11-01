// 职责: 验证视频处理产物的落点：放在源节点右侧，挡路的节点（场次整场）整体右移，连续产物往下排。
// 关联文件:
//   lib/shared/services/production/derived_placement.dart
//   lib/desktop/features/production/board.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/production/asset_content.dart';
import 'package:reveric/shared/services/production/derived_placement.dart';
import 'package:reveric/desktop/features/production/node_card.dart';

void main() {
  const size = Size(260, 146);
  Rect card(double x, double y) => Offset(x, y) & size;

  test('media aspect uses stored image and video dimensions', () {
    expect(
      productionMediaAspect(const ImageAssetContent(width: 1600, height: 900)),
      16 / 9,
    );
    expect(
      productionMediaAspect(const VideoAssetContent(width: 900, height: 1600)),
      9 / 16,
    );
    expect(
      productionMediaAspect(const ImageAssetContent(width: 1000, height: 1000)),
      1,
    );
  });

  test(
    'audio and unavailable dimensions leave node sizing to its existing defaults',
    () {
      for (final content in <AssetContent?>[
        null,
        const AudioAssetContent(),
        const ImageAssetContent(),
        const VideoAssetContent(width: 1920),
        const ImageAssetContent(width: 0, height: 100),
        const VideoAssetContent(width: 100, height: -1),
      ]) {
        expect(productionMediaAspect(content), isNull);
      }
    },
  );

  test('first output sits right of the source; free canvas moves nothing', () {
    final placement = productionDerivedPlacement(
      sourceId: 'src',
      size: size,
      nodes: {'src': card(0, 0), 'below': card(0, 600)},
      sceneOf: const {},
      siblings: const [],
    );
    expect(placement.at, (x: 260 + productionDerivedGap, y: 0.0));
    expect(placement.moves, isEmpty);
  });

  test('blocking nodes in the row shift right together, keeping spacing', () {
    final placement = productionDerivedPlacement(
      sourceId: 'src',
      size: size,
      nodes: {
        'src': card(0, 0),
        'next': card(400, 0),
        'after': card(800, 50),
        // 不在这一行、也没被撞到的节点不动。
        'other_row': card(400, 900),
        // 源节点左侧的节点不推。
        'left': card(-600, 0),
      },
      sceneOf: const {},
      siblings: const [],
    );
    final slotRight = 260 + productionDerivedGap + 260;
    final dx = slotRight + productionDerivedGap - 400;
    expect(placement.moves, {
      'next': (x: 400 + dx, y: 0.0),
      'after': (x: 800 + dx, y: 50.0),
    });
  });

  test('a scene moves as a whole and pushes what it then collides with', () {
    final placement = productionDerivedPlacement(
      sourceId: 'src',
      size: size,
      nodes: {
        'src': card(0, 0),
        'a': card(420, 0),
        // 同场的下一个片段不在这一行，也要跟着整场移。
        'b': card(420, 400),
        // 整场右移后会撞上它。
        'blocker': card(800, 400),
      },
      sceneOf: const {'a': 'scene', 'b': 'scene'},
      siblings: const [],
    );
    expect(placement.moves.keys, unorderedEquals(['a', 'b', 'blocker']));
    final dx = placement.moves['a']!.x - 420;
    expect(dx, greaterThan(0));
    expect(placement.moves['b']!.x - 420, dx);
    expect(placement.moves['blocker']!.x - 800, dx);
  });

  test('a blocking storyboard group moves as one unit with every cell', () {
    final placement = productionDerivedPlacement(
      sourceId: 'src',
      size: const Size(600, 400),
      nodes: {
        'src': card(0, 0),
        'group': const Rect.fromLTWH(420, 0, 522, 294),
        'cell1': card(420, 0),
        'cell2': card(682, 0),
      },
      sceneOf: const {},
      groupOf: const {'group': 'group', 'cell1': 'group', 'cell2': 'group'},
      siblings: const [],
    );
    expect(placement.moves.keys, unorderedEquals(['group', 'cell1', 'cell2']));
    final delta = placement.moves['group']!.x - 420;
    expect(placement.moves['cell1']!.x - 420, delta);
    expect(placement.moves['cell2']!.x - 682, delta);
  });

  test('later outputs stack under the lowest previous output', () {
    final placement = productionDerivedPlacement(
      sourceId: 'src',
      size: size,
      nodes: {'src': card(0, 0), 'out': card(380, 0)},
      sceneOf: const {},
      siblings: const ['out'],
    );
    expect(placement.at.x, 380);
    expect(placement.at.y, greaterThan(146 + productionNodeHeaderExtent));
    expect(placement.moves, isEmpty);
  });

  test('a node reaching in from the left pushes the slot down instead', () {
    final placement = productionDerivedPlacement(
      sourceId: 'src',
      size: size,
      nodes: {
        'src': card(0, 0),
        'out': card(380, 0),
        // 从左边横跨到产物列下方的宽节点：不能推，落点让到它下面。
        'wide': const Rect.fromLTWH(-100, 200, 900, 146),
      },
      sceneOf: const {},
      siblings: const ['out'],
    );
    expect(placement.at.y, greaterThan(346));
    expect(placement.moves, isEmpty);
  });
}
