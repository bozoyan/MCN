// 职责: 验证媒体规格解析、编码并发、取消、磁盘失败、临时文件清理，以及截帧、分离音轨、静音、裁剪的参数与校验。
// 关联文件:
//   lib/shared/services/production/media_service.dart
//   lib/shared/services/production/ffmpeg_runner.dart
//   lib/shared/models/production/media.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/production/media.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/media_service.dart';

const probeJson = {
  'format': {'duration': '1.5'},
  'streams': [
    {
      'codec_type': 'video',
      'codec_name': 'h264',
      'width': 720,
      'height': 1280,
      'avg_frame_rate': '24/1',
      'pix_fmt': 'yuv420p',
    },
    {'codec_type': 'audio', 'codec_name': 'aac'},
  ],
};

void main() {
  test('probe preserves video/audio metadata and audio-only files', () {
    final info = MediaInfo.fromProbe(probeJson);
    expect(info.duration, const Duration(milliseconds: 1500));
    expect(info.width, 720);
    expect(info.frameRate, 24);
    expect(info.hasAudio, true);
    final audio = MediaInfo.fromProbe({
      'format': {'duration': '2'},
      'streams': [
        {'codec_type': 'audio', 'codec_name': 'pcm_s16le'},
      ],
    });
    expect(audio.hasVideo, false);
    expect(audio.width, isNull);
    final album = MediaInfo.fromProbe({
      'format': {'duration': '2'},
      'streams': [
        {
          'codec_type': 'video',
          'codec_name': 'mjpeg',
          'disposition': {'attached_pic': 1},
        },
        {'codec_type': 'audio', 'codec_name': 'mp3'},
      ],
    });
    expect(album.hasVideo, false);
    expect(album.hasAudio, true);
    expect(
      () => MediaInfo.fromProbe({'streams': []}),
      throwsA(isA<MediaException>()),
    );
  });

  test(
    'one active encoding forwards cancellation, cleans partial file and releases slot',
    () async {
      final runner = _Runner();
      final service = MediaService(runner);
      final started = Completer<void>();
      final end = Completer<String>();
      runner.encode = (args, token) async {
        await File(args.last).writeAsString('partial');
        await token.bind(
          () async =>
              end.completeError(const MediaException(MediaFailure.cancelled)),
        );
        started.complete();
        return end.future;
      };
      final operation = service.encodeVideo(
        inputPath: 'input.png',
        imageSequence: true,
      );
      final expectation = expectLater(
        operation.result,
        throwsA(
          isA<MediaException>().having(
            (e) => e.reason,
            'reason',
            MediaFailure.cancelled,
          ),
        ),
      );
      await started.future;
      expect(
        () => service.encodeVideo(inputPath: 'other.mp4'),
        throwsA(
          isA<MediaException>().having(
            (e) => e.reason,
            'reason',
            MediaFailure.busy,
          ),
        ),
      );
      await operation.cancel();
      await expectation;
      expect(await File(runner.output!).exists(), false);
      runner.encode = _successfulEncode;
      final result = await service.encodeVideo(inputPath: 'input.mp4').result;
      expect(result.info.videoCodec, 'h264');
      expect(runner.arguments, contains('libx264'));
      expect(runner.arguments, contains('aac'));
      await result.dispose();
    },
  );

  test(
    'disk failure and invalid encoded specs preserve inputs and remove owned temporary output',
    () async {
      final runner = _Runner();
      final service = MediaService(runner);
      runner.encode = (args, token) async {
        await File(args.last).writeAsString('partial');
        throw const FileSystemException('simulated disk full');
      };
      await expectLater(
        service.encodeVideo(inputPath: 'source.mp4').result,
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(runner.output!).parent.exists(), false);
      runner.encode = _successfulEncode;
      runner.outputProbe = jsonEncode({
        'streams': [
          {
            'codec_type': 'video',
            'codec_name': 'mpeg4',
            'width': 720,
            'height': 1280,
          },
        ],
        'format': {'duration': '1'},
      });
      await expectLater(
        service.encodeVideo(inputPath: 'source.mp4').result,
        throwsA(isA<MediaException>()),
      );
      expect(await File(runner.output!).parent.exists(), false);
    },
  );

  test(
    'frame capture seeks to the requested time or decodes the last second',
    () async {
      final runner = _Runner();
      final service = MediaService(runner);
      Future<List<String>> capture({
        Duration at = Duration.zero,
        bool last = false,
      }) async {
        final result = await service.extractFrame('in.mp4', at: at, last: last);
        expect(runner.output, endsWith('.png'));
        await result.dispose();
        return runner.arguments!;
      }

      final first = await capture();
      expect(first.sublist(1, 3), ['-ss', '0.0']);
      expect(first, containsAllInOrder(['-frames:v', '1']));
      final current = await capture(at: const Duration(milliseconds: 700));
      expect(current.sublist(1, 3), ['-ss', '0.7']);
      // 末帧从最后一秒开始逐帧覆盖；离结尾不到 100ms 的当前帧也按末帧截。
      for (final args in [
        await capture(last: true),
        await capture(at: const Duration(milliseconds: 1450)),
      ]) {
        expect(args.sublist(1, 3), ['-ss', '0.5']);
        expect(args, containsAllInOrder(['-update', '1']));
        expect(args, isNot(contains('-frames:v')));
      }
    },
  );

  test(
    'video transform cancellation waits for native completion and cleans output',
    () async {
      final runner = _Runner();
      final service = MediaService(runner);
      final started = Completer<void>();
      final nativeFinished = Completer<String>();
      final token = MediaCancellation();
      var cancelRequested = false;
      var finished = false;
      runner.encode = (args, cancellation) async {
        expect(identical(cancellation, token), true);
        await File(args.last).writeAsString('partial');
        await cancellation.bind(() async {
          cancelRequested = true;
        });
        started.complete();
        return nativeFinished.future;
      };
      final result = service
          .mute('source.mp4', cancellation: token)
          .whenComplete(() {
            finished = true;
          });
      final expectation = expectLater(result, throwsA(isA<MediaException>()));
      await started.future;
      await token.cancel();
      expect(cancelRequested, true);
      expect(finished, false);
      nativeFinished.completeError(
        const MediaException(MediaFailure.cancelled),
      );
      await expectation;
      expect(await File(runner.output!).parent.exists(), false);
    },
  );

  for (final phase in ['input', 'output']) {
    test(
      '$phase probe timeout waits for native completion before returning and cleanup',
      () async {
        final runner = _Runner();
        final service = MediaService(runner);
        final stopped = Completer<void>();
        final native = Completer<String>();
        runner.probing = (args, token) async {
          if (phase == 'input' || args.last == runner.output) {
            await token.bind(() async {
              stopped.complete();
            });
            return native.future;
          }
          return runner.outputProbe;
        };
        var finished = false;
        Object? failure;
        final done = runZoned(
          () async {
            try {
              if (phase == 'input') {
                await service.probe('source.mp4');
              } else {
                await service.mute('source.mp4');
              }
            } catch (error) {
              failure = error;
            } finally {
              finished = true;
            }
          },
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) =>
                parent.createTimer(
                  zone,
                  duration == const Duration(seconds: 30)
                      ? const Duration(milliseconds: 1)
                      : duration,
                  callback,
                ),
          ),
        );
        await stopped.future;
        await Future<void>.delayed(Duration.zero);
        final completedBeforeNative = finished;
        final outputStillPresent = phase == 'output'
            ? await File(runner.output!).exists()
            : null;
        native.completeError(const MediaException(MediaFailure.cancelled));
        await done;
        expect(
          completedBeforeNative,
          false,
          reason: 'Cancel request is not native completion',
        );
        if (phase == 'output') {
          expect(
            outputStillPresent,
            true,
            reason: 'Native probe still owns the temporary output',
          );
          expect(await File(runner.output!).parent.exists(), false);
        }
        expect(
          failure,
          isA<MediaException>().having(
            (e) => e.reason,
            'reason',
            MediaFailure.timeout,
          ),
        );
      },
    );
  }

  test('audio extraction, mute and trim build their outputs', () async {
    final runner = _Runner();
    final service = MediaService(runner);
    final audio = await service.extractAudio('in.mp4');
    expect(runner.output, endsWith('.m4a'));
    expect(runner.arguments, containsAllInOrder(['-map', '0:a:0', '-vn']));
    await audio.dispose();
    final muted = await service.mute('in.mp4');
    expect(runner.arguments, containsAllInOrder(['-an', '-c:v', 'copy']));
    await muted.dispose();
    final trimmed = await service.trim(
      'in.mp4',
      const Duration(milliseconds: 200),
      const Duration(milliseconds: 1200),
    );
    expect(
      runner.arguments,
      containsAllInOrder(['-ss', '0.2', '-i', 'in.mp4', '-t', '1.0']),
    );
    expect(runner.arguments, contains('libx264'));
    await trimmed.dispose();
    expect(
      () => service.trim('in.mp4', Duration.zero, const Duration(seconds: 2)),
      throwsA(isA<MediaException>()),
    );
  });

  test('audio operations reject videos without an audio track', () async {
    final runner = _Runner()
      ..outputProbe = jsonEncode({
        'format': {'duration': '1.5'},
        'streams': [(probeJson['streams'] as List).first],
      });
    final service = MediaService(runner);
    for (final operation in [service.extractAudio, service.mute]) {
      await expectLater(
        operation('in.mp4'),
        throwsA(
          isA<MediaException>().having(
            (e) => e.reason,
            'reason',
            MediaFailure.no_audio,
          ),
        ),
      );
    }
    expect(runner.arguments, isNull);
  });
}

Future<String> _successfulEncode(
  List<String> args,
  MediaCancellation token,
) async {
  await File(args.last).writeAsString('encoded fixture');
  return '';
}

class _Runner extends FfmpegRunner {
  Future<String> Function(List<String>, MediaCancellation) encode =
      _successfulEncode;
  Future<String> Function(List<String>, MediaCancellation)? probing;
  String outputProbe = jsonEncode(probeJson);
  List<String>? arguments;
  String? output;
  @override
  Future<String> execute(
    List<String> args, {
    required bool probe,
    required MediaCancellation cancellation,
  }) async {
    if (probe) {
      return probing == null ? outputProbe : probing!(args, cancellation);
    }
    arguments = args;
    output = args.last;
    return encode(args, cancellation);
  }
}
