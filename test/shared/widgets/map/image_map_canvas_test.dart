// 职责: 验证图片地图在视口缩放后仍使用一致的命中与地点坐标
// 关联文件:
//   lib/shared/widgets/map/image_map_canvas.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/map/image_map_canvas.dart';

void main() {
  test('大画布按比例缩进视口', () {
    final size = fitImageMapCanvasSize(
      viewport: const Size(800, 600),
      logicalCanvas: const Size(3072, 1728),
    );

    expect(size.width, closeTo(800, 0.001));
    expect(size.height, closeTo(450, 0.001));
  });

  test('地点逻辑坐标投影到同一展示坐标系', () {
    final projected = projectImageMapCanvasPosition(
      position: const Offset(1536, 864),
      logicalCanvas: const Size(3072, 1728),
      displaySize: const Size(800, 450),
    );

    expect(projected, const Offset(400, 225));
  });

  test('地点透明命中区始终对应 32 个视口像素', () {
    final rect = imageMapLocationTargetRect(
      position: const Offset(400, 225),
      scale: 2,
    );

    expect(rect.center, const Offset(400, 225));
    expect(rect.width * 2, 32);
    expect(rect.height * 2, 32);
  });

  test('选中圆环在一个周期内平滑呼吸', () {
    final start = imageMapSelectionPulse(0);
    final middle = imageMapSelectionPulse(0.5);
    final end = imageMapSelectionPulse(1);

    expect(start.diameter, 22);
    expect(start.opacity, 0.68);
    expect(middle.diameter, 32);
    expect(middle.opacity, closeTo(0.16, 0.0001));
    expect(end.diameter, closeTo(start.diameter, 0.0001));
    expect(end.opacity, closeTo(start.opacity, 0.0001));
  });

  test('系统禁用动画时选中圆环保持静态', () {
    final first = imageMapSelectionPulse(0.25, animationsDisabled: true);
    final second = imageMapSelectionPulse(0.75, animationsDisabled: true);

    expect(first, second);
    expect(first.diameter, 22);
    expect(first.opacity, 0.68);
  });
}
