// 职责: 测试 AI 会话持久化服务 — 验证消息快照落库规则。
// 关联文件:
//   lib/shared/services/ai/session_persistence.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/ai_chat_models.dart
//   lib/shared/agent/agent_context_manager.dart
//   lib/shared/services/ai/context_message_matcher.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:reveric/shared/utils/storage_paths.dart';
import 'package:reveric/shared/services/ai/files/session_files.dart';
import 'package:drift/native.dart';
import 'package:reveric/shared/services/ai/tool_operations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_context_manager.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/ai_session_mode.dart';
import 'package:reveric/shared/models/ask_user_models.dart';
import 'package:reveric/shared/services/ai/agent_message_mapping.dart';
import 'package:reveric/shared/services/ai/context_message_matcher.dart';
import 'package:reveric/shared/services/ai/session_persistence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDb;
  late NovelContentDatabase novelDb;
  late AiSessionPersistenceService service;

  setUp(() {
    appDb = AppDatabase.forTest(NativeDatabase.memory());
    novelDb = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = AiSessionPersistenceService(appDb, 'novel_1');
  });

  tearDown(() async {
    await novelDb.close();
    await appDb.close();
  });

  group('feedback context', () {
    test(
      'exports descendants once with full tools and run references',
      () async {
        await service.upsertSession(id: 'root', title: 'Write chapters');
        await service.upsertSession(
          id: 'writer',
          title: 'Writer',
          parentId: 'root',
          model: 'writer-model',
          agentSlug: 'writer',
          metadata: {'spawn_run_id': 'run_2', 'spawn_run_status': 'completed'},
        );
        await service.upsertSession(
          id: 'review',
          title: 'Review',
          parentId: 'writer',
        );
        await service.saveMessages(
          sessionId: 'root',
          novelDatabase: novelDb,
          messages: [
            for (final run in ['run_1', 'run_2'])
              AiMessage.assistant(
                id: 'spawn_$run',
                content: '',
                blocks: [
                  AiToolCallBlock(
                    id: 'block_$run',
                    callId: 'call_$run',
                    toolName: 'SpawnAgent',
                    arguments: {'task': run, 'session_id': 'writer'},
                    status: AiToolCallStatus.success,
                    result: {'session_id': 'writer', 'run_id': run},
                  ),
                ],
              ),
          ],
        );
        await service.saveMessages(
          sessionId: 'writer',
          novelDatabase: novelDb,
          messages: [
            AiMessage.assistant(
              id: 'writer_read',
              content: '',
              blocks: const [
                AiToolCallBlock(
                  id: 'read_block',
                  callId: 'read_call',
                  toolName: 'Read',
                  arguments: {
                    'path': 'chapters/one/content',
                    'offset': 20,
                    'limit': 5,
                  },
                  status: AiToolCallStatus.success,
                  result: {
                    'value': '完整正文片段',
                    'has_more': true,
                    'next_offset': 25,
                  },
                ),
              ],
            ),
          ],
        );

        final payload =
            jsonDecode(
                  jsonEncode(
                    await service.loadFeedbackContext(
                      sessionId: 'root',
                      novelDatabase: novelDb,
                    ),
                  ),
                )
                as Map<String, dynamic>;
        expect(payload['session_count'], 3);
        expect(payload['total_message_count'], 3);
        final children = (payload['sub_sessions'] as List)
            .cast<Map<String, dynamic>>();
        expect(children.map((s) => s['session_id']), ['writer', 'review']);
        expect(children.last['parent_session_id'], 'writer');
        expect(children.first['model'], 'writer-model');
        expect(children.first['metadata']['spawn_run_id'], 'run_2');
        final tool = children.first['messages'][0]['blocks'][0];
        expect(tool['arguments'], {
          'path': 'chapters/one/content',
          'offset': 20,
          'limit': 5,
        });
        expect(tool['result']['value'], '完整正文片段');
        expect(tool['result']['next_offset'], 25);
        expect(
          (payload['messages'] as List).map(
            (m) => m['blocks'][0]['result']['run_id'],
          ),
          ['run_1', 'run_2'],
        );
      },
    );

    test(
      'finds paginated children without spawn messages and excludes unrelated data',
      () async {
        await service.upsertSession(id: 'root', title: 'Compacted parent');
        for (var i = 0; i < 23; i++) {
          await service.upsertSession(
            id: 'child_$i',
            title: '$i',
            parentId: 'root',
          );
        }
        await service.upsertSession(
          id: 'unrelated',
          title: 'Other conversation',
        );
        await service.upsertSession(
          id: 'deleted',
          title: 'Deleted',
          parentId: 'root',
        );
        await appDb.aiChatSessionDao.softDelete('deleted', novelId: 'novel_1');
        await appDb.aiChatSessionDao.upsert(
          id: 'other_work',
          novelId: 'novel_2',
          title: 'Other work',
          parentId: 'root',
        );
        final payload = await service.loadFeedbackContext(
          sessionId: 'root',
          novelDatabase: novelDb,
        );
        final children = (payload['sub_sessions'] as List)
            .cast<Map<String, dynamic>>();
        expect(children.map((s) => s['session_id']).toSet(), {
          for (var i = 0; i < 23; i++) 'child_$i',
        });
        expect(payload['session_count'], 24);
      },
    );

    test(
      'marks unfinished records and terminates malformed parent cycles',
      () async {
        await service.upsertSession(
          id: 'root',
          title: 'Root',
          parentId: 'child',
        );
        await service.upsertSession(
          id: 'child',
          title: 'Running',
          parentId: 'root',
          metadata: {'spawn_run_status': 'running'},
        );
        await service.upsertSession(
          id: 'failed_save',
          title: 'Failed save',
          parentId: 'root',
          metadata: {
            'spawn_run_status': 'completed',
            'spawn_persistence_error_code': 'spawn_message_persistence_failed',
          },
        );
        final payload = await service.loadFeedbackContext(
          sessionId: 'root',
          novelDatabase: novelDb,
        );
        expect(payload['session_count'], 3);
        expect(payload['message_source'], 'persisted');
        expect(
          payload['incomplete_session_ids'],
          unorderedEquals(['child', 'failed_save']),
        );
      },
    );

    test(
      'fails instead of returning a partial package when a child cannot be read',
      () async {
        await service.upsertSession(id: 'root', title: 'Root');
        await service.upsertSession(
          id: 'broken',
          title: 'Broken',
          parentId: 'root',
        );
        final failing = _FeedbackReadFailurePersistence(appDb, 'novel_1');
        await expectLater(
          failing.loadFeedbackContext(
            sessionId: 'root',
            novelDatabase: novelDb,
          ),
          throwsStateError,
        );
        await expectLater(
          service.loadFeedbackContext(
            sessionId: 'missing',
            novelDatabase: novelDb,
          ),
          throwsStateError,
        );
      },
    );
  });

  test(
    'explicit selection reactivates cached history and invalid active pointers stay empty',
    () async {
      final sessions = AiSessionPersistenceService(
        appDb,
        'novel_1',
        novelContentDatabase: novelDb,
      );
      expect(
        effectiveAiChatSessionId(novelId: 'novel_1', activeId: null),
        isNull,
      );
      await sessions.createActiveSession(id: 'a', title: 'A');
      await sessions.createActiveSession(id: 'b', title: 'B');
      await sessions.activateSession('a');
      expect((await sessions.getPreferredSession())?.id, 'a');
      await sessions.createActiveSession(
        id: 'child',
        title: 'Child',
        parentId: 'a',
      );
      await sessions.activateSession('child');
      expect((await sessions.getPreferredSession())?.id, 'a');
      await sessions.activateSession('b', isCurrent: () => false);
      expect((await sessions.getPreferredSession())?.id, 'a');
      for (final id in ['child', 'missing']) {
        await novelDb.novelStateDao.setActiveChatSessionId(id);
        expect(await sessions.getPreferredSession(), isNull);
        expect(await sessions.watchActiveSessionId().first, isNull);
      }
    },
  );

  test(
    'late child operation patches its original record and stale saves retain terminal summary',
    () async {
      final registry = ToolOperationRegistry();
      final operation = ToolOperationRecord(
        runId: 'run',
        ownerSessionId: 'parent',
        sourceSessionId: 'child',
        sourceTurnId: 'turn',
        callId: 'call',
        workId: 'novel_1',
        kind: 'editing.preview',
        targetPath: '/editings/one',
        background: true,
        createdAt: DateTime.now(),
        status: ToolOperationStatus.running,
      );
      registry.records[operation.runId] = operation;
      final persistence = AiSessionPersistenceService(
        appDb,
        'novel_1',
        novelContentDatabase: novelDb,
        operationRecords: registry.forSession,
      );
      final message = AiMessage.assistant(
        id: 'assistant',
        content: '',
        blocks: const [
          AiToolCallBlock(
            id: 'block',
            callId: 'call',
            toolName: 'Run',
            arguments: {},
            status: AiToolCallStatus.success,
            result: {'ok': true, 'run_id': 'run'},
          ),
        ],
      );
      await persistence.saveMessages(
        sessionId: 'child',
        messages: [message],
        novelDatabase: novelDb,
      );
      await persistence.saveMessages(
        sessionId: 'other',
        messages: [AiMessage.user(id: 'other', content: 'unrelated')],
        novelDatabase: novelDb,
      );
      operation.status = ToolOperationStatus.completed;
      operation.result = {
        'ok': true,
        'files': ['preview.mp4'],
      };
      await persistence.saveToolOperation(operation);
      Future<Map<String, dynamic>> snapshot() async {
        final row = (await novelDb.aiChatMessageDao.getBySession(
          'child',
        )).single;
        return ((row.blocks!.single as AiToolCallBlock).metadata!['operations']
                    as List)
                .single
            as Map<String, dynamic>;
      }

      expect((await snapshot())['status'], 'completed');
      expect((await snapshot())['result'], operation.result);
      await persistence.saveMessages(
        sessionId: 'child',
        messages: [message],
        novelDatabase: novelDb,
      );
      expect((await snapshot())['status'], 'completed');
      operation.status = ToolOperationStatus.running;
      await persistence.saveMessages(
        sessionId: 'child',
        messages: [message],
        novelDatabase: novelDb,
      );
      registry.records.clear();
      final recovered = await persistence.loadSessionMessages(
        sessionId: 'child',
        novelDatabase: novelDb,
      );
      final recoveredSnapshot =
          ((recovered.messages.single.blocks.single as AiToolCallBlock)
                          .metadata!['operations']
                      as List)
                  .single
              as Map;
      expect(recoveredSnapshot['status'], 'interrupted');
      expect((recoveredSnapshot['result'] as Map)['error_code'], 'interrupted');
      expect(
        (await novelDb.aiChatMessageDao.getBySession('other')).single.content,
        'unrelated',
      );
    },
  );

  group('AiSessionPersistenceService.saveMessages', () {
    test('syncs completed messages and removes old rows', () async {
      await service.saveMessages(
        sessionId: 'session_1',
        novelDatabase: novelDb,
        messages: [
          AiMessage.user(id: 'user_1', content: 'plan today'),
          AiMessage.assistant(id: 'assistant_1', content: 'old answer'),
        ],
      );

      await service.saveMessages(
        sessionId: 'session_1',
        novelDatabase: novelDb,
        messages: [AiMessage.user(id: 'user_1', content: 'plan today')],
      );

      final rows = await novelDb.aiChatMessageDao.getBySession('session_1');

      expect(rows.map((row) => row.id), ['user_1']);
    });

    test(
      'does not insert a second compact_summary when UI already has the same id',
      () async {
        const sessionId = 'session_1';
        final summaryId = compactSummaryMessageId(sessionId, 1);
        await service.saveMessages(
          sessionId: sessionId,
          novelDatabase: novelDb,
          messages: [
            AiMessage.user(
              id: summaryId,
              content: '已完成：初始化引导',
              type: AiMessageType.compact_summary,
              metadata: buildCompactSummaryMetadata(
                compactionCount: 1,
                replayFromMessageId: 'continue_late',
              ),
            ),
            AiMessage.user(id: 'continue_late', content: '继续'),
            AiMessage.assistant(id: 'recent', content: '写第 15 章'),
          ],
          contextSnapshot: AgentContextSnapshot(
            messages: [
              AgentMessage.user(id: 'continue_late', content: '继续'),
              AgentMessage.assistant(id: 'asst_recent', content: '写第 15 章'),
            ],
            summary: '已完成：初始化引导',
            compactionCount: 1,
          ),
        );

        final rows = await novelDb.aiChatMessageDao.getBySession(sessionId);

        expect(rows.map((row) => row.id), [
          summaryId,
          'continue_late',
          'recent',
        ]);
        expect(rows.map((row) => row.sequence), [0, 1, 2]);
      },
    );

    test(
      'inserts compact_summary once when the UI list does not yet have it',
      () async {
        const sessionId = 'session_1';
        await service.saveMessages(
          sessionId: sessionId,
          novelDatabase: novelDb,
          messages: [
            AiMessage.user(id: 'continue_late', content: '继续'),
            AiMessage.assistant(id: 'recent', content: '写第 15 章'),
          ],
          contextSnapshot: AgentContextSnapshot(
            messages: [
              AgentMessage.user(id: 'continue_late', content: '继续'),
              AgentMessage.assistant(id: 'asst_recent', content: '写第 15 章'),
            ],
            summary: '已完成：初始化引导',
            compactionCount: 1,
          ),
        );

        final rows = await novelDb.aiChatMessageDao.getBySession(sessionId);
        final summaryId = compactSummaryMessageId(sessionId, 1);

        expect(rows.map((row) => row.id), [
          summaryId,
          'continue_late',
          'recent',
        ]);
        expect(rows.map((row) => row.sequence), [0, 1, 2]);
      },
    );
  });

  group('AiSessionPersistenceService.upsertCompletedMessages', () {
    test(
      'round-trips timeout source, automatic answers and unanswered IDs',
      () async {
        const block = AiAskUserBlock(
          id: 'ask',
          callId: 'call',
          questions: [
            {'id': 'choice', 'question': 'Choice'},
            {'id': 'text', 'question': 'Text'},
          ],
          status: AiAskUserStatus.timed_out,
          resolution: AskUserResolution.timeout,
          answers: [
            {
              'question_id': 'choice',
              'selected_options': ['Recommended'],
            },
          ],
          unansweredQuestionIds: ['text'],
        );
        await service.upsertCompletedMessages(
          sessionId: 'session_1',
          novelDatabase: novelDb,
          messages: [
            AiMessage.assistant(
              id: 'assistant',
              content: '',
              blocks: const [block],
            ),
          ],
        );
        final rows = await novelDb.aiChatMessageDao.getBySession('session_1');
        final restored = rows.single.blocks!.single as AiAskUserBlock;
        expect(restored.toJson(), block.toJson());
        expect(restored.isPending, false);
      },
    );

    test(
      'persists only completed messages while a later message is streaming',
      () async {
        await service.upsertCompletedMessages(
          sessionId: 'session_1',
          novelDatabase: novelDb,
          messages: [
            AiMessage.user(id: 'user_1', content: 'plan today'),
            AiMessage.assistant(
              id: 'assistant_1',
              content: 'completed answer',
              blocks: const [
                AiTextBlock(id: 'text_1', text: 'completed answer'),
              ],
            ),
            AiMessage.assistant(
              id: 'assistant_2',
              content: 'partial answer',
              isStreaming: true,
              blocks: const [AiTextBlock(id: 'text_2', text: 'partial answer')],
            ),
          ],
        );

        final rows = await novelDb.aiChatMessageDao.getBySession('session_1');

        expect(rows.map((row) => row.id), ['user_1', 'assistant_1']);
        expect(rows.last.role, AiMessageRole.assistant.name);
        expect(rows.last.content, 'completed answer');
        expect(rows.last.blocks, isNotEmpty);
      },
    );

    test('does not persist messages with active tool calls', () async {
      await service.upsertCompletedMessages(
        sessionId: 'session_1',
        novelDatabase: novelDb,
        messages: [
          AiMessage.user(id: 'user_1', content: 'plan today'),
          AiMessage.assistant(
            id: 'assistant_1',
            content: '',
            blocks: const [
              AiToolCallBlock(
                id: 'tool_1',
                callId: 'call_1',
                toolName: 'Read',
                arguments: {'path': 'chapters'},
                status: AiToolCallStatus.running,
              ),
            ],
          ),
        ],
      );

      final rows = await novelDb.aiChatMessageDao.getBySession('session_1');

      expect(rows.map((row) => row.id), ['user_1']);
    });

    test('does not delete existing rows outside the upsert batch', () async {
      await service.saveMessages(
        sessionId: 'session_1',
        novelDatabase: novelDb,
        messages: [AiMessage.user(id: 'user_1', content: 'plan today')],
      );

      await service.upsertCompletedMessages(
        sessionId: 'session_1',
        novelDatabase: novelDb,
        messages: [
          AiMessage.assistant(id: 'assistant_1', content: 'new answer'),
        ],
      );

      final rows = await novelDb.aiChatMessageDao.getBySession('session_1');

      expect(rows.map((row) => row.id), ['user_1', 'assistant_1']);
    });
  });

  group('AiSessionPersistenceService.forkSession', () {
    test(
      'fork owns its attachment copies after source session cleanup',
      () async {
        final root = await Directory.systemTemp.createTemp('chat_fork_');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channel = MethodChannel('plugins.flutter.io/path_provider');
        messenger.setMockMethodCallHandler(channel, (call) async => root.path);
        addTearDown(() async {
          messenger.setMockMethodCallHandler(channel, null);
          await root.delete(recursive: true);
        });
        await RevericPaths.initialize();
        final files = SessionFiles(novelId: 'novel_1');
        final file = await files.allocate('source', '.txt');
        await file.writeAsString('durable source');
        await service.createActiveSession(id: 'source', title: 'Source');
        await service.saveMessages(
          sessionId: 'source',
          novelDatabase: novelDb,
          messages: [
            AiMessage.user(
              id: 'user_file',
              content: '[notes.txt]',
              blocks: [
                AiAttachmentBlock(
                  id: 'attached',
                  name: 'notes.txt',
                  path: files.reference(file),
                  mimeType: 'text/plain',
                ),
              ],
            ),
            AiMessage.assistant(id: 'answer', content: 'Read'),
          ],
        );
        final fork = await service.forkSession(
          sourceSessionId: 'source',
          cutAtSourceId: 'answer',
          titleSuffix: 'Copy',
          novelDatabase: novelDb,
        );
        final saved = await service.loadSessionMessages(
          sessionId: fork,
          novelDatabase: novelDb,
        );
        final attachment = saved.messages.first.blocks
            .whereType<AiAttachmentBlock>()
            .single;
        expect(
          attachment.path,
          startsWith('file_workspaces/novel_1/sessions/$fork/'),
        );
        await files.deleteSessions(['source']);
        expect(
          await (await files.resolve(attachment.path)).readAsString(),
          'durable source',
        );
      },
    );

    for (final summaryBeforeRetained in [true, false]) {
      test('preserves compacted replay when summaryBeforeRetained='
          '$summaryBeforeRetained', () async {
        const sessionId = 'compacted_source';
        final summary = AiMessage.user(
          id: compactSummaryMessageId(sessionId, 1),
          content: '压缩摘要',
          type: AiMessageType.compact_summary,
          metadata: buildCompactSummaryMetadata(
            compactionCount: 1,
            replayFromMessageId: 'current_user',
            tokensBefore: 180000,
            tokensAfter: 48000,
          ),
        );
        final messages = [
          AiMessage.user(id: 'overflow', content: '已压缩的旧请求'),
          if (summaryBeforeRetained) summary,
          AiMessage.user(id: 'current_user', content: '当前请求'),
          AiMessage.assistant(id: 'step', content: '压缩前步骤'),
          if (!summaryBeforeRetained) summary,
          AiMessage.assistant(id: 'final', content: '压缩后回答'),
          AiMessage.user(id: 'future', content: '分叉点之后的请求'),
        ];
        await service.createActiveSession(id: sessionId, title: '原会话');
        await service.saveMessages(
          sessionId: sessionId,
          messages: messages,
          novelDatabase: novelDb,
        );
        final sourceBeforeFork = await service.loadSessionMessages(
          sessionId: sessionId,
          novelDatabase: novelDb,
        );

        final forkedId = await service.forkSession(
          sourceSessionId: sessionId,
          cutAtSourceId: 'final',
          titleSuffix: '副本',
          novelDatabase: novelDb,
        );
        final forked = await service.loadSessionMessages(
          sessionId: forkedId,
          novelDatabase: novelDb,
        );
        final restored = restorePersistedChatContext(forked.messages);
        expect(restored.summary, summary.content);
        expect(restored.compactionCount, 1);
        expect(restored.lastCompactionTokensBefore, 180000);
        expect(restored.lastCompactionTokensAfter, 48000);
        expect(restored.retainedMessages.map((message) => message.content), [
          '当前请求',
          '压缩前步骤',
          '压缩后回答',
        ]);
        final forkedSummary = forked.messages.singleWhere(
          (message) => message.type == AiMessageType.compact_summary,
        );
        expect(
          compactReplayFromMessageId(forkedSummary.metadata),
          restored.retainedMessages.first.id,
        );
        expect(
          forked.messages
              .map((message) => message.id)
              .toSet()
              .intersection(messages.map((message) => message.id).toSet()),
          isEmpty,
        );
        final source = await service.loadSessionMessages(
          sessionId: sessionId,
          novelDatabase: novelDb,
        );
        expect(
          source.messages.map((message) => message.toJson()),
          sourceBeforeFork.messages.map((message) => message.toJson()),
        );
      });
    }

    test(
      'copies messages up to and including the cut point with regenerated ids, '
      'leaving the source session untouched',
      () async {
        await service.createActiveSession(
          id: 'session_1',
          title: '原会话',
          mode: AiSessionMode.chat.value,
        );
        await service.saveMessages(
          sessionId: 'session_1',
          novelDatabase: novelDb,
          messages: [
            AiMessage.user(id: 'user_1', content: '问'),
            AiMessage.assistant(id: 'assistant_1', content: '答一'),
            AiMessage.user(id: 'user_2', content: '再问'),
            AiMessage.assistant(id: 'assistant_2', content: '答二'),
          ],
        );

        // 从 assistant_1 处分叉：应只保留它及之前的消息。
        final forkedId = await service.forkSession(
          sourceSessionId: 'session_1',
          cutAtSourceId: 'assistant_1',
          titleSuffix: '副本',
          novelDatabase: novelDb,
        );

        // 新会话继承标题并带后缀。
        final forkedSession = await service.getSession(forkedId);
        expect(forkedSession, isNotNull);
        expect(forkedSession!.title, '原会话 (副本)');

        // 截断点之后的消息不复制；id 全部重新生成，不与源会话冲突。
        final forkedRows = await novelDb.aiChatMessageDao.getBySession(
          forkedId,
        );
        expect(forkedRows.map((r) => r.role), ['user', 'assistant']);
        expect(forkedRows.map((r) => r.content), ['问', '答一']);
        expect(forkedRows.map((r) => r.id), isNot(contains('user_1')));
        expect(forkedRows.map((r) => r.id), isNot(contains('assistant_1')));

        // 源会话消息原样保留。
        final sourceRows = await novelDb.aiChatMessageDao.getBySession(
          'session_1',
        );
        expect(sourceRows.map((r) => r.id), [
          'user_1',
          'assistant_1',
          'user_2',
          'assistant_2',
        ]);
      },
    );
  });

  group('AiSessionPersistenceService.upsertSession', () {
    test('persists reasoning effort on session row', () async {
      await service.upsertSession(
        id: 'session_1',
        title: 'Test',
        provider: 'openai',
        model: 'gpt-5',
        reasoningEffort: 'high',
      );

      final session = await service.getSession('session_1');
      expect(session?.reasoningEffort, 'high');
      expect(reasoningEffortFromSession(session!), 'high');
    });
  });
}

class _FeedbackReadFailurePersistence extends AiSessionPersistenceService {
  _FeedbackReadFailurePersistence(super.appDatabase, super.novelId);

  @override
  Future<PersistedAiChatSessionData> loadSessionMessages({
    required String sessionId,
    required NovelContentDatabase novelDatabase,
  }) {
    if (sessionId == 'broken') {
      throw StateError('Cannot read child messages');
    }
    return super.loadSessionMessages(
      sessionId: sessionId,
      novelDatabase: novelDatabase,
    );
  }
}
