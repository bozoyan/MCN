// 职责: 在真实 GPU 上验证焦点转移改变前后景清晰度，并保存对照图。
// 关联文件:
//   lib/shared/services/director/renderer.dart
//   lib/shared/services/director/scene_builder.dart
//   lib/shared/models/director/sampling.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/commands.dart';
import 'package:reveric/shared/services/director/renderer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'rack focus renders different near and far sharpness',
    (tester) async {
      await tester.runAsync(() async {
        final history = CommandHistory(DirectorDocument.blank('Rack focus'));
        final renderer = DirectorRenderer();
        final directory = await Directory.systemTemp.createTemp(
          'reveric_focus_',
        );
        try {
          history.addObject('prop.cube.v1', 'Near');
          history.addObject('prop.cube.v1', 'Far');
          history.execute((j) {
            j['output'] = {
              'width': 640,
              'height': 360,
              'aspect_mode': 'auto',
              'background': '#E8E8E8',
            };
            final near = j['objects'][0], far = j['objects'][1];
            near['position'] = [-0.1, 0.125, 2.5];
            far['position'] = [0.5, 0.125, 0];
            for (final o in [near, far]) {
              o['scale'] = [0.2, 0.45, 0.1];
              o['color'] = '#24466A';
            }
            final c = j['cameras'][0];
            c['position'] = [0, 0.35, 4];
            c['camera_target'] = {
              'type': 'object',
              'object_id': far['id'],
              'offset': [0, 0.225, 0],
            };
            c['focus_distance_m'] = 1.5;
            c['focal_length_mm'] = 50;
            c['aperture_fstop'] = 0.7;
          });
          history.move(history.document.defaultCameraId, 'rack_focus', 0, 48);
          final pinhole = history.document.mutate((j) {
            j['camera_moves'] = [];
            j['cameras'][0]['aperture_fstop'] = 0.0;
          });
          final pinholeBytes = await renderer.capture(
            pinhole,
            0,
            pinhole.defaultCameraId,
          );
          await File(
            '${directory.path}/pinhole.png',
          ).writeAsBytes(pinholeBytes);
          Future<Uint8List> decode(Uint8List png) async {
            final codec = await ui.instantiateImageCodec(png);
            final image = (await codec.getNextFrame()).image;
            try {
              return (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
            } finally {
              image.dispose();
              codec.dispose();
            }
          }

          final pinholePixels = await decode(pinholeBytes);
          final pixels = <Uint8List>[];
          for (final frame in [0, 48]) {
            final png = await renderer.capture(
              history.document,
              frame,
              history.document.defaultCameraId,
            );
            await File('${directory.path}/focus-$frame.png').writeAsBytes(png);
            pixels.add(await decode(png));
          }
          // Compare each object against its sharp pinhole reference. Raw edge
          // energy would mistake a dark defocus halo for a sharper silhouette.
          double defocusError(Uint8List rgba, int left, int right) {
            var error = 0.0;
            for (var y = 100; y < 260; y++) {
              for (var x = left; x < right; x++) {
                final i = (y * 640 + x) * 4;
                error += (rgba[i] - pinholePixels[i]).abs();
              }
            }
            return error / (160 * (right - left));
          }

          final nearStart = defocusError(pixels[0], 90, 225),
              nearEnd = defocusError(pixels[1], 90, 225);
          final farStart = defocusError(pixels[0], 270, 370),
              farEnd = defocusError(pixels[1], 270, 370);
          debugPrint(
            'DIRECTOR_FOCUS_ARTIFACTS=${directory.path} near=$nearStart/$nearEnd far=$farStart/$farEnd',
          );
          expect(nearEnd, greaterThan(nearStart * 1.2));
          expect(farStart, greaterThan(farEnd * 1.2));
          // Focus must not turn an in-focus object's interior black. A negative
          // inferred far plane misclassifies the background as near blur.
          var interiorError = 0.0;
          for (var y = 140; y < 165; y++) {
            for (var x = 312; x < 328; x++) {
              final i = (y * 640 + x) * 4;
              interiorError += (pixels[1][i] - pinholePixels[i]).abs();
            }
          }
          expect(interiorError / (25 * 16), lessThan(10));
        } finally {
          renderer.dispose();
          history.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
