// 职责: 验证包内音色原始字节、按作品去重导入和损坏资源的失败边界。
// 关联文件:
//   lib/shared/models/production/builtin_voices.dart
//   lib/shared/services/production/builtin_voice_orchestrator.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/production/builtin_voices.dart';
import 'package:reveric/shared/models/production/media.dart';
import 'package:reveric/shared/services/production/builtin_voice_orchestrator.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';

class _WaveMedia extends MediaService {
  _WaveMedia() : super(FfmpegRunner());
  bool fail = false;
  @override
  Future<MediaInfo> probe(
    String path, {
    MediaCancellation? cancellation,
  }) async {
    if (fail) {
      throw const MediaException(MediaFailure.invalid_media);
    }
    final bytes = await File(path).readAsBytes();
    final data = ByteData.sublistView(bytes);
    return MediaInfo(
      duration: Duration(
        microseconds:
            ((bytes.length - 44) * 1000000 / data.getUint32(28, Endian.little))
                .round(),
      ),
      hasAudio: true,
      hasVideo: false,
      audioCodec: 'pcm_s16le',
      formatName: 'wav',
    );
  }
}

class _CorruptBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(44);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'seven bundled voices preserve their approved WAV bytes and metadata',
    () async {
      expect(productionBuiltinVoices, hasLength(7));
      expect(productionBuiltinVoices.map((v) => v.id).toSet(), hasLength(7));
      for (final voice in productionBuiltinVoices) {
        final data = await rootBundle.load(voice.bundlePath);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        expect(
          sha256.convert(bytes).toString(),
          voice.sha256,
          reason: voice.id,
        );
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
        expect(data.getUint16(20, Endian.little), 1);
        expect(data.getUint16(22, Endian.little), 2);
        expect(data.getUint32(24, Endian.little), 24000);
        expect(data.getUint16(34, Endian.little), 16);
        final duration =
            ((bytes.length - 44) * 1000 / data.getUint32(28, Endian.little))
                .round();
        expect(duration, voice.durationMs);
      }
    },
  );

  test(
    'selected voices become durable assets, deduplicate within a work and retain the bundled source',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'builtin-voices-test-',
      );
      final db = AppDatabase.forTest(NativeDatabase.memory());
      final library = MediaLibraryService(db, _WaveMedia(), root);
      final voice = productionBuiltinVoices.first;
      Future<AssetRow> select(String novelId) => BuiltinVoiceOrchestrator().run(
        library: library,
        novelId: novelId,
        voice: voice,
        name: '温柔女声',
      );
      try {
        final first = await select('work-a');
        final again = await select('work-a');
        final secondWork = await select('work-b');
        expect(again.id, first.id);
        expect(secondWork.id, isNot(first.id));
        expect(first.source, 'bundled');
        expect(first.type, 'audio');
        expect(first.durationMs, voice.durationMs);
        expect(first.path, startsWith('file_workspaces/work-a/audio/'));
        expect(secondWork.path, startsWith('file_workspaces/work-b/audio/'));
        expect(first.inLibrary, isFalse);
        expect(await db.select(db.assets).get(), hasLength(2));
        for (final asset in [first, secondWork]) {
          expect(
            sha256
                .convert(await File(library.resolve(asset)).readAsBytes())
                .toString(),
            voice.sha256,
          );
        }
        final source = await rootBundle.load(voice.bundlePath);
        expect(
          sha256
              .convert(
                source.buffer.asUint8List(
                  source.offsetInBytes,
                  source.lengthInBytes,
                ),
              )
              .toString(),
          voice.sha256,
        );
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'damaged or unprobeable bundled audio does not leave asset records',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'builtin-voices-failure-',
      );
      final db = AppDatabase.forTest(NativeDatabase.memory());
      final media = _WaveMedia();
      final library = MediaLibraryService(db, media, root);
      try {
        await expectLater(
          BuiltinVoiceOrchestrator().run(
            library: library,
            novelId: 'work',
            voice: productionBuiltinVoices.first,
            name: 'Voice',
            bundle: _CorruptBundle(),
          ),
          throwsFormatException,
        );
        expect(await db.select(db.assets).get(), isEmpty);
        media.fail = true;
        await expectLater(
          BuiltinVoiceOrchestrator().run(
            library: library,
            novelId: 'work',
            voice: productionBuiltinVoices.first,
            name: 'Voice',
          ),
          throwsA(isA<MediaException>()),
        );
        expect(await db.select(db.assets).get(), isEmpty);
        expect(
          await root.list(recursive: true).where((e) => e is File).toList(),
          isEmpty,
        );
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
  );
}
