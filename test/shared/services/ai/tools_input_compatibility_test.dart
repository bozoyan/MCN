// 职责: 测试 AI 工具入参兼容性，覆盖模型传入字符串简写或数字字符串的情况
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_todo.dart
//   lib/shared/services/ai/tools_read.dart
//   lib/shared/agent/agent_tool_dispatcher.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import '../../../helpers/working_change_test_helper.dart';

void main() {
  group('AI tool input compatibility', () {
    late NovelContentDatabase db;
    late AppDatabase appDb;
    late NovelContentService contentService;
    late WorkingOverlayService overlay;
    late AiToolManager toolManager;

    setUp(() {
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      appDb = AppDatabase.forTest(NativeDatabase.memory());
      contentService = NovelContentService(db);

      overlay = WorkingOverlayService(
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

    test('Write accepts flattened and mixed document fields', () async {
      for (final fields in <Map<String, dynamic>>[
        {'category': '人类', 'content': '第一版'},
        {
          'category': '世界规则',
          'fields': {'content': '第二版'},
        },
        {
          'category': ' 世界规则 ',
          'fields': {'category': '世界规则', 'content': '第三版'},
        },
      ]) {
        final written = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'lore/测试设定', ...fields},
        );
        expect(written['ok'], isTrue, reason: '$written');
        final read = await toolManager.executeTool(
          name: 'Read',
          input: {'path': 'lore/测试设定'},
        );
        expect(read['category'], (fields['category'] as String).trim());
        expect(
          read['content'],
          fields['content'] ?? (fields['fields'] as Map)['content'],
        );
      }
    });

    test(
      'Write rejects conflicting flattened fields without changing data',
      () async {
        await contentService.documentsService.createDocument(
          type: 'lore',
          title: '冲突测试',
          content: '原文',
          category: '原分类',
        );
        for (final reverse in [false, true]) {
          final written = await toolManager.executeTool(
            name: 'Write',
            input: {
              'path': 'lore/冲突测试',
              'category': reverse ? '人类' : '世界规则',
              'fields': {
                'category': reverse ? '世界规则' : '人类',
                'content': '不应写入',
              },
            },
          );
          expect(written['error_code'], 'invalid_argument');
          expect(
            written['validation_errors'],
            contains(containsPair('code', 'conflicting_fields')),
          );
          final read = await toolManager.executeTool(
            name: 'Read',
            input: {'path': 'lore/冲突测试'},
          );
          expect(read['category'], '原分类');
          expect(read['content'], '原文');
          expect(await db.select(db.workingChanges).get(), isEmpty);
        }
      },
    );

    test(
      'Write normalizes flattened field and value sources together',
      () async {
        final chapter = await contentService.createChapter(
          siblingOrder: 1,
          title: '原题',
        );
        final written = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'chapters/$chapter/tension',
            'tension': '7.8',
            'value': 8,
            'fields': {'tension': 8},
          },
        );
        expect(written['ok'], isTrue, reason: '$written');
        final read = await toolManager.executeTool(
          name: 'Read',
          input: {'path': 'chapters/$chapter/tension'},
        );
        expect(read['value'], 8);
        final rejected = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'chapters/$chapter/tension',
            'value': 8,
            'tension': 5,
          },
        );
        expect(rejected['error_code'], 'invalid_argument');
        expect(
          rejected['validation_errors'],
          contains(containsPair('code', 'conflicting_fields')),
        );
      },
    );

    test(
      'Write reports unknown flattened fields and does not create an empty document',
      () async {
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'lore/不应创建', 'unknown_field': 'ignored'},
        );
        expect(result['updated'], isFalse, reason: '$result');
        expect(result['ignored_fields'], contains('unknown_field'));
        expect(await db.select(db.documents).get(), isEmpty);
      },
    );

    test(
      'all duplicate scalar sources report identical complete issues in either order',
      () async {
        final chapter = await contentService.createChapter(
          siblingOrder: 1,
          title: 'original',
        );
        final character = await contentService.createCharacterProfile(
          name: 'original',
        );
        Future<List<Object?>> snapshot() async => [
          (await db.select(db.chapters).get())
              .map((row) => row.toJson())
              .toList(),
          (await db.select(db.characterProfiles).get())
              .map((row) => row.toJson())
              .toList(),
          (await db.select(db.workingChanges).get())
              .map((row) => row.toJson())
              .toList(),
        ];
        final before = await snapshot();
        for (final scenario
            in <(String, String, String, Object?, Object?, String)>[
              ('chapters', chapter, 'tension', 8, 'bad', 'invalid_integer'),
              ('chapters', chapter, 'tension', 8, 99, 'invalid_integer'),
              (
                'characters',
                character,
                'role',
                'protagonist',
                'bad',
                'invalid_enum',
              ),
              ('chapters', chapter, 'title', 'valid', null, 'required'),
              (
                'chapters',
                chapter,
                'title',
                'valid',
                <String, dynamic>{},
                'invalid_type',
              ),
            ]) {
          for (final create in [false, true]) {
            List<Object?>? firstIssues;
            for (final reverse in [false, true]) {
              final first = reverse ? scenario.$5 : scenario.$4;
              final second = reverse ? scenario.$4 : scenario.$5;
              final result = await toolManager.executeTool(
                name: create ? 'Create' : 'Write',
                input: create
                    ? {
                        'path': scenario.$1,
                        'fields': {
                          if (scenario.$1 == 'chapters')
                            'title': 'unused'
                          else
                            'name': 'unused',
                          scenario.$3: first,
                        },
                        scenario.$3: second,
                      }
                    : {
                        'path': '${scenario.$1}/${scenario.$2}/${scenario.$3}',
                        'fields': {scenario.$3: first},
                        'value': second,
                      },
              );
              expect(
                result['error_code'],
                'invalid_argument',
                reason: '$scenario/$create/$reverse: $result',
              );
              final issues = (result['validation_errors'] as List).cast<Map>();
              expect(
                issues.map((issue) => issue['code']),
                unorderedEquals([
                  'conflicting_fields',
                  if (create || scenario.$5 != null) scenario.$6,
                ]),
              );
              if (firstIssues == null) {
                firstIssues = issues;
              } else {
                expect(issues, firstIssues);
              }
              expect(await snapshot(), before);
            }
          }
        }
        for (final value in <Object?>['bad']) {
          final result = await toolManager.executeTool(
            name: 'Write',
            input: {
              'path': 'chapters/$chapter/tension',
              'value': value,
              'fields': {'tension': value, 'value': value},
            },
          );
          expect(result['validation_errors'], hasLength(1));
          expect(
            (result['validation_errors'] as List).single['code'],
            'invalid_integer',
          );
        }
        expect(await snapshot(), before);
      },
    );

    test(
      'integer rounding and normalized sources agree across Create and Write',
      () async {
        for (final raw in <Object>[7.2, 7.8, '7.8']) {
          final expected = raw == 7.2 ? 7 : 8;
          final created = await toolManager.executeTool(
            name: 'Create',
            input: {
              'path': 'chapters',
              'tension': expected,
              'fields': {'title': ' $raw ', 'tension': raw},
            },
          );
          expect(created['ok'], true, reason: '$created');
          final path = created['path'] as String;
          for (final payload in <Map<String, dynamic>>[
            {
              'path': '$path/tension',
              'value': raw,
              'fields': {'tension': expected},
            },
            {
              'path': path,
              'fields': {'tension': raw},
            },
          ]) {
            expect(
              (await toolManager.executeTool(
                name: 'Write',
                input: payload,
              ))['ok'],
              true,
            );
            expect(
              (await toolManager.executeTool(
                name: 'Read',
                input: {'path': '$path/tension'},
              ))['value'],
              expected,
            );
          }
        }
        for (final raw in <Object>['NaN', 'Infinity', '-Infinity', 99.8]) {
          final before = (await db.select(db.workingChanges).get())
              .map((row) => row.toJson())
              .toList();
          final result = await toolManager.executeTool(
            name: 'Create',
            input: {
              'path': 'chapters',
              'fields': {'title': 'must not exist', 'tension': raw},
            },
          );
          expect(result['error_code'], 'invalid_argument', reason: '$result');
          expect(
            (await db.select(db.workingChanges).get())
                .map((row) => row.toJson())
                .toList(),
            before,
          );
        }
      },
    );

    test(
      'JSON arrays normalize recursively, deduplicate structurally and clear on null',
      () async {
        final created = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'chapters',
            'fields': {
              'title': 'Arrays',
              'emotion': '[" tense ", "tense", 7, "7"]',
              'events':
                  "[{'title':' Turn ', 'summary':' Summary '}, {'summary':'Summary','title':'Turn'}]",
            },
          },
        );
        expect(created['ok'], true, reason: '$created');
        final path = created['path'] as String;
        expect(
          (await toolManager.executeTool(
            name: 'Read',
            input: {'path': '$path/emotion'},
          ))['value'],
          ['tense', '7'],
        );
        expect(
          (await toolManager.executeTool(
            name: 'Read',
            input: {'path': '$path/events'},
          ))['value'],
          [
            {'title': 'Turn', 'summary': 'Summary'},
          ],
        );
        for (final payload in <Map<String, dynamic>>[
          {
            'path': '$path/emotion',
            'value': null,
            'fields': {'emotion': []},
          },
          {
            'path': path,
            'fields': {'emotion': null},
          },
        ]) {
          expect(
            (await toolManager.executeTool(
              name: 'Write',
              input: payload,
            ))['ok'],
            true,
          );
          expect(
            (await toolManager.executeTool(
              name: 'Read',
              input: {'path': '$path/emotion'},
            ))['value'],
            isEmpty,
          );
        }
        for (final raw in <Object>[
          'tense、calm',
          ['valid', ' '],
          [
            {'wrong': 'object'},
          ],
        ]) {
          final result = await toolManager.executeTool(
            name: 'Write',
            input: {'path': '$path/emotion', 'value': raw},
          );
          expect(result['error_code'], 'invalid_argument', reason: '$result');
          expect(
            (await toolManager.executeTool(
              name: 'Read',
              input: {'path': '$path/emotion'},
            ))['value'],
            isEmpty,
          );
        }
        // 数组元素内部的未知键与顶层同规则：跳过并按位置回报，可空字段的 null 不算问题。
        final nested = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': '$path/events',
            'value': [
              {'title': null, 'surprise': true},
              {'summary': null},
            ],
          },
        );
        expect(nested['ok'], isTrue, reason: '$nested');
        expect(nested['validation_errors'], isNull);
        expect(nested['ignored_fields'], ['events[0].surprise']);
      },
    );

    test(
      'field aliases and enum formats share canonical declarations and conflict checks',
      () async {
        final created = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'outlines',
            'fields': {
              'title': 'Alias',
              'status': 'inProgress',
              'start_chapter_num': '7.8',
              'beats':
                  "[{'title':' Beat ', 'chapterCount':'2.8', 'chapter_count':3, 'status':'IN-PROGRESS'}]",
            },
          },
        );
        expect(created['ok'], true, reason: '$created');
        final path = created['path'] as String;
        final beatListing = await toolManager.executeTool(
          name: 'Read',
          input: {'path': '$path/beats'},
        );
        final beatPath = (beatListing['entries'] as List).single['path'];
        expect(
          (await toolManager.executeTool(
            name: 'Read',
            input: {'path': '$path/status'},
          ))['value'],
          'in_progress',
        );
        expect(
          (await toolManager.executeTool(
            name: 'Read',
            input: {'path': '$path/start_chapter_num'},
          ))['value'],
          8,
        );
        expect(
          (await toolManager.executeTool(
            name: 'Read',
            input: {'path': '$beatPath/chapter_count'},
          ))['value'],
          3,
        );
        final before = (await db.select(db.workingChanges).get())
            .map((row) => row.toJson())
            .toList();
        final conflict = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': '$path/beats',
            'value': [
              {'title': 'wrong', 'chapterCount': 2, 'chapter_count': 3},
            ],
          },
        );
        expect(conflict['error_code'], 'invalid_argument');
        expect(
          (conflict['validation_errors'] as List).cast<Map>().single['field'],
          'beats[0].chapter_count',
        );
        expect(
          (await db.select(db.workingChanges).get())
              .map((row) => row.toJson())
              .toList(),
          before,
        );
        final character = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'characters',
            'role': ' main ',
            'fields': {'name': 'Name', 'role': '主角'},
          },
        );
        expect(character['ok'], true, reason: '$character');
        final invalid = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'characters/${character['id']}/role',
            'value': 'protagonis',
          },
        );
        expect(invalid['error_code'], 'invalid_argument');
        expect(
          (invalid['validation_errors'] as List)
              .cast<Map>()
              .single['suggestion'],
          'protagonist',
        );
        final idRejected = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'chapters',
            'fields': {'title': 'ID', 'volume_id': 123},
          },
        );
        expect(idRejected['error_code'], 'invalid_argument');
      },
    );

    test(
      'missing, null and unknown fields report all issues without mutation',
      () async {
        final id = await contentService.createChapter(
          siblingOrder: 1,
          title: 'original',
        );
        final path = 'chapters/$id/title';
        final before = (await db.select(db.workingChanges).get())
            .map((row) => row.toJson())
            .toList();
        for (final input in <Map<String, dynamic>>[
          {},
          {'fields': {}},
        ]) {
          final result = await toolManager.executeTool(
            name: 'Write',
            input: {'path': path, ...input},
          );
          expect(result['error_code'], 'invalid_argument');
          expect(result['validation_errors'], [
            {'code': 'required', 'field': 'title'},
          ]);
          expect(result['hint'], contains('Read /_schema/chapters'));
        }
        final malformed = await toolManager.executeTool(
          name: 'Write',
          input: {'path': path, 'fields': <Object>[]},
        );
        expect(malformed['error_code'], 'invalid_argument');
        expect(malformed['validation_errors'], isNotEmpty);
        // 字段路径只认路径上那个字段：别的键跳过，路径字段仍算缺失。
        final wrongField = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': path,
            'fields': {'content': 'wrong field'},
          },
        );
        expect(wrongField['error_code'], 'invalid_argument');
        expect(wrongField['ignored_fields'], ['content']);
        expect(wrongField['validation_errors'], [
          {'code': 'required', 'field': 'title'},
        ]);
        expect(
          (await db.select(db.workingChanges).get())
              .map((row) => row.toJson())
              .toList(),
          before,
        );
        expect(
          (await toolManager.executeTool(
            name: 'Read',
            input: {'path': path},
          ))['value'],
          'original',
        );
      },
    );

    test(
      'normalized duplicate sources agree with preview or reject atomically',
      () async {
        Map<String, dynamic>? preview;
        toolManager = AiToolManager(
          contentService,
          workingOverlayService: overlay,
          onToolStarted: (_, tool, _, extra, _) {
            if (tool == 'Write') {
              preview = extra;
            }
          },
        )..registerAllTools();
        final id = await contentService.createChapter(
          siblingOrder: 1,
          title: 'original',
        );
        final path = 'chapters/$id/title';
        Future<Object?> read() async => (await toolManager.executeTool(
          name: 'Read',
          input: {'path': path},
        ))['value'];
        for (final input in <Map<String, dynamic>>[
          {
            'value': 42,
            'fields': {'value': 'fallback'},
          },
          {
            'fields': {'value': 42, 'title': 'fallback'},
          },
          {
            'value': null,
            'fields': {'value': 'fallback'},
          },
          {
            'fields': {'value': null, 'title': 'fallback'},
          },
        ]) {
          final before = (await db.select(db.workingChanges).get())
              .map((row) => row.toJson())
              .toList();
          final result = await toolManager.executeTool(
            name: 'Write',
            input: {'path': path, ...input},
          );
          expect(result['error_code'], 'invalid_argument', reason: '$result');
          expect(
            (result['validation_errors'] as List).cast<Map>().any(
              (issue) => issue['code'] == 'conflicting_fields',
            ),
            isTrue,
          );
          expect(preview?['diffNewText'], isNull);
          expect(await read(), 'original');
          expect(
            (await db.select(db.workingChanges).get())
                .map((row) => row.toJson())
                .toList(),
            before,
          );
        }
        for (final scenario in <(Map<String, dynamic>, String)>[
          (
            {
              'value': 42,
              'fields': {'title': ' 42 ', 'value': '42'},
            },
            '42',
          ),
          (
            {
              'fields': {'title': true},
            },
            'true',
          ),
          ({'value': '  first\n  second  '}, 'first\n  second'),
          ({'value': ''}, ''),
        ]) {
          final result = await toolManager.executeTool(
            name: 'Write',
            input: {'path': path, ...scenario.$1},
          );
          expect(result['ok'], isTrue, reason: '$result');
          expect(await read(), scenario.$2);
          expect(preview?['diffNewText'], scenario.$2);
        }
      },
    );

    test(
      'Create ignores unknown fields but rejects missing and invalid values without mutation',
      () async {
        final before = (await db.select(db.workingChanges).get())
            .map((row) => row.toJson())
            .toList();
        final missingRequired = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'characters',
            'fields': {'id': 'not-a-created-id', 'ignored': true},
          },
        );
        expect(missingRequired['error_code'], 'invalid_argument');
        expect(missingRequired['ignored_fields'], ['id', 'ignored']);
        for (final name in <Object?>[null, '']) {
          final result = await toolManager.executeTool(
            name: 'Create',
            input: {
              'path': 'characters',
              'fields': {
                'name': name,
                'role': 'bad',
                'gender': 'bad',
                'ignored': true,
              },
            },
          );
          expect(result['error_code'], 'invalid_argument');
          final issues = (result['validation_errors'] as List).cast<Map>();
          expect(
            issues.map((issue) => issue['field']),
            containsAll(['name', 'role', 'gender']),
          );
          expect(
            issues.where((issue) => issue['code'] == 'invalid_enum'),
            hasLength(2),
          );
          expect(result['ignored_fields'], ['ignored']);
          expect(issues.any((issue) => issue['field'] == 'ignored'), isFalse);
          expect(result['hint'], contains('Read /_schema/characters'));
        }
        expect(
          (await toolManager.executeTool(
            name: 'Read',
            input: {'path': 'characters'},
          ))['entries'],
          isEmpty,
        );
        expect(
          (await db.select(db.workingChanges).get())
              .map((row) => row.toJson())
              .toList(),
          before,
        );
      },
    );

    test('Write previews and applies the same normalized enum value', () async {
      Map<String, dynamic>? preview;
      toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay,
        onToolStarted: (_, _, _, extra, _) => preview = extra,
      )..registerAllTools();
      final created = await toolManager.executeTool(
        name: 'Create',
        input: {
          'path': 'characters',
          'fields': {'name': '林默', 'role': '配角'},
        },
      );
      expect(created['created'], isTrue, reason: '$created');
      final path = 'characters/${created['id']}/role';
      for (final input in [
        <String, dynamic>{'path': path, 'value': '主角'},
        <String, dynamic>{
          'path': 'characters/${created['id']}',
          'fields': {'role': '配角'},
        },
      ]) {
        final written = await toolManager.executeTool(
          name: 'Write',
          input: input,
        );
        expect(written['error'], isNull, reason: '$written');
        final newText = preview?['diffNewText'];
        final read = await toolManager.executeTool(
          name: 'Read',
          input: {'path': path},
        );
        expect(newText, read['value']);
        expect(newText, isIn(['protagonist', 'supporting']));
      }
    });

    test(
      'normalized mixed writes execute consistently and reject invalid updates atomically',
      () async {
        final chapterId = await contentService.createChapter(
          siblingOrder: 1,
          title: '原标题',
        );
        final path = 'chapters/$chapterId';
        final fields = <String, dynamic>{
          'title': 42,
          'tension': 5.7,
          'emotion': '["紧张", " 决绝 ", "紧张"]',
          'events': '[{"title":"转折"}]',
        };
        final written = await toolManager.executeTool(
          name: 'Write',
          input: {'path': path, 'fields': fields},
        );
        expect(written['error'], isNull, reason: '$written');
        expect(written['ignored_fields'], isNull);
        Future<Object?> read(String field) async =>
            (await toolManager.executeTool(
              name: 'Read',
              input: {'path': '$path/$field'},
            ))['value'];
        expect(await read('title'), '42');
        expect(await read('tension'), 6);
        expect(await read('emotion'), ['紧张', '决绝']);
        expect(await read('events'), [
          {'title': '转折', 'summary': ''},
        ]);
        expect(fields['tension'], 5.7);
        expect(fields['events'], isA<String>());

        final rejected = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': path,
            'fields': {'title': '不应写入', 'tension': 99},
          },
        );
        expect(rejected['error_code'], 'invalid_argument');
        expect(await read('title'), '42');
        expect(await read('tension'), 6);
      },
    );

    test('numeric field preview accepts the normalized number', () async {
      Map<String, dynamic>? preview;
      toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay,
        onToolStarted: (_, _, _, extra, _) => preview = extra,
      )..registerAllTools();
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '章节',
      );
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'chapters/$chapterId/tension', 'value': '7'},
      );
      expect(result['error'], isNull, reason: '$result');
      expect(preview?['targetPath'], 'chapters/$chapterId/tension');
      expect(preview?['diffNewText'], '7');
      final read = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters/$chapterId/tension'},
      );
      expect(read['value'], 7);
    });

    test('TodoWrite accepts a string shorthand todo item', () async {
      final result = await toolManager.executeTool(
        name: 'TodoWrite',
        input: {
          'todos': ['检查工具入参兼容性'],
        },
        callId: 'call_todo_string_item_test',
      );

      expect(result['ok'], isTrue);
      final todos = result['todos'] as List<dynamic>;
      expect(todos, hasLength(1));
      expect(todos.first, {
        'id': 'todo_1',
        'content': '检查工具入参兼容性',
        'status': 'pending',
        'priority': 'medium',
      });
    });

    test(
      'TodoWrite uses conversation sessionId instead of mutation source',
      () async {
        String? capturedSessionId;
        toolManager.todoWriteCallback = (todos, sessionId) async {
          capturedSessionId = sessionId;
          return todos;
        };

        final result = await toolManager.executeTool(
          name: 'TodoWrite',
          input: {
            'todos': ['子会话待办'],
          },
          callId: 'call_todo_session_prefer_todo_id',
          context: ToolExecutionContext(
            sessionId: 'sub_session_xyz',
            sourceSessionId: 'parent_session',
          ),
        );

        expect(result['ok'], isTrue);
        expect(capturedSessionId, 'sub_session_xyz');
      },
    );

    test(
      'TodoWrite does not treat mutation source as conversation session',
      () async {
        String? capturedSessionId;
        toolManager.todoWriteCallback = (todos, sessionId) async {
          capturedSessionId = sessionId;
          return todos;
        };

        final result = await toolManager.executeTool(
          name: 'TodoWrite',
          input: {
            'todos': ['父会话待办'],
          },
          callId: 'call_todo_session_fallback_source',
          context: ToolExecutionContext(sourceSessionId: 'parent_session'),
        );

        expect(result['ok'], isFalse);
        expect(result['error_code'], 'unavailable');
        expect(capturedSessionId, isNull);
      },
    );

    test('TodoWrite with callback requires a session id', () async {
      toolManager.todoWriteCallback = (todos, sessionId) async => todos;

      final result = await toolManager.executeTool(
        name: 'TodoWrite',
        input: {
          'todos': ['无会话'],
        },
        callId: 'call_todo_session_missing',
      );

      expect(result['ok'], isFalse);
      expect(result['error_code'], 'unavailable');
    });

    test('TodoWrite coerces object fields to strings', () async {
      final result = await toolManager.executeTool(
        name: 'TodoWrite',
        input: {
          'todos': [
            {
              'id': 7,
              'content': 42,
              'status': 'in_progress',
              'priority': 'high',
            },
          ],
        },
        callId: 'call_todo_coerce_fields_test',
      );

      expect(result['ok'], isTrue);
      final todos = result['todos'] as List<dynamic>;
      expect(todos, hasLength(1));
      expect(todos.first, {
        'id': '7',
        'content': '42',
        'status': 'in_progress',
        'priority': 'high',
      });
    });

    test('Read accepts numeric strings for pagination', () async {
      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters', 'offset': '0', 'limit': '5'},
        callId: 'call_read_numeric_strings_test',
      );

      expect(result['error'], isNull);
      expect(result['type'], 'listing');
      expect(result['limit'], 5);
    });

    test('Read paginates listings by default', () async {
      for (var i = 0; i < 55; i += 1) {
        await contentService.createChapter(siblingOrder: i, title: '章节 $i');
      }

      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters'},
        callId: 'call_read_default_listing_pagination_test',
      );

      expect(result['type'], 'listing');
      expect(result['total'], 55);
      expect(result['limit'], 50);
      expect(result['has_more'], isTrue);
      expect(result['entries'], hasLength(50));
    });

    test('Read lists chapters by chapter_num descending by default', () async {
      for (var i = 1; i <= 3; i += 1) {
        await contentService.createChapter(siblingOrder: i, title: '章节 $i');
      }

      final defaultResult = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters'},
        callId: 'call_read_chapters_default_order_test',
      );
      final ascendingResult = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters', 'sort': 'chapter_num'},
        callId: 'call_read_chapters_ascending_order_test',
      );

      List<int?> chapterNums(Map<String, dynamic> result) {
        final entries = result['entries'] as List<dynamic>;
        return entries.map((entry) => entry['chapter_num'] as int?).toList();
      }

      expect(chapterNums(defaultResult), [3, 2, 1]);
      expect(chapterNums(ascendingResult), [1, 2, 3]);
    });

    test('Read paginates long text fields by default', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '章节',
      );
      final content = List.generate(205, (index) => 'line $index').join('\n');
      final writeResult = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'chapters/$chapterId/content', 'value': content},
        callId: 'call_read_default_text_pagination_write_test',
      );
      expect(writeResult.containsKey('working_change_id'), isFalse);
      await overlay.commitWorkingChanges(
        [await onlyActiveWorkingChangeId(db)],
        source: workingChangeSourceAi,
        message: 'test.accept_read_pagination_fixture',
      );

      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters/$chapterId/content'},
        callId: 'call_read_default_text_pagination_test',
      );

      expect(result['total_lines'], 205);
      expect(result['start_line'], 1);
      expect(result['end_line'], 200);
      expect(result['limit'], 200);
      expect(result['has_more'], isTrue);
      expect(result['next_offset'], 200);
      expect((result['value'] as String).split('\n'), hasLength(200));
    });

    test('Read returns real written text and reject reverts it', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '章节',
      );
      await contentService.updateChapterContent(
        chapterId: chapterId,
        title: '章节',
        outline: '',
        content: '已提交正文',
      );

      await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'chapters/$chapterId/content', 'value': '已写入正文'},
        callId: 'call_read_committed_only_write_test',
      );

      final writtenRead = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters/$chapterId/content'},
        callId: 'call_read_committed_only_pending_test',
      );
      expect(writtenRead['value'], '已写入正文');

      await overlay.rejectWorkingChange(await onlyActiveWorkingChangeId(db));

      final revertedRead = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters/$chapterId/content'},
        callId: 'call_read_committed_only_after_commit_test',
      );
      expect(revertedRead['value'], '已提交正文');
    });

    test('successive Edit calls are immediately visible to Read', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '章节',
      );
      await contentService.updateChapterContent(
        chapterId: chapterId,
        title: '章节',
        outline: '',
        content: '2024 年的夏天\n屏幕上弹出一条私信提醒\n再睁开眼',
      );

      final firstEdit = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'chapters/$chapterId/content',
          'old_text': '2024 年的夏天',
          'new_text': '　　2024 年的夏天',
        },
        callId: 'call_successive_edit_first_test',
      );
      expect(firstEdit['edited'], isTrue);
      expect(firstEdit.containsKey('working_change_id'), isFalse);
      final firstChangeId = await onlyActiveWorkingChangeId(db);

      final secondEdit = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'chapters/$chapterId/content',
          'old_text': '屏幕上弹出一条私信提醒',
          'new_text': '　　屏幕上弹出一条私信提醒',
        },
        callId: 'call_successive_edit_second_test',
      );
      expect(secondEdit['edited'], isTrue);
      expect(secondEdit.containsKey('working_change_id'), isFalse);
      // 同一资源上的连续 Edit 必须复用同一条 working change 记录，而不是新建一条：
      // id 变了意味着 createdAt / sourceTurnId 丢失，turn 级回退会断。
      expect(await onlyActiveWorkingChangeId(db), firstChangeId);

      final read = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters/$chapterId/content', 'offset': 0, 'limit': 5},
        callId: 'call_successive_edit_read_test',
      );

      expect(read['value'], '　　2024 年的夏天\n　　屏幕上弹出一条私信提醒\n再睁开眼');
    });

    test(
      'Write trims outer whitespace and preserves internal indentation when creating material content',
      () async {
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'materials/缩进素材/content', 'value': '　　素材正文'},
          callId: 'call_write_material_indentation_test',
        );

        expect(result['created'], isTrue);
        final read = await toolManager.executeTool(
          name: 'Read',
          input: {'path': 'materials/缩进素材/content'},
          callId: 'call_read_material_indentation_test',
        );
        expect(read['value'], '　　素材正文'.trim());
      },
    );

    test(
      'Create trims outer whitespace and preserves internal indentation in character text fields',
      () async {
        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'characters',
            'fields': {
              'name': '林默',
              'biography': '　　小传第一行',
              'description': '　　左眉有浅疤',
              'current_state': '　　右臂受伤',
            },
          },
          callId: 'call_create_character_indentation_test',
        );

        expect(result['created'], isTrue);
        final character = await contentService.getCharacterProfileById(
          result['id'] as String,
        );
        expect(character!.biography, '　　小传第一行'.trim());
        expect(character.description, '　　左眉有浅疤'.trim());
        expect(character.currentState, '　　右臂受伤'.trim());
      },
    );

    test(
      'Create trims outer whitespace and preserves internal indentation in foreshadowing text fields',
      () async {
        final result = await toolManager.executeTool(
          name: 'Create',
          input: {
            'path': 'foreshadowing',
            'fields': {'title': '镜中提醒', 'setup': '　　弹出私信', 'payoff': '　　镜中人现身'},
          },
          callId: 'call_create_foreshadowing_indentation_test',
        );

        expect(result['created'], isTrue);
        final entry = await contentService.getForeshadowingById(
          result['id'] as String,
        );
        expect(entry!.setup, '　　弹出私信'.trim());
        expect(entry.payoff, '　　镜中人现身'.trim());
      },
    );

    test('Read clamps oversized limits to tool bounds', () async {
      final chapterId = await contentService.createChapter(
        siblingOrder: 1,
        title: '章节',
      );
      final content = List.generate(505, (index) => 'line $index').join('\n');
      await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'chapters/$chapterId/content', 'value': content},
        callId: 'call_read_limit_clamp_write_test',
      );
      await overlay.commitWorkingChanges(
        [await onlyActiveWorkingChangeId(db)],
        source: workingChangeSourceAi,
        message: 'test.accept_read_limit_clamp_fixture',
      );

      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters/$chapterId/content', 'limit': 999},
        callId: 'call_read_limit_clamp_test',
      );

      expect(result['limit'], 500);
      expect(result['requested_limit'], 999);
      expect(result['end_line'], 500);
      expect(result['has_more'], isTrue);
      expect(result['next_offset'], 500);
    });

    test('Read rejects invalid pagination values', () async {
      final negativeOffset = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters', 'offset': -1},
        callId: 'call_read_negative_offset_test',
      );
      final zeroLimit = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters', 'limit': 0},
        callId: 'call_read_zero_limit_test',
      );

      expect(negativeOffset['error'], 'offset must be >= 0');
      expect(zeroLimit['error'], 'limit must be >= 1');
    });

    test('Read accepts sort and limit embedded in path query', () async {
      for (var i = 1; i <= 5; i += 1) {
        await contentService.createChapter(siblingOrder: i, title: '章节 $i');
      }

      final result = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'chapters?sort=-chapter_num&limit=2'},
        callId: 'call_read_path_query_pagination_test',
      );

      expect(result['error'], isNull);
      expect(result['type'], 'listing');
      expect(result['limit'], 2);
      final entries = result['entries'] as List<dynamic>;
      expect(entries, hasLength(2));
      expect(entries.first['chapter_num'], 5);
      expect(entries.last['chapter_num'], 4);
    });

    test(
      'Write chapter fields ignores unsupported fields and writes supported fields',
      () async {
        final chapterId = await contentService.createChapter(
          siblingOrder: 1,
          title: '旧标题',
        );

        final result = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'chapters/$chapterId',
            'fields': {
              'title': '新标题',
              'content': '新正文',
              'word_count': 4480,
              'status': 'draft',
            },
          },
          callId: 'call_write_chapter_bulk_ignored_fields_test',
        );

        expect(result['ok'], isTrue, reason: '$result');
        expect(result['updated'], isTrue);
        expect(result['ignored_fields'], ['word_count', 'status']);
        final chapter = (await contentService.getChapterById(chapterId))!;
        expect(chapter.title, '新标题');
        expect(chapter.content, '新正文');
        expect(chapter.wordCount, isNot(4480));
      },
    );

    test(
      'Write chapter single read-only field still returns an error',
      () async {
        final chapterId = await contentService.createChapter(
          siblingOrder: 1,
          title: '章节',
        );

        final result = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'chapters/$chapterId/word_count', 'value': '4480'},
          callId: 'call_write_chapter_single_word_count_test',
        );

        expect(result['updated'], isNot(isTrue));
        expect(result['error_code'], 'permission_denied');
        expect(result['error'], contains('word_count'));
      },
    );

    test(
      'Write bulk payload ignores unsupported fields across resource types',
      () async {
        final volumeId = await contentService.createVolume(title: '旧卷');
        final characterId = await contentService.createCharacterProfile(
          defaultName: '旧角色',
        );
        final itemId = await contentService.createItem(
          type: 'item',
          defaultTitle: '旧物品',
        );
        await contentService.documentsService.createDocument(
          type: 'lore',
          title: '魔法系统',
        );

        final volumeResult = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'volumes/$volumeId',
            'fields': {'title': '新卷', 'word_count': 1},
          },
          callId: 'call_write_volume_bulk_ignored_fields_test',
        );
        final characterResult = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'characters/$characterId',
            'fields': {'name': '新角色', 'id': 'ignored-character-id'},
          },
          callId: 'call_write_character_bulk_ignored_fields_test',
        );
        final itemResult = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'items/$itemId',
            'fields': {
              'content': '新内容',
              'photos': ['/tmp/item.png'],
            },
          },
          callId: 'call_write_item_bulk_ignored_fields_test',
        );
        final documentResult = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'lore/魔法系统',
            'fields': {'content': '新设定', 'word_count': 9},
          },
          callId: 'call_write_document_bulk_ignored_fields_test',
        );

        for (final result in [
          volumeResult,
          characterResult,
          itemResult,
          documentResult,
        ]) {
          expect(result['ok'], isTrue, reason: '$result');
          expect(result['updated'], isTrue);
          expect(result['ignored_fields'], isNotEmpty);
        }
        for (final entry in {
          'volumes/$volumeId/title': '新卷',
          'characters/$characterId/name': '新角色',
          'items/$itemId/content': '新内容',
          'lore/魔法系统/content': '新设定',
        }.entries) {
          final read = await toolManager.executeTool(
            name: 'Read',
            input: {'path': entry.key},
          );
          expect(read['value'], entry.value, reason: '$read');
        }
      },
    );

    test(
      'Write with only unsupported fields does not create a document',
      () async {
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'lore/不存在的文档',
            'fields': {'word_count': 9, 'unknown': true},
          },
        );
        expect(result['ok'], isTrue, reason: '$result');
        expect(result['updated'], isFalse);
        expect(result['ignored_fields'], ['word_count', 'unknown']);
        expect(await db.select(db.documents).get(), isEmpty);
        expect(await db.select(db.workingChanges).get(), isEmpty);
      },
    );

    test(
      'Write preview ignores unsupported fields but validates writable values',
      () async {
        Map<String, dynamic>? preview;
        toolManager = AiToolManager(
          contentService,
          workingOverlayService: overlay,
          onToolStarted: (_, _, _, extra, _) => preview = extra,
        )..registerAllTools();
        final chapterId = await contentService.createChapter(
          siblingOrder: 1,
          title: '原标题',
        );
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'chapters/$chapterId',
            'fields': {'title': '新标题', 'word_count': 999},
          },
        );
        expect(result['ok'], isTrue, reason: '$result');
        expect(preview?['diffNewText'], '新标题');
        final rejected = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'chapters/$chapterId',
            'fields': {'title': '不应写入', 'tension': 99, 'unknown': true},
          },
        );
        expect(rejected['error_code'], 'invalid_argument');
        expect(rejected['ignored_fields'], ['unknown']);
        expect((await contentService.getChapterById(chapterId))!.title, '新标题');
      },
    );

    test('Write single unsupported field still returns an error', () async {
      final volumeId = await contentService.createVolume(title: '卷');

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'volumes/$volumeId/content', 'value': '错误字段'},
        callId: 'call_write_single_unsupported_field_test',
      );

      expect(result['updated'], isNot(isTrue));
      expect(result['error_code'], 'invalid_argument');
      expect(result['error'], contains('content'));
    });

    test('Write accepts a numeric value for a string field', () async {
      final volumeId = await contentService.createVolume(title: '卷');

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'volumes/$volumeId/title', 'value': 123},
        callId: 'call_write_undeclared_field_non_string_test',
      );

      expect(result['updated'], isTrue);
      expect(result['error_code'], isNull);
      expect(
        (await toolManager.executeTool(
          name: 'Read',
          input: {'path': 'volumes/$volumeId/title'},
        ))['value'],
        '123',
      );
    });

    // fields 里同名投放是另一条分支，同样守缺省值。
    test('Write accepts a numeric fields entry for a string field', () async {
      final volumeId = await contentService.createVolume(title: '卷');

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': 'volumes/$volumeId/title',
          'fields': {'title': 123},
        },
        callId: 'call_write_undeclared_field_non_string_fields_test',
      );

      expect(result['updated'], isTrue);
      expect(result['error_code'], isNull);
      expect(
        (await toolManager.executeTool(
          name: 'Read',
          input: {'path': 'volumes/$volumeId/title'},
        ))['value'],
        '123',
      );
    });
  });
}
