// 职责: 验证真实着色器查看器的键盘、全屏共享视角与资源卸载。
// 关联文件:
//   lib/shared/widgets/production/panorama/viewer.dart
//   lib/shared/widgets/production/panorama/fullscreen.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/production/panorama.dart';
import 'package:reveric/shared/widgets/production/panorama/controller.dart';
import 'package:reveric/shared/widgets/production/panorama/fullscreen.dart';
import 'package:reveric/shared/widgets/production/panorama/painter.dart';
import 'package:reveric/shared/widgets/production/panorama/texture.dart';
import 'package:reveric/shared/widgets/production/panorama/viewer.dart';
import '../../../desktop/director/harness.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(initializeDirectorTest);
  testWidgets(
    'node and fullscreen share angles, reload and release the texture',
    (tester) async {
      late Directory root;
      late String path;
      late PanoramaTexture warm;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('panorama-viewer-');
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawPaint(ui.Paint()..color = const Color(0xffaa7766));
        final picture = recorder.endRecording();
        final image = await picture.toImage(512, 256);
        picture.dispose();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        path = (await File(
          '${root.path}/fixture.png',
        ).writeAsBytes(bytes!.buffer.asUint8List())).path;
        await PanoramaShader.program();
        warm = await PanoramaTextures.acquire(path);
      });
      var saved = const PanoramaView(yaw: 20, pitch: 10, fov: 65);
      final controller = PanoramaController(
        initial: saved,
        save: (view) async {
          saved = view;
        },
      );
      Future<void> settleImage() async {
        await tester.pumpAndSettle();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        directorTestApp(
          SizedBox(
            width: 300,
            height: 200,
            child: PanoramaViewer(path: path, controller: controller),
          ),
        ),
      );
      await settleImage();
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is PanoramaPainter,
        ),
        findsOneWidget,
      );
      warm.dispose();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();
      expect(controller.view.yaw, 25);
      final full = showPanoramaFullscreen(
        tester.element(find.byType(PanoramaViewer)),
        path,
        controller,
      );
      await settleImage();
      expect(PanoramaTextures.activePaths, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.pump();
      expect(controller.view.pitch, 15);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await full;
      expect(saved, const PanoramaView(yaw: 25, pitch: 15, fov: 65));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
      await settleImage();
      expect(PanoramaTextures.activePaths, 0);
      warm = (await tester.runAsync(() => PanoramaTextures.acquire(path)))!;
      final reloaded = PanoramaController(initial: saved, save: (_) async {});
      await tester.pumpWidget(
        directorTestApp(
          PanoramaViewer(path: path, controller: reloaded, fullscreen: true),
        ),
      );
      await settleImage();
      expect(find.text('Yaw 25° · Pitch 15° · FOV 65°'), findsOneWidget);
      warm.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      reloaded.dispose();
      await settleImage();
      expect(PanoramaTextures.activePaths, 0);
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
  testWidgets('replacing a mounted viewer path never paints released resources', (
    tester,
  ) async {
    late Directory root;
    late String firstPath, secondPath;
    final warm = <PanoramaTexture>[];
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('panorama-swap-');
      for (final (name, width) in [('a', 128), ('b', 256)]) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawPaint(ui.Paint()..color = const Color(0xff887766));
        final picture = recorder.endRecording();
        final image = await picture.toImage(width, 64);
        picture.dispose();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final path = (await File(
          '${root.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List())).path;
        if (name == 'a') {
          firstPath = path;
        } else {
          secondPath = path;
        }
        warm.add(await PanoramaTextures.acquire(path));
      }
      await PanoramaShader.program();
    });
    final path = ValueNotifier(firstPath);
    final controller = PanoramaController(
      initial: const PanoramaView(),
      save: (_) async {},
    );
    final paintings = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is PanoramaPainter,
    );
    Future<void> settleResources() async {
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    try {
      await tester.pumpWidget(
        directorTestApp(
          ValueListenableBuilder<String>(
            valueListenable: path,
            builder: (_, value, _) => SizedBox(
              width: 300,
              height: 200,
              child: PanoramaViewer(path: value, controller: controller),
            ),
          ),
        ),
      );
      await settleResources();
      expect(paintings, findsOneWidget);
      final old =
          tester.widget<CustomPaint>(paintings).painter! as PanoramaPainter;
      expect(old.image.width, 128);
      path.value = secondPath;
      await tester.pump();
      // Resolve disposal in the original Future's queue, without completing B's shader continuation.
      controller.set(const PanoramaView(yaw: 10));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        paintings,
        findsNothing,
        reason: 'B is pending; A resources have been released',
      );
      await settleResources();
      expect(old.shader.debugDisposed, true);
      expect(paintings, findsOneWidget);
      final next =
          tester.widget<CustomPaint>(paintings).painter! as PanoramaPainter;
      expect(next.image.width, 256);
      expect(next.shader.debugDisposed, false);
      path.value = '${root.path}/missing.png';
      await tester.pump();
      controller.set(const PanoramaView(yaw: 20));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(paintings, findsNothing);
      // Wait for the same failed load used by the viewer, then render its error state.
      await tester.runAsync(() async {
        try {
          await PanoramaTextures.acquire(path.value);
        } catch (_) {
          /* The viewer owns and displays the expected file error. */
        }
      });
      await settleResources();
      expect(
        find.byTooltip('Cannot display panorama. Check the image file.'),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settleResources();
      for (final lease in warm) {
        lease.dispose();
      }
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(PanoramaTextures.activePaths, 0);
      await controller.stopSaving();
      controller.dispose();
      path.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    }
  });
}
