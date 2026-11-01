// 职责: 验证深度任务的素材入库、来源变化、防重入、取消与重启恢复。
// 关联文件:
//   lib/shared/services/depth/task_controller.dart
//   test/shared/production/depth_native_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart' as app;
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/asset_purpose.dart';
import 'package:reveric/shared/models/production/media.dart';
import 'package:reveric/shared/services/depth/model.dart';
import 'package:reveric/shared/services/depth/model_service.dart';
import 'package:reveric/shared/services/depth/task_controller.dart';
import 'package:reveric/shared/services/production/canvas_service.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';
import 'depth_native_test.dart' show DepthTestFfmpeg, GrayFixtureRunner, binary;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('depth task lifecycle', () {
    late Directory root;
    late app.AppDatabase appDb;
    late NovelContentDatabase db;
    late ProductionCanvasService canvas;
    late DepthModelService models;
    late DepthTaskController controller;
    late String nodeId;
    var released = 0;
    Future<void> Function()? beforeRun;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('depth-task-');
      appDb = app.AppDatabase.forTest(NativeDatabase.memory());
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      final ffmpeg = DepthTestFfmpeg();
      final library = MediaLibraryService(appDb, MediaService(ffmpeg), root);
      canvas = ProductionCanvasService(StoryboardService(db), library, 'work');
      final initial = await ScreenplayService(db).createInitialStructure();
      final board = await canvas.ensureCanvas(initial.episodeId);
      final source = File('${root.path}/source.mp4');
      await ffmpeg.execute(
        [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=96x64:rate=25:duration=0.16',
          '-c:v',
          'libx264',
          source.path,
        ],
        probe: false,
        cancellation: MediaCancellation(),
      );
      final asset = await library.importFile(
        source,
        name: 'video.mp4',
        novelId: 'work',
        purpose: AssetPurpose.production_video_tool,
        cancellation: MediaCancellation(),
      );
      nodeId = (await canvas.addMedia(board.id, asset.id)).id;
      final seed = await File('${root.path}/seed').writeAsBytes([1, 2, 3]);
      models = DepthModelService(
        Directory('${root.path}/cache/modles'),
        DepthModelManifest(
          bytes: 3,
          sha256: sha256.convert([1, 2, 3]).toString(),
          source: seed.path,
        ),
      );
      released = 0;
      beforeRun = null;
      controller = DepthTaskController(
        root: Directory('${root.path}/tasks'),
        models: models,
        native: GrayFixtureRunner(
          executable: binary,
          beforeRun: () async {
            await beforeRun?.call();
          },
        ),
        resolve: (_) async => canvas,
        release: (_) async {
          released++;
        },
        ffmpeg: ffmpeg,
      );
    });
    tearDown(() async {
      await controller.dispose();
      await db.close();
      await appDb.close();
      await root.delete(recursive: true);
    });
    test('result enters the library and creates a derived node', () async {
      await controller.start('work', nodeId);
      final result = controller.state.value!;
      expect(result.stage, DepthStage.complete);
      expect(result.outputNodeId, isNotNull);
      final output = await appDb.assetDao.getAsset(result.assetId!);
      expect(output, isNotNull);
      expect(output!.inLibrary, true);
      expect(await File(canvas.library.resolve(output)).exists(), true);
      expect(released, 1);
      expect(
        await Directory('${root.path}/tasks/work-${result.id}').exists(),
        false,
      );
    });
    test('deleted source still keeps a usable library result', () async {
      beforeRun = () => canvas.removeNode(nodeId);
      await controller.start('work', nodeId);
      expect(controller.state.value!.stage, DepthStage.complete);
      expect(controller.state.value!.assetId, isNotNull);
      expect(controller.state.value!.outputNodeId, isNull);
      expect(released, 1);
    });
    test(
      'serial gate rejects duplicate starts and cancellation cleans workspace',
      () async {
        final entered = Completer<void>(), unblock = Completer<void>();
        beforeRun = () async {
          entered.complete();
          await unblock.future;
        };
        final running = controller.start('work', nodeId);
        await entered.future;
        await expectLater(
          controller.start('work', nodeId),
          throwsA(isA<MediaException>()),
        );
        await controller.cancel();
        unblock.complete();
        await running;
        expect(controller.state.value!.stage, DepthStage.cancelled);
        expect(released, 1);
        expect(
          await Directory(
            '${root.path}/tasks/work-${controller.state.value!.id}',
          ).exists(),
          false,
        );
      },
    );
    test(
      'restart marks interrupted work and removes only its temporary workspace',
      () async {
        await controller.initialize();
        const id = '11111111-1111-1111-1111-111111111111';
        final workspace = await Directory(
          '${root.path}/tasks/work-$id',
        ).create();
        await File('${workspace.path}/input.rgb').writeAsBytes([1]);
        await File('${root.path}/tasks/last-task.json').writeAsString(
          jsonEncode(
            DepthTask(
              id: id,
              novelId: 'work',
              nodeId: nodeId,
              stage: DepthStage.inference,
            ).toJson(),
          ),
        );
        final restored = DepthTaskController(
          root: controller.root,
          models: models,
          native: controller.native,
          resolve: controller.resolve,
          release: controller.release,
          ffmpeg: controller.ffmpeg,
        );
        try {
          await restored.initialize();
          expect(restored.state.value!.stage, DepthStage.interrupted);
          expect(await workspace.exists(), false);
          await restored.start('work', nodeId);
          expect(restored.state.value!.stage, DepthStage.complete);
        } finally {
          await restored.dispose();
        }
      },
    );
    test('application exit marks a running task interrupted', () async {
      final entered = Completer<void>(), unblock = Completer<void>();
      beforeRun = () async {
        entered.complete();
        await unblock.future;
      };
      final running = controller.start('work', nodeId);
      await entered.future;
      final stopping = controller.stop();
      unblock.complete();
      await stopping;
      await running;
      expect(controller.state.value!.stage, DepthStage.interrupted);
      expect(released, 1);
    });
  }, skip: binary.isEmpty);
}
