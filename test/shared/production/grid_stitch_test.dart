// 职责: 验证 2K 拼接的尺寸、cover 裁切、格位底色与序号开关。
// 关联文件:
//   lib/shared/services/production/grid_stitch.dart
//   lib/shared/models/production/group_layout.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reveric/shared/models/production/group_layout.dart';
import 'package:reveric/shared/services/production/grid_stitch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '2K size follows full-grid aspect for landscape, portrait and rectangles',
    () {
      for (final ratio in ['16:9', '9:16', '4:3', '3:4', '1:1', '21:9']) {
        for (final spec in [(1, 1), (2, 3), (5, 5)]) {
          final layout = StoryboardGroupLayout(
            cols: spec.$1,
            rows: spec.$2,
            ratio: ratio,
          );
          final size = storyboardStitchSize(layout);
          expect(size.width == 2048 || size.height == 2048, isTrue);
          expect(
            size.width / size.height,
            closeTo(productionAspect(ratio)! * spec.$1 / spec.$2, .005),
          );
        }
      }
    },
  );

  test(
    'slots stay in place, holes keep the background and numbers include holes',
    () async {
      final root = await Directory.systemTemp.createTemp('stitch-pixels-');
      try {
        final red = img.Image(width: 8, height: 4);
        img.fill(red, color: img.ColorRgb8(220, 30, 40));
        final blue = img.Image(width: 4, height: 8);
        img.fill(blue, color: img.ColorRgb8(20, 50, 230));
        final redFile = await File(
          '${root.path}/red.png',
        ).writeAsBytes(img.encodePng(red));
        final blueFile = await File(
          '${root.path}/blue.png',
        ).writeAsBytes(img.encodePng(blue));
        final plainPath = '${root.path}/plain.png';
        final numberedPath = '${root.path}/numbered.png';
        const layout = StoryboardGroupLayout(rows: 2, cols: 2, ratio: '16:9');
        await stitchProductionGrid(
          layout: layout,
          files: {0: redFile.path, 3: blueFile.path},
          outputPath: plainPath,
          background: 0xff102030,
          foreground: 0xffeeeeee,
        );
        await stitchProductionGrid(
          layout: layout.copyWith(numbered: true),
          files: {0: redFile.path, 3: blueFile.path},
          outputPath: numberedPath,
          background: 0xff102030,
          foreground: 0xffeeeeee,
        );
        final plain = img.decodePng(await File(plainPath).readAsBytes())!;
        final numbered = img.decodePng(await File(numberedPath).readAsBytes())!;
        expect((plain.width, plain.height), (2048, 1152));
        List<num> rgb(int x, int y) {
          final p = plain.getPixel(x, y);
          return [p.r, p.g, p.b];
        }

        expect(rgb(512, 288), [220, 30, 40]);
        expect(rgb(1536, 864), [20, 50, 230]);
        expect(rgb(1536, 288), [16, 32, 48]);
        expect(rgb(512, 864), [16, 32, 48]);
        for (final origin in [(0, 0), (1024, 0), (0, 576), (1024, 576)]) {
          var changed = 0;
          for (var y = 8; y < 50; y++) {
            for (var x = 8; x < 60; x++) {
              final a = plain.getPixel(origin.$1 + x, origin.$2 + y);
              final b = numbered.getPixel(origin.$1 + x, origin.$2 + y);
              if (a.r != b.r || a.g != b.g || a.b != b.b) {
                changed++;
              }
            }
          }
          expect(changed, greaterThan(0));
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'cover crops the center rather than stretching or adding letterboxes',
    () async {
      final root = await Directory.systemTemp.createTemp('stitch-cover-');
      try {
        final source = img.Image(width: 4, height: 2);
        for (var y = 0; y < 2; y++) {
          source.setPixelRgb(0, y, 200, 0, 0);
          source.setPixelRgb(1, y, 0, 200, 0);
          source.setPixelRgb(2, y, 0, 200, 0);
          source.setPixelRgb(3, y, 0, 0, 200);
        }
        final input = await File(
          '${root.path}/source.png',
        ).writeAsBytes(img.encodePng(source));
        final output = '${root.path}/cover.png';
        await stitchProductionGrid(
          layout: const StoryboardGroupLayout(rows: 1, cols: 1, ratio: '1:1'),
          files: {0: input.path},
          outputPath: output,
          background: 0xff102030,
          foreground: 0xffeeeeee,
        );
        final result = img.decodePng(await File(output).readAsBytes())!;
        for (final x in [0, 1024, 2047]) {
          final p = result.getPixel(x, 1024);
          expect([p.r, p.g, p.b], [0, 200, 0]);
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
