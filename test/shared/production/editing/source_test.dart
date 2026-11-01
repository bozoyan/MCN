// 职责: 验证素材替换、源区间与运行时缓存指纹，未知工程版本不会被空工程覆盖。
// 关联文件:
//   lib/shared/services/editing/service.dart
//   lib/shared/database/type_converters.dart
import 'dart:io';
import 'package:drift/native.dart';
import 'package:reveric/shared/models/production/asset_content.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/editing/document.dart';
import 'package:reveric/shared/models/production/media.dart';
import 'package:reveric/shared/services/editing/render_service.dart';
import 'package:reveric/shared/services/editing/service.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';

class ProbeMedia extends MediaService {
  ProbeMedia() : super(FfmpegRunner());
  Duration duration = const Duration(seconds: 1);
  @override
  Future<MediaInfo> probe(
    String path, {
    MediaCancellation? cancellation,
  }) async {
    if (!await File(path).exists() || await File(path).length() == 0) {
      throw const MediaException(MediaFailure.invalid_media);
    }
    return MediaInfo(
      duration: duration,
      hasVideo: true,
      hasAudio: false,
      width: 100,
      height: 100,
    );
  }
}

void main() {
  test(
    'changed media stays usable, cache fingerprints change and invalid ranges fail',
    () async {
      final dir = await Directory.systemTemp.createTemp('editing-source-');
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      final app = AppDatabase.forTest(NativeDatabase.memory());
      final media = ProbeMedia();
      final service = EditingService(db, MediaLibraryService(app, media, dir));
      final file = await File(
        '${dir.path}/file_workspaces/work/clip.mp4',
      ).create(recursive: true);
      await file.writeAsBytes([1, 2, 3]);
      await app.assetDao.insertAsset(
        AssetsCompanion.insert(
          id: 'clip-asset',
          type: 'video',
          purpose: 'general',
          path: const Value('file_workspaces/work/clip.mp4'),
          content: const Value(VideoAssetContent(mimeType: 'video/mp4')),
        ),
      );
      final doc = EditingDocument.empty('16:9').copyWith(
        clips: [
          EditingClip(
            id: 'clip',
            trackId: 'V1',
            startFrame: 0,
            durationFrames: 24,
            content: EditingVideoContent(
              source: EditingSource(
                assetId: 'clip-asset',
                mediaType: 'video',
                durationUs: 1000000,
              ),
            ),
          ),
        ],
      );
      try {
        await service.verify(doc, MediaCancellation());
        final before = await service.fingerprints(doc, MediaCancellation());
        await file.writeAsBytes([3, 2, 1]);
        await service.verify(doc, MediaCancellation());
        final after = await service.fingerprints(doc, MediaCancellation());
        expect(
          EditingRenderService.cacheKey(doc, 0, 24, (
            100,
            100,
          ), sourceFingerprints: before),
          isNot(
            EditingRenderService.cacheKey(doc, 0, 24, (
              100,
              100,
            ), sourceFingerprints: after),
          ),
        );
        media.duration = const Duration(milliseconds: 500);
        await expectLater(
          service.verify(doc, MediaCancellation()),
          throwsA(isA<EditingSourceProblem>()),
        );
        await file.delete();
        await expectLater(
          service.verify(doc, MediaCancellation()),
          throwsA(isA<EditingSourceProblem>()),
        );
      } finally {
        await db.close();
        await app.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('unsupported document remains unchanged after a failed load', () async {
    final db = NovelContentDatabase.forTest(NativeDatabase.memory());
    final app = AppDatabase.forTest(NativeDatabase.memory());
    final service = EditingService(
      db,
      MediaLibraryService(
        app,
        MediaService(FfmpegRunner()),
        Directory.systemTemp,
      ),
    );
    const raw =
        '{"format":"reveric.editing","version":99,"futureField":"keep"}';
    try {
      await db.customStatement(
        "INSERT INTO video_editings(id,title,created_at,updated_at,document,revision) VALUES('ep','Independent',100,200,?,7)",
        [raw],
      );
      await expectLater(service.load('ep'), throwsFormatException);
      final row = await db
          .customSelect(
            "SELECT document, revision FROM video_editings WHERE id='ep'",
          )
          .getSingle();
      expect(row.read<String>('document'), raw);
      expect(row.read<int>('revision'), 7);
    } finally {
      await db.close();
      await app.close();
    }
  });
  test(
    'audio content accepts audio or video with audio, not silent video or images',
    () {
      for (final (type, hasAudio, accepted) in [
        ('audio', true, true),
        ('video', true, true),
        ('video', false, false),
        ('image', false, false),
      ]) {
        final doc = EditingDocument.empty('16:9').copyWith(
          clips: [
            EditingClip(
              id: 'audio',
              trackId: 'A1',
              startFrame: 0,
              durationFrames: 24,
              content: EditingAudioContent(
                source: EditingSource(
                  assetId: 'source',
                  mediaType: type,
                  durationUs: 1000000,
                  hasAudio: hasAudio,
                ),
              ),
            ),
          ],
        );
        expect(
          () => EditingDocument.fromJson(doc.toJson()),
          accepted ? returnsNormally : throwsFormatException,
        );
      }
    },
  );
}
