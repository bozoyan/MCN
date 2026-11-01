// 职责: 用原生媒体工具验证深度输出的帧时间、旋转、尺寸与取消协议。
// 关联文件:
//   lib/shared/services/depth/orchestrator.dart
//   lib/shared/services/depth/native_runner.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reveric/shared/services/depth/model.dart';
import 'package:reveric/shared/services/depth/native_runner.dart';
import 'package:reveric/shared/services/depth/orchestrator.dart';
import 'package:reveric/shared/services/depth/timeline.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/models/production/media.dart';

const binary = String.fromEnvironment('FFMPEG_TEST_BIN');
const modelPath = String.fromEnvironment('DEPTH_TEST_MODEL');
const nativePath = String.fromEnvironment('DEPTH_TEST_BIN');

class DepthTestFfmpeg extends FfmpegRunner {
  @override
  Future<String> execute(
    List<String> arguments, {
    required bool probe,
    required MediaCancellation cancellation,
  }) async {
    checkDepthCancellation(cancellation);
    final process = await Process.start(
      probe ? p.join(p.dirname(binary), 'ffprobe') : binary,
      arguments,
    );
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    await cancellation.bind(() async {
      process.kill();
      await process.exitCode;
    });
    try {
      final code = await process.exitCode;
      final text = await output, diagnostics = await errors;
      checkDepthCancellation(cancellation);
      if (code != 0) {
        throw StateError('ffmpeg $code: $diagnostics');
      }
      return text;
    } finally {
      cancellation.unbind();
    }
  }
}

class GrayFixtureRunner extends DepthNativeRunner {
  const GrayFixtureRunner({String executable = 'fixture', this.beforeRun})
    : super(executable);
  final Future<void> Function()? beforeRun;
  @override
  Future<void> run({
    required String model,
    required Directory workspace,
    required DepthProfile profile,
    required int frames,
    required MediaCancellation cancellation,
    required DepthProgress progress,
  }) async {
    await beforeRun?.call();
    checkDepthCancellation(cancellation);
    final output = await File(
      p.join(workspace.path, 'depth.gray'),
    ).open(mode: FileMode.write);
    try {
      for (var i = 0; i < frames; i++) {
        await output.writeFrom(List.filled(profile.pixels, i % 256));
      }
    } finally {
      await output.close();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('native depth media', () {
    late Directory root;
    late DepthTestFfmpeg ffmpeg;
    setUp(() async {
      root = await Directory.systemTemp.createTemp("depth-'中文'-");
      ffmpeg = DepthTestFfmpeg();
    });
    tearDown(() async {
      await root.delete(recursive: true);
    });
    Future<String> makeVideo(
      String name, {
      bool variable = false,
      bool portrait = false,
    }) async {
      final output = p.join(root.path, name);
      await ffmpeg.execute(
        [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=${portrait ? '64x96' : '96x64'}:rate=25:duration=0.32',
          '-vf',
          variable ? "setpts='if(lt(N,4),N,4+(N-4)*2)/(25*TB)'" : 'null',
          '-vsync',
          'vfr',
          '-c:v',
          'libx264',
          output,
        ],
        probe: false,
        cancellation: MediaCancellation(),
      );
      return output;
    }

    Future<DepthTimeline> probe(String input) async => DepthTimeline.fromProbe(
      jsonDecode(
            await ffmpeg.execute(
              [
                '-v',
                'error',
                '-select_streams',
                'v:0',
                '-show_frames',
                '-show_streams',
                '-of',
                'json',
                input,
              ],
              probe: true,
              cancellation: MediaCancellation(),
            ),
          )
          as Map<String, dynamic>,
    );
    for (final kind in ['landscape', 'portrait', 'vfr', 'rotation']) {
      test('$kind keeps every frame, orientation and timeline', () async {
        var input = await makeVideo(
          'source.mp4',
          variable: kind == 'vfr',
          portrait: kind == 'portrait',
        );
        if (kind == 'rotation') {
          final rotated = p.join(root.path, 'rotated.mp4');
          await ffmpeg.execute(
            [
              '-v',
              'error',
              '-display_rotation:v:0',
              '90',
              '-i',
              input,
              '-c',
              'copy',
              rotated,
            ],
            probe: false,
            cancellation: MediaCancellation(),
          );
          input = rotated;
        }
        final source = await probe(input);
        if (kind == 'rotation') {
          expect((source.width, source.height), (64, 96));
        }
        final workspace = await root.createTemp('work-');
        final output = await DepthOrchestrator().run(
          input: input,
          model: File('fixture'),
          workspace: workspace,
          ffmpeg: ffmpeg,
          native: const GrayFixtureRunner(),
          token: MediaCancellation(),
          progress: (_, _) {},
        );
        final result = await probe(output.file.path);
        expect(result.timestamps, source.timestamps);
        expect(result.durationUs, source.durationUs);
        expect((result.width, result.height), (source.width, source.height));
        expect(output.info.hasAudio, false);
        await output.dispose();
      });
    }
    test(
      'real CPU model completes and native cancellation exits',
      () async {
        final input = await makeVideo('source.mp4');
        final workspace = await root.createTemp('work-');
        final native = DepthNativeRunner(nativePath);
        final output = await DepthOrchestrator().run(
          input: input,
          model: File(modelPath),
          workspace: workspace,
          ffmpeg: ffmpeg,
          native: native,
          token: MediaCancellation(),
          progress: (_, _) {},
        );
        expect(output.info.frameCount, 8);
        final token = MediaCancellation();
        await expectLater(
          native.run(
            model: modelPath,
            workspace: workspace,
            profile: DepthProfile.forVideo(96, 64),
            frames: 8,
            cancellation: token,
            progress: (stage, _) {
              if (stage == DepthStage.inference) {
                unawaited(token.cancel());
              }
            },
          ),
          throwsA(isA<MediaException>()),
        );
        await output.dispose();
      },
      skip: modelPath.isEmpty || nativePath.isEmpty,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }, skip: binary.isEmpty);
}
