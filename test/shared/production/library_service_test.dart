// 职责: 验证媒体导入复制去重、探测失败回滚、软删除与无覆盖导出。
// 关联文件:
//   lib/shared/services/production/library_service.dart
//   lib/shared/services/production/import_orchestrator.dart

import 'dart:convert';
import 'dart:io';
import 'package:reveric/shared/database/daos/asset_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/production/media.dart';
import 'package:reveric/shared/models/asset_purpose.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late File source;
  late _Database db;
  late _Media media;
  late MediaLibraryService library;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('media-library-test-');
    root = await Directory('${temporary.path}/support').create();
    source = await File(
      '${temporary.path}/原始拍摄.mp4',
    ).writeAsBytes(List.generate(200000, (i) => i % 256));
    db = _Database(NativeDatabase.memory());
    media = _Media();
    library = MediaLibraryService(db, media, root);
  });
  tearDown(() async {
    await db.close();
    await temporary.delete(recursive: true);
  });
  Future<AssetRow> import({MediaCancellation? token}) => library.importFile(
    source,
    name: '原始拍摄.mp4',
    novelId: 'work-a',
    purpose: AssetPurpose.production_upload,
    cancellation: token ?? MediaCancellation(),
  );
  test(
    'file metadata shares probes by canonical path and invalidates changed files',
    () async {
      final asset = await import();
      final before = media.calls;
      final results = await Future.wait([
        library.probePath(asset.path!),
        library.probePath(library.resolve(asset)),
      ]);
      expect(results.first.duration, const Duration(milliseconds: 1250));
      expect(results.first.width, 640);
      expect(media.calls - before, 1);
      await library.probePath(asset.path!);
      expect(media.calls - before, 1);
      await File(
        library.resolve(asset),
      ).setLastModified(DateTime.now().add(const Duration(seconds: 3)));
      await library.probePath(asset.path!);
      expect(media.calls - before, 2);
    },
  );
  test(
    'concurrent identical imports keep one identity and independent controlled copy',
    () async {
      final assets = await Future.wait([import(), import()]);
      expect(assets[0].id, assets[1].id);
      expect(assets[0].durationMs, 1250);
      expect(assets[0].width, 640);
      expect(assets[0].type, 'video');
      expect(assets[0].mimeType, 'video/mp4');
      expect(assets[0].name, '原始拍摄.mp4');
      expect(
        await File(library.resolve(assets[0])).readAsBytes(),
        await source.readAsBytes(),
      );
      expect(await db.assetDao.watchAssets().first, hasLength(1));
    },
  );
  test(
    'editing import joins the library and re-import restores membership',
    () async {
      Future<AssetRow> upload({bool addToLibrary = true}) => library.importFile(
        source,
        name: '原始拍摄.mp4',
        novelId: 'work-a',
        purpose: AssetPurpose.editing_upload,
        cancellation: MediaCancellation(),
        addToLibrary: addToLibrary,
      );
      Future<List<String>> visibleIds() async =>
          (await db.assetDao
                  .watchAssets(novelId: 'work-a', inLibrary: true)
                  .first)
              .map((asset) => asset.id)
              .toList();

      final original = await upload();
      expect(original.inLibrary, isTrue);
      expect(await visibleIds(), [original.id]);

      await db.assetDao.setInLibrary(original.id, false);
      expect(await visibleIds(), isEmpty);
      final restored = await upload();
      expect(restored.id, original.id);
      expect(restored.inLibrary, isTrue);
      expect(await visibleIds(), [original.id]);

      final reused = await upload(addToLibrary: false);
      expect(reused.inLibrary, isTrue);
      expect(await visibleIds(), [original.id]);
      expect(await db.assetDao.watchAssets().first, hasLength(1));
      expect(
        await root
            .list(recursive: true)
            .where((entry) => entry is File)
            .toList(),
        hasLength(1),
      );
    },
  );
  test('same-named imports in one work get a counted name', () async {
    final bytes = await source.readAsBytes();
    final other = File('${temporary.path}/other.mp4')
      ..writeAsBytesSync([...bytes.take(bytes.length - 1), bytes.last ^ 1]);
    Future<AssetRow> upload(File file, String novelId) => library.importFile(
      file,
      name: '原始拍摄.mp4',
      novelId: novelId,
      purpose: AssetPurpose.production_upload,
      cancellation: MediaCancellation(),
    );
    expect((await upload(source, 'work-a')).name, '原始拍摄.mp4');
    expect((await upload(other, 'work-a')).name, '原始拍摄 (2).mp4');
    expect((await upload(source, 'work-a')).name, '原始拍摄.mp4');
    expect((await upload(other, 'work-b')).name, '原始拍摄.mp4');
  });
  test(
    'importing another work file copies it and retains both identities',
    () async {
      final a = await import();
      final b = await library.importFile(
        File(library.resolve(a)),
        name: 'copied.mp4',
        novelId: 'work-b',
        purpose: AssetPurpose.production_upload,
        cancellation: MediaCancellation(),
      );
      expect(a.path, startsWith('file_workspaces/work-a/videos/'));
      expect(b.path, startsWith('file_workspaces/work-b/videos/'));
      expect(b.id, isNot(a.id));
      expect(
        await File(library.resolve(a)).readAsBytes(),
        await File(library.resolve(b)).readAsBytes(),
      );
    },
  );

  test(
    'dedup copies an out-of-scope location without replacing the asset identity',
    () async {
      final a = await import();
      final legacy = File('${root.path}/file_workspaces/work/legacy.mp4');
      await legacy.parent.create(recursive: true);
      await File(library.resolve(a)).copy(legacy.path);
      await db.customStatement('UPDATE assets SET path = ? WHERE id = ?', [
        'file_workspaces/work/legacy.mp4',
        a.id,
      ]);
      final repaired = await import();
      expect(repaired.id, a.id);
      expect(repaired.path, startsWith('file_workspaces/work-a/videos/'));
      expect(await legacy.readAsBytes(), await source.readAsBytes());
    },
  );

  test('ordinary imports stay outside the library', () async {
    final asset = await import();
    expect(asset.inLibrary, isFalse);
    expect(await db.assetDao.watchAssets(inLibrary: true).first, isEmpty);
  });
  for (final type in ['image', 'video']) {
    test(
      '$type imports reuse within a work and stay separate across works',
      () async {
        final file = type == 'image'
            ? await File('${temporary.path}/frame.png').writeAsBytes(
                base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                ),
              )
            : source;
        Future<AssetRow> upload(String novelId) => library.importFile(
          file,
          name: type == 'image' ? 'frame.png' : 'clip.mp4',
          novelId: novelId,
          purpose: AssetPurpose.production_upload,
          cancellation: MediaCancellation(),
        );
        final original = await upload('work-a');
        final again = await upload('work-a');
        final other = await upload('work-b');
        expect(again.id, original.id);
        expect(other.id, isNot(original.id));
        expect(original.novelId, 'work-a');
        expect(other.novelId, 'work-b');
        expect(original.purpose, AssetPurpose.production_upload.value);
        expect((await db.assetDao.getAsset(original.id))!.novelId, 'work-a');
        expect(await db.select(db.assets).get(), hasLength(2));
        expect(
          await root
              .list(recursive: true)
              .where((entry) => entry is File)
              .toList(),
          hasLength(2),
        );
      },
    );
  }
  test(
    'cancel and format failure leave source intact without asset or controlled partial',
    () async {
      final token = MediaCancellation();
      media.afterProbe = token.cancel;
      await expectLater(
        import(token: token),
        throwsA(
          isA<MediaException>().having(
            (e) => e.reason,
            'reason',
            MediaFailure.cancelled,
          ),
        ),
      );
      media.afterProbe = null;
      media.result = const MediaInfo(
        duration: Duration(seconds: 1),
        hasAudio: true,
        hasVideo: false,
        formatName: 'mp3',
      );
      await expectLater(import(), throwsA(isA<MediaException>()));
      expect(await db.assetDao.watchAssets().first, isEmpty);
      expect(await root.list(recursive: true).toList(), isEmpty);
      expect(await source.length(), 200000);
    },
  );
  test(
    'registration failure rolls back the row and operation-owned file',
    () async {
      db.assetDao.fail = true;
      await expectLater(import(), throwsA(isA<StateError>()));
      expect(await db.assetDao.watchAssets().first, isEmpty);
      expect(
        await root.list(recursive: true).where((item) => item is File).toList(),
        isEmpty,
      );
      expect(await source.length(), 200000);
    },
  );
  test('export refuses collisions and soft delete retains bytes', () async {
    final asset = await import();
    final exported = File('${temporary.path}/输出.mp4');
    await library.exportFile(asset, exported.path);
    expect(await exported.readAsBytes(), await source.readAsBytes());
    await exported.writeAsString('existing user export');
    await expectLater(
      library.exportFile(asset, exported.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await exported.readAsString(), 'existing user export');
    await library.delete(asset.id);
    expect(await db.assetDao.getAsset(asset.id), isNull);
    expect(await File(library.resolve(asset)).length(), 200000);
  });
  test(
    'unwritable destination rejects registration and preserves source',
    () async {
      final blocked = await File(
        '${temporary.path}/not-a-directory',
      ).writeAsString('keep');
      final failing = MediaLibraryService(db, media, Directory(blocked.path));
      await expectLater(
        failing.importFile(
          source,
          name: 'clip.mp4',
          novelId: 'work-a',
          purpose: AssetPurpose.production_upload,
          cancellation: MediaCancellation(),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await db.assetDao.watchAssets().first, isEmpty);
      expect(await blocked.readAsString(), 'keep');
      expect(await source.length(), 200000);
    },
  );
}

class _Media extends MediaService {
  _Media() : super(_Runner());
  MediaInfo result = const MediaInfo(
    duration: Duration(milliseconds: 1250),
    hasAudio: true,
    hasVideo: true,
    width: 640,
    height: 360,
    videoCodec: 'h264',
    formatName: 'mov,mp4,m4a,3gp,3g2,mj2',
  );
  int calls = 0;
  Future<void> Function()? afterProbe;
  @override
  Future<MediaInfo> probe(
    String path, {
    MediaCancellation? cancellation,
  }) async {
    calls++;
    expect(await File(path).length(), 200000);
    await afterProbe?.call();
    return result;
  }
}

class _Runner extends FfmpegRunner {
  @override
  Future<String> execute(
    List<String> arguments, {
    required bool probe,
    required MediaCancellation cancellation,
  }) => throw UnimplementedError();
}

class _Database extends AppDatabase {
  _Database(super.executor) : super.forTest();
  late final _Dao _dao = _Dao(this);
  @override
  _Dao get assetDao => _dao;
}

class _Dao extends AssetDao {
  _Dao(super.db);
  bool fail = false;
  @override
  Future<void> insertAsset(AssetsCompanion asset) async {
    await super.insertAsset(asset);
    if (fail) {
      throw StateError('simulated registration failure');
    }
  }
}
