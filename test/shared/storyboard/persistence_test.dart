// 职责: 验证当前内容库持久化场次和分镜内容。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';

void main() {
  test('screenplay and shots survive reopening a new database', () async {
    final dir = await Directory.systemTemp.createTemp(
      'storyboard-persistence-',
    );
    final file = File('${dir.path}/content.sqlite');
    var db = NovelContentDatabase.forTest(NativeDatabase(file));
    await db.customStatement(
      "INSERT INTO screenplay_scenes(id,screenplay_id,episode_id,title,synopsis,created_at,updated_at) VALUES('scene','script','episode','Original','Keep',100,200)",
    );
    await db.customStatement(
      "INSERT INTO screenplay_scene_elements(id,scene_id,episode_id,time_label,sort_order,type,created_at,updated_at) VALUES('heading','scene','episode','Night',0,'scene_heading',100,200)",
    );
    await db.customStatement('''
INSERT INTO screenplays(id, created_at, updated_at) VALUES('script',100,200);
INSERT INTO screenplay_episodes(id,screenplay_id,season_id,episode_number,created_at,updated_at) VALUES('episode','script','season',1,100,200);
''');
    try {
      expect((await db.screenplayDao.getScene('scene'))!.title, 'Original');
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        NovelContentDatabase.currentSchemaVersion,
      );
      expect(
        (await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE name='production_image_runs'",
            )
            .get()),
        isEmpty,
      );
      final columns = await db
          .customSelect('PRAGMA table_info(production_clips)')
          .get();
      expect(
        columns
            .singleWhere((r) => r.read<String>('name') == 'created_at')
            .read<String>('type'),
        'INTEGER',
      );
      expect(
        columns
            .singleWhere((r) => r.read<String>('name') == 'id')
            .read<int>('pk'),
        1,
      );
      expect(
        columns.map((r) => r.read<String>('name')),
        isNot(contains('revision')),
      );
      final itemColumn = columns.singleWhere(
        (r) => r.read<String>('name') == 'item_id',
      );
      expect(itemColumn.read<String>('type'), 'TEXT');
      expect(itemColumn.read<int>('notnull'), 0);
      final root = (await db.screenplayDao.getRoot())!;
      expect(root.ratio, '16:9');
      expect(root.styleId, isNull);
      expect(
        columns.map((r) => r.read<String>('name')),
        contains('style_selection'),
      );
      expect(root.resolution, '720p');
      expect(
        columns.map((r) => r.read<String>('name')),
        containsAll(['reference_mode', 'error_dismissed', 'item_id']),
      );
      expect(
        columns.map((r) => r.read<String>('name')),
        isNot(
          anyOf(
            contains('generation_mode'),
            contains('fps'),
            contains('status'),
            contains('width'),
            contains('height'),
          ),
        ),
      );
      final screenplayColumns = await db
          .customSelect('PRAGMA table_info(screenplays)')
          .get();
      expect(
        screenplayColumns.map((r) => r.read<String>('name')),
        isNot(contains('production_settings_prompted')),
      );
      expect(
        screenplayColumns
            .singleWhere((r) => r.read<String>('name') == 'style_id')
            .read<String>('type'),
        'TEXT',
      );
      expect(
        (await db.customSelect('PRAGMA table_info(screenplay_episodes)').get())
            .map((r) => r.read<String>('name')),
        isNot(contains('style_id')),
      );
      await (db.update(
        db.screenplays,
      )..where((t) => t.id.equals(root.id))).write(
        const ScreenplaysCompanion(
          styleId: Value('preset:eastern-ink-decorative'),
        ),
      );
      expect((await db.screenplayDao.getEpisode('episode'))!.canvasId, isNull);
      expect(
        await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE name='episode_productions'",
            )
            .get(),
        isEmpty,
      );
      final indexes = await db
          .customSelect('PRAGMA index_list(production_clips)')
          .get();
      expect(
        indexes.map((r) => r.read<String>('name')),
        contains('production_clips_by_scene_id_deleted_at_sort_order'),
      );
      await db
          .into(db.productionClips)
          .insert(
            ProductionClipsCompanion.insert(
              id: 'shot',
              episodeId: 'episode',
              kind: 'video',
              sceneId: const Value('scene'),
              sortOrder: const Value(0),
              errorDismissed: const Value(true),
              prompt: const Value('夜雨'),
            ),
          );
      await db
          .into(db.productionClips)
          .insert(
            ProductionClipsCompanion.insert(
              id: 'compendium',
              episodeId: 'episode',
              kind: 'image',
              itemId: const Value('entry'),
            ),
          );
      await db.close();
      db = NovelContentDatabase.forTest(NativeDatabase(file));
      final clips = await db.select(db.productionClips).get();
      final shot = clips.singleWhere((row) => row.id == 'shot');
      expect(
        clips.singleWhere((row) => row.id == 'compendium').itemId,
        'entry',
      );
      expect(
        (await db.screenplayDao.getRoot())!.styleId,
        'preset:eastern-ink-decorative',
      );
      expect(shot.itemId, isNull);
      expect(shot.prompt, '夜雨');
      expect(shot.styleSelection, isNull);
      expect(shot.errorDismissed, isTrue);
      expect(shot.deletedAt, notDeletedSentinel);
      expect((await db.screenplayDao.getScene('scene'))!.synopsis, 'Keep');
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
