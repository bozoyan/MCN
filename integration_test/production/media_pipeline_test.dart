// 职责: 在桌面宿主验证实际探测、H.264/AAC 编码、取消和播放器同进程共存。
// 关联文件:
//   lib/shared/services/production/media_service.dart
//   lib/shared/services/production/playback_service.dart
//   test/fixtures/video_media.dart

import 'package:reveric/shared/models/asset_purpose.dart';
import 'package:drift/native.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reveric/shared/models/production/media.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/media_service.dart';
import 'package:reveric/shared/services/production/playback_service.dart';
import '../../test/fixtures/video_media.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'packaged software encoder and one player coexist with probe cancellation and failure',
    (tester) async {
      final playback = PlaybackService();
      final media = MediaService(FfmpegRunner());
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp(
          'reveric_media_pipeline_',
        );
        EncodedMedia? encoded;
        try {
          for (var i = 0; i < 24; i++) {
            await File(
              '${directory.path}/frame-${i.toString().padLeft(3, '0')}.png',
            ).writeAsBytes(base64Decode(videoReferencePngBase64));
          }
          final audio = '${directory.path}/tone.wav';
          final runner = FfmpegRunner();
          final version = await runner.execute(
            ['-version'],
            probe: false,
            cancellation: MediaCancellation(),
          );
          expect(version, contains('8.1.2'));
          debugPrint('Native FFmpeg version: ${version.split("\n").first}');
          final configuration = await runner.execute(
            ['-buildconf'],
            probe: false,
            cancellation: MediaCancellation(),
          );
          expect(configuration, contains('--enable-libx264'));
          expect(configuration, contains('--enable-gpl'));
          debugPrint('Native FFmpeg configuration: $configuration');
          final capabilities = await runner.execute(
            ['-hide_banner', '-encoders'],
            probe: false,
            cancellation: MediaCancellation(),
          );
          expect(capabilities, contains('libx264'));
          expect(capabilities, contains('aac'));
          await runner.execute(
            [
              '-y',
              '-f',
              'lavfi',
              '-i',
              'sine=frequency=440:duration=1',
              '-c:a',
              'pcm_s16le',
              audio,
            ],
            probe: false,
            cancellation: MediaCancellation(),
          );
          expect((await media.probe(audio)).hasAudio, true);
          final rawProbe = await runner.execute(
            ['-show_format', '-show_streams', '-of', 'json', audio],
            probe: true,
            cancellation: MediaCancellation(),
          );
          expect((jsonDecode(rawProbe) as Map)['streams'], isNotEmpty);
          encoded = await media
              .encodeVideo(
                inputPath: '${directory.path}/frame-%03d.png',
                audioPath: audio,
                imageSequence: true,
                width: 64,
                height: 96,
                fps: 24,
                duration: const Duration(seconds: 1),
              )
              .result;
          expect(encoded.info.videoCodec, 'h264');
          expect(encoded.info.audioCodec, 'aac');
          expect(encoded.info.pixelFormat, 'yuv420p');
          expect(encoded.info.duration.inMilliseconds, closeTo(1000, 100));
          expect(encoded.info.frameRate, 24);
          final db = AppDatabase.forTest(NativeDatabase.memory());
          try {
            final library = MediaLibraryService(
              db,
              media,
              Directory('${directory.path}/library'),
            );
            for (final input in [
              File('${directory.path}/frame-000.png'),
              File(audio),
              encoded.file,
            ]) {
              final name = input == encoded.file
                  ? '输出.mp4'
                  : input.uri.pathSegments.last;
              final asset = await library.importFile(
                input,
                name: name,
                novelId: 'native-media',
                purpose: AssetPurpose.production_upload,
                cancellation: MediaCancellation(),
              );
              expect(
                await File(library.resolve(asset)).readAsBytes(),
                await input.readAsBytes(),
              );
              expect(
                asset.type,
                input == encoded.file
                    ? 'video'
                    : name.endsWith('.png')
                    ? 'image'
                    : 'audio',
              );
              final export =
                  '${directory.path}/export-${asset.id}.${name.split('.').last}';
              await library.exportFile(asset, export);
              expect(
                await File(export).readAsBytes(),
                await input.readAsBytes(),
              );
              if (asset.type != 'image') {
                expect(asset.durationMs, greaterThan(0));
              }
            }
            expect(await db.assetDao.watchAssets().first, hasLength(3));
          } finally {
            await db.close();
          }
          for (var i = 0; i < 2; i++) {
            await playback.open(
              owner: 'video',
              path: encoded.file.path,
              play: true,
            );
            _expectSharedFfmpeg();
            final info = await media.probe(encoded.file.path);
            expect(info.width, 64);
            expect(info.height, 96);
            await playback.release('video');
            await playback.open(owner: 'audio', path: audio, play: true);
            await playback.release('audio');
            final second = await media
                .encodeVideo(
                  inputPath: encoded.file.path,
                  width: 64,
                  height: 96,
                )
                .result;
            expect(second.info.videoCodec, 'h264');
            await second.dispose();
          }
          final cancel = MediaCancellation();
          final running = runner.execute(
            [
              '-y',
              '-re',
              '-f',
              'lavfi',
              '-i',
              'testsrc=size=64x96:rate=24',
              '-t',
              '60',
              '-pix_fmt',
              'yuv420p',
              '-c:v',
              'libx264',
              '${directory.path}/cancel.mp4',
            ],
            probe: false,
            cancellation: cancel,
          );
          final cancelled = expectLater(
            running,
            throwsA(
              isA<MediaException>().having(
                (e) => e.reason,
                'reason',
                MediaFailure.cancelled,
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await cancel.cancel();
          await cancelled;
          final corrupt = await File(
            '${directory.path}/corrupt.mp4',
          ).writeAsString('not media');
          await expectLater(
            media.probe(corrupt.path),
            throwsA(isA<MediaException>()),
          );
        } finally {
          await playback.dispose();
          await encoded?.dispose();
          await directory.delete(recursive: true);
        }
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

void _expectSharedFfmpeg() {
  if (Platform.isMacOS) {
    final process = DynamicLibrary.process();
    final count = process.lookupFunction<Uint32 Function(), int Function()>(
      '_dyld_image_count',
    );
    final name = process
        .lookupFunction<
          Pointer<Utf8> Function(Uint32),
          Pointer<Utf8> Function(int)
        >('_dyld_get_image_name');
    final paths = List.generate(count(), (i) => name(i).toDartString());
    final codecs = paths
        .where((p) => p.contains('avcodec') || p.contains('Avcodec'))
        .toList();
    expect(codecs, hasLength(1));
    expect(codecs.single, contains('libavcodec.framework'));
    expect(paths.any((p) => RegExp(r'libffmpeg\.\d').hasMatch(p)), false);
    expect(paths.any((p) => p.contains('mdk.framework')), true);
    debugPrint('Shared playback/encoding codec: ${codecs.single}');
  } else if (Platform.isWindows) {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final getModule = kernel
        .lookupFunction<
          Pointer<Void> Function(Pointer<Utf16>),
          Pointer<Void> Function(Pointer<Utf16>)
        >('GetModuleHandleW');
    bool loaded(String library) {
      final name = library.toNativeUtf16();
      try {
        return getModule(name) != nullptr;
      } finally {
        calloc.free(name);
      }
    }

    expect(loaded('mdk.dll'), true);
    expect(loaded('avcodec-62.dll'), true);
    expect(loaded('ffmpeg-9.dll'), false);
    expect(loaded('libmpv-2.dll'), false);
  }
}
