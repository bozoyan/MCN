// 职责: 测试 AskUser 工具的多问题解析、回调透传与结果序列化
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_ask_user.dart
//   lib/shared/models/ask_user_models.dart

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/ai/trace_reporter_service.dart';
import 'package:reveric/shared/services/anonymous_outbox_service.dart';
import 'package:reveric/shared/services/device_id_service.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AskUser', () {
    late NovelContentDatabase db;
    late AppDatabase appDb;
    late NovelContentService contentService;

    setUp(() {
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      appDb = AppDatabase.forTest(NativeDatabase.memory());
      contentService = NovelContentService(db);
    });

    tearDown(() async {
      await db.close();
      await appDb.close();
    });

    AiToolManager managerFor(AiAskUserCallback callback) {
      return AiToolManager(
        contentService,
        workingOverlayService: WorkingOverlayService(
          db,
          contentService,
          novelActionsService: NovelActionsService(appDb),
        ),
        askUserCallback: callback,
      )..registerAllTools();
    }

    for (final encodeQuestions in [false, true]) {
      test(
        'accepts JSON array strings (questions encoded: $encodeQuestions)',
        () async {
          AskUserRequest? captured;
          final manager = managerFor((request) async {
            captured = request;
            return const AskUserResult(ok: true);
          });
          final questions = [
            {
              'question': 'Continue?',
              'options': jsonEncode([
                {'label': 'Yes', 'recommended': true},
                'No',
              ]),
              'allow_free_text': false,
            },
          ];
          final result = await manager.executeTool(
            name: 'AskUser',
            input: {
              'questions': encodeQuestions ? jsonEncode(questions) : questions,
            },
          );
          expect(result['ok'], true);
          expect(captured?.questions.single.question, 'Continue?');
          expect(captured!.questions.single.options!.map((o) => o.label), [
            'Yes',
            'No',
          ]);
          expect(captured!.questions.single.options!.first.recommended, true);
          expect(captured!.questions.single.allowFreeText, false);
        },
      );
    }

    test('optional options and empty questions retain their meaning', () async {
      var calls = 0;
      final manager = managerFor((request) async {
        calls++;
        expect(request.questions.single.options, isNull);
        expect(request.questions.single.allowFreeText, true);
        return const AskUserResult(ok: true);
      });
      for (final question in [
        {'question': 'Continue?'},
        {'question': 'Continue?', 'options': null},
        {'question': 'Continue?', 'options': <Object>[]},
      ]) {
        final result = await manager.executeTool(
          name: 'AskUser',
          input: {
            'questions': [question],
          },
        );
        expect(result['ok'], true);
      }
      for (final input in <Map<String, dynamic>>[
        {},
        {'questions': null},
        {'questions': <Object>[]},
        {'questions': '[]'},
      ]) {
        final result = await manager.executeTool(name: 'AskUser', input: input);
        expect(result['ok'], false);
        expect(result['error_code'], 'invalid_argument');
      }
      expect(calls, 3);
    });

    for (final entry in <String, Object>{
      'plain text': 'PRIVATE_QUESTION',
      'truncated JSON': '["PRIVATE_QUESTION"',
      'JSON object': '{"question":"PRIVATE_QUESTION"}',
      'object': {'question': 'PRIVATE_QUESTION'},
      'boolean': true,
      'number': 12,
    }.entries) {
      for (final field in ['questions', 'questions[1].options']) {
        test(
          'rejects ${entry.key} at $field with actionable feedback',
          () async {
            var calls = 0;
            final manager = managerFor((_) async {
              calls++;
              return const AskUserResult(ok: true);
            });
            final result = await manager.executeTool(
              name: 'AskUser',
              input: {
                'questions': field == 'questions'
                    ? entry.value
                    : [
                        {'question': 'First valid question?'},
                        {
                          'question': 'PRIVATE_QUESTION',
                          'options': entry.value,
                        },
                      ],
              },
            );
            expect(calls, 0);
            expect(result['ok'], false);
            expect(result['error_code'], 'invalid_argument');
            expect(result['error'], contains(field));
            expect(result['error'], contains('received'));
            expect(result['hint'], contains('JSON arrays'));
            expect(jsonEncode(result), isNot(contains('PRIVATE_QUESTION')));
            expect(jsonEncode(result), isNot(contains('TypeError')));
          },
        );
      }
    }

    test(
      'callback format errors remain internal failures with safe feedback',
      () async {
        final manager = managerFor((_) async {
          throw const FormatException('PRIVATE_CALLBACK_DETAIL');
        });
        final result = await manager.executeTool(
          name: 'AskUser',
          input: {
            'questions': ['Continue?'],
          },
        );
        expect(result['ok'], false);
        expect(result['error_code'], 'internal');
        expect(result['error'], 'AskUser could not complete the request.');
      },
    );

    test(
      'array shape failure reaches outbox without question or option text',
      () async {
        SharedPreferences.setMockInitialValues({'device_id': 'test-device'});
        final input = {
          'questions': [
            {'question': 'PRIVATE_QUESTION', 'options': 'PRIVATE_OPTION'},
          ],
        };
        var called = false;
        final result = await managerFor((_) async {
          called = true;
          return const AskUserResult(ok: true);
        }).executeTool(name: 'AskUser', input: input);
        final outbox = AnonymousOutboxService(
          database: appDb,
          httpClient: MockClient((_) async => throw UnimplementedError()),
          getBaseUrl: () => null,
          getEnabled: () => true,
          autoFlush: false,
        );
        try {
          await TraceReporterService(
            deviceIdService: DeviceIdService(),
            outbox: outbox,
          ).onToolCallError(
            'test-session',
            'test-model',
            'AskUser',
            result: result,
            toolInput: input,
          );
          final row =
              (await appDb.select(appDb.anonymousOutboxEvents).get()).single;
          final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
          expect(called, false);
          expect(payload['error_code'], 'invalid_argument');
          expect(
            payload['exception_message'],
            contains('questions[0].options'),
          );
          expect(payload['exception_message'], contains('received string'));
          expect(row.payloadJson, isNot(contains('PRIVATE_QUESTION')));
          expect(row.payloadJson, isNot(contains('PRIVATE_OPTION')));
        } finally {
          outbox.dispose();
        }
      },
    );

    test('parses multiple questions and returns structured answers', () async {
      AskUserRequest? capturedRequest;
      final overlay = WorkingOverlayService(
        db,
        contentService,
        novelActionsService: NovelActionsService(appDb),
      );
      final toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay,
        askUserCallback: (request) async {
          capturedRequest = request;
          return const AskUserResult(
            ok: true,
            answers: [
              AskUserAnswer(
                questionId: 'genre',
                selectedOptions: ['悬疑'],
                answer: '偏黑色电影一点',
              ),
              AskUserAnswer(questionId: 'ending', answer: '收在不安感上'),
            ],
          );
        },
      )..registerAllTools();

      final result = await toolManager.executeTool(
        name: 'AskUser',
        input: {
          'questions': [
            {
              'id': 'genre',
              'question': '这段剧情更偏向什么类型？',
              'options': [
                {'label': '悬疑'},
                {'label': '恋爱'},
              ],
              'allow_free_text': true,
            },
            {'id': 'ending', 'question': '这一章以什么情绪收束？'},
          ],
        },
        callId: 'call_ask_user_test',
      );

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.callId, 'call_ask_user_test');
      expect(capturedRequest!.questions, hasLength(2));
      expect(capturedRequest!.questions[0].id, 'genre');
      expect(capturedRequest!.questions[0].options, hasLength(2));
      expect(capturedRequest!.questions[1].allowFreeText, isTrue);

      expect(result['ok'], isTrue);
      expect(result['cancelled'], isFalse);
      final answers = result['answers'] as List<dynamic>;
      expect(answers, hasLength(2));
      expect(answers[0], {
        'question_id': 'genre',
        'answer': '偏黑色电影一点',
        'selected_options': ['悬疑'],
      });
      expect(answers[1], {'question_id': 'ending', 'answer': '收在不安感上'});
    });

    test(
      'timeout remains successful through tool result normalization',
      () async {
        final overlay = WorkingOverlayService(
          db,
          contentService,
          novelActionsService: NovelActionsService(appDb),
        );
        final toolManager = AiToolManager(
          contentService,
          workingOverlayService: overlay,
          askUserCallback: (request) async =>
              AskUserResult.timeout(request.questions),
        )..registerAllTools();
        final result = await toolManager.executeTool(
          name: 'AskUser',
          input: {
            'questions': [
              {'id': 'q', 'question': 'Continue?'},
            ],
          },
          callId: 'timeout',
        );
        expect(result['ok'], true);
        expect(result['cancelled'], false);
        expect(result['resolution'], 'timeout');
        expect(result['unanswered_question_ids'], ['q']);
        expect(result['error_code'], isNull);
      },
    );

    test('returns user_cancelled instead of a tool execution error', () async {
      final overlay = WorkingOverlayService(
        db,
        contentService,
        novelActionsService: NovelActionsService(appDb),
      );
      final toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay,
        askUserCallback: (_) async =>
            const AskUserResult(ok: false, cancelled: true),
      )..registerAllTools();

      final result = await toolManager.executeTool(
        name: 'AskUser',
        input: {
          'questions': ['是否继续？'],
        },
        callId: 'call_ask_user_cancelled',
      );

      expect(result['ok'], isFalse);
      expect(result['cancelled'], isTrue);
      expect(result['error_code'], 'user_cancelled');
      expect(result['error'], 'User cancelled');
    });

    test('parses a single question through questions list', () {
      final input = AskUserInput.fromJson({
        'questions': [
          {
            'id': 'confirm',
            'question': '是否继续？',
            'options': [
              {'label': '继续'},
              {'label': '暂停'},
            ],
            'allow_free_text': false,
          },
        ],
      });

      expect(input.questions, hasLength(1));
      expect(input.questions[0].id, 'confirm');
      expect(input.questions[0].question, '是否继续？');
      expect(input.questions[0].options, hasLength(2));
      expect(input.questions[0].allowFreeText, isFalse);
    });

    test('accepts string shorthand questions from model tool calls', () {
      final input = AskUserInput.fromJson({
        'questions': ['要继续搜索外部资料吗？'],
      });

      expect(input.questions, hasLength(1));
      expect(input.questions[0].id, 'q1');
      expect(input.questions[0].question, '要继续搜索外部资料吗？');
      expect(input.questions[0].options, isNull);
    });

    test('accepts string shorthand options from model tool calls', () {
      final input = AskUserInput.fromJson({
        'questions': [
          {
            'id': 'source',
            'question': '优先看哪类资料？',
            'options': ['作者访谈', '读者评论'],
            'allow_free_text': 'false',
            'multi_select': 'true',
          },
        ],
      });

      expect(input.questions, hasLength(1));
      expect(input.questions[0].options, hasLength(2));
      expect(input.questions[0].options![0].label, '作者访谈');
      expect(input.questions[0].options![1].label, '读者评论');
      expect(input.questions[0].allowFreeText, isFalse);
      expect(input.questions[0].multiSelect, isTrue);
    });
  });
}
