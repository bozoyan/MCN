// 职责: 使用全景着色器投影纹理，供屏幕与离屏截图复用。
// 关联文件:
//   lib/shared/widgets/production/panorama/viewer.dart
//   lib/shared/widgets/production/panorama/capture.dart
//   shaders/equirect_view.frag
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import '../../../models/production/panorama.dart';

void paintPanorama(
  ui.Canvas canvas,
  ui.Size size,
  ui.FragmentShader shader,
  ui.Image image,
  PanoramaView view,
) {
  shader
    ..setFloat(0, size.width)
    ..setFloat(1, size.height)
    ..setFloat(2, view.displayYaw)
    ..setFloat(3, view.pitch)
    ..setFloat(4, view.fov)
    ..setFloat(5, image.width.toDouble())
    ..setFloat(6, image.height.toDouble())
    ..setImageSampler(0, image);
  canvas.drawRect(ui.Offset.zero & size, ui.Paint()..shader = shader);
}

class PanoramaPainter extends CustomPainter {
  const PanoramaPainter(this.shader, this.image, this.view);
  final ui.FragmentShader shader;
  final ui.Image image;
  final PanoramaView view;
  @override
  void paint(ui.Canvas canvas, ui.Size size) =>
      paintPanorama(canvas, size, shader, image, view);
  @override
  bool shouldRepaint(PanoramaPainter old) =>
      old.shader != shader || old.image != image || old.view != view;
}
