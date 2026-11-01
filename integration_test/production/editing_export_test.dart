// 职责: 用打包的 FFmpeg 验证多轨合成、字幕烧录、分块复用、帧数、混音和取消。
// 关联文件:
//   lib/shared/services/editing/render_service.dart
//   lib/shared/services/editing/service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/editing/document.dart';
import 'package:reveric/shared/models/production/media.dart';
import 'package:reveric/shared/services/editing/service.dart';
import 'package:reveric/shared/services/editing/render_service.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';

class CountingRunner extends FfmpegRunner {
  int encodes = 0;
  @override
  Future<String> execute(
    List<String> args, {
    required bool probe,
    required MediaCancellation cancellation,
  }) {
    if (!probe) {
      encodes++;
    }
    return super.execute(args, probe: probe, cancellation: cancellation);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'packaged FFmpeg composes layered video and float audio across a 120-frame boundary',
    (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp(
          'reveric_editing_native_',
        );
        final app = AppDatabase.forTest(NativeDatabase.memory());
        final db = NovelContentDatabase.forTest(NativeDatabase.memory());
        final runner = CountingRunner();
        final media = MediaService(runner);
        final library = MediaLibraryService(app, media, dir);
        final projects = EditingService(db, library);
        final renderer = EditingRenderService(projects, runner);
        Future<void> run(List<String> args) => runner.execute(
          args,
          probe: false,
          cancellation: MediaCancellation(),
        );
        try {
          await Directory('${dir.path}/media').create();
          final path = '${dir.path}/media/source.mp4';
          await run([
            '-y',
            '-f',
            'lavfi',
            '-i',
            'color=c=red:s=128x72:r=30:d=6',
            '-f',
            'lavfi',
            '-i',
            'sine=frequency=440:duration=6',
            '-c:v',
            'libx264',
            '-pix_fmt',
            'yuv420p',
            '-c:a',
            'aac',
            '-shortest',
            path,
          ]);
          final source = await projects.source('media/source.mp4');
          await run([
            '-y',
            '-f',
            'lavfi',
            '-i',
            'color=c=blue:s=72x128:r=25:d=2',
            '-c:v',
            'libx264',
            '-pix_fmt',
            'yuv420p',
            '${dir.path}/media/blue.mp4',
          ]);
          final blue = await projects.source('media/blue.mp4');
          await run([
            '-y',
            '-f',
            'lavfi',
            '-i',
            'sine=frequency=440:duration=6',
            '-c:a',
            'pcm_s16le',
            '${dir.path}/media/tone.wav',
          ]);
          final tone = await projects.source('media/tone.wav');
          final screenplay = ScreenplayService(db);
          final initial = await screenplay.createInitialStructure();
          final scene = await screenplay.createScene(
            screenplayId: (await db.screenplayDao.getRoot())!.id,
            episodeId: initial.episodeId,
            title: 'Scene',
          );
          final shots = StoryboardService(db);
          final first = await shots.create(scene, values: {'title': 'First'});
          final second = await shots.create(scene, values: {'title': 'Second'});
          await shots.create(
            scene,
            values: {'kind': 'image', 'title': 'Not a film segment'},
          );
          await (db.update(
            db.productionClips,
          )..where((t) => t.id.equals(first.id))).write(
            ProductionClipsCompanion(adoptedAssetId: Value(blue.assetId)),
          );
          await (db.update(
            db.productionClips,
          )..where((t) => t.id.equals(second.id))).write(
            ProductionClipsCompanion(adoptedAssetId: Value(source.assetId)),
          );
          final (direct, skipped) = await projects.fromAdopted(
            initial.episodeId,
            '16:9',
          );
          expect(skipped, isEmpty);
          expect(direct.totalFrames, 192);
          expect(
            direct.clips
                .where((c) => direct.track(c.trackId).kind == 'video')
                .map((c) => c.name),
            ['First', 'Second'],
          );
          final film = await renderer.render(
            direct,
            cancellation: MediaCancellation(),
            progress: (_, _) {},
          );
          try {
            expect(film.info.frameCount, 192);
            expect(film.info.width, 1280);
            expect(film.info.height, 720);
            for (final frame in [24, 72]) {
              final pixel = '${dir.path}/direct-$frame.rgb';
              await run([
                '-y',
                '-i',
                film.file.path,
                '-vf',
                "select='eq(n,$frame)',crop=2:2:640:360,format=rgb24",
                '-frames:v',
                '1',
                '-f',
                'rawvideo',
                pixel,
              ]);
              final bytes = await File(pixel).readAsBytes();
              expect(frame == 24 ? bytes[2] : bytes[0], greaterThan(220));
            }
          } finally {
            await film.dispose();
          }
          // 主轨原声压到几乎无声，音量和淡入淡出看 A1 的正弦音频。
          final doc = EditingDocument.empty('16:9').copyWith(
            clips: [
              EditingClip(
                id: 'v',
                trackId: 'V1',
                content: EditingVideoContent(source: source, gainDb: -60),
                startFrame: 0,
                durationFrames: 144,
              ),
              EditingClip(
                id: 'o',
                trackId: 'V2',
                content: EditingVideoContent(
                  source: blue,
                  transform: const EditingTransform(scale: .5),
                ),
                startFrame: 110,
                durationFrames: 34,
              ),
              EditingClip(
                id: 'a',
                trackId: 'A1',
                content: EditingAudioContent(
                  source: tone,
                  gainDb: 3,
                  fadeInFrames: 24,
                  fadeOutFrames: 48,
                ),
                startFrame: 0,
                durationFrames: 144,
              ),
              const EditingClip(
                id: 't',
                trackId: 'T1',
                startFrame: 0,
                durationFrames: 48,
                content: EditingTextContent(text: 'Hello 字幕'),
              ),
            ],
          );
          final output = await renderer.render(
            doc,
            cancellation: MediaCancellation(),
            preview: true,
            progress: (_, _) {},
          );
          try {
            expect(output.info.frameCount, 144);
            expect(output.info.frameRate, 24);
            expect(output.info.width, 854);
            expect(output.info.height, 480);
            expect(output.info.audioCodec, 'aac');
            expect(output.info.duration.inMilliseconds, closeTo(6000, 42));
            // 缩小的叠加画面靠右上角：竖版 72×128 缩到 240 高，落在 x 668–803、y 29–269。
            for (final frame in [100, 115, 125]) {
              final pixel = '${dir.path}/pixel-$frame.rgb';
              await run([
                '-y',
                '-i',
                output.file.path,
                '-vf',
                "select='eq(n,$frame)',crop=2:2:730:150,format=rgb24",
                '-frames:v',
                '1',
                '-f',
                'rawvideo',
                pixel,
              ]);
              final bytes = await File(pixel).readAsBytes();
              expect(bytes.length, 12);
              expect(frame == 100 ? bytes[0] : bytes[2], greaterThan(220));
              expect(frame == 100 ? bytes[2] : bytes[0], lessThan(30));
            }
            // 字幕在底部烧录：白字只在 0–48 帧出现。
            Future<int> greenPeak(int frame) async {
              final band = '${dir.path}/text-$frame.rgb';
              await run([
                '-y',
                '-i',
                output.file.path,
                '-vf',
                "select='eq(n,$frame)',crop=400:40:227:400,format=rgb24",
                '-frames:v',
                '1',
                '-f',
                'rawvideo',
                band,
              ]);
              final bytes = await File(band).readAsBytes();
              var peak = 0;
              for (var i = 1; i < bytes.length; i += 3) {
                peak = bytes[i] > peak ? bytes[i] : peak;
              }
              return peak;
            }

            expect(await greenPeak(10), greaterThan(200));
            expect(await greenPeak(100), lessThan(80));
            final pcm = '${dir.path}/decoded.f32';
            await run([
              '-y',
              '-i',
              output.file.path,
              '-vn',
              '-ar',
              '48000',
              '-ac',
              '2',
              '-f',
              'f32le',
              pcm,
            ]);
            final samples = ByteData.sublistView(await File(pcm).readAsBytes());
            double sample(int index) =>
                samples.getFloat32(index * 8, Endian.little);
            // Fade is calculated against the entire clip, including the chunk join at 5s.
            expect((sample(240000) - sample(239999)).abs(), lessThan(.03));
            double energy(int frame) {
              var total = 0.0;
              for (var n = frame * 2000; n < (frame + 1) * 2000; n++) {
                total += sample(n).abs();
              }
              return total / 2000;
            }

            expect(energy(119), greaterThan(energy(140) * 4));
            final before = runner.encodes;
            final cached = await renderer.render(
              doc,
              cancellation: MediaCancellation(),
              preview: true,
              progress: (_, _) {},
            );
            await cached.dispose();
            // Cached blocks only need final mux/limiting and decode validation.
            expect(runner.encodes - before, 2);
            final token = MediaCancellation();
            await token.cancel();
            await expectLater(
              renderer.render(doc, cancellation: token, progress: (_, _) {}),
              throwsA(isA<MediaException>()),
            );
            expect(await File(path).exists(), isTrue);
          } finally {
            await output.dispose();
          }
        } finally {
          await renderer.dispose();
          await db.close();
          await app.close();
          await dir.delete(recursive: true);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
