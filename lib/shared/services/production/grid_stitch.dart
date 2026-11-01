// 职责: 在后台 isolate 按分镜比例和格位 cover 拼接 2K PNG，绘制底色及可选序号。
// 关联文件:
//   lib/shared/services/production/grid_orchestrator.dart
//   lib/shared/models/production/group_layout.dart
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:image/image.dart' as image;
import '../../models/production/group_layout.dart';

({int width, int height}) storyboardStitchSize(StoryboardGroupLayout layout) {
  layout.validate();
  final aspect = productionAspect(layout.ratio)! * layout.cols / layout.rows;
  return aspect >= 1
      ? (width: 2048, height: math.max(1, (2048 / aspect).round()))
      : (width: math.max(1, (2048 * aspect).round()), height: 2048);
}

Future<void> stitchProductionGrid({
  required StoryboardGroupLayout layout,
  required Map<int, String> files,
  required String outputPath,
  required int background,
  required int foreground,
}) => Isolate.run(() async {
  final size = storyboardStitchSize(layout);
  if (files.keys.any((slot) => slot < 0 || slot >= layout.capacity)) {
    throw const FormatException('Invalid storyboard slot');
  }
  image.ColorRgba8 color(int argb) => image.ColorRgba8(
    (argb >> 16) & 255,
    (argb >> 8) & 255,
    argb & 255,
    (argb >> 24) & 255,
  );
  final sheet = image.Image(
    width: size.width,
    height: size.height,
    numChannels: 4,
  );
  image.fill(sheet, color: color(background));
  for (var slot = 0; slot < layout.capacity; slot++) {
    final row = slot ~/ layout.cols, col = slot % layout.cols;
    final x = (col * size.width / layout.cols).round();
    final y = (row * size.height / layout.rows).round();
    final width = ((col + 1) * size.width / layout.cols).round() - x;
    final height = ((row + 1) * size.height / layout.rows).round() - y;
    final path = files[slot];
    if (path != null) {
      final decoded = image.decodeImage(await File(path).readAsBytes());
      if (decoded == null) {
        throw const FormatException('Unsupported storyboard image');
      }
      final source = image.bakeOrientation(decoded);
      final aspect = width / height;
      final cropWidth = math
          .min(source.width, (source.height * aspect).round())
          .clamp(1, source.width);
      final cropHeight = math
          .min(source.height, (source.width / aspect).round())
          .clamp(1, source.height);
      final cropped = image.copyCrop(
        source,
        x: (source.width - cropWidth) ~/ 2,
        y: (source.height - cropHeight) ~/ 2,
        width: cropWidth,
        height: cropHeight,
      );
      image.compositeImage(
        sheet,
        image.copyResize(
          cropped,
          width: width,
          height: height,
          interpolation: image.Interpolation.average,
        ),
        dstX: x,
        dstY: y,
      );
    }
    if (layout.numbered) {
      final label = '${slot + 1}';
      final font = image.arial24;
      final textWidth = label
          .split('')
          .fold(0, (sum, char) => sum + font.characterXAdvance(char));
      image.fillRect(
        sheet,
        x1: x + 8,
        y1: y + 8,
        x2: x + textWidth + 20,
        y2: y + font.lineHeight + 14,
        color: color(background),
      );
      image.drawString(
        sheet,
        label,
        font: font,
        x: x + 14,
        y: y + 11,
        color: color(foreground),
      );
    }
  }
  await File(outputPath).writeAsBytes(image.encodePng(sheet));
});
