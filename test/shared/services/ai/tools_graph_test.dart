// 职责: 测试 AI 关系图工具的关系类型校验与落库保护。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_graph.dart
//   lib/shared/services/entity_relations_service.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  group('Create /relations', () {
    late NovelContentDatabase db;
    late AppDatabase appDb;
    late NovelContentService contentService;
    late AiToolManager toolManager;

    setUp(() {
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      appDb = AppDatabase.forTest(NativeDatabase.memory());
      contentService = NovelContentService(db);
      final overlay = WorkingOverlayService(
        db,
        contentService,
        novelActionsService: NovelActionsService(appDb),
      );
      toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay,
      )..registerAllTools();
    });

    tearDown(() async {
      await db.close();
      await appDb.close();
    });

    test(
      'relation identity and exact field reads preserve stored evidence',
      () async {
        final created = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'relations',
            'fields': {
              'source_type': 'character',
              'source_id': 'character_a',
              'target_type': 'character',
              'target_id': 'character_b',
              'relation_type': 'friend',
              'proof': '  并肩战斗  ',
            },
          },
        );
        final id = created['id'] as String;
        final path = created['path'] as String;
        final detail = await toolManager.executeTool(
          name: 'Read',
          input: {'path': path},
        );
        expect(detail['id'], id);
        expect(detail['proof'], '并肩战斗');
        final fieldRead = await toolManager.executeTool(
          name: 'Read',
          input: {'path': '$path/proof'},
        );
        expect(fieldRead['value'], '并肩战斗');
        for (final operation in ['Write', 'Edit']) {
          final rejected = await toolManager.executeTool(
            name: operation,
            input: {
              'path': '$path/proof',
              if (operation == 'Write') 'value': '不应修改',
              if (operation == 'Edit') ...{
                'old_text': '不存在的原文',
                'new_text': '不应修改',
              },
            },
          );
          expect(rejected['ok'], isFalse);
        }
        final relation = await contentService.entityRelationsService
            .getRelationById(id);
        expect(relation!.proof, '并肩战斗');
        expect(await db.workingChangeDao.getAll(), isEmpty);
      },
    );

    test(
      'rejects unsupported source and target pairs without writing',
      () async {
        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'relations',
            'fields': {
              'source_type': 'character',
              'source_id': 'character_1',
              'target_type': 'location',
              'target_id': 'location_1',
              'relation_type': 'friend',
              'chapter_id': 'chapter_1',
              'proof': '角色在该地点出现。',
            },
          },
        );

        expect(result['ok'], isFalse);
        expect(result['error_code'], 'invalid_argument');
        expect(
          result['error'],
          'No supported relation types for character → location',
        );

        final relations = await contentService.entityRelationsService
            .getAllRelations();
        expect(relations, isEmpty);
      },
    );
    test(
      'accepts alter_ego character relations and normalized Chinese aliases',
      () async {
        await db
            .into(db.chapters)
            .insert(
              ChaptersCompanion.insert(
                id: 'chapter_1',
                type: 'chapter',
                siblingOrder: 1,
              ),
            );
        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'relations',
            'fields': {
              'source_type': 'character',
              'source_id': 'character_klein',
              'target_type': 'character',
              'target_id': 'character_fool',
              'relation_type': '马甲',
              'chapter_id': 'chapter_1',
              'proof': '克莱恩以愚者身份行动。',
            },
          },
        );

        expect(result['created'], isTrue);
        expect(result['relation_type'], characterRelationAlterEgo);

        final relations = await contentService.entityRelationsService
            .getAllRelations();
        expect(relations, hasLength(1));
        expect(relations.single.sourceId, 'character_klein');
        expect(relations.single.targetId, 'character_fool');
        expect(relations.single.relationType, characterRelationAlterEgo);
      },
    );

    test('CreateRelation tool is retired in favour of Create /relations', () {
      expect(toolManager.allToolNames(), isNot(contains('CreateRelation')));
      expect(
        toolManager.allToolDefs().map((def) => def.name),
        isNot(contains('CreateRelation')),
      );

      final result = toolManager.allToolNames();
      expect(result, contains('Create'));
      expect(result, contains('GraphSearch'));
    });

    test('Create failure on relations carries the field contract', () async {
      final result = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'relations',
          'fields': {'proof': '证据'},
        },
        callId: 'call_relations_missing_fields',
      );

      // 字段契约只在失败时按路径返回，不再常驻 _links.create。
      expect(result['ok'], isFalse);
      final contract = result['input_contract'] as Map<String, dynamic>;
      expect(contract['input'], {
        'path': 'relations',
        'fields': <String, dynamic>{},
      });
      expect(
        contract['required_fields'],
        containsAll(['source_type', 'source_id', 'relation_type', 'proof']),
      );
    });

    test('hidden relations keep a discoverable query contract', () async {
      // hidden 集合不进常驻路径索引，query 契约必须能经 /_schema 查到。
      final contract = await toolManager.executeTool(
        name: 'Read',
        input: {'path': '/_schema/relations'},
        callId: 'call_relations_schema',
      );
      expect(contract['query'], contains('source_type'));
    });

    test(
      'invalid relation_type error lists the legal values for that pair',
      () async {
        // 这是删掉内联对照表之后的兜底路径：模型猜错一次就能拿到该组合的全部合法值。
        // 它失效就等于关系类型信息在运行时彻底不可发现。
        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'relations',
            'fields': {
              'source_type': 'character',
              'source_id': 'character_1',
              'target_type': 'skill',
              'target_id': 'skill_1',
              'relation_type': 'friend',
              'chapter_id': 'chapter_1',
              'proof': '证据',
            },
          },
          callId: 'call_relations_bad_relation_type',
        );

        expect(result['ok'], isFalse);
        expect(result['error_code'], 'invalid_argument');
        final error = result['error'] as String;
        for (final type in characterSkillRelationTypes) {
          expect(
            error,
            contains(type),
            reason: 'character → skill 的 $type 必须出现在错误信息里',
          );
        }
        // 不该把别的实体对的类型也倒出来。
        expect(error, isNot(contains('master_disciple')));
      },
    );

    test(
      'Create relations reports the offending field on enum errors',
      () async {
        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'relations',
            'fields': {
              'source_type': '不存在的类型',
              'source_id': 'character_1',
              'target_type': 'character',
              'target_id': 'character_2',
              'relation_type': 'friend',
              'chapter_id': 'chapter_1',
              'proof': '证据',
            },
          },
          callId: 'call_relations_bad_type',
        );

        expect(result['ok'], isFalse);
        expect(result['error_code'], 'invalid_argument');
        // 并入 Create 后要和其他集合一样给出 field_constraint，模型才知道改哪个字段。
        expect((result['field_constraint'] as Map)['field'], 'source_type');
        expect((result['field_constraint'] as Map)['enum'], entityTypes);
        expect(
          (result['validation_errors'] as List).cast<Map>().single['code'],
          'invalid_enum',
        );
      },
    );

    test(
      'pathSchema field notes hide relations and skip entity type enums',
      () {
        final notes = pathSchemaFieldNotes();

        expect(notes, isNot(contains('- /relations')));
        expect(notes, isNot(contains('- source_type*')));
        expect(
          notes,
          isNot(contains('foreshadowing | creature')),
          reason: '实体类型枚举不应出现在字段字典',
        );
      },
    );
  });

  group('GraphSearch', () {
    late NovelContentDatabase db;
    late AppDatabase appDb;
    late AiToolManager toolManager;

    setUp(() {
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      appDb = AppDatabase.forTest(NativeDatabase.memory());
      final contentService = NovelContentService(db);
      toolManager = AiToolManager(
        contentService,
        workingOverlayService: WorkingOverlayService(
          db,
          contentService,
          novelActionsService: NovelActionsService(appDb),
        ),
      )..registerAllTools();
    });

    tearDown(() async {
      await db.close();
      await appDb.close();
    });

    test('canonical type/id still search from the starting entity', () async {
      final result = await toolManager.executeTool(
        name: 'GraphSearch',
        input: {'type': 'character', 'id': 'char_a'},
        callId: 'call_graph_canonical',
      );

      expect(result['start_entity_type'], 'character');
      expect(result['start_entity_id'], 'char_a');
    });

    test(
      'accepts entity_type/entity_id aliases like SpawnAgent agent_name',
      () async {
        final result = await toolManager.executeTool(
          name: 'GraphSearch',
          input: {'entity_type': 'character', 'entity_id': 'char_a'},
          callId: 'call_graph_alias',
        );

        expect(result['start_entity_type'], 'character');
        expect(result['start_entity_id'], 'char_a');
      },
    );

    test('canonical type/id win when aliases are also present', () async {
      final result = await toolManager.executeTool(
        name: 'GraphSearch',
        input: {
          'type': 'faction',
          'id': 'faction_1',
          'entity_type': 'character',
          'entity_id': 'char_a',
        },
        callId: 'call_graph_canonical_wins',
      );

      expect(result['start_entity_type'], 'faction');
      expect(result['start_entity_id'], 'faction_1');
    });

    test('invalid relation_type returns hint with legal values', () async {
      final result = await toolManager.executeTool(
        name: 'GraphSearch',
        input: {
          'type': 'character',
          'id': 'char_a',
          'relation_type': 'totally_made_up',
        },
        callId: 'call_graph_bad_relation_type',
      );

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'invalid_argument');
      expect(result['enum_field'], 'relation_type');
      final hint = result['hint'] as String;
      expect(hint, contains('省略 relation_type'));
      expect(hint, contains('禁止猜测'));
      expect(hint, contains('friend'));
      expect(hint, contains('master_disciple'));
      expect(hint, contains('learned'));
    });

    test('known relation_type still searches', () async {
      final result = await toolManager.executeTool(
        name: 'GraphSearch',
        input: {'type': 'character', 'id': 'char_a', 'relation_type': 'friend'},
        callId: 'call_graph_ok_relation_type',
      );

      expect(result['ok'], isNot(false));
      expect(result['error_code'], isNull);
      expect(result['start_entity_type'], 'character');
      expect(result['start_entity_id'], 'char_a');
    });
  });
}
