// 职责: 验证匿名 trace 对流式重试和取消控制流的聚合、降噪行为。
// 关联文件:
//   lib/shared/agent/hooks/trace_hook.dart
//   lib/shared/services/ai/trace_reporter_service.dart
//   lib/shared/services/anonymous_outbox_service.dart
//   lib/shared/services/ai/tools.dart

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:http/testing.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:reveric/shared/agent/agent_hook.dart';
import 'package:reveric/shared/agent/agent_event.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/client.dart';
import 'package:reveric/shared/agent/hooks/trace_hook.dart';
import 'package:reveric/shared/agent/message.dart';
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
  test(
    'MCP anonymous errors contain neither service identity nor business payload',
    () async {
      final fixture = await _TraceFixture.create();
      addTearDown(fixture.dispose);
      final hook = fixture.hook();
      await hook.afterToolCall(
        const AfterToolCallContext(
          source: AgentToolSource.mcp,
          call: ToolCall(
            callId: 'external',
            toolName: 'mcp__private_notes__secret_search',
            arguments: {'query': 'private-manuscript', 'token': 'secret-token'},
          ),
          result: {
            'ok': false,
            'error_code': 'mcp_connection_lost',
            'error': 'private-manuscript',
            'structuredContent': {'secret': 'secret-token'},
          },
        ),
      );
      final rows = await fixture.database
          .select(fixture.database.anonymousOutboxEvents)
          .get();
      final payload = rows.map((row) => row.payloadJson).join();
      expect(payload, contains('mcp_connection_lost'));
      for (final value in [
        'private_notes',
        'secret_search',
        'private-manuscript',
        'secret-token',
      ]) {
        expect(payload, isNot(contains(value)));
      }
    },
  );

  test(
    'handled context exhaustion does not emit anonymous error events',
    () async {
      final fixture = await _TraceFixture.create();
      addTearDown(fixture.dispose);
      final hook = fixture.hook();
      const error = openai.ApiException(
        statusCode: 400,
        message: 'Context is full',
        code: 'context_length_exceeded',
      );
      await hook.onStart('task');
      await hook.onLLMError(error, 1, isStreamError: true);
      await hook.onError(error, null);
      await hook.afterToolCall(
        AfterToolCallContext(
          call: const ToolCall(
            callId: 'child',
            toolName: 'SpawnAgent',
            arguments: {},
          ),
          result: const {
            'ok': false,
            'error': 'Context is full',
            'error_code': 'internal',
            'failure_kind': 'contextWindowExhausted',
          },
        ),
      );
      await hook.onEnd();
      final rows = await fixture.database
          .select(fixture.database.anonymousOutboxEvents)
          .get();
      expect(rows.where((r) => r.channel != 'trace'), isEmpty);
      expect(
        rows.map((r) => (jsonDecode(r.payloadJson) as Map)['event_type']),
        ['turn_start', 'turn_end'],
      );
      // 普通 400 和其他子 Agent 失败继续上报，不能按状态码一律丢弃。
      await hook.onError(
        const openai.ApiException(statusCode: 400, message: 'Invalid request'),
        null,
      );
      await hook.afterToolCall(
        AfterToolCallContext(
          call: const ToolCall(
            callId: 'child2',
            toolName: 'SpawnAgent',
            arguments: {},
          ),
          result: const {
            'error': 'Stream interrupted',
            'error_code': 'internal',
            'failure_kind': 'streamInterrupted',
          },
        ),
      );
      final after = await fixture.database
          .select(fixture.database.anonymousOutboxEvents)
          .get();
      expect(after.where((r) => r.channel == 'requestError'), hasLength(1));
      expect(after.where((r) => r.channel == 'toolError'), hasLength(1));
    },
  );

  test(
    'provider categories reach errors and retry summaries without private IDs',
    () async {
      final fixture = await _TraceFixture.create();
      addTearDown(fixture.dispose);
      for (final entry in <String?, String>{
        null: 'unknown',
        '': 'unknown',
        'reveric': 'custom',
        'public_welfare': 'custom',
        'private-provider-id': 'custom',
      }.entries) {
        final hook = fixture.hook().copyWith(providerId: () => entry.key);
        await hook.onStart('task');
        const error = IncompleteModelResponseException(
          reason: IncompleteResponseReason.emptyResponse,
          textChars: 0,
          thinkingChars: 0,
        );
        await hook.onLLMError(error, 5, isStreamError: true);
        await hook.onError(error, null);
        await hook.afterToolCall(
          AfterToolCallContext(
            call: const ToolCall(
              callId: 'read',
              toolName: 'Read',
              arguments: {},
            ),
            result: const {'error': 'Not found', 'error_code': 'not_found'},
          ),
        );
        await hook.onEnd();
        final rows = await fixture.database
            .select(fixture.database.anonymousOutboxEvents)
            .get();
        for (final channel in ['requestError', 'toolError', 'trace']) {
          final payload = rows
              .where((r) => r.channel == channel)
              .map((r) => jsonDecode(r.payloadJson) as Map)
              .where(
                (p) =>
                    channel != 'trace' ||
                    p['event_type'] == 'stream_retry_summary',
              )
              .last;
          expect(payload['provider_kind'], entry.value);
          expect(payload.toString(), isNot(contains('private-provider-id')));
        }
      }
      final parent = fixture.hook().copyWith(
        providerId: () => 'provider_parent',
      );
      final child = parent.copyWith(
        providerId: () => 'provider_child',
        sessionId: () => 'child',
      );
      await child.onError(StateError('test failure'), null);
      await fixture.reporter.onToolCallError(
        'parent',
        'model',
        'SpawnAgent',
        providerId: 'provider_parent',
        result: {'error': 'Child failed', 'provider_kind': 'custom'},
      );
      final rows = await fixture.database
          .select(fixture.database.anonymousOutboxEvents)
          .get();
      for (final channel in ['requestError', 'toolError']) {
        final payload =
            jsonDecode(rows.lastWhere((r) => r.channel == channel).payloadJson)
                as Map;
        expect(payload['provider_kind'], 'custom');
      }
    },
  );

  test('cancelled request gates do not upload loop errors', () async {
    final fixture = await _TraceFixture.create();
    addTearDown(fixture.dispose);
    final db = NovelContentDatabase.forTest(NativeDatabase.memory());
    addTearDown(db.close);
    final content = NovelContentService(db);
    var started = 0;
    var gateChecks = 0;
    final manager = AiToolManager(
      content,
      workingOverlayService: WorkingOverlayService(
        db,
        content,
        novelActionsService: NovelActionsService(fixture.database),
      ),
      shouldExecuteTool: () {
        gateChecks++;
        return false;
      },
      onToolStarted: (_, _, _, _, _) => started++,
      askUserCallback: (_) async => throw StateError('Cancelled AskUser ran'),
      suggestNextActionCallback: (_, _) =>
          throw StateError('Cancelled SuggestNextAction ran'),
    )..registerAllTools();
    addTearDown(manager.dispose);
    final agent = FakeAgent.create(
      toolManager: manager,
      hooks: [fixture.hook()],
      responses: const [
        FakeProviderClientResponse.toolCalls([
          ToolCall(callId: 'read', toolName: 'Read', arguments: {'path': '/'}),
          ToolCall(
            callId: 'write',
            toolName: 'Write',
            arguments: {'path': 'chapters/missing/title', 'value': 'new'},
          ),
          ToolCall(callId: 'ask', toolName: 'AskUser', arguments: {}),
          ToolCall(
            callId: 'suggest',
            toolName: 'SuggestNextAction',
            arguments: {},
          ),
        ]),
        FakeProviderClientResponse.text('Stopped.'),
      ],
    );
    // Reproduce the request cancellation gate without also cancelling Agent,
    // which would overwrite the tool result and hide the incorrect error code.
    final events = await agent.process('task').toList();
    expect(gateChecks, 4);
    expect(started, 0);
    expect(await db.select(db.workingChanges).get(), isEmpty);
    expect(events.whereType<AgentToolSkipped>(), hasLength(4));
    final rows = await fixture.database
        .select(fixture.database.anonymousOutboxEvents)
        .get();
    expect(rows.where((row) => row.channel == 'toolError'), isEmpty);
    final results = agent.contextManager.messages
        .expand((message) => message.blocks)
        .whereType<ToolResultBlock>();
    expect(results, hasLength(4));
    for (final result in results) {
      final payload =
          jsonDecode((result.content.single as TextBlock).text) as Map;
      expect(result.isError, isTrue);
      expect(payload['ok'], isFalse);
      expect(payload['cancelled'], isTrue);
      expect(payload['error_code'], 'user_cancelled');
      expect(payload['skipped'], isNull);
    }
  });

  test(
    'skipped control flow is ignored while real failures are uploaded',
    () async {
      final fixture = await _TraceFixture.create();
      addTearDown(fixture.dispose);
      final hook = fixture.hook();
      const call = ToolCall(callId: 'read', toolName: 'Read', arguments: {});
      await hook.afterToolCall(
        AfterToolCallContext(
          call: call,
          result: const {
            'ok': false,
            'skipped': true,
            'error_code': 'loop_skipped',
          },
        ),
      );
      await hook.afterToolCall(
        AfterToolCallContext(
          call: call,
          result: const {
            'ok': false,
            'error': 'Read failed',
            'error_code': 'execution_error',
          },
        ),
      );
      final rows = await fixture.database
          .select(fixture.database.anonymousOutboxEvents)
          .get();
      final errors = rows.where((row) => row.channel == 'toolError').toList();
      expect(errors, hasLength(1));
      expect(
        jsonDecode(errors.single.payloadJson)['error_code'],
        'execution_error',
      );
    },
  );

  test('user cancellation is control flow and not a tool error', () async {
    final fixture = await _TraceFixture.create();
    addTearDown(fixture.dispose);
    final hook = fixture.hook();

    await hook.afterToolCall(
      AfterToolCallContext(
        call: const ToolCall(
          callId: 'edit_cancelled',
          toolName: 'Edit',
          arguments: {'path': '/chapters/1'},
        ),
        result: const {
          'ok': false,
          'error': 'User cancelled',
          'error_code': 'user_cancelled',
          'cancelled': true,
        },
      ),
    );

    final rows = await fixture.database
        .select(fixture.database.anonymousOutboxEvents)
        .get();
    expect(rows, isEmpty);
  });

  test(
    'recovered stream failures emit one trace summary, not errors',
    () async {
      final fixture = await _TraceFixture.create();
      addTearDown(fixture.dispose);
      final hook = fixture.hook();

      await hook.onStart('task');
      await hook.onLLMError(
        ClientException('Connection closed'),
        1,
        isStreamError: true,
      );
      await hook.onLLMError(
        ClientException('Connection closed'),
        2,
        isStreamError: true,
      );
      hook.onDone('done');
      await hook.onEnd();

      final rows = await fixture.database
          .select(fixture.database.anonymousOutboxEvents)
          .get();
      expect(rows.where((row) => row.channel == 'requestError'), isEmpty);

      final payloads = rows
          .where((row) => row.channel == 'trace')
          .map((row) => jsonDecode(row.payloadJson) as Map<String, dynamic>)
          .toList();
      final summary = payloads.singleWhere(
        (payload) => payload['event_type'] == 'stream_retry_summary',
      );
      expect(summary['request_count'], 0);
      expect(jsonDecode(summary['message'] as String), {
        'outcome': 'recovered',
        'codes': {'stream_retry_network': 2},
      });
    },
  );

  test(
    'recovered incomplete response is aggregated without uploading content',
    () async {
      final fixture = await _TraceFixture.create();
      addTearDown(fixture.dispose);
      final hook = fixture.hook();
      const error = IncompleteModelResponseException(
        reason: IncompleteResponseReason.outputLimit,
        finishReason: StreamFinishReason.length,
        textChars: 0,
        thinkingChars: 40805,
      );

      await hook.onStart('task');
      await hook.onIncompleteResponse(error, willRetry: true);
      hook.onDone('done');
      await hook.onEnd();

      final rows = await fixture.database
          .select(fixture.database.anonymousOutboxEvents)
          .get();
      expect(rows.where((row) => row.channel == 'requestError'), isEmpty);
      final payloads = rows
          .where((row) => row.channel == 'trace')
          .map((row) => jsonDecode(row.payloadJson) as Map<String, dynamic>)
          .toList();
      final summary = payloads.singleWhere(
        (payload) => payload['event_type'] == 'stream_retry_summary',
      );
      expect(jsonDecode(summary['message'] as String), {
        'outcome': 'recovered',
        'codes': {'stream_retry_response_incomplete_length': 1},
      });
      expect(summary['message'], isNot(contains('long reasoning')));
    },
  );

  test('terminal incomplete response is a request error', () async {
    final fixture = await _TraceFixture.create();
    addTearDown(fixture.dispose);
    final hook = fixture.hook();
    const error = IncompleteModelResponseException(
      reason: IncompleteResponseReason.missingFinalAnswer,
      finishReason: StreamFinishReason.stop,
      textChars: 0,
      thinkingChars: 1024,
    );

    await hook.onStart('task');
    await hook.onError(error, null);
    await hook.onEnd();

    final rows = await fixture.database
        .select(fixture.database.anonymousOutboxEvents)
        .get();
    final row = rows.singleWhere((event) => event.channel == 'requestError');
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    expect(payload['error_type'], 'request_error');
    expect(payload['error_code'], 'response_incomplete_no_final_answer');
    expect(payload['exception_type'], 'IncompleteModelResponseException');
    expect(payload['exception_message'], isNot(contains('long reasoning')));
  });

  test('cancelled turn records its source as trace control flow', () async {
    final fixture = await _TraceFixture.create();
    addTearDown(fixture.dispose);
    final hook = fixture.hook(cancelSource: () => 'stop_button');

    await hook.onStart('task');
    await hook.onEnd();

    final rows = await fixture.database
        .select(fixture.database.anonymousOutboxEvents)
        .get();
    expect(rows.where((row) => row.channel == 'requestError'), isEmpty);
    expect(rows.where((row) => row.channel == 'toolError'), isEmpty);

    final payloads = rows
        .where((row) => row.channel == 'trace')
        .map((row) => jsonDecode(row.payloadJson) as Map<String, dynamic>)
        .toList();
    expect(
      payloads,
      contains(
        allOf(
          containsPair('event_type', 'turn_cancelled'),
          containsPair('message', 'stop_button'),
        ),
      ),
    );
  });

  test(
    'late cancel source does not override recovered or failed outcomes',
    () async {
      final fixture = await _TraceFixture.create();
      addTearDown(fixture.dispose);

      final recoveredHook = fixture.hook(cancelSource: () => 'runtime_dispose');
      await recoveredHook.onStart('task');
      await recoveredHook.onLLMError(
        ClientException('Connection closed'),
        1,
        isStreamError: true,
      );
      recoveredHook.onDone('done');
      await recoveredHook.onEnd();

      final failedHook = fixture.hook(cancelSource: () => 'runtime_dispose');
      await failedHook.onStart('task');
      await failedHook.onLLMError(
        ClientException('Connection closed'),
        1,
        isStreamError: true,
      );
      await failedHook.onError(ClientException('Connection closed'), null);
      await failedHook.onEnd();

      final payloads =
          (await fixture.database
                  .select(fixture.database.anonymousOutboxEvents)
                  .get())
              .where((row) => row.channel == 'trace')
              .map((row) => jsonDecode(row.payloadJson) as Map<String, dynamic>)
              .toList();

      expect(
        payloads.where((payload) => payload['event_type'] == 'turn_cancelled'),
        isEmpty,
      );

      final summaries = payloads
          .where((payload) => payload['event_type'] == 'stream_retry_summary')
          .map(
            (payload) =>
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>,
          )
          .toList();
      expect(summaries, hasLength(2));
      expect(summaries.map((summary) => summary['outcome']), [
        'recovered',
        'failed',
      ]);
    },
  );
}

class _TraceFixture {
  _TraceFixture({
    required this.database,
    required this.outbox,
    required this.reporter,
  });

  final AppDatabase database;
  final AnonymousOutboxService outbox;
  final TraceReporterService reporter;

  static Future<_TraceFixture> create() async {
    SharedPreferences.setMockInitialValues({'device_id': 'test-device'});
    final database = AppDatabase.forTest(NativeDatabase.memory());
    final outbox = AnonymousOutboxService(
      database: database,
      httpClient: MockClient((_) async => throw UnimplementedError()),
      getBaseUrl: () => null,
      getEnabled: () => true,
      autoFlush: false,
    );
    final reporter = TraceReporterService(
      deviceIdService: DeviceIdService(),
      outbox: outbox,
    );
    return _TraceFixture(
      database: database,
      outbox: outbox,
      reporter: reporter,
    );
  }

  TraceHook hook({String? Function()? cancelSource}) {
    return TraceHook(
      reporter: reporter,
      sessionId: () => 'session_1',
      model: () => 'model_1',
      sessionMode: () => 'chat',
      cancelSource: cancelSource,
    );
  }

  Future<void> dispose() async {
    outbox.dispose();
    await database.close();
  }
}
