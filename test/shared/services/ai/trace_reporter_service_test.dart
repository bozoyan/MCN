// 职责: 验证匿名错误诊断的 Outbox 内容、隐私边界与错误去重。
// 关联文件:
//   lib/shared/services/ai/trace_reporter_service.dart
//   lib/shared/services/anonymous_outbox_service.dart
//   lib/shared/database/app_database.dart
//   lib/shared/agent/client/provider_history_preflight.dart

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:reveric/shared/agent/client.dart';
import 'package:reveric/shared/agent/client/provider_history_preflight.dart';
import 'package:reveric/shared/agent/hooks/todo_continuation_hook.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/services/ai/trace_reporter_service.dart';
import 'package:reveric/shared/services/anonymous_outbox_service.dart';
import 'package:reveric/shared/services/device_id_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Codemode JS error message reaches anonymous outbox', () async {
    SharedPreferences.setMockInitialValues({'device_id': 'test-device'});
    final database = AppDatabase.forTest(NativeDatabase.memory());
    final outbox = AnonymousOutboxService(
      database: database,
      httpClient: MockClient((_) async => throw UnimplementedError()),
      getBaseUrl: () => null,
      getEnabled: () => true,
      autoFlush: false,
    );
    addTearDown(() async {
      outbox.dispose();
      await database.close();
    });
    await TraceReporterService(
      deviceIdService: DeviceIdService(),
      outbox: outbox,
    ).onToolCallError(
      'test-session',
      'test-model',
      'Codemode',
      toolInput: {'code': 'PRIVATE_SOURCE'},
      result: {
        'error_code': 'codemode_script_error',
        '_metadata': {
          'codemode_js_error':
              "ReferenceError: 'missingName' is not defined\n at /PRIVATE/path.js:1:2",
        },
        'output': ['PRIVATE_OUTPUT'],
        'diagnostics': {
          'failure_stage': 'script',
          'failure_reason': 'reference',
        },
      },
    );
    final event =
        (await database.select(database.anonymousOutboxEvents).get()).single;
    final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
    expect(
      payload['exception_message'],
      "ReferenceError: 'missingName' is not defined",
    );
    expect(payload['error_code'], 'codemode_script_error');
    expect(
      jsonDecode(payload['tool_input'] as String)['failure_reason'],
      'reference',
    );
    expect(event.payloadJson, isNot(contains('PRIVATE')));
  });

  test(
    'Codemode limit diagnostics reach outbox without script or output',
    () async {
      SharedPreferences.setMockInitialValues({'device_id': 'test-device'});
      final database = AppDatabase.forTest(NativeDatabase.memory());
      final outbox = AnonymousOutboxService(
        database: database,
        httpClient: MockClient((_) async => throw UnimplementedError()),
        getBaseUrl: () => null,
        getEnabled: () => true,
        autoFlush: false,
      );
      addTearDown(() async {
        outbox.dispose();
        await database.close();
      });
      final reporter = TraceReporterService(
        deviceIdService: DeviceIdService(),
        outbox: outbox,
      );
      await reporter.onToolCallError(
        'test-session',
        'test-model',
        'Codemode',
        toolInput: {'code': 'PRIVATE_SOURCE'},
        result: {
          'error_code': 'codemode_resource_limit',
          'output': ['PRIVATE_OUTPUT'],
          'call_count': 10,
          'completed_count': 10,
          'failed_count': 0,
          'diagnostics': {
            'phase': 'finished',
            'failure_stage': 'return_value',
            'failure_reason': 'output_bytes',
            'limit': 131072,
            'observed': 140000,
            'elapsed_ms': 1500,
            'output_bytes': 1000,
            'output_frames': 1,
            'return_bytes': 139000,
            'last_tool': 'Read',
            'max_input_bytes': 80,
            'output_limit_bytes': 131072,
            'output_limit_frames': 1024,
            'input_limit_bytes': 262144,
            'execution_limit_ms': 120000,
            'source': 'PRIVATE_SOURCE',
            'raw_error': 'PRIVATE_ERROR',
          },
        },
      );
      final event =
          (await database.select(database.anonymousOutboxEvents).get()).single;
      final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
      final diagnostic = jsonDecode(payload['tool_input'] as String);
      expect(diagnostic['failure_reason'], 'output_bytes');
      expect(diagnostic['failure_stage'], 'return_value');
      expect(diagnostic['limit'], 131072);
      expect(diagnostic['observed'], 140000);
      expect(diagnostic['completed_count'], 10);
      expect(diagnostic['output_frames'], 1);
      expect(diagnostic['last_tool'], 'Read');
      expect(diagnostic['execution_limit_ms'], 120000);
      expect(event.payloadJson, isNot(contains('PRIVATE')));
    },
  );

  test('unfinished todo snapshot reaches trace outbox as counts', () async {
    SharedPreferences.setMockInitialValues({'device_id': 'test-device'});
    final database = AppDatabase.forTest(NativeDatabase.memory());
    final outbox = AnonymousOutboxService(
      database: database,
      httpClient: MockClient((_) async => throw UnimplementedError()),
      getBaseUrl: () => null,
      getEnabled: () => true,
      autoFlush: false,
    );
    addTearDown(() async {
      outbox.dispose();
      await database.close();
    });
    final reporter = TraceReporterService(
      deviceIdService: DeviceIdService(),
      outbox: outbox,
    );

    await reporter.onTodoUnfinishedAtDone(
      'test-session',
      'test-model',
      sessionMode: 'chat',
      snapshot: const UnfinishedTodoSnapshot(
        totalCount: 3,
        pendingCount: 1,
        inProgressCount: 1,
        requestCount: 4,
        toolCallCount: 6,
        endsWithQuestion: false,
        continuationCount: 0,
        decision: TodoContinuationDecision.disabled,
      ),
    );

    final row =
        (await database.select(database.anonymousOutboxEvents).get()).single;
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    expect(row.channel, 'trace');
    expect(payload['event_type'], 'todo_unfinished_at_done');
    expect(payload['model'], 'test-model');
    expect(payload['request_count'], 4);
    expect(payload['tool_call_count'], 6);
    expect(jsonDecode(payload['message'] as String), {
      'total': 3,
      'unfinished': 2,
      'pending': 1,
      'in_progress': 1,
      'ends_with_question': false,
      'continuation_count': 0,
      'decision': 'disabled',
    });
  });

  test(
    'Edit and Write diagnostics reach outbox without text or hashes',
    () async {
      SharedPreferences.setMockInitialValues({'device_id': 'test-device'});
      final database = AppDatabase.forTest(NativeDatabase.memory());
      final outbox = AnonymousOutboxService(
        database: database,
        httpClient: MockClient((_) async => throw UnimplementedError()),
        getBaseUrl: () => null,
        getEnabled: () => true,
        autoFlush: false,
      );
      addTearDown(() async {
        outbox.dispose();
        await database.close();
      });
      final reporter = TraceReporterService(
        deviceIdService: DeviceIdService(),
        outbox: outbox,
      );
      await reporter.onToolCallError(
        'test-session',
        'test-model',
        'Edit',
        toolInput: {
          'path': 'chapters/test/content',
          'old_text': 'private old body',
          'new_text': 'private new body',
        },
        result: {
          'error_code': 'old_text_not_found',
          'error': 'old_text not found.',
          '_metadata': {
            'edit_diagnostics': {
              'match_reason': 'first_line_diverged',
              'divergence_offset': 17,
              'source_length': 100,
              'old_text_length': 30,
              'fingerprint': 'private hash',
            },
          },
        },
      );
      await reporter.onToolCallError(
        'test-session',
        'test-model',
        'Write',
        toolInput: {
          'path': 'chapters/test/outline',
          'fields': {'content': 'private body'},
        },
        result: {
          'error_code': 'missing_required_fields',
          'error': 'Missing outline in fields.',
          'missing_fields': ['outline'],
          'required_fields': ['outline'],
        },
      );
      final events = await database
          .select(database.anonymousOutboxEvents)
          .get();
      expect(events, hasLength(2));
      final payloads = events.map((e) => jsonDecode(e.payloadJson)).toList();
      final edit = jsonDecode(
        payloads.singleWhere((p) => p['tool_name'] == 'Edit')['tool_input'],
      );
      expect(edit['match_reason'], 'first_line_diverged');
      expect(edit['divergence_offset'], 17);
      final write = jsonDecode(
        payloads.singleWhere((p) => p['tool_name'] == 'Write')['tool_input'],
      );
      expect(write['field_shapes'], {'content': 'string'});
      expect(write['missing_fields'], ['outline']);
      for (final event in events) {
        expect(event.payloadJson, isNot(contains('private')));
      }
    },
  );

  test(
    'WebFetch diagnostics reach outbox without its URL or response body',
    () async {
      SharedPreferences.setMockInitialValues({'device_id': 'test-device'});
      final database = AppDatabase.forTest(NativeDatabase.memory());
      final outbox = AnonymousOutboxService(
        database: database,
        httpClient: MockClient((_) async => throw UnimplementedError()),
        getBaseUrl: () => null,
        getEnabled: () => true,
        autoFlush: false,
      );
      addTearDown(() async {
        outbox.dispose();
        await database.close();
      });
      final reporter = TraceReporterService(
        deviceIdService: DeviceIdService(),
        outbox: outbox,
      );
      await reporter.onToolCallError(
        'test-session',
        'test-model',
        'WebFetch',
        result: {
          'error_code': 'web_fetch_failed',
          'error': 'Web fetch failed. Please try again later.',
          'failure_kind': 'timeout',
          'failure_stage': 'redirect',
          'failure_type': 'TimeoutException',
        },
        toolInput: {'url': 'https://example.invalid/private?token=secret'},
      );
      final event =
          (await database.select(database.anonymousOutboxEvents).get()).single;
      final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
      expect(payload['exception_type'], 'ToolFailure');
      expect(payload['exception_message'], contains('failure_kind=timeout'));
      expect(payload['exception_message'], contains('failure_stage=redirect'));
      expect(
        payload['exception_message'],
        contains('failure_type=timeoutexception'),
      );
      expect(payload.toString(), isNot(contains('example.invalid')));
      expect(payload.toString(), isNot(contains('token=secret')));
    },
  );
  test('classifies incomplete model responses without response content', () {
    const cases = {
      IncompleteResponseReason.outputLimit: 'response_incomplete_length',
      IncompleteResponseReason.contentFiltered:
          'response_incomplete_content_filter',
      IncompleteResponseReason.missingFinalAnswer:
          'response_incomplete_no_final_answer',
      IncompleteResponseReason.emptyResponse: 'response_incomplete_empty',
    };

    for (final entry in cases.entries) {
      final error = IncompleteModelResponseException(
        reason: entry.key,
        finishReason: StreamFinishReason.unknown,
        textChars: 0,
        thinkingChars: 10,
      );
      expect(classifyRequestError(error), entry.value);
      expect(classifyStreamError(error), 'stream_retry_${entry.value}');
      expect(error.toString(), isNot(contains('response body')));
    }
  });

  test(
    'does not enqueue HTTP credential, quota, or permission errors',
    () async {
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
      addTearDown(() async {
        outbox.dispose();
        await database.close();
      });

      for (final statusCode in [401, 402, 403]) {
        await reporter.onRequestError(
          'session_$statusCode',
          'model_1',
          _StatusCodeException(statusCode),
        );
      }

      expect(
        await database.select(database.anonymousOutboxEvents).get(),
        isEmpty,
      );
    },
  );

  test(
    'reports provider history indexes without tool IDs or content',
    () async {
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
      addTearDown(() async {
        outbox.dispose();
        await database.close();
      });

      await reporter.onRequestError(
        'session_1',
        'model_1',
        const ProviderHistoryValidationException(
          protocol: ProviderHistoryProtocol.anthropic,
          issue: ProviderHistoryIssue.emptyToolCallId,
          messageIndex: 4,
          blockIndex: 2,
          pendingCallCount: 1,
        ),
      );

      final event =
          (await database.select(database.anonymousOutboxEvents).get()).single;
      final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
      expect(payload['error_code'], 'history_empty_tool_call_id');
      expect(payload['exception_type'], 'ProviderHistoryValidationException');
      expect(payload['exception_message'], contains('protocol=anthropic'));
      expect(payload['exception_message'], contains('message_index=4'));
      expect(payload['exception_message'], isNot(contains('tool-use-id')));
      expect(payload['exception_message'], isNot(contains('private content')));

      await reporter.onRequestError(
        'session_1',
        'model_1',
        const ProviderHistoryValidationException(
          protocol: ProviderHistoryProtocol.gemini,
          issue: ProviderHistoryIssue.duplicateToolCallId,
          messageIndex: 441,
          blockIndex: 0,
          pendingCallCount: 0,
          duplicateOfMessageIndex: 128,
          duplicateOfBlockIndex: 2,
          sameMessageId: false,
          sameToolName: true,
          sameArguments: false,
        ),
      );
      final events = await database
          .select(database.anonymousOutboxEvents)
          .get();
      final duplicate = events
          .map((event) => jsonDecode(event.payloadJson) as Map<String, dynamic>)
          .singleWhere(
            (payload) =>
                payload['error_code'] == 'history_duplicate_tool_call_id',
          );
      final message = duplicate['exception_message'] as String;
      expect(message, contains('duplicate_of_message_index=128'));
      expect(message, contains('duplicate_of_block_index=2'));
      expect(message, contains('same_message_id=false'));
      expect(message, contains('same_arguments=false'));
      expect(message.length, lessThan(500));
    },
  );

  test('preserves structured Create failure reason and input values', () async {
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
    addTearDown(() async {
      outbox.dispose();
      await database.close();
    });

    await reporter.onToolCallError(
      'session_1',
      'model_1',
      'Create',
      result: {
        'error_code': 'invalid_role',
        'error':
            'Invalid character role: "main". Valid values: "protagonist", "antagonist", "supporting", "minor".',
        'enum_field': 'character_role',
      },
      toolInput: {
        'path': '/characters',
        'fields': {'name': 'Alice', 'role': 'main'},
      },
    );

    final event =
        (await database.select(database.anonymousOutboxEvents).get()).single;
    final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
    expect(payload['exception_type'], 'ToolFailure');
    expect(
      payload['exception_message'],
      'Invalid character role: "main". Valid values: "protagonist", "antagonist", "supporting", "minor".',
    );
    expect(jsonDecode(payload['tool_input'] as String), {
      'collection': 'characters',
      'path': '/characters',
      'top_level_keys': ['path', 'fields'],
      'fields_shape': 'object',
      'field_names': ['name', 'role'],
      'fields': {'name': 'Alice', 'role': 'main'},
    });
  });

  test(
    'SpawnAgent sub_agent_error reports failure_kind and status_code',
    () async {
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
      addTearDown(() async {
        outbox.dispose();
        await database.close();
      });

      // 此前 SpawnAgent 只上报 "sub-agent failed"，无法区分子 agent 失败原因；
      // failure_kind / status_code 必须进入 exception_message。
      await reporter.onToolCallError(
        'session_1',
        'model_1',
        'SpawnAgent',
        result: {
          'error_code': 'sub_agent_error',
          'error': 'sub-agent failed',
          'failure_kind': 'network',
          'status_code': 500,
          'session_id': 'ai_session_sub_1',
        },
      );

      final event =
          (await database.select(database.anonymousOutboxEvents).get()).single;
      final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
      expect(payload['error_code'], 'sub_agent_error');
      expect(payload['exception_type'], 'ToolFailure');
      expect(payload['exception_message'], contains('sub-agent failed'));
      expect(payload['exception_message'], contains('failure_kind=network'));
      expect(payload['exception_message'], contains('status_code=500'));
    },
  );

  test(
    'keeps Create input shape without uploading full chapter content',
    () async {
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
      addTearDown(() async {
        outbox.dispose();
        await database.close();
      });

      // Create /chapters 缺 title 也报 missing_required_fields，此时 fields
      // 里可能是整章正文；上报必须只保留形状诊断，不能原样上传正文。
      await reporter.onToolCallError(
        'session_1',
        'model_1',
        'Create',
        result: {
          'error_code': 'missing_required_fields',
          'error': 'CreateChapter requires title',
        },
        toolInput: {
          'path': '/chapters',
          'fields': {'content': '正文' * 5000},
        },
      );

      final event =
          (await database.select(database.anonymousOutboxEvents).get()).single;
      final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
      final encoded = payload['tool_input'] as String;
      final toolInput = jsonDecode(encoded) as Map<String, dynamic>;
      expect(toolInput['top_level_keys'], ['path', 'fields']);
      expect(toolInput['fields_shape'], 'object');
      expect(toolInput['field_names'], ['content']);
      expect(toolInput['fields']['content'], endsWith('...[truncated]'));
      expect(encoded.length, lessThan(1000));
    },
  );
}

class _StatusCodeException implements Exception {
  const _StatusCodeException(this.statusCode);

  final int statusCode;
}
