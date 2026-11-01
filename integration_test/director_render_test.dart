// 职责: 在真实桌面 GPU 宿主验证导演姿态画面、切镜帧序列与 H.264 输出。
// 关联文件:
//   lib/shared/services/director/renderer.dart
//   lib/shared/services/director/export_task.dart
//   lib/shared/services/production/media_service.dart
//   test/fixtures/director/animated.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/presets.dart';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:reveric/shared/models/director/rig.dart';
import 'package:reveric/shared/services/director/commands.dart';
import 'package:reveric/shared/services/director/scene_builder.dart';
import 'package:reveric/shared/services/director/actor_models.dart';
import 'package:reveric/shared/services/director/prop_models.dart';
import 'package:reveric/shared/services/director/export_task.dart';
import 'package:reveric/shared/services/director/renderer.dart';
import 'package:reveric/shared/services/director/storage.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/media_service.dart';
import '../test/fixtures/director/animated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real GPU pose captures and cut sequence encode to MP4',
    (tester) async {
      await tester.runAsync(() async {
        const requested = String.fromEnvironment('DIRECTOR_ACCEPTANCE_DIR');
        final root = requested.isEmpty
            ? await Directory.systemTemp.createTemp('reveric_director_native_')
            : await Directory(requested).create(recursive: true);
        // Artifacts remain available for explicit visual inspection after the test.
        final output = Directory('${root.path}/output');
        final temporary = Directory('${root.path}/temporary');
        await output.create(recursive: true);
        await temporary.create(recursive: true);
        final renderer = DirectorRenderer();
        final task = ExportTaskOrchestrator();
        try {
          for (final geometry in actorGeometries) {
            for (final scale in [.5, 1.0, 2.0]) {
              final h = CommandHistory(DirectorDocument.blank('Support'));
              try {
                for (final preset in ['sit', 'squat', 'kneel', 'kneel_both']) {
                  h.addObject(geometry, preset);
                }
                h.execute((json) {
                  json['output'] = {
                    'width': 1280,
                    'height': 720,
                    'background': '#E8E8E8',
                  };
                  for (var i = 0; i < 4; i++) {
                    final object = json['objects'][i];
                    object['position'] = [(i - 1.5) * 2.5 * scale, 0, 0];
                    object['scale'] = [scale, scale, scale];
                    object['pose'] = posePreset(
                      object['name'],
                      geometry,
                    ).toJson();
                  }
                  json['cameras'][0]['position'] = [0, 2.5 * scale, 12 * scale];
                  json['cameras'][0]['camera_target'] = {
                    'type': 'point',
                    'position': [0, .8 * scale, 0],
                  };
                });
                final bytes = await renderer.capture(
                  h.document,
                  0,
                  h.document.defaultCameraId,
                );
                final image = await ui.instantiateImageCodec(bytes);
                final frame = await image.getNextFrame();
                expect((frame.image.width, frame.image.height), (1280, 720));
                frame.image.dispose();
                image.dispose();
                await File(
                  '${root.path}/support-$geometry-$scale.png',
                ).writeAsBytes(bytes);
              } finally {
                h.dispose();
              }
            }
          }
          const input = String.fromEnvironment('DIRECTOR_DOCUMENT_FILE');
          final document = input.isEmpty
              ? animatedDirectorDocument().mutate((json) {
                  json['output'] = {
                    'width': 640,
                    'height': 360,
                    'aspect_mode': 'auto',
                    'background': '#E8E8E8',
                  };
                })
              : DirectorDocument.parse(await File(input).readAsString());
          final sampleFrames = [
            0,
            24,
            47,
            48,
            72,
            96,
            120,
            168,
            240,
            336,
            408,
            480,
            528,
            600,
            719,
          ].where((f) => f <= document.durationFrames).toList();
          await ActorModels.load();
          final scene = SceneBuilder(
            document,
            props: await PropModels.load(document),
          );
          try {
            for (final frame in sampleFrames) {
              scene.apply(document, frame, document.cameraAt(frame));
              for (final actor in sampleDocument(
                document,
                frame,
              ).objects.where((o) => o['kind'] == 'actor')) {
                final rendered = scene.actors[actor['id']]!.model
                    .getChildByName('Head')!
                    .globalTransform
                    .getTranslation();
                final sampled = boneWorldPoint(actor, 'head', [0, 0, 0]);
                expect(rendered.x, closeTo(sampled[0], 1e-5));
                expect(rendered.y, closeTo(sampled[1], 1e-5));
                expect(rendered.z, closeTo(sampled[2], 1e-5));
              }
            }
          } finally {
            scene.dispose();
          }
          await File('${root.path}/sampled-anchors.json').writeAsString(
            jsonEncode([
              for (final frame in sampleFrames)
                {
                  'frame': frame,
                  'camera_id': document.cameraAt(frame),
                  'actors': [
                    for (final actor in sampleDocument(
                      document,
                      frame,
                    ).objects.where((o) => o['kind'] == 'actor'))
                      {
                        'id': actor['id'],
                        'name': actor['name'],
                        'position': actor['position'],
                        'head': boneWorldPoint(actor, 'head', [0, 0, 0]),
                        'chest': boneWorldPoint(actor, 'chest', [0, 0, 0]),
                      },
                  ],
                },
            ]),
          );
          await File(
            '${root.path}/animation.director.json',
          ).writeAsString(document.encode());
          await task.run(
            workspace: DirectorStorage(output, temporary),
            document: document,
            renderer: renderer,
            cameraMode: 'sequence',
          );
          expect(
            task.state,
            OutputState.completed,
            reason: '${task.errorCode}: ${task.diagnostic}',
          );
          final frames = task.result!;
          final manifest =
              jsonDecode(
                    await File('${frames.path}/manifest.json').readAsString(),
                  )
                  as Json;
          expect(manifest['frameCount'], document.durationFrames);
          expect(manifest['frames'][47]['cameraId'], document.cameraAt(47));
          expect(manifest['frames'][48]['cameraId'], document.cameraAt(48));
          final media = MediaService(FfmpegRunner());
          final encoded = await media
              .encodeVideo(
                inputPath: '${frames.path}/frame_%06d.png',
                imageSequence: true,
                width: document.width,
                height: document.height,
                fps: document.fps,
              )
              .result;
          try {
            expect(encoded.info.frameCount, document.durationFrames);
            expect(
              encoded.info.duration,
              Duration(
                milliseconds: document.durationFrames * 1000 ~/ document.fps,
              ),
            );
            await encoded.file.copy('${root.path}/animation-sequence.mp4');
          } finally {
            await encoded.dispose();
          }
          await File('${root.path}/evidence.json').writeAsString(
            jsonEncode({
              'renderer': 'DirectorRenderer',
              'frames_directory': frames.path,
              'frame_count': document.durationFrames,
              'camera_mode': 'sequence',
              'visual_review': 'pending',
              'gui_interactions': 'not covered by this test',
            }),
          );
          debugPrint('DIRECTOR_NATIVE_ARTIFACTS=${root.path}');
        } finally {
          renderer.dispose();
          task.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
