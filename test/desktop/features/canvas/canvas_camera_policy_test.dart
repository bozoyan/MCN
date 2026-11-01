// 职责: 画布跟随镜头决策测试 — 覆盖「不晃镜头」闸门、内容变大自动缩小、图过大局部跟随、收尾适配
// 关联文件:
//   lib/desktop/features/canvas/canvas_camera_policy.dart
//   lib/desktop/features/canvas/widgets/canvas_board.dart

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/canvas_camera_policy.dart';

/// 典型画布区尺寸(桌面窗口减去 chat panel)。
const Size _screen = Size(1100, 760);

/// 由屏幕与缩放反推可视画布区，与 controller.visibleGraphBounds 同构。
Rect _visibleFor({required Offset center, required double zoom}) {
  final width = _screen.width / zoom;
  final height = _screen.height / zoom;
  return Rect.fromCenter(center: center, width: width, height: height);
}

CanvasCameraCommand _decide({
  required Rect content,
  Rect? focus,
  required Offset viewCenter,
  required double zoom,
  bool settled = false,
}) {
  return decideCanvasCamera(
    screenSize: _screen,
    currentZoom: zoom,
    visibleBounds: _visibleFor(center: viewCenter, zoom: zoom),
    contentBounds: content,
    focusBounds: focus,
    settled: settled,
    minZoom: 0.2,
    maxZoom: 3.0,
  );
}

