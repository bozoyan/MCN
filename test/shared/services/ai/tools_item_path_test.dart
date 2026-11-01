// 职责: 验证四类图谱资料的 ID 寻址、搜索、预览及改名后的审阅与回退。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_support.dart
//   lib/shared/services/working_overlay.dart

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  late NovelContentDatabase db;
  late AppDatabase appDb;
  late NovelContentService content;
  late WorkingOverlayService overlay;
  late AiToolManager tools;
  late List<Map<String, dynamic>> previews;

  setUp(() {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    appDb = AppDatabase.forTest(NativeDatabase.memory());
    content = NovelContentService(db);
    overlay = WorkingOverlayService(
      db,
      content,
      novelActionsService: NovelActionsService(appDb),
    );
    previews = [];
    tools = AiToolManager(
      content,
      workingOverlayService: overlay,
      onToolStarted: (_, _, _, extra, _) {
        if (extra != null) {
          previews.add(extra);
        }
      },
    )..registerAllTools();
  });

  tearDown(() async {
    await db.close();
    await appDb.close();
  });

  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> input) {
    return tools.executeTool(name: name, input: input);
  }

  test(
    'character skill references keep readable paths after renaming',
    () async {
      final characterId = await content.createCharacterProfile(
        defaultName: '角色',
      );
      final created = await call('Create', {
        'path': 'skills',
        'fields': {'title': '旧技能', 'content': '技能正文'},
      });
      final id = created['id'] as String;
      await content.entityRelationsService.createRelation(
        sourceType: 'character',
        sourceId: characterId,
        targetType: 'skill',
        targetId: id,
        relationType: characterSkillMastered,
      );
      await call('Write', {'path': 'skills/$id/title', 'value': '新技能'});
      final character = await call('Read', {'path': 'characters/$characterId'});
      final reference = (character['skills'] as List).single as Map;
      expect(reference['path'], 'skills/$id');
      expect(reference['name'], '新技能');
      expect(
        (await call('Read', {'path': reference['path']}))['content'],
        '技能正文',
      );
      final graph = await call('GraphSearch', {'type': 'skill', 'id': id});
      expect(graph['total_relations'], 1);
    },
  );

  for (final entry in const {
    'skills': 'skill',
    'items': 'item',
    'factions': 'faction',
    'creatures': 'creature',
  }.entries) {
    final collection = entry.key;
    final type = entry.value;

    group(collection, () {
      test(
        'Create, query, rename, field reads and Remove share an ID path',
        () async {
          expect(pathSchemaFieldNotes(), contains('$collection/{${type}_id}'));
          final contract = await call('Read', {'path': '/_schema/$collection'});
          expect(contract['resource_path'], '$collection/{${type}_id}');
          final created = await call('Create', {
            'path': collection,
            'fields': {'title': '旧标题', 'content': '原始正文'},
          });
          final id = created['id'] as String;
          final path = '$collection/$id';
          expect(created['path'], path);
          expect(
            (await db.workingChangeDao.getAll()).single.resourcePath,
            path,
          );
          final listing = await call('Read', {'path': '$collection?search=旧标'});
          expect(
            (listing['entries'] as List).single,
            containsPair('path', path),
          );
          expect((listing['entries'] as List).single, containsPair('id', id));

          final renamed = await call('Write', {
            'path': path,
            'fields': {'title': '新标题', 'content': '新正文', 'category': '分类'},
          });
          expect(renamed['updated'], isTrue, reason: '$renamed');
          expect(
            (await call('Read', {'path': '$path/content'}))['value'],
            '新正文',
          );
          expect(
            (await call('Read', {'path': '$path/category'}))['value'],
            '分类',
          );
          final edited = await call('Edit', {
            'path': '$path/title',
            'old_text': '新',
            'new_text': '最终',
          });
          expect(edited['edited'], isTrue, reason: '$edited');
          expect((await call('Read', {'path': path}))['title'], '最终标题');
          expect(
            (await call('Read', {'path': '$collection?search=旧标题'}))['entries'],
            isEmpty,
          );
          expect(
            (await call('Read', {'path': '$collection/最终标题'}))['error_code'],
            'not_found',
          );
          final removed = await call('Remove', {'path': path});
          expect(removed['removed'], isTrue);
          expect(await content.getItemById(id), isNull);
          expect(
            (await call('Read', {'path': path}))['error_code'],
            'not_found',
          );
        },
      );

      test(
        'old titles, foreign types, deleted IDs and deep paths cannot mutate targets',
        () async {
          final id = await content.createItem(
            type: type,
            title: '同名',
            content: '原文',
          );
          final foreignId = await content.createItem(
            type: type == 'skill' ? 'item' : 'skill',
            title: '同名',
            content: '原文',
          );
          final deletedId = await content.createItem(
            type: type,
            title: '已删除',
            content: '原文',
          );
          await db.itemDao.softDelete(deletedId);
          for (final token in ['同名', foreignId, deletedId, 'missing']) {
            final path = '$collection/$token';
            for (final operation in ['Read', 'Write', 'Edit', 'Remove']) {
              final result = await call(operation, {
                'path': operation == 'Edit' ? '$path/content' : path,
                if (operation == 'Write') 'fields': {'content': '篡改'},
                if (operation == 'Edit') ...{
                  'old_text': '原文',
                  'new_text': '篡改',
                },
              });
              expect(
                result['error'],
                isNotNull,
                reason: '$operation $path: $result',
              );
            }
          }
          for (final operation in ['Read', 'Write', 'Edit', 'Remove']) {
            final result = await call(operation, {
              'path': '$collection/$id/content/extra',
              if (operation == 'Write') 'value': '篡改',
              if (operation == 'Edit') ...{'old_text': '原文', 'new_text': '篡改'},
              if (operation == 'Remove') 'force': true,
            });
            expect(
              result['error_code'],
              'invalid_argument',
              reason: '$operation: $result',
            );
          }
          await call('Remove', {
            'path': '$collection/$foreignId',
            'force': true,
          });
          expect((await content.getItemById(id))!.content, '原文');
          expect((await content.getItemById(foreignId))!.content, '原文');
          final tombstone = await (db.select(
            db.items,
          )..where((row) => row.id.equals(deletedId))).getSingle();
          expect(tombstone.content, '原文');
          expect(tombstone.deletedAt, isNot(notDeletedSentinel));
          expect(await db.workingChangeDao.getAll(), isEmpty);
        },
      );

      test(
        'normalized values and rejected batches preserve the correct entry',
        () async {
          final created = await call('Create', {
            'path': collection,
            'fields': '{"title":"  名称  ","content":"  原文  ","category":"旧分类"}',
          });
          final id = created['id'] as String;
          expect((await content.getItemById(id))!.title, '名称');
          expect((await content.getItemById(id))!.content, '原文');
          final updated = await call('Write', {
            'path': '$collection/$id',
            'fields': {'category': null},
          });
          expect(updated['updated'], isTrue);
          expect((await content.getItemById(id))!.category, '');
          expect((await content.getItemById(id))!.content, '原文');
          final before = await db.workingChangeDao.getAll();
          final rejected = await call('Write', {
            'path': '$collection/$id/content',
            'value': '一份输入',
            'fields': {'content': '冲突输入'},
          });
          expect(rejected['ok'], isFalse);
          expect((await content.getItemById(id))!.content, '原文');
          expect(
            (await db.workingChangeDao.getAll()).map((change) => change.id),
            before.map((change) => change.id),
          );
        },
      );

      test(
        'Glob and Grep return readable ID paths and Replace edits them',
        () async {
          final id = await content.createItem(
            type: type,
            title: '资料',
            content: '一条线索',
          );
          final path = '$collection/$id/content';
          final glob = await call('Glob', {'pattern': '$collection/*/content'});
          expect(glob['matches'], [path]);
          expect((await call('Read', {'path': path}))['value'], '一条线索');
          final grep = await call('Grep', {
            'path': collection,
            'pattern': '线索',
            'output_mode': 'files_with_matches',
          });
          expect(grep['text'], contains(path));
          final replaced = await call('Replace', {
            'path': collection,
            'pattern': '线索',
            'replacement': '证据',
            'dry_run': false,
          });
          expect(replaced['applied_fields'], 1, reason: '$replaced');
          expect((await content.getItemById(id))!.content, '一条证据');
          final change = (await db.workingChangeDao.getAll()).single;
          expect(change.resourcePath, path);
          await overlay.rollbackChange(change.id);
          expect((await content.getItemById(id))!.content, '一条线索');
        },
      );

      test(
        'mixed historical and short IDs survive search, preview and undo',
        () async {
          const oldId = 'item_aBcD0123456789XY';
          await db
              .into(db.items)
              .insert(
                ItemsCompanion.insert(
                  id: oldId,
                  type: type,
                  title: '历史资料',
                  content: const Value('历史线索'),
                ),
              );
          final newId = await content.createItem(
            type: type,
            title: '新增资料',
            content: '新增线索',
          );
          expect(newId, matches(r'^[a-z]{3}_[A-Z0-9]{6}$'));
          final glob = await call('Glob', {'pattern': '$collection/*/content'});
          expect(
            glob['matches'],
            unorderedEquals([
              '$collection/$oldId/content',
              '$collection/$newId/content',
            ]),
          );
          final grep = await call('Grep', {
            'path': collection,
            'pattern': '线索',
            'output_mode': 'files_with_matches',
          });
          for (final id in [oldId, newId]) {
            final path = '$collection/$id/content';
            final original = id == oldId ? '历史线索' : '新增线索';
            expect(grep['text'], contains(path));
            expect((await call('Read', {'path': path}))['value'], original);
            final write = await call('Write', {'path': path, 'value': '修订线索'});
            expect(write['updated'], isTrue, reason: '$write');
            expect(previews.last, containsPair('targetPath', path));
            expect(previews.last, containsPair('diffOldText', original));
            final change = (await db.workingChangeDao.getByResource(
              path,
            )).single;
            expect(change.resourcePath, path);
            await overlay.rollbackChange(change.id);
            expect((await content.getItemById(id))!.content, original);
          }
        },
      );

      test(
        'Write and Edit coalesce through rename, preview, accept and commit rollback',
        () async {
          final id = await content.createItem(
            type: type,
            title: '旧标题',
            content: '原文',
          );
          final path = '$collection/$id';
          await call('Write', {'path': '$path/content', 'value': '初稿'});
          expect(previews.last, containsPair('targetPath', '$path/content'));
          expect(previews.last, containsPair('diffOldText', '原文'));
          await call('Write', {'path': '$path/title', 'value': '新标题'});
          await call('Edit', {
            'path': '$path/content',
            'old_text': '初稿',
            'new_text': '终稿',
          });
          expect(previews.last, containsPair('targetPath', '$path/content'));
          expect(previews.last, containsPair('diffOldText', '初稿'));
          expect(previews.last, containsPair('diffNewText', '终稿'));
          final changes = await db.workingChangeDao.getAll();
          expect(changes, hasLength(2));
          final change = changes.singleWhere((c) => c.field == 'content');
          expect(change.resourcePath, '$path/content');
          expect(change.oldText, '原文');
          expect(change.newText, '终稿');
          expect(
            await db.workingChangeDao.getByResource('$path/content'),
            hasLength(1),
          );
          final commitId = await overlay.commitWorkingChanges(
            changes.map((c) => c.id).toList(),
            source: workingChangeSourceAi,
            message: 'accept',
          );
          final items = await db.changeCommitDao.getItemsByCommit(commitId!);
          expect(
            items.map((i) => i.resourcePath),
            unorderedEquals(['$path/title', '$path/content']),
          );
          await overlay.rollbackCommit(commitId: commitId);
          final restored = (await content.getItemById(id))!;
          expect(restored.title, '旧标题');
          expect(restored.content, '原文');
        },
      );

      test('category participates in committed field rollback', () async {
        final id = await content.createItem(
          type: type,
          title: '资料',
          content: '正文',
          category: '旧分类',
        );
        final written = await call('Write', {
          'path': '$collection/$id/category',
          'value': '新分类',
        });
        expect(written['updated'], isTrue);
        final change = (await db.workingChangeDao.getAll()).single;
        final commitId = await overlay.commitWorkingChanges(
          [change.id],
          source: workingChangeSourceAi,
          message: 'accept category',
        );
        expect(
          await overlay.rollbackCommit(commitId: commitId!),
          RestoreResourceResult.restored,
        );
        final restored = (await content.getItemById(id))!;
        expect(restored.category, '旧分类');
        expect(restored.content, '正文');
      });

      test('new creation can be accepted and rolled back by ID', () async {
        final created = await call('Create', {
          'path': collection,
          'fields': {'title': '新建资料', 'content': '正文'},
        });
        final id = created['id'] as String;
        final change = (await db.workingChangeDao.getAll()).single;
        final commitId = await overlay.commitWorkingChanges(
          [change.id],
          source: workingChangeSourceAi,
          message: 'accept',
        );
        expect(
          (await db.changeCommitDao.getItemsByCommit(
            commitId!,
          )).single.resourcePath,
          '$collection/$id',
        );
        await overlay.rollbackCommit(commitId: commitId);
        expect(await content.getItemById(id), isNull);
      });

      test(
        'legacy title history stays separate and retains ID-based rollback',
        () async {
          final id = await content.createItem(
            type: type,
            title: '旧标题',
            content: '原文',
          );
          final oldPath = '$collection/旧标题/content';
          final newPath = '$collection/$id/content';
          await overlay.stageTextChange(
            resourcePath: oldPath,
            resourceType: collection,
            resourceId: id,
            field: 'content',
            oldText: '原文',
            newText: '历史修改',
            source: workingChangeSourceAi,
            toolName: 'Write',
          );
          final legacy = (await db.workingChangeDao.getByResource(
            oldPath,
          )).single;
          await call('Write', {'path': newPath, 'value': '当前修改'});
          expect(
            await db.workingChangeDao.getByResource(oldPath),
            hasLength(1),
          );
          expect(
            await db.workingChangeDao.getByResource(newPath),
            hasLength(1),
          );
          expect(
            (await db.workingChangeDao.getById(legacy.id))!.resourcePath,
            oldPath,
          );
          final current = (await db.workingChangeDao.getByResource(
            newPath,
          )).single;
          await overlay.rollbackChange(current.id);
          expect((await content.getItemById(id))!.content, '历史修改');
          await overlay.rollbackChange(legacy.id);
          expect((await content.getItemById(id))!.content, '原文');
        },
      );
    });
  }
}
