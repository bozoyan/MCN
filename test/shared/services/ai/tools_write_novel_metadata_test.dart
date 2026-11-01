// 职责: 测试 Create/Write/Edit/Read 对作品元数据直写与回读，以及 Remove 拒绝删除。
// 关联文件:
//   lib/shared/services/ai/tools_write.dart
//   lib/shared/services/ai/tools_read.dart
//   lib/shared/services/ai/tools.dart

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import 'package:reveric/shared/utils/storage_paths.dart';

void main() {
  group('Write/Read novel metadata', () {
    late Directory tempSupport;
    late NovelContentDatabase db;
    late AppDatabase appDb;
    late NovelContentService contentService;
    late AiToolManager toolManager;
    late Map<String, dynamic> store;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempSupport = await Directory.systemTemp.createTemp(
        'reveric_write_novel_meta_',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
              if (call.method == 'getApplicationSupportDirectory') {
                return tempSupport.path;
              }
              return null;
            },
          );
      await RevericPaths.initialize();

      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      appDb = AppDatabase.forTest(NativeDatabase.memory());
      contentService = NovelContentService(db);
      store = <String, dynamic>{
        'title': '未命名作品',
        'author_name': '',
        'description': '',
        'category': '',
        'status': 'in_progress',
        'tags': <String>[],
        'word_count': 0,
      };

      toolManager = AiToolManager(
        contentService,
        workingOverlayService: WorkingOverlayService(
          db,
          contentService,
          novelActionsService: NovelActionsService(appDb),
        ),
        novelReader: () async =>
            Map<String, dynamic>.from(store)
              ..['tags'] = List<String>.from(store['tags'] as List),
        novelWriter: (fields) async {
          if (fields.containsKey('title')) {
            store['title'] = fields['title'];
          }
          if (fields.containsKey('author_name')) {
            store['author_name'] = fields['author_name'];
          }
          if (fields.containsKey('description')) {
            store['description'] = fields['description'];
          }
          if (fields.containsKey('category')) {
            store['category'] = fields['category'];
          }
          if (fields.containsKey('tags')) {
            store['tags'] = List<String>.from(fields['tags'] as List);
          }
          // 生产实现走 novelActions.updateNovelStatus；这里只验证 status 确实被
          // 交给了 writer，而不是被 stage 成永远 apply 不了的 working change。
          if (fields.containsKey('status')) {
            store['status'] = fields['status'];
          }
        },
      )..registerAllTools();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await db.close();
      await appDb.close();
      if (await tempSupport.exists()) {
        await tempSupport.delete(recursive: true);
      }
    });

    test(
      'Write author name, category and tags directly without working_change',
      () async {
        final authorResult = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'profile/author_name', 'value': '辰东'},
          callId: 'call_write_novel_author_name',
        );
        expect(authorResult['error'], isNull);
        expect(authorResult['updated'], isTrue);
        expect(authorResult['fields'], contains('author_name'));
        expect(authorResult.containsKey('working_change_id'), isFalse);
        expect(store['author_name'], '辰东');

        final categoryResult = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'profile/category', 'value': '玄幻'},
          callId: 'call_write_novel_category',
        );
        expect(categoryResult['error'], isNull);
        expect(categoryResult['updated'], isTrue);
        expect(categoryResult['fields'], contains('category'));
        expect(categoryResult.containsKey('working_change_id'), isFalse);
        expect(store['category'], '玄幻');

        final tagsResult = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'profile/tags', 'value': '重生, 系统, 爽文'},
          callId: 'call_write_novel_tags',
        );
        expect(tagsResult['error'], isNull);
        expect(tagsResult['updated'], isTrue);
        expect(tagsResult['fields'], contains('tags'));
        expect(tagsResult.containsKey('working_change_id'), isFalse);
        expect(store['tags'], ['重生', '系统', '爽文']);
      },
    );

    test('status 直写落到 writer，不留成永远 apply 不了的 working change', () async {
      // 改前 status 走 _stageTextChange，返回 updated:true 却只记了一条 patch；
      // working overlay 的 novel 分支不 apply status，接受与否都不会落库。
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'profile/status', 'value': 'finished'},
        callId: 'call_write_novel_status',
      );

      expect(result['error'], isNull);
      expect(result['updated'], isTrue);
      expect(result['fields'], contains('status'));
      expect(result.containsKey('working_change_id'), isFalse);
      expect(store['status'], 'finished');
    });

    test('status 拒绝枚举外的值', () async {
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'profile/status', 'value': 'hiatus'},
        callId: 'call_write_novel_status_invalid',
      );

      expect(result['error_code'], 'invalid_argument');
      expect(result['enum_field'], 'status');
      expect(store['status'], 'in_progress');
    });

    test(
      'Create and Write update the same profile and reject invalid fields atomically',
      () async {
        final written = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'profile',
            'fields': {
              'title': '  新作品  ',
              'status': 'IN PROGRESS',
              'tags': '甲, 乙',
            },
          },
        );
        expect(written['updated'], isTrue);
        expect(store['title'], '新作品');
        expect(store['status'], 'in_progress');
        expect(store['tags'], ['甲', '乙']);
        for (final tool in ['Create', 'Write']) {
          final updated = await toolManager.executeTool(
            name: tool,
            input: {
              'path': 'profile',
              'fields': {'title': '  $tool  '},
            },
          );
          expect(updated['updated'], isTrue);
          expect(updated['path'], 'profile');
          expect(store['title'], tool);
          expect(store['tags'], ['甲', '乙']);
          expect(store['status'], 'in_progress');
          final before = Map<String, dynamic>.from(store);
          final rejected = await toolManager.executeTool(
            name: tool,
            input: {
              'path': 'profile',
              'fields': {'title': '不应保存', 'status': 'unknown'},
            },
          );
          expect(rejected['error_code'], 'invalid_argument');
          expect(store, before);
        }
        final before = Map<String, dynamic>.from(store);
        for (final path in ['profile', 'profile/title']) {
          final result = await toolManager.executeTool(
            name: 'Remove',
            input: {'path': path, 'force': true, 'recursive': true},
          );
          expect(result['ok'], isFalse);
          expect(store, before);
        }
        expect(await db.select(db.workingChanges).get(), isEmpty);
      },
    );

    test('Read returns author name, category and comma-joined tags', () async {
      store['author_name'] = '天蚕土豆';
      store['category'] = '都市';
      store['tags'] = ['商战', '重生'];

      final authorName = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'profile/author_name'},
        callId: 'call_read_novel_author_name',
      );
      expect(authorName['value'], '天蚕土豆');

      final category = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'profile/category'},
        callId: 'call_read_novel_category',
      );
      expect(category['value'], '都市');

      final tags = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'profile/tags'},
        callId: 'call_read_novel_tags',
      );
      expect(tags['value'], '商战, 重生');

      final all = await toolManager.executeTool(
        name: 'Read',
        input: {'path': 'profile'},
        callId: 'call_read_novel_all',
      );
      expect(all['author_name'], '天蚕土豆');
      expect(all['category'], '都市');
      expect(all['tags'], '商战, 重生');
    });

    test('batch Write keeps sibling metadata fields', () async {
      final result = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': 'profile',
          'fields': {
            'title': '剑起苍穹',
            'author_name': '忘语',
            'category': '仙侠',
            'tags': '修真, 热血',
            'description': '一剑破万法。',
          },
        },
        callId: 'call_write_novel_batch',
      );
      expect(result['error'], isNull);
      expect(result['updated'], isTrue);
      expect(
        result['fields'],
        containsAll([
          'title',
          'author_name',
          'category',
          'tags',
          'description',
        ]),
      );
      expect(store['title'], '剑起苍穹');
      expect(store['author_name'], '忘语');
      expect(store['category'], '仙侠');
      expect(store['tags'], ['修真', '热血']);
      expect(store['description'], '一剑破万法。');
    });

    test(
      'Edit null novel description with empty old_text initializes the field',
      () async {
        store['description'] = null;

        final result = await toolManager.executeTool(
          name: 'Edit',
          input: {
            'path': 'profile/description',
            'old_text': '',
            'new_text': '一剑破万法。',
          },
          callId: 'call_edit_novel_null_description',
        );

        expect(result['error'], isNull);
        expect(result['edited'], isTrue);
        expect(result['error_code'], isNull);
        expect(store['description'], '一剑破万法。');
      },
    );

    test(
      'Edit null novel description with non-empty old_text is not unknown_field',
      () async {
        store['description'] = null;

        final result = await toolManager.executeTool(
          name: 'Edit',
          input: {
            'path': 'profile/description',
            'old_text': '旧简介',
            'new_text': '新简介',
          },
          callId: 'call_edit_novel_null_description_miss',
        );

        expect(result['error_code'], 'failed_precondition');
        expect(result['error'], isNot(contains('Unknown')));
        expect(result['error'], isNot(contains('not a text field')));
        expect(result['hint'], contains('empty string'));
      },
    );

    test('Edit author name directly without working_change', () async {
      store['author_name'] = '旧笔名';

      final result = await toolManager.executeTool(
        name: 'Edit',
        input: {
          'path': 'profile/author_name',
          'old_text': '旧笔名',
          'new_text': '新笔名',
        },
        callId: 'call_edit_novel_author_name',
      );

      expect(result['error'], isNull);
      expect(result['edited'], isTrue);
      expect(result.containsKey('working_change_id'), isFalse);
      expect(store['author_name'], '新笔名');
    });

    test(
      'legacy novel path is accepted but returns canonical profile path',
      () async {
        final result = await toolManager.executeTool(
          name: 'Read',
          input: {'path': 'profile/title'},
        );

        expect(result['value'], store['title']);
        expect(result['path'], 'profile/title');
      },
    );
  });
}
