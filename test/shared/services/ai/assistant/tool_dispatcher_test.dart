// 职责: 验证 AssistantToolDispatcher 的 job_status / send_to_job / start_job 工具 —
//       job_id 参数解析、回调透传、缺失参数与异常兜底
// 关联文件:
//   lib/shared/services/ai/assistant/tool_dispatcher.dart
//   lib/shared/agent/agent_tool_dispatcher.dart
//
// 说明：定位符直接用 Job 的 AiChatSession id（job_id），不再经 taskId 解析。
// Job 不是 Task（todo）。chatId / channelType 不在工具 schema 内（LLM 不可知），
// 由 coordinator 从 inbound 上下文注入到业务回调，dispatcher 层回调签名不含
// chat 上下文。jobStatus / sendToJob / startJob 的真实业务路径（steer /
// idle 续跑 / 落库）依赖 ProviderContainer + DB，由方案 §6 手动集成测试覆盖，
// 此处不重复。

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/assistant/tool_dispatcher.dart';

void main() {
  group('AssistantToolDispatcher job_status', () {
    test('passes job_id to callback and merges result', () async {
      String? capturedJobId;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async {
          capturedJobId = jobId;
          return {
            'ok': true,
            'status': 'running',
            'session_id': 'sess_1',
            'recent_output': ['hello'],
          };
        },
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'job_status',
        input: const {'job_id': 'run_abc'},
      );

      expect(capturedJobId, 'run_abc');
      expect(result, {
        'ok': true,
        'status': 'running',
        'session_id': 'sess_1',
        'recent_output': ['hello'],
      });
    });

    test('missing job_id returns error without invoking callback', () async {
      var callbackInvoked = false;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async {
          callbackInvoked = true;
          return {'ok': true};
        },
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'job_status',
        input: const {},
      );

      expect(
        callbackInvoked,
        isFalse,
        reason: 'missing job_id should short-circuit before callback',
      );
      expect(result['ok'], isFalse);
      expect(result['error'].toString(), contains('job_id is required'));
    });

    test('callback throws → caught and returned as ok:false error', () async {
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async {
          throw StateError('boom');
        },
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'job_status',
        input: const {'job_id': 'run_x'},
      );

      expect(result['ok'], isFalse);
      expect(result['error'].toString(), contains('boom'));
    });
  });

  group('AssistantToolDispatcher send_to_job', () {
    test('passes job_id and text to callback and merges result', () async {
      String? capturedJobId;
      String? capturedText;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async => {'ok': true},
        sendToJobCallback: (jobId, text) async {
          capturedJobId = jobId;
          capturedText = text;
          return {
            'ok': true,
            'action': 'steered',
            'job_id': jobId,
            'session_id': 'sess_1',
          };
        },
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'send_to_job',
        input: const {'job_id': 'run_abc', 'text': '请改写第三章'},
      );

      expect(capturedJobId, 'run_abc');
      expect(capturedText, '请改写第三章');
      expect(result, {
        'ok': true,
        'action': 'steered',
        'job_id': 'run_abc',
        'session_id': 'sess_1',
      });
    });

    test('missing job_id returns error without invoking callback', () async {
      var callbackInvoked = false;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async => {'ok': true},
        sendToJobCallback: (jobId, text) async {
          callbackInvoked = true;
          return {'ok': true};
        },
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'send_to_job',
        input: const {'text': 'hi'},
      );

      expect(callbackInvoked, isFalse);
      expect(result['ok'], isFalse);
      expect(
        result['error'].toString(),
        contains('job_id and text are required'),
      );
    });

    test('missing text returns error without invoking callback', () async {
      var callbackInvoked = false;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async => {'ok': true},
        sendToJobCallback: (jobId, text) async {
          callbackInvoked = true;
          return {'ok': true};
        },
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'send_to_job',
        input: const {'job_id': 'run_abc'},
      );

      expect(callbackInvoked, isFalse);
      expect(result['ok'], isFalse);
      expect(
        result['error'].toString(),
        contains('job_id and text are required'),
      );
    });

    test('accepts camelCase jobId as alt key (backward compat)', () async {
      String? capturedJobId;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async => {'ok': true},
        sendToJobCallback: (jobId, text) async {
          capturedJobId = jobId;
          return {'ok': true, 'action': 'resumed', 'job_id': jobId};
        },
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      // 旧 agent 偶尔会传 camelCase jobId；解析层应兼容。
      final result = await dispatcher.executeTool(
        name: 'send_to_job',
        input: const {'jobId': 'run_alt', 'text': 'resume me'},
      );

      expect(capturedJobId, 'run_alt');
      expect(result['ok'], isTrue);
      expect(result['action'], 'resumed');
    });
  });

  group('AssistantToolDispatcher start_job', () {
    test('passes novel_id and seed to callback and merges result', () async {
      String? capturedNovelId;
      String? capturedSeed;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async {
          capturedNovelId = novelId;
          capturedSeed = seed;
          return {'ok': true, 'job_id': 'run_new', 'status': 'started'};
        },
        jobStatusCallback: (jobId) async => {'ok': false},
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'start_job',
        input: const {'novel_id': 'novel_1', 'seed': '写第3章'},
      );

      expect(capturedNovelId, 'novel_1');
      expect(capturedSeed, '写第3章');
      expect(result, {'ok': true, 'job_id': 'run_new', 'status': 'started'});
    });

    test('missing novel_id returns error without invoking callback', () async {
      var callbackInvoked = false;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async {
          callbackInvoked = true;
          return {'ok': true};
        },
        jobStatusCallback: (jobId) async => {'ok': false},
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'start_job',
        input: const {'seed': '写第3章'},
      );

      expect(callbackInvoked, isFalse);
      expect(result['ok'], isFalse);
      expect(
        result['error'].toString(),
        contains('novel_id and seed are required'),
      );
    });

    test('missing seed returns error without invoking callback', () async {
      var callbackInvoked = false;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async {
          callbackInvoked = true;
          return {'ok': true};
        },
        jobStatusCallback: (jobId) async => {'ok': false},
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'start_job',
        input: const {'novel_id': 'novel_1'},
      );

      expect(callbackInvoked, isFalse);
      expect(result['ok'], isFalse);
      expect(
        result['error'].toString(),
        contains('novel_id and seed are required'),
      );
    });

    test('callback throws → caught and returned as ok:false error', () async {
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async {
          throw StateError('start_job boom');
        },
        jobStatusCallback: (jobId) async => {'ok': false},
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'start_job',
        input: const {'novel_id': 'novel_1', 'seed': 'go'},
      );

      expect(result['ok'], isFalse);
      expect(result['error'].toString(), contains('start_job boom'));
    });
  });

  group('AssistantToolDispatcher tool schema (Job ≠ Task)', () {
    // 锁定 job_id 契约：定位符直接用 Job 的 AiChatSession id，
    // 不再经 taskId 解析。Job 不是 Task（todo）。
    // chat_id / channel_type 不在工具 schema（coordinator 注入）。
    final dispatcher = AssistantToolDispatcher(
      listNovelsCallback: () async => const [],
      startJobCallback: (novelId, seed) async => {'ok': false},
      jobStatusCallback: (jobId) async => {'ok': true},
      sendToJobCallback: (jobId, text) async => {'ok': true},
      createNovelCallback: (novel) async => {'ok': false},
      editNovelCallback: (novelId, fields) async => {'ok': false},
    );

    test('job_status schema declares job_id, not task_id', () {
      final defs = dispatcher.allToolDefs();
      final jobStatusDef = defs.firstWhere((d) => d.name == 'job_status');
      final props = jobStatusDef.inputSchema['properties'] as Map;

      expect(
        props.containsKey('job_id'),
        isTrue,
        reason: 'job_status must accept job_id (AiChatSession id)',
      );
      expect(
        props.containsKey('task_id'),
        isFalse,
        reason: 'job_status must NOT accept task_id',
      );
      expect(jobStatusDef.inputSchema['required'], contains('job_id'));
    });

    test('send_to_job schema declares job_id, not task_id', () {
      final defs = dispatcher.allToolDefs();
      final sendToJobDef = defs.firstWhere((d) => d.name == 'send_to_job');
      final props = sendToJobDef.inputSchema['properties'] as Map;

      expect(props.containsKey('job_id'), isTrue);
      expect(props.containsKey('task_id'), isFalse);
      expect(sendToJobDef.inputSchema['required'], contains('job_id'));
      expect(sendToJobDef.inputSchema['required'], contains('text'));
    });

    test('start_job schema declares novel_id and seed (no chat context)', () {
      final defs = dispatcher.allToolDefs();
      final startJobDef = defs.firstWhere((d) => d.name == 'start_job');
      final props = startJobDef.inputSchema['properties'] as Map;

      expect(props.containsKey('novel_id'), isTrue);
      expect(props.containsKey('seed'), isTrue);
      expect(startJobDef.inputSchema['required'], contains('novel_id'));
      expect(startJobDef.inputSchema['required'], contains('seed'));
      // chat_id / channel_type 不在 schema — coordinator 从 inbound 上下文注入
      expect(props.containsKey('chat_id'), isFalse);
      expect(props.containsKey('channel_type'), isFalse);
    });

    test('does not expose the Run command tool', () {
      expect(dispatcher.allToolNames(), isNot(contains('Run')));
    });
  });

  group('AssistantToolDispatcher create_novel', () {
    test('passes populated novel map to callback and merges result', () async {
      Map<String, dynamic>? capturedNovel;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async => {'ok': false},
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async {
          capturedNovel = novel;
          return {'ok': true, 'novel_id': 'novel_new'};
        },
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'create_novel',
        input: const {
          'title': '我的新书',
          'description': '一个故事',
          'author_name': '阿明',
          'category': '玄幻',
          'type': 'original',
          'tags': ['a', 'b'],
        },
      );

      expect(result, {'ok': true, 'novel_id': 'novel_new'});
      expect(capturedNovel, {
        'title': '我的新书',
        'description': '一个故事',
        'author_name': '阿明',
        'category': '玄幻',
        'type': 'original',
        'tags': ['a', 'b'],
      });
    });

    test('missing title returns error without invoking callback', () async {
      var callbackInvoked = false;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async => {'ok': false},
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async {
          callbackInvoked = true;
          return {'ok': true};
        },
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'create_novel',
        input: const {'description': 'no title'},
      );

      expect(callbackInvoked, isFalse);
      expect(result['ok'], isFalse);
      expect(result['error'].toString(), contains('title is required'));
    });

    test('callback ok:false is respected', () async {
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async => {'ok': false},
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async {
          return {'ok': false, 'error': 'title conflict: 我的新书', 'exit_code': 1};
        },
        editNovelCallback: (novelId, fields) async => {'ok': false},
      );

      final result = await dispatcher.executeTool(
        name: 'create_novel',
        input: const {'title': '我的新书'},
      );

      expect(result['ok'], isFalse);
      expect(result['error'], contains('title conflict'));
    });
  });

  group('AssistantToolDispatcher edit_novel', () {
    test('passes novel_id and only-provided fields to callback', () async {
      String? capturedNovelId;
      Map<String, dynamic>? capturedFields;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async => {'ok': false},
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async {
          capturedNovelId = novelId;
          capturedFields = fields;
          return {'ok': true, 'novel_id': novelId};
        },
      );

      final result = await dispatcher.executeTool(
        name: 'edit_novel',
        input: const {
          'novel_id': 'novel_1',
          'title': '新标题',
          'tags': ['x'],
        },
      );

      expect(capturedNovelId, 'novel_1');
      // 只含用户指定字段 — 未指定的作者/分类/类型不出现
      expect(capturedFields, {
        'title': '新标题',
        'tags': ['x'],
      });
      expect(result, {'ok': true, 'novel_id': 'novel_1'});
    });

    test('accepts camelCase novelId as alt key (backward compat)', () async {
      String? capturedNovelId;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async => {'ok': false},
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async {
          capturedNovelId = novelId;
          return {'ok': true, 'novel_id': novelId};
        },
      );

      final result = await dispatcher.executeTool(
        name: 'edit_novel',
        input: const {'novelId': 'novel_alt', 'title': '改标题'},
      );

      expect(capturedNovelId, 'novel_alt');
      expect(result['ok'], isTrue);
    });

    test('missing novel_id returns error without invoking callback', () async {
      var callbackInvoked = false;
      final dispatcher = AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async => {'ok': false},
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async {
          callbackInvoked = true;
          return {'ok': true};
        },
      );

      final result = await dispatcher.executeTool(
        name: 'edit_novel',
        input: const {'title': '改标题'},
      );

      expect(callbackInvoked, isFalse);
      expect(result['ok'], isFalse);
      expect(result['error'].toString(), contains('novel_id is required'));
    });
  });

  group('AssistantToolDispatcher create/edit schema', () {
    final dispatcher = AssistantToolDispatcher(
      listNovelsCallback: () async => const [],
      startJobCallback: (novelId, seed) async => {'ok': false},
      jobStatusCallback: (jobId) async => {'ok': false},
      sendToJobCallback: (jobId, text) async => {'ok': false},
      createNovelCallback: (novel) async => {'ok': false},
      editNovelCallback: (novelId, fields) async => {'ok': false},
    );

    test('create_novel requires title, allows optional metadata', () {
      final defs = dispatcher.allToolDefs();
      final createDef = defs.firstWhere((d) => d.name == 'create_novel');
      final props = createDef.inputSchema['properties'] as Map;

      expect(createDef.inputSchema['required'], contains('title'));
      expect(props.containsKey('description'), isTrue);
      expect(props.containsKey('author_name'), isTrue);
      expect(props.containsKey('category'), isTrue);
      expect(props.containsKey('tags'), isTrue);
      expect(props.containsKey('type'), isTrue);
    });

    test('edit_novel requires novel_id, optional editable fields', () {
      final defs = dispatcher.allToolDefs();
      final editDef = defs.firstWhere((d) => d.name == 'edit_novel');
      final props = editDef.inputSchema['properties'] as Map;

      expect(editDef.inputSchema['required'], contains('novel_id'));
      expect(props.containsKey('title'), isTrue);
      expect(props.containsKey('description'), isTrue);
      expect(props.containsKey('author_name'), isTrue);
      expect(props.containsKey('category'), isTrue);
      expect(props.containsKey('tags'), isTrue);
      expect(props.containsKey('type'), isTrue);
    });
  });

  group('AssistantToolDispatcher list_chapters', () {
    AssistantToolDispatcher dispatcherFor(
      Future<Map<String, dynamic>> Function(String) listChapters,
    ) {
      return AssistantToolDispatcher(
        listNovelsCallback: () async => const [],
        startJobCallback: (novelId, seed) async => {'ok': false},
        jobStatusCallback: (jobId) async => {'ok': false},
        sendToJobCallback: (jobId, text) async => {'ok': false},
        createNovelCallback: (novel) async => {'ok': false},
        editNovelCallback: (novelId, fields) async => {'ok': false},
        listChaptersCallback: listChapters,
      );
    }

    List<Map<String, dynamic>> sampleChapters() => [
      {
        'id': 'ch_1',
        'chapter_num': 1,
        'title': '第 1 章 · 开端',
        'word_count': 800,
        'updated_at': '2026-08-01T00:00:00.000',
        'content': 'should not leak',
      },
      {
        'id': 'ch_2',
        'chapter_num': 2,
        'title': '第 2 章 · 转折',
        'word_count': 900,
        'updated_at': '2026-08-10T00:00:00.000',
        'body': 'should not leak either',
      },
      {
        'id': 'ch_3',
        'chapter_num': 3,
        'title': '第 3 章 · 高潮',
        'word_count': 1200,
        'updated_at': '2026-08-14T00:00:00.000',
      },
    ];

    test('filters by chapter_nums and never returns body', () async {
      final dispatcher = dispatcherFor(
        (novelId) async => {
          'ok': true,
          'novel_id': novelId,
          'title': '测试',
          'chapters': sampleChapters(),
        },
      );

      final result = await dispatcher.executeTool(
        name: 'list_chapters',
        input: const {
          'novel_id': 'novel_1',
          'chapter_nums': [3, 1],
        },
      );

      expect(result['ok'], isTrue);
      expect(result['matched_count'], 2);
      final chapters = result['chapters'] as List;
      expect(chapters, hasLength(2));
      expect(chapters.map((c) => (c as Map)['id']), ['ch_1', 'ch_3']);
      for (final chapter in chapters) {
        final map = chapter as Map;
        expect(map.containsKey('content'), isFalse);
        expect(map.containsKey('body'), isFalse);
        expect(map.containsKey('chapter_num'), isTrue);
      }
    });

    test('range filter then caps by limit', () async {
      final dispatcher = dispatcherFor(
        (novelId) async => {
          'ok': true,
          'novel_id': novelId,
          'chapters': [
            for (var i = 1; i <= 8; i++)
              {
                'id': 'ch_$i',
                'chapter_num': i,
                'title': '第 $i 章',
                'word_count': i * 100,
                'updated_at': '2026-08-01T00:00:00.000',
              },
          ],
        },
      );

      final result = await dispatcher.executeTool(
        name: 'list_chapters',
        input: const {
          'novel_id': 'novel_1',
          'from_chapter_num': 2,
          'to_chapter_num': 7,
          'limit': 3,
        },
      );

      expect(result['ok'], isTrue);
      expect(result['matched_count'], 6);
      final chapters = result['chapters'] as List;
      expect(chapters, hasLength(3));
      expect(chapters.map((c) => (c as Map)['chapter_num']), [2, 3, 4]);
    });

    test(
      'no filter returns most recently updated, not the full catalog',
      () async {
        final dispatcher = dispatcherFor(
          (novelId) async => {
            'ok': true,
            'novel_id': novelId,
            'chapters': [
              for (var i = 1; i <= 30; i++)
                {
                  'id': 'ch_$i',
                  'chapter_num': i,
                  'title': '第 $i 章',
                  'word_count': 100,
                  'updated_at': DateTime.utc(2026, 1, i).toIso8601String(),
                },
            ],
          },
        );

        final result = await dispatcher.executeTool(
          name: 'list_chapters',
          input: const {'novel_id': 'novel_1'},
        );

        expect(result['ok'], isTrue);
        expect(result['matched_count'], 30);
        final chapters = result['chapters'] as List;
        expect(chapters, hasLength(20));
        expect((chapters.first as Map)['id'], 'ch_30');
        expect((chapters.last as Map)['id'], 'ch_11');
      },
    );

    test('clamps limit to 50', () async {
      final dispatcher = dispatcherFor(
        (novelId) async => {
          'ok': true,
          'novel_id': novelId,
          'chapters': [
            for (var i = 1; i <= 80; i++)
              {
                'id': 'ch_$i',
                'chapter_num': i,
                'title': '第 $i 章',
                'word_count': 10,
                'updated_at': '2026-08-01T00:00:00.000',
              },
          ],
        },
      );

      final result = await dispatcher.executeTool(
        name: 'list_chapters',
        input: const {
          'novel_id': 'novel_1',
          'from_chapter_num': 1,
          'to_chapter_num': 80,
          'limit': 999,
        },
      );

      expect(result['ok'], isTrue);
      expect(result['matched_count'], 80);
      expect(result['chapters'], hasLength(50));
    });

    test('filters by title substring, case-insensitive', () async {
      final dispatcher = dispatcherFor(
        (novelId) async => {
          'ok': true,
          'novel_id': novelId,
          'chapters': [
            ...sampleChapters(),
            {
              'id': 'ch_extra',
              'chapter_num': 4,
              'title': 'The Opening Storm',
              'word_count': 100,
              'updated_at': '2026-08-15T00:00:00.000',
            },
          ],
        },
      );

      final result = await dispatcher.executeTool(
        name: 'list_chapters',
        input: const {'novel_id': 'novel_1', 'title': 'opening'},
      );

      expect(result['ok'], isTrue);
      expect(result['matched_count'], 1);
      expect(((result['chapters'] as List).first as Map)['id'], 'ch_extra');
    });

    test('title filter ANDs with chapter_nums', () async {
      final dispatcher = dispatcherFor(
        (novelId) async => {
          'ok': true,
          'novel_id': novelId,
          'chapters': sampleChapters(),
        },
      );

      final result = await dispatcher.executeTool(
        name: 'list_chapters',
        input: const {
          'novel_id': 'novel_1',
          'chapter_nums': [1, 2],
          'title': '转折',
        },
      );

      expect(result['ok'], isTrue);
      expect(result['matched_count'], 1);
      expect(((result['chapters'] as List).first as Map)['id'], 'ch_2');
    });

    test('missing novel_id returns error without invoking callback', () async {
      var callbackInvoked = false;
      final dispatcher = dispatcherFor((novelId) async {
        callbackInvoked = true;
        return {'ok': true};
      });

      final result = await dispatcher.executeTool(
        name: 'list_chapters',
        input: const {},
      );

      expect(callbackInvoked, isFalse);
      expect(result['ok'], isFalse);
      expect(result['error'].toString(), contains('novel_id is required'));
    });
  });
}
