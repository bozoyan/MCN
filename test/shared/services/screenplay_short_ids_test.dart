// 职责: 验证剧本结构和正文短 ID 的有效行、软删除行、同批碰撞与严格创建。
// 关联文件:
//   lib/shared/services/screenplay_service.dart
//   lib/shared/database/novel_content_daos/screenplay_dao.dart
//   lib/shared/utils/short_entity_id_allocator.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/models/screenplay_document.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/utils/short_entity_id.dart';
import 'package:reveric/shared/utils/short_entity_id_allocator.dart';

void main() {
  late NovelContentDatabase db;
  setUp(() => db = NovelContentDatabase.forTest(NativeDatabase.memory()));
  tearDown(() => db.close());

  for (final deleted in [false, true]) {
    test(
      'all screenplay creates avoid ${deleted ? 'deleted' : 'active'} identities',
      () async {
        final firstIds = <ShortEntityIdType, String>{};
        final first = ScreenplayService(
          db,
          idBuilder: (type) => firstIds.putIfAbsent(
            type,
            () => '${shortEntityIdPrefixes[type]}_000001',
          ),
        );
        final initial = await first.createInitialStructure();
        final root = (await db.screenplayDao.getRoot())!;
        expect(root.id, 'scr_000001');
        final scene = await first.createScene(
          screenplayId: root.id,
          episodeId: initial.episodeId,
        );
        await first.createBeat(
          screenplayId: root.id,
          episodeId: initial.episodeId,
          actNumber: 1,
        );
        if (deleted) {
          for (final table in [
            'screenplay_seasons',
            'screenplay_episodes',
            'screenplay_beats',
            'screenplay_scenes',
            'screenplay_scene_elements',
          ]) {
            await db.customUpdate('UPDATE $table SET deleted_at = 1');
          }
        }
        final attempts = <ShortEntityIdType, int>{};
        final service = ScreenplayService(
          db,
          idBuilder: (type) {
            final count = attempts.update(
              type,
              (n) => n + 1,
              ifAbsent: () => 1,
            );
            return count == 1
                ? firstIds[type]!
                : '${shortEntityIdPrefixes[type]}_000002';
          },
        );
        final next = await service.createSeason(screenplayId: root.id);
        final nextScene = await service.createScene(
          screenplayId: root.id,
          episodeId: next.episodeId,
        );
        final beat = await service.createBeat(
          screenplayId: root.id,
          episodeId: next.episodeId,
          actNumber: 1,
        );
        expect(next.seasonId, 'sea_000002');
        expect(next.episodeId, 'epi_000002');
        expect(nextScene, 'scn_000002');
        expect(beat, 'sbt_000002');
        final heading = (await db.screenplayDao.getDocumentElements(
          next.episodeId,
        )).single;
        expect(heading.id, 'elm_000002');
        expect(heading.sceneId, nextScene);
        expect(attempts.values, everyElement(2));
        final old = await db
            .customSelect(
              'SELECT deleted_at FROM screenplay_scenes WHERE id = ?',
              variables: [Variable.withString(scene)],
            )
            .getSingle();
        expect(old.read<int>('deleted_at'), deleted ? 1 : 0);
      },
    );
  }

  test(
    'body batch avoids active, deleted and already reserved IDs and preserves retained identity',
    () async {
      final regular = ScreenplayService(db);
      final initial = await regular.createInitialStructure();
      final root = (await db.screenplayDao.getRoot())!;
      final scene = await regular.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
      );
      final heading = (await db.screenplayDao.getDocumentElements(
        initial.episodeId,
      )).single.id!;
      final archived = (await regular.writeElements(
        sceneId: scene,
        elements: const [
          ScreenplayElement(
            type: ScreenplayElementType.action,
            text: 'archived',
          ),
        ],
      )).elements.single;
      await regular.writeElements(sceneId: scene, elements: []);
      final ids = [
        heading,
        archived.id!,
        'elm_000010',
        'elm_000010',
        'elm_000011',
      ].iterator;
      final service = ScreenplayService(
        db,
        idBuilder: (_) {
          expect(ids.moveNext(), isTrue);
          return ids.current;
        },
      );
      final saved = await service.writeElements(
        sceneId: scene,
        elements: const [
          ScreenplayElement(type: ScreenplayElementType.action, text: 'one'),
          ScreenplayElement(type: ScreenplayElementType.action, text: 'two'),
        ],
      );
      expect(saved.elements.map((e) => e.id), ['elm_000010', 'elm_000011']);
      final again = await service.writeElements(
        sceneId: scene,
        elements: saved.elements,
      );
      expect(again.elements.map((e) => e.id), ['elm_000010', 'elm_000011']);
      final document = await regular.readDocument(initial.episodeId);
      final split = document
          .split(ScreenplayPosition(document.sceneElements(scene).last.id!, 1))
          .copyWith();
      expect(
        split.reservedIds,
        containsAll({
          archived.id,
          heading,
          ...document.elements.map((e) => e.id),
        }),
      );
      final draftCandidates = [
        archived.id!,
        heading,
        ...split.newElementIds,
        'elm_000012',
      ].iterator;
      expect(
        allocateScreenplayDraftId(
          ShortEntityIdType.screenplayElement,
          {...split.reservedIds},
          buildId: (_) {
            expect(draftCandidates.moveNext(), isTrue);
            return draftCandidates.current;
          },
        ),
        'elm_000012',
      );
      final restored = await regular.writeElements(
        sceneId: scene,
        elements: [archived],
      );
      expect(restored.elements.single.id, archived.id);
    },
  );

  test(
    '32 collisions fail without inserting a season or child episode',
    () async {
      final initial = await ScreenplayService(db).createInitialStructure();
      final root = (await db.screenplayDao.getRoot())!;
      var attempts = 0;
      final service = ScreenplayService(
        db,
        idBuilder: (_) {
          attempts++;
          return initial.seasonId;
        },
      );
      await expectLater(
        service.createSeason(screenplayId: root.id),
        throwsA(isA<ShortEntityIdAllocationException>()),
      );
      expect(attempts, 32);
      expect(await db.screenplayDao.getSeasons(root.id), hasLength(1));
      expect(
        await db.screenplayDao.getEpisodes(initial.seasonId),
        hasLength(1),
      );
    },
  );
}
