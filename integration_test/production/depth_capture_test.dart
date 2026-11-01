// 职责: 在桌面宿主验证打包深度进程、真实模型、FFmpegKit 与素材入库完整链路。
// 关联文件:
//   lib/shared/services/depth/task_controller.dart
//   lib/shared/services/depth/orchestrator.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reveric/shared/database/app_database.dart' as app;
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/asset_purpose.dart';
import 'package:reveric/shared/services/depth/model.dart';
import 'package:reveric/shared/services/depth/model_service.dart';
import 'package:reveric/shared/services/depth/native_runner.dart';
import 'package:reveric/shared/services/depth/task_controller.dart';
import 'package:reveric/shared/services/depth/timeline.dart';
import 'package:reveric/shared/services/production/canvas_service.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';

const modelSource = String.fromEnvironment('DEPTH_TEST_MODEL');

// Build an actual display-matrix fixture independently of FFmpegKit's remux
// options (its packaged command wrapper does not preserve -display_rotation).
Future<void> rotateFixture(String source, String destination) async {
  final bytes = await File(source).readAsBytes();
  final data = ByteData.sublistView(bytes);
  var changed = false;
  void visit(int start, int end) {
    for (var offset = start; offset + 8 <= end;) {
      final size = data.getUint32(offset);
      if (size < 8 || offset + size > end) {
        throw StateError('Invalid fixture box');
      }
      final type = ascii.decode(bytes.sublist(offset + 4, offset + 8));
      if (type == 'moov' || type == 'trak') {
        visit(offset + 8, offset + size);
      }
      if (type == 'tkhd') {
        final matrix = offset + (data.getUint8(offset + 8) == 1 ? 60 : 48);
        if (data.getUint32(matrix + 36) != 0) {
          final values = [0, 65536, 0, -65536, 0, 0, 0, 0, 1073741824];
          for (var i = 0; i < values.length; i++) {
            data.setInt32(matrix + i * 4, values[i]);
          }
          changed = true;
        }
      }
      offset += size;
    }
  }

  visit(0, bytes.length);
  if (!changed) {
    throw StateError('Video track missing from fixture');
  }
  await File(destination).writeAsBytes(bytes);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'bundled CPU depth task preserves rotated VFR and saves a derived asset',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp(
          'reveric-depth-integration-',
        );
        final db = NovelContentDatabase.forTest(NativeDatabase.memory());
        final database = app.AppDatabase.forTest(NativeDatabase.memory());
        final ffmpeg = FfmpegRunner();
        final library = MediaLibraryService(
          database,
          MediaService(ffmpeg),
          root,
        );
        final canvas = ProductionCanvasService(
          StoryboardService(db),
          library,
          'depth-test',
        );
        final models = DepthModelService(
          Directory('${root.path}/cache/modles'),
          const DepthModelManifest(source: modelSource),
        );
        final native = DepthNativeRunner(DepthNativeRunner.bundledExecutable());
        final controller = DepthTaskController(
          root: Directory('${root.path}/tasks'),
          models: models,
          native: native,
          resolve: (_) async => canvas,
          release: (_) async {},
          ffmpeg: ffmpeg,
        );
        try {
          expect(await File(native.executable).exists(), true);
          final source = '${root.path}/source.mp4',
              rotated = '${root.path}/rotated.mp4';
          await ffmpeg.execute(
            [
              '-y',
              '-f',
              'lavfi',
              '-i',
              'testsrc2=size=96x64:rate=25:duration=0.32',
              '-f',
              'lavfi',
              '-i',
              'sine=frequency=440:duration=0.44',
              '-vf',
              "setpts='if(lt(N,4),N,4+(N-4)*2)/(25*TB)'",
              '-vsync',
              'vfr',
              '-c:v',
              'libx264',
              '-c:a',
              'aac',
              source,
            ],
            probe: false,
            cancellation: MediaCancellation(),
          );
          await rotateFixture(source, rotated);
          Future<DepthTimeline> probe(String path) async {
            final data =
                jsonDecode(
                      await ffmpeg.execute(
                        [
                          '-v',
                          'error',
                          '-select_streams',
                          'v:0',
                          '-show_streams',
                          '-show_frames',
                          '-of',
                          'json',
                          path,
                        ],
                        probe: true,
                        cancellation: MediaCancellation(),
                      ),
                    )
                    as Map<String, dynamic>;
            return DepthTimeline.fromProbe(data);
          }

          final before = await probe(rotated);
          expect((before.width, before.height), (64, 96));
          final initial = await ScreenplayService(db).createInitialStructure();
          final board = await canvas.ensureCanvas(initial.episodeId);
          final asset = await library.importFile(
            File(rotated),
            name: 'source.mp4',
            novelId: 'depth-test',
            purpose: AssetPurpose.production_video_tool,
            cancellation: MediaCancellation(),
          );
          final node = await canvas.addMedia(board.id, asset.id);
          final stages = <DepthStage>{};
          controller.state.addListener(() {
            stages.add(controller.state.value!.stage);
          });
          await controller.start('depth-test', node.id);
          final task = controller.state.value!;
          expect(task.stage, DepthStage.complete, reason: task.failure?.name);
          expect(task.outputNodeId, isNotNull);
          final result = (await database.assetDao.getAsset(task.assetId!))!;
          final after = await probe(library.resolve(result));
          expect(after.timestamps, before.timestamps);
          expect(after.durationUs, before.durationUs);
          expect((after.width, after.height), (before.width, before.height));
          expect(
            (await library.media.probe(library.resolve(result))).hasAudio,
            false,
          );
          expect(await models.isReady(MediaCancellation()), true);
          expect(
            stages,
            containsAll([
              DepthStage.preparing,
              DepthStage.decoding,
              DepthStage.inference,
              DepthStage.mapping,
              DepthStage.encoding,
              DepthStage.saving,
              DepthStage.complete,
            ]),
          );
          expect(
            await Directory('${root.path}/tasks/work-${task.id}').exists(),
            false,
          );
          debugPrint(
            'DEPTH_INTEGRATION_OK frames=${after.frames} duration_us=${after.durationUs} size=${after.width}x${after.height} stages=${stages.map((s) => s.name).join(",")}',
          );
        } finally {
          await controller.dispose();
          await db.close();
          await database.close();
          await root.delete(recursive: true);
        }
      });
    },
    skip: modelSource.isEmpty,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
