// 职责: 用查看器同一着色器离屏渲染不带辅助线与 HUD 的 PNG。
// 关联文件:
//   lib/shared/widgets/production/panorama/painter.dart
//   lib/shared/services/production/panorama_service.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../../models/production/panorama.dart';
import 'painter.dart';
import 'texture.dart';

class PanoramaCapture {
  static Future<Uint8List> render(
    ui.Image texture,
    PanoramaView view,
    ui.Size size,
  ) async {
    view.validate();
    if (size.width <= 0 ||
        size.height <= 0 ||
        !size.width.isFinite ||
        !size.height.isFinite) {
      throw const FormatException('Invalid capture size');
    }
    final shader = (await PanoramaShader.program()).fragmentShader();
    try {
      final recorder = ui.PictureRecorder();
      paintPanorama(ui.Canvas(recorder), size, shader, texture, view);
      final picture = recorder.endRecording();
      try {
        final output = await picture.toImage(
          size.width.round(),
          size.height.round(),
        );
        try {
          final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null) {
            throw StateError('PNG encoding failed');
          }
          return bytes.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          );
        } finally {
          output.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      shader.dispose();
    }
  }
}

ui.Size panoramaCaptureSize(String ratio) {
  final dimensions = ratio.split(':').map(double.parse).toList();
  if (dimensions.length != 2 || dimensions.any((v) => !v.isFinite || v <= 0)) {
    throw const FormatException('Invalid capture aspect ratio');
  }
  final aspect = dimensions[0] / dimensions[1];
  return aspect >= 1
      ? ui.Size(1920, (1920 / aspect).roundToDouble())
      : ui.Size((1920 * aspect).roundToDouble(), 1920);
}
