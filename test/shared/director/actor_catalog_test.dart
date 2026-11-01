// 职责: 验证角色目录合并、失败重试、销毁保护及剧本场次人物适配。
// 关联文件:
//   lib/shared/services/director/actor_catalog.dart
//   lib/shared/services/screenplay/actor_catalog.dart
import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/director/actor_catalog.dart';
import 'package:reveric/shared/services/director/actor_catalog.dart';
import 'package:reveric/shared/services/screenplay/actor_catalog.dart';

void main() {
  const first = DirectorActor(id: 'first', name: 'First');
  test(
    'initial candidates survive loading and empty results; same IDs update in place',
    () async {
      final request = Completer<List<DirectorActor>>();
      final catalog = DirectorActorCatalogController(
        DirectorActorCatalog(
          initialActors: [first],
          load: () => request.future,
        ),
      );
      addTearDown(catalog.dispose);
      final loading = catalog.load();
      expect(catalog.actors, [first]);
      request.complete([
        const DirectorActor(id: 'second', name: 'Second'),
        const DirectorActor(
          id: 'first',
          name: 'Renamed',
          body: DirectorActorBody.female,
        ),
      ]);
      await loading;
      expect(catalog.actors.map((a) => a.id), ['first', 'second']);
      expect(catalog.actors.first.name, 'Renamed');
      expect(catalog.actors.first.body, DirectorActorBody.female);
      final empty = DirectorActorCatalogController(
        DirectorActorCatalog(initialActors: [first], load: () async => []),
      );
      addTearDown(empty.dispose);
      await empty.load();
      expect(empty.actors, [first]);
    },
  );
  test(
    'failure preserves candidates and retry replaces failure with loaded data',
    () async {
      var attempts = 0;
      final catalog = DirectorActorCatalogController(
        DirectorActorCatalog(
          initialActors: [first],
          load: () async {
            if (attempts++ == 0) {
              throw StateError('loader unavailable');
            }
            return [const DirectorActor(id: 'next', name: 'Next')];
          },
        ),
      );
      addTearDown(catalog.dispose);
      await catalog.load();
      expect(catalog.failed, isTrue);
      expect(catalog.actors, [first]);
      await catalog.load();
      expect(catalog.failed, isFalse);
      expect(catalog.actors.map((a) => a.id), ['first', 'next']);
    },
  );
  test('late result after disposal cannot update the old catalog', () async {
    final request = Completer<List<DirectorActor>>();
    final catalog = DirectorActorCatalogController(
      DirectorActorCatalog(load: () => request.future),
    );
    final load = catalog.load();
    catalog.dispose();
    request.complete([first]);
    await load;
    expect(catalog.actors, isEmpty);
  });
  test(
    'staging starts with no actors; library loads every active character',
    () async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      addTearDown(db.close);
      for (final (id, name, gender) in [
        ('other', 'Other actor', 'male'),
        ('known', '林音', 'female'),
        ('unknown', '未定人物', 'unknown'),
        ('removed', 'Removed', 'male'),
      ]) {
        await db
            .into(db.characterProfiles)
            .insert(
              CharacterProfilesCompanion.insert(
                id: id,
                name: name,
                gender: Value(gender),
                deletedAt: id == 'removed'
                    ? Value(DateTime.now())
                    : const Value.absent(),
              ),
            );
      }
      final source = loadScreenplayActorCatalog(db);
      expect(source.initialActors, isEmpty);
      final catalog = DirectorActorCatalogController(source);
      addTearDown(catalog.dispose);
      await catalog.load();
      final bodies = {for (final a in catalog.actors) a.id: a.body};
      expect(bodies, {
        'other': DirectorActorBody.male,
        'known': DirectorActorBody.female,
        'unknown': DirectorActorBody.male,
      });
      expect(
        (await db.characterProfileDao.getById('unknown'))!.gender,
        'unknown',
      );
    },
  );
}
