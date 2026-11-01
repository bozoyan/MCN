// 职责: 验证全景反投影、视角边界、保存节流与共享纹理释放。
// 关联文件:
//   lib/shared/models/production/panorama.dart
//   lib/shared/widgets/production/panorama/controller.dart
//   lib/shared/widgets/production/panorama/texture.dart
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/production/panorama.dart';
import 'package:reveric/shared/widgets/production/panorama/controller.dart';
import 'package:reveric/shared/widgets/production/panorama/texture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('projection centers and edge rays match spherical angles', () {
    for (final yaw in [-180.0, -90.0, 0.0, 90.0, 180.0, 720.0]) {
      for (final pitch in [-60.0, 0.0, 60.0]) {
        final view = PanoramaView(yaw: yaw, pitch: pitch);
        final ray = panoramaRay(view, .5, .5, 16 / 9);
        expect(
          ray.x,
          closeTo(
            math.sin(yaw * math.pi / 180) * math.cos(pitch * math.pi / 180),
            1e-10,
          ),
        );
        expect(ray.y, closeTo(math.sin(pitch * math.pi / 180), 1e-10));
        expect(
          ray.z,
          closeTo(
            math.cos(yaw * math.pi / 180) * math.cos(pitch * math.pi / 180),
            1e-10,
          ),
        );
        final uv = panoramaUv(view, .5, .5, 16 / 9);
        expect(uv.u, closeTo((yaw / 360 + .5) % 1, 1e-10));
        expect(uv.v, closeTo(.5 - pitch / 180, 1e-10));
      }
    }
    final edge = panoramaRay(const PanoramaView(fov: 90), 1, .5, 1);
    expect(math.atan2(edge.x, edge.z), closeTo(math.pi / 4, 1e-10));
    final upper = panoramaRay(const PanoramaView(fov: 90), .5, 0, 2);
    expect(math.atan2(upper.y, upper.z), closeTo(math.atan(.5), 1e-10));
    expect(
      const PanoramaView().changed(pitch: 100, fov: 5),
      const PanoramaView(pitch: 85, fov: 30),
    );
    expect(
      () => const PanoramaView(yaw: double.nan).validate(),
      throwsFormatException,
    );
  });
  testWidgets(
    'local operations ignore stale DB echoes and debounce at 500 ms',
    (tester) async {
      final saved = <PanoramaView>[];
      final controller = PanoramaController(
        initial: const PanoramaView(),
        save: (view) async {
          saved.add(view);
        },
      );
      controller.begin();
      controller.update(const PanoramaView(yaw: 30));
      controller.restore(const PanoramaView());
      expect(controller.view.yaw, 30);
      await tester.pump(const Duration(seconds: 1));
      expect(saved, isEmpty);
      controller.end();
      await tester.pump(const Duration(milliseconds: 499));
      expect(saved, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(saved.single.yaw, 30);
      controller.set(const PanoramaView(yaw: 60));
      await controller.stopSaving();
      await tester.pump(const Duration(seconds: 1));
      expect(saved, hasLength(1));
      controller.dispose();
    },
  );
  testWidgets(
    'queued A B A saves keep the final revision dirty until persisted',
    (tester) async {
      const a = PanoramaView(yaw: 30);
      const b = PanoramaView(yaw: 60);
      final first = Completer<void>();
      final second = Completer<void>();
      final calls = <PanoramaView>[];
      var persisted = const PanoramaView();
      final controller = PanoramaController(
        initial: persisted,
        save: (view) async {
          calls.add(view);
          if (calls.length == 1) {
            await first.future;
          }
          if (calls.length == 2) {
            await second.future;
          }
          persisted = view;
        },
      );
      try {
        controller.set(a);
        await tester.pump(const Duration(milliseconds: 500));
        expect(calls, [a]);
        controller.set(b);
        await tester.pump(const Duration(milliseconds: 500));
        controller.set(a);
        first.complete();
        await tester.pump();
        expect(calls, [a, b]);
        second.complete();
        await tester.pump();
        expect(persisted, b);
        await tester.pump(const Duration(milliseconds: 500));
        // The final A is a distinct local edit, despite equaling the first save.
        expect(calls, [a, b, a]);
        expect(persisted, a);
        controller.restore(persisted);
        expect(controller.view, a);
      } finally {
        if (!first.isCompleted) {
          first.complete();
        }
        if (!second.isCompleted) {
          second.complete();
        }
        await controller.stopSaving();
        controller.dispose();
      }
    },
  );
  testWidgets(
    'a failed latest save remains retryable and ignores stale echoes',
    (tester) async {
      var fail = true;
      PanoramaView? persisted;
      final controller = PanoramaController(
        initial: const PanoramaView(),
        save: (view) async {
          if (fail) {
            throw StateError('fake save failure');
          }
          persisted = view;
        },
      );
      controller.set(const PanoramaView(yaw: 45));
      await controller.flush();
      expect(controller.error, isA<StateError>());
      controller.restore(const PanoramaView(yaw: -90));
      expect(controller.view.yaw, 45);
      fail = false;
      await controller.flush();
      expect(persisted, const PanoramaView(yaw: 45));
      expect(controller.error, isNull);
      controller.dispose();
    },
  );
  test(
    'texture leases share original decode and release after twenty sessions',
    () async {
      final root = await Directory.systemTemp.createTemp('panorama-texture-');
      try {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawPaint(ui.Paint()..color = const ui.Color(0xff887755));
        final picture = recorder.endRecording();
        final image = await picture.toImage(512, 256);
        picture.dispose();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final file = await File(
          '${root.path}/fixture.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        for (var i = 0; i < 20; i++) {
          final a = await PanoramaTextures.acquire(file.path);
          final b = await PanoramaTextures.acquire(file.path);
          expect(identical(a.image, b.image), true);
          expect(a.image.width, 512);
          a.dispose();
          expect(PanoramaTextures.activePaths, 1);
          b.dispose();
          expect(PanoramaTextures.activePaths, 0);
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