void main() {
  group('decideCanvasCamera', () {
    test('焦点已在安全区内且缩放可读时不动镜头', () {
      // AI 在视野正中加了一张便签：镜头静止，否则连着加 8 张会疯狂晃。
      final command = _decide(
        content: const Rect.fromLTWH(0, 0, 800, 400),
        focus: const Rect.fromLTWH(300, 150, 280, 168),
        viewCenter: const Offset(400, 200),
        zoom: 1.0,
      );

      expect(command, isA<CanvasCameraHold>());
    });

    test('焦点落在视野外时把全图拉进画面', () {
      // 新节点摆到 col=5、row=-1，完全在视野外 —— 这正是「AI 干了什么用户看不见」。
      final content = const Rect.fromLTWH(0, -248, 2400, 416);
      final command = _decide(
        content: content,
        focus: const Rect.fromLTWH(2000, -248, 280, 168),
        viewCenter: const Offset(400, 84),
        zoom: 1.0,
      );

      expect(command, isA<CanvasCameraMove>());
      final move = command as CanvasCameraMove;
      expect(move.center, content.center);
      // 2400 宽要装进 1100 - 128 的可用宽度 → 缩到 0.4 上下。
      expect(move.zoom, lessThan(1.0));
      expect(move.zoom, greaterThan(0.2));
    });

    test('内容变大时自动缩小以容纳全图', () {
      final small = _decide(
        content: const Rect.fromLTWH(0, 0, 800, 400),
        focus: const Rect.fromLTWH(600, 0, 280, 168),
        viewCenter: const Offset(0, 0),
        zoom: 2.0,
      );
      final large = _decide(
        content: const Rect.fromLTWH(0, 0, 1600, 400),
        focus: const Rect.fromLTWH(1400, 0, 280, 168),
        viewCenter: const Offset(0, 0),
        zoom: 2.0,
      );

      expect(small, isA<CanvasCameraMove>());
      expect(large, isA<CanvasCameraMove>());
      expect(
        (large as CanvasCameraMove).zoom,
        lessThan((small as CanvasCameraMove).zoom),
      );
    });

    test('图大到全图会糊时改为局部跟随焦点', () {
      // 24 格宽的画布：全图 fit 只有 ~0.1，节点全糊，只能跟着焦点看。
      final content = const Rect.fromLTWH(0, 0, 9600, 1500);
      final focus = const Rect.fromLTWH(8000, 1200, 280, 168);
      final command = _decide(
        content: content,
        focus: focus,
        viewCenter: const Offset(200, 200),
        zoom: 0.8,
      );

      expect(command, isA<CanvasCameraMove>());
      final move = command as CanvasCameraMove;
      // 跟的是焦点而不是全图中心，且缩放留在可读区间。
      expect((move.center - focus.center).distance, lessThan(1));
      expect(move.zoom, greaterThanOrEqualTo(0.6));
      expect(move.zoom, lessThanOrEqualTo(1.1));
    });

    test('收尾时内容已经在视野内且缩放合适则不动', () {
      final command = _decide(
        content: const Rect.fromLTWH(0, 0, 800, 400),
        viewCenter: const Offset(400, 200),
        zoom: 1.0,
        settled: true,
      );

      expect(command, isA<CanvasCameraHold>());
    });

    test('收尾时用户放得太大导致内容出框则重新适配全图', () {
      // 用户之前放大到 2.4 看某张便签，内容已经溢出视野，整理完布局后回到全貌。
      final content = const Rect.fromLTWH(0, 0, 800, 400);
      final command = _decide(
        content: content,
        viewCenter: const Offset(400, 200),
        zoom: 2.4,
        settled: true,
      );

      expect(command, isA<CanvasCameraMove>());
      final move = command as CanvasCameraMove;
      expect(move.center, content.center);
      // 节点很少时也不该怼到脸上：上限 1.2。
      expect(move.zoom, lessThanOrEqualTo(1.2));
    });

    test('删除类操作(无焦点)按收尾规则处理', () {
      final command = _decide(
        content: const Rect.fromLTWH(0, 0, 2400, 400),
        viewCenter: const Offset(200, 200),
        zoom: 1.0,
      );

      expect(command, isA<CanvasCameraMove>());
    });

    test('收尾时全图大到适配后看不清则保持不动', () {
      // 十几列的时间线 fit 下来只有 0.2 上下：收尾缩成一片字都认不出，不如停在
      // 最后一个焦点上。
      final command = _decide(
        content: const Rect.fromLTWH(0, 0, 6000, 900),
        viewCenter: const Offset(3000, 400),
        zoom: 0.8,
        settled: true,
      );

      expect(command, isA<CanvasCameraHold>());
    });

    test('锁定缩放时焦点出框只平移、不改缩放', () {
      // 图还装得下全貌（规则 3 会给全图并缩小），但这一轮缩放已经定下。
      final focus = const Rect.fromLTWH(1800, 0, 280, 168);
      final command = decideCanvasCamera(
        screenSize: _screen,
        currentZoom: 0.8,
        visibleBounds: _visibleFor(center: const Offset(400, 84), zoom: 0.8),
        contentBounds: const Rect.fromLTWH(0, 0, 2080, 168),
        focusBounds: focus,
        settled: false,
        minZoom: 0.2,
        maxZoom: 3.0,
        lockedZoom: 0.8,
      );

      expect(command, isA<CanvasCameraMove>());
      final move = command as CanvasCameraMove;
      expect(move.zoom, 0.8);
      // 只在出框的那一轴上平移；焦点停在中心偏后，前进方向（右边）留出空间
      // 接住后面的节点，而不是正中对焦、下一个又出框。
      expect(move.center.dy, 84);
      expect(move.center.dx, greaterThan(focus.center.dx));
      final view = _visibleFor(center: move.center, zoom: 0.8);
      expect(view.deflate(view.width * 0.08).contains(focus.topRight), isTrue);
    });

    test('锁定缩放时焦点在安全区内不动', () {
      final command = decideCanvasCamera(
        screenSize: _screen,
        currentZoom: 0.8,
        visibleBounds: _visibleFor(center: const Offset(400, 84), zoom: 0.8),
        contentBounds: const Rect.fromLTWH(0, 0, 2080, 168),
        focusBounds: const Rect.fromLTWH(300, 0, 280, 168),
        settled: false,
        minZoom: 0.2,
        maxZoom: 3.0,
        lockedZoom: 0.8,
      );

      expect(command, isA<CanvasCameraHold>());
    });

    test('新连线任一端在可视区内就不动镜头', () {
      // 一端在时间线（视野内），另一端是角落里的便签：线会自己长进画面，
      // 拿两端包围盒取景会让镜头每条线都大幅平移。
      final focus = canvasEdgeFocus(
        visibleBounds: const Rect.fromLTWH(0, 0, 1100, 760),
        endpoints: const [
          Rect.fromLTWH(200, 200, 280, 168),
          Rect.fromLTWH(-3000, 2400, 280, 168),
        ],
      );

      expect(focus, isNull);
    });

    test('新连线两端都在视野外时只追终点', () {
      const target = Rect.fromLTWH(5000, 0, 280, 168);
      final focus = canvasEdgeFocus(
        visibleBounds: const Rect.fromLTWH(0, 0, 1100, 760),
        endpoints: const [Rect.fromLTWH(-3000, 2400, 280, 168), target],
      );

      expect(focus, target);
    });

    test('空画布/零尺寸时不动镜头', () {
      expect(
        decideCanvasCamera(
          screenSize: Size.zero,
          currentZoom: 1,
          visibleBounds: Rect.zero,
          contentBounds: Rect.zero,
          settled: true,
          minZoom: 0.2,
          maxZoom: 3.0,
        ),
        isA<CanvasCameraHold>(),
      );
    });
  });
}
