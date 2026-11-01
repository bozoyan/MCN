// 职责: 验证「整理画布」的落点：按连线从左到右分列，场次和分组整体移动，无连线的排在下方，选区只动选中的单位。
// 关联文件:
//   lib/shared/services/production/tidy_layout.dart
//   lib/desktop/features/production/board.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/production/derived_placement.dart';
import 'package:reveric/shared/services/production/tidy_layout.dart';

void main() {
  const size = Size(260, 146);
  Rect card(double x, double y) => Offset(x, y) & size;
  Offset at(Map<String, Offset> moved, Map<String, Rect> nodes, String id) =>
      moved[id] ?? nodes[id]!.topLeft;

  test('connected nodes line up left to right along their edges', () {
    final nodes = {
      'video': card(0, 0),
      'image': card(900, 700),
      'ref': card(400, 300),
    };
    final moved = productionTidyLayout(
      nodes: nodes,
      sceneOf: const {},
      edges: const [('ref', 'image'), ('image', 'video')],
    );
    final ref = at(moved, nodes, 'ref');
    final image = at(moved, nodes, 'image');
    final video = at(moved, nodes, 'video');
    expect(ref.dy, image.dy);
    expect(image.dy, video.dy);
    expect(image.dx - ref.dx, size.width + productionTidyLayerGap);
    expect(video.dx - image.dx, size.width + productionTidyLayerGap);
    // 整理后左上角留在原来的左上角。
    expect(ref, const Offset(0, 0));
  });

  test('loose nodes go below the connected ones without overlapping', () {
    final nodes = {
      'a': card(0, 0),
      'b': card(2000, 0),
      'x': card(500, 500),
      'y': card(520, 520),
    };
    final moved = productionTidyLayout(
      nodes: nodes,
      sceneOf: const {},
      edges: const [('a', 'b')],
    );
    final b = at(moved, nodes, 'b');
    final x = at(moved, nodes, 'x') & size;
    final y = at(moved, nodes, 'y') & size;
    expect(x.top, greaterThan(b.dy + size.height));
    expect(x.overlaps(y), isFalse);
  });

  test('a scene moves as one band and keeps its vertical order', () {
    final nodes = {
      'shot1': card(1000, 0),
      'shot2': card(1000, 200),
      'ref': card(0, 0),
    };
    final moved = productionTidyLayout(
      nodes: nodes,
      sceneOf: const {'shot1': 's', 'shot2': 's'},
      edges: const [('ref', 'shot2')],
    );
    final shot1 = at(moved, nodes, 'shot1');
    final shot2 = at(moved, nodes, 'shot2');
    expect(shot2 - shot1, const Offset(0, 200));
    final band = productionSceneBand(
      (shot1 & size).expandToInclude(shot2 & size),
    );
    expect(band.left, greaterThan(at(moved, nodes, 'ref').dx + size.width));
  });

  test('references sit left, each scene gets its own column in film order', () {
    // 参考都连到各场；场次原来竖着叠在一列，第 4 场没有任何连线。
    final nodes = {
      for (var i = 0; i < 4; i++) 'ref$i': card(0, i * 200.0),
      's1a': card(600, 0),
      's1b': card(600, 200),
      's2a': card(600, 600),
      's3a': card(600, 1000),
      's4a': card(600, 1400),
      'audio': card(1200, 0),
    };
    final moved = productionTidyLayout(
      nodes: nodes,
      sceneOf: const {
        's1a': 'one',
        's1b': 'one',
        's2a': 'two',
        's3a': 'three',
        's4a': 'four',
      },
      edges: [
        for (var i = 0; i < 4; i++)
          for (final shot in ['s1a', 's2a', 's3a']) ('ref$i', shot),
        ('s1a', 'audio'),
      ],
      sceneOrder: const ['one', 'two', 'three', 'four'],
    );
    Rect band(List<String> ids) => productionSceneBand(
      ids
          .map((id) => at(moved, nodes, id) & size)
          .reduce((a, b) => a.expandToInclude(b)),
    );
    final bands = [
      band(['s1a', 's1b']),
      band(['s2a']),
      band(['s3a']),
      band(['s4a']),
    ];
    for (var i = 0; i < bands.length; i++) {
      expect(bands[i].top, bands.first.top);
      if (i > 0) {
        expect(bands[i].left, greaterThan(bands[i - 1].right));
      }
    }
    for (var i = 0; i < 4; i++) {
      expect(
        at(moved, nodes, 'ref$i').dx + size.width,
        lessThan(bands.first.left),
      );
    }
    // 音频只来自第 1 场，贴在第 1 场右侧。
    final audio = at(moved, nodes, 'audio') & size;
    expect(audio.left, greaterThan(bands.first.right));
    expect(audio.right, lessThan(bands[1].left));
  });

  test('outputs of one scene sit right of it; shared outputs after all scenes', () {
    // 第 1 场生成尾帧，尾帧又给第 2 场做参考；合成来自第 2、3 场。
    final nodes = {
      'ref': card(0, 0),
      's1': card(600, 0),
      's2': card(600, 400),
      's3': card(600, 800),
      'last': card(2000, 0),
      'mix': card(2000, 400),
    };
    final moved = productionTidyLayout(
      nodes: nodes,
      sceneOf: const {'s1': 'one', 's2': 'two', 's3': 'three'},
      edges: const [
        ('ref', 's1'),
        ('ref', 's2'),
        ('s1', 'last'),
        ('last', 's2'),
        ('s2', 'mix'),
        ('s3', 'mix'),
      ],
      sceneOrder: const ['one', 'two', 'three'],
    );
    Rect band(String id) => productionSceneBand(at(moved, nodes, id) & size);
    final last = at(moved, nodes, 'last') & size;
    expect(band('s2').top, band('s1').top);
    expect(band('s3').top, band('s1').top);
    expect(last.left, band('s1').right + productionDerivedGap);
    expect(last.right, lessThan(band('s2').left));
    expect(at(moved, nodes, 'mix').dx, greaterThan(band('s3').right));
  });

  test('many references wrap into several columns no taller than the scene', () {
    final nodes = {
      for (var i = 0; i < 12; i++) 'ref$i': card(0, i * 200.0),
      'shot': card(600, 0),
    };
    final moved = productionTidyLayout(
      nodes: nodes,
      sceneOf: const {'shot': 'one'},
      edges: [for (var i = 0; i < 12; i++) ('ref$i', 'shot')],
      sceneOrder: const ['one'],
    );
    final band = productionSceneBand(at(moved, nodes, 'shot') & size);
    final refs = [for (var i = 0; i < 12; i++) at(moved, nodes, 'ref$i') & size];
    expect(refs.map((r) => r.left).toSet().length, greaterThan(1));
    for (final (i, ref) in refs.indexed) {
      expect(ref.right, lessThan(band.left));
      expect(ref.bottom, lessThanOrEqualTo(band.bottom));
      for (final other in refs.skip(i + 1)) {
        expect(ref.overlaps(other), isFalse);
      }
    }
  });

  test('cycles still terminate and every unit gets a column', () {
    final nodes = {'a': card(0, 0), 'b': card(500, 0), 'c': card(0, 500)};
    final moved = productionTidyLayout(
      nodes: nodes,
      sceneOf: const {},
      edges: const [('a', 'b'), ('b', 'c'), ('c', 'a')],
    );
    final rects = [for (final id in nodes.keys) at(moved, nodes, id) & size];
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse);
      }
    }
  });

  test('a selection of several units leaves the rest in place', () {
    final nodes = {
      'a': card(0, 0),
      'b': card(800, 600),
      'other': card(3000, 3000),
    };
    final moved = productionTidyLayout(
      nodes: nodes,
      sceneOf: const {},
      edges: const [('a', 'b'), ('b', 'other')],
      scope: const {'a', 'b'},
    );
    expect(moved.containsKey('other'), isFalse);
    expect(moved['b'], Offset(size.width + productionTidyLayerGap, 0));
  });

  test('group members move with their frame', () {
    final nodes = {
      'group': const Rect.fromLTWH(1000, 1000, 600, 400),
      'member': card(1100, 1100),
      'src': card(0, 0),
    };
    final moved = productionTidyLayout(
      nodes: nodes,
      sceneOf: const {},
      groupOf: const {'group': 'group', 'member': 'group'},
      edges: const [('src', 'group')],
    );
    expect(
      moved['member']! - moved['group']!,
      const Offset(100, 100),
    );
  });
}
