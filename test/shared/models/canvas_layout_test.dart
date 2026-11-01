// 职责: 画布摆位算法测试 — 覆盖网格位/相对方位/自动追加/重叠避让/精确坐标逃生口
// 关联文件:
//   lib/shared/models/canvas_layout.dart
//   lib/shared/services/ai/tools_canvas.dart

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/canvas_layout.dart';

Rect _stickyAt(int col, int row) {
  return canvasGridOrigin(col, row) & canvasStickyDefaultSize;
}

void main() {
  test('全量网格按稳定顺序最多6列排列变尺寸卡片，短行靠左且不重叠', () {
    final nodes = [
      for (var i = 0; i < 14; i++)
        CanvasArrangeNode(
          id: '$i',
          sortOrder: i,
          size: Size(i % 3 == 0 ? 420 : 200, i % 4 == 0 ? 360 : 62),
        ),
    ];
    final result = resolveCanvasGridLayout(nodes.reversed);
    expect(result, resolveCanvasGridLayout(nodes));
    expect(result['0'], const Offset(56, 44));
    expect(result['6']!.dx, 56);
    expect(result['12']!.dx, 56);
    expect(result['6']!.dy, result['0']!.dy + 360 + 80);
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        expect(
          (result[nodes[i].id]! & nodes[i].size).overlaps(
            result[nodes[j].id]! & nodes[j].size,
          ),
          isFalse,
        );
      }
    }
  });

  group('canvas grid', () {
    test('网格步长 = 默认尺寸 + 空隙，因此同行相邻两格必不重叠', () {
      expect(canvasGridPitchX, canvasStickyDefaultWidth + canvasGridGapX);
      expect(canvasGridPitchY, canvasStickyDefaultHeight + canvasGridGapY);

      final first = _stickyAt(0, 0);
      final second = _stickyAt(1, 0);
      expect(first.overlaps(second), isFalse);
      expect(second.left - first.right, canvasGridGapX);
    });

    test('col/row 换算成画布坐标，负数网格位合法', () {
      expect(canvasGridOrigin(2, 1), const Offset(800, 248));
      expect(canvasGridOrigin(-1, 0), const Offset(-400, 0));
    });

    test('画布坐标反查网格位', () {
      expect(canvasGridCellOf(const Offset(800, 248)), (2, 1));
      // 手拖后的非整格坐标取最近格，AI 拿到后能接着往下排。
      expect(canvasGridCellOf(const Offset(815, 240)), (2, 1));
    });

    test('列间距容得下边标签，连线不会被标签字条整段盖住', () {
      // 「第11章起」这类 5 字标签在 11px 下约 55px 宽，加 chip padding ~67px。
      expect(canvasGridGapX, greaterThan(80));
    });
  });

  group('resolveCanvasNodePlacement', () {
    test('col/row 直接落到对应网格位', () {
      final placement = resolveCanvasNodePlacement(
        size: canvasStickyDefaultSize,
        occupied: const [],
        col: 2,
        row: 0,
      );
      expect(placement.position, const Offset(800, 0));
      expect(placement.adjusted, isFalse);
    });

    test('只给 col 时 row 视作 0', () {
      final placement = resolveCanvasNodePlacement(
        size: canvasStickyDefaultSize,
        occupied: const [],
        col: 1,
      );
      expect(placement.position, const Offset(400, 0));
    });

    test('near + direction 四个方位都贴着锚点节点摆，且留出统一空隙', () {
      const anchor = Rect.fromLTWH(100, 100, 280, 168);
      const size = canvasStickyDefaultSize;

      Offset place(CanvasPlaceDirection direction) {
        return resolveCanvasNodePlacement(
          size: size,
          occupied: const [],
          anchor: anchor,
          direction: direction,
        ).position;
      }

      expect(
        place(CanvasPlaceDirection.right),
        Offset(anchor.right + canvasGridGapX, anchor.top),
      );
      expect(
        place(CanvasPlaceDirection.left),
        Offset(anchor.left - canvasGridGapX - size.width, anchor.top),
      );
      expect(
        place(CanvasPlaceDirection.below),
        Offset(anchor.left, anchor.bottom + canvasGridGapY),
      );
      expect(
        place(CanvasPlaceDirection.above),
        Offset(anchor.left, anchor.top - canvasGridGapY - size.height),
      );
    });

    test('都不给时行优先追加到第一个空网格位', () {
      final placement = resolveCanvasNodePlacement(
        size: canvasStickyDefaultSize,
        occupied: [_stickyAt(0, 0), _stickyAt(1, 0)],
      );
      expect(placement.position, canvasGridOrigin(2, 0));
    });

    test('满一行后换到下一行', () {
      final occupied = [
        for (var col = 0; col < canvasGridColumnsPerRow; col++)
          _stickyAt(col, 0),
      ];
      final placement = resolveCanvasNodePlacement(
        size: canvasStickyDefaultSize,
        occupied: occupied,
      );
      expect(placement.position, canvasGridOrigin(0, 1));
    });

    test('目标格被占用时沿 +x 推开并标记 adjusted', () {
      final placement = resolveCanvasNodePlacement(
        size: canvasStickyDefaultSize,
        occupied: [_stickyAt(1, 0)],
        col: 1,
        row: 0,
      );
      expect(placement.position, canvasGridOrigin(2, 0));
      expect(placement.adjusted, isTrue);
    });

    test('贴边但未相交也算重叠 —— 视觉上仍是糊在一起', () {
      // 旧数据的病灶形态：宽 280 的便签按 260 间距排，压后一张 20px。
      const crowded = Rect.fromLTWH(260, 0, 280, 168);
      final placement = resolveCanvasNodePlacement(
        size: canvasStickyDefaultSize,
        occupied: const [crowded],
        col: 0,
        row: 0,
      );
      expect(placement.adjusted, isTrue);
      expect(
        (placement.position & canvasStickyDefaultSize).overlaps(crowded),
        isFalse,
      );
    });

    test('explicit 是逃生口：原样返回，不做避让', () {
      const explicit = Offset(12, 34);
      final placement = resolveCanvasNodePlacement(
        size: canvasStickyDefaultSize,
        occupied: [_stickyAt(0, 0)],
        explicit: explicit,
        col: 3,
        row: 3,
      );
      expect(placement.position, explicit);
      expect(placement.adjusted, isFalse);
    });

    test('引用节点用自己的尺寸做避让判定', () {
      final placement = resolveCanvasNodePlacement(
        size: canvasReferenceDefaultSize,
        occupied: [_stickyAt(0, 0)],
        col: 0,
        row: 0,
      );
      expect(placement.adjusted, isTrue);
      expect(
        (placement.position & canvasReferenceDefaultSize).overlaps(
          _stickyAt(0, 0),
        ),
        isFalse,
      );
    });
  });
}
