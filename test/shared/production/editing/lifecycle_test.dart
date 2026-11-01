// 职责: 验证独立剪辑与剧集创建、补建、并发、失败回滚及软删除的业务边界。
// 关联文件:
//   lib/shared/services/production/editing_orchestrator.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/database/novel_content_daos/editing_dao.dart
import 'dart:io';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/editing/document.dart';
import 'package:reveric/shared/services/editing/service.dart';
import 'package:reveric/shared/services/production/library_service.dart';
import 'package:reveric/shared/services/production/media_service.dart';
import 'package:reveric/shared/services/production/ffmpeg_runner.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/screenplay.dart';
import 'package:reveric/shared/services/production/editing_orchestrator.dart';
import 'package:reveric/shared/services/screenplay_service.dart';

class _AdoptedSources extends EditingService {
  _AdoptedSources(super.database, super.library);
  @override
  Future<EditingSource> source(
    String assetId, {
    MediaCancellation? cancellation,
  }) async => EditingSource(
    assetId: assetId,
    mediaType: 'video',
    durationUs: 1000000,
    hasAudio: true,
  );
}

void main() {
  late NovelContentDatabase db;
  late ScreenplayService service;
  setUp(() {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = ScreenplayService(db);
  });
  tearDown(() => db.close());
  Future<VideoEditingRow> editing(String episodeId) async => (await db
      .editingDao
      .get((await db.screenplayDao.getEpisode(episodeId))!.editingId!))!;

  test(
    'all creation entries bind empty independent projects, title and ratio stay independent',
    () async {
      final first = await service.createInitialStructure();
      final root = (await db.screenplayDao.getRoot())!;
      await (db.update(db.screenplays)..where((t) => t.id.equals(root.id)))
          .write(const ScreenplaysCompanion(ratio: Value('9:16')));
      final second = await service.createEpisode(
        seasonId: first.seasonId,
        title: 'Second',
      );
      final season = await service.createSeason(screenplayId: root.id);
      final rows = await Future.wait([
        editing(first.episodeId),
        editing(second),
        editing(season.episodeId),
      ]);
      expect(rows.map((r) => r.id).toSet(), hasLength(3));
      expect(rows.map((r) => r.document.clips), everyElement(isEmpty));
      expect(rows.map((r) => r.revision), everyElement(0));
      expect(rows.map((r) => r.title), ['1', 'Second', '1']);
      expect(rows.map((r) => r.document.ratio), ['16:9', '9:16', '9:16']);
      await service.updateEpisode(episodeId: second, title: 'Renamed');
      await (db.update(db.screenplays)..where((t) => t.id.equals(root.id)))
          .write(const ScreenplaysCompanion(ratio: Value('1:1')));
      expect((await editing(second)).title, 'Second');
      expect((await editing(second)).document.ratio, '9:16');
      await service.deleteEpisode(second);
      expect(await db.editingDao.get(rows[1].id), isNotNull);
    },
  );

  test(
    'parallel opens initialize only a null reference, and invalid non-null references fail',
    () async {
      final first = await service.createInitialStructure();
      final oldId = (await editing(first.episodeId)).id;
      await (db.update(db.screenplayEpisodes)
            ..where((t) => t.id.equals(first.episodeId)))
          .write(const ScreenplayEpisodesCompanion(editingId: Value(null)));
      final before = (await db.editingDao.list()).length;
      final results = await Future.wait(
        List.generate(
          8,
          (_) => EpisodeEditingOrchestrator().ensureEpisodeEditing(
            db,
            first.episodeId,
          ),
        ),
      );
      expect(results.map((r) => r.editing.id).toSet(), hasLength(1));
      expect(results.where((r) => r.created), hasLength(1));
      expect((await db.editingDao.list()).length, before + 1);
      expect(await db.editingDao.get(oldId), isNotNull);
      final id = results.first.editing.id;
      await db.editingDao.softDelete(id);
      await expectLater(
        EpisodeEditingOrchestrator().ensureEpisodeEditing(db, first.episodeId),
        throwsA(isA<ScreenplayServiceException>()),
      );
      expect(
        (await db.screenplayDao.getEpisode(first.episodeId))!.editingId,
        id,
      );
    },
  );

  test(
    'binding failure rolls back the empty editing and the next open can retry',
    () async {
      final first = await service.createInitialStructure();
      await (db.update(db.screenplayEpisodes)
            ..where((t) => t.id.equals(first.episodeId)))
          .write(const ScreenplayEpisodesCompanion(editingId: Value(null)));
      final before = (await db.editingDao.list()).length;
      await db.customStatement(
        "CREATE TRIGGER fail_binding BEFORE UPDATE OF editing_id ON screenplay_episodes BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(
        EpisodeEditingOrchestrator().ensureEpisodeEditing(db, first.episodeId),
        throwsA(anything),
      );
      expect((await db.editingDao.list()).length, before);
      expect(
        (await db.screenplayDao.getEpisode(first.episodeId))!.editingId,
        isNull,
      );
      await db.customStatement('DROP TRIGGER fail_binding');
      final result = await EpisodeEditingOrchestrator().ensureEpisodeEditing(
        db,
        first.episodeId,
      );
      expect(result.created, isTrue);
      expect((await db.editingDao.list()).length, before + 1);
    },
  );

  test(
    'editing creation failure rolls back initial structure and episode creation, retry works',
    () async {
      // A fixture trigger injects an SQLite failure; production schema has no trigger.
      await db.customStatement(
        "CREATE TRIGGER fail_editing BEFORE INSERT ON video_editings BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(service.createInitialStructure(), throwsA(anything));
      expect(await db.select(db.screenplays).get(), isEmpty);
      expect(await db.select(db.screenplaySeasons).get(), isEmpty);
      expect(await db.select(db.screenplayEpisodes).get(), isEmpty);
      await db.customStatement('DROP TRIGGER fail_editing');
      final first = await service.createInitialStructure();
      await db.customStatement(
        "CREATE TRIGGER fail_editing BEFORE INSERT ON video_editings BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(
        service.createEpisode(seasonId: first.seasonId),
        throwsA(anything),
      );
      expect(await db.select(db.screenplayEpisodes).get(), hasLength(1));
      expect(await db.editingDao.list(), hasLength(1));
      await db.customStatement('DROP TRIGGER fail_editing');
      final id = await service.createEpisode(seasonId: first.seasonId);
      expect((await db.screenplayDao.getEpisode(id))!.episodeNumber, 2);
      expect((await editing(id)).document.clips, isEmpty);
    },
  );
  test(
    'adopted imports freeze the asset and record production clip provenance',
    () async {
      final app = AppDatabase.forTest(NativeDatabase.memory());
      final projects = _AdoptedSources(
        db,
        MediaLibraryService(
          app,
          MediaService(FfmpegRunner()),
          Directory.systemTemp,
        ),
      );
      try {
        await db
            .into(db.productionClips)
            .insert(
              ProductionClipsCompanion.insert(
                id: 'adopted-shot',
                episodeId: 'episode',
                kind: 'video',
                sceneId: const Value('scene'),
                adoptedAssetId: const Value('adopted-asset'),
                title: const Value('Shot title'),
              ),
            );
        await db
            .into(db.productionClips)
            .insert(
              ProductionClipsCompanion.insert(
                id: 'pending-shot',
                episodeId: 'episode',
                kind: 'video',
                sceneId: const Value('scene'),
              ),
            );
        final (doc, skipped) = await projects.fromAdopted('episode', '9:16');
        expect(skipped, ['pending-shot']);
        expect(doc.mainClips.single.origin!.toJson(), {
          'type': 'production_clip',
          'id': 'adopted-shot',
        });
        expect(doc.mainClips.single.media!.source.assetId, 'adopted-asset');
        expect(doc.mainClips.single.name, 'Shot title');
      } finally {
        await app.close();
      }
    },
  );
}
