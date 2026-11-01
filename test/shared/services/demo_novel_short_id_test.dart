// 职责: 验证真实示例作品种子碰撞重试后所有关系使用最终短 ID。
// 关联文件:
//   lib/shared/services/demo_novel.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/utils/storage_paths.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/demo_novel.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/utils/short_entity_id.dart';
import 'package:reveric/shared/utils/text_unit_count.dart';
import 'package:reveric/shared/utils/storage_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seed initial chapter once with the final short identity', () async {
    final db = NovelContentDatabase.forTest(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaultWorkspace(
      includeInitialChapter: true,
      idBuilder: (_) => 'chp_000001',
    );
    await db.seedDefaultWorkspace(
      includeInitialChapter: true,
      idBuilder: (_) => throw StateError('must retain the existing chapter'),
    );
    expect((await db.select(db.chapters).get()).single.id, 'chp_000001');
  });

  test(
    'demo collisions retain distinct rows and final relation endpoints',
    () async {
      final root = await Directory.systemTemp.createTemp('demo_short_id_');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(channel, (_) async => root.path);
      final appDb = AppDatabase.forTest(NativeDatabase.memory());
      addTearDown(() async {
        await NovelContentDatabase.closeAllCached();
        await appDb.close();
        messenger.setMockMethodCallHandler(channel, null);
        await root.delete(recursive: true);
      });
      await RevericPaths.initialize();
      final attempts = <ShortEntityIdType, int>{};
      final novelId = await createDemoNovel(
        appDb,
        idBuilder: (type) {
          final attempt = attempts.update(
            type,
            (value) => value + 1,
            ifAbsent: () => 0,
          );
          // Each stored candidate is offered again to the next entity of its type.
          final suffix = (attempt ~/ 2)
              .toRadixString(36)
              .toUpperCase()
              .padLeft(6, '0');
          return '${shortEntityIdPrefixes[type]}_$suffix';
        },
      );
      expect(novelId, matches(r'^nov_[A-Z0-9]{6}$'));
      final novel = (await appDb.novelDao.get(novelId))!;
      final cover = (await appDb.assetDao.getAsset(novel.coverAssetId!))!;
      expect(cover.purpose, 'cover');
      expect(cover.novelId, novelId);
      expect(cover.path, startsWith('file_workspaces/$novelId/images/'));
      expect(
        await File(RevericPaths.resolveStored(cover.path)!).exists(),
        true,
      );
      expect(await Directory('${root.path}/novel_covers').exists(), false);
      final db = NovelContentDatabase(
        await buildNovelContentDatabasePath(novelId),
      );
      final chapters = await db.select(db.chapters).get();
      expect(novel.title, '潮汐邮局');
      expect(chapters, hasLength(6));
      final orderedChapters = [...chapters]
        ..sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));
      for (var index = 0; index < orderedChapters.length; index++) {
        final chapter = orderedChapters[index];
        expect(chapter.outline, isNotEmpty);
        if (index < 2) {
          expect(chapter.content.length, greaterThan(1000));
          expect(chapter.wordCount, countTextUnits(chapter.content));
        } else {
          expect(chapter.content, isEmpty);
          expect(chapter.wordCount, 0);
        }
      }
      expect(
        novel.wordCount,
        chapters.fold<int>(0, (total, chapter) => total + chapter.wordCount),
      );
      expect(chapters.map((row) => row.id).toSet(), hasLength(6));
      for (final row in chapters) {
        expect(row.id, matches(r'^chp_[A-Z0-9]{6}$'));
      }
      final characters = await db.select(db.characterProfiles).get();
      expect(characters, hasLength(3));
      for (final row in characters) {
        expect(row.id, matches(r'^cha_[A-Z0-9]{6}$'));
      }
      final items = await db.select(db.items).get();
      const prefixes = {
        entityTypeSkill: 'ski',
        entityTypeFaction: 'fac',
        entityTypeCreature: 'cre',
      };
      for (final row in items) {
        expect(row.id, matches('^${prefixes[row.type]}_[A-Z0-9]{6}\$'));
      }
      final endpoints = {
        ...characters.map((row) => row.id),
        ...items.map((row) => row.id),
      };
      final relations = await db.select(db.entityRelations).get();
      expect(relations, hasLength(10));
      for (final row in relations) {
        expect(row.id, matches(r'^rel_[A-Z0-9]{6}$'));
        expect(endpoints, contains(row.sourceId));
        expect(endpoints, contains(row.targetId));
      }
      final documents = await db.select(db.documents).get();
      expect(
        documents.singleWhere((row) => row.title == '雾港沉街年表').content,
        contains('## 七年前'),
      );
      for (final row in documents) {
        final prefix = row.type == documentTypeLore ? 'lrd' : 'mtd';
        expect(row.id, matches('^${prefix}_[A-Z0-9]{6}\$'));
      }
      for (final row in await db.select(db.locations).get()) {
        expect(row.id, matches(r'^loc_[A-Z0-9]{6}$'));
      }
      for (final row in await db.select(db.foreshadowings).get()) {
        expect(row.id, matches(r'^fsh_[A-Z0-9]{6}$'));
      }
      expect(attempts[ShortEntityIdType.character], 4);
      expect(await createDemoNovel(appDb), novelId);
      expect(await NovelContentService(db).getChapters(), hasLength(6));
    },
  );
}
