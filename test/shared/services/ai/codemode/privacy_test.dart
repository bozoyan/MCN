// 职责: 验证 Codemode 向模型和匿名上报提供脱敏的 JS 错误诊断。
// 关联文件:
//   lib/shared/services/ai/tool_error_normalize.dart
//   lib/shared/services/ai/trace_reporter_service.dart
//   lib/shared/services/ai/codemode/runtime.dart
//   lib/shared/services/ai/agent_message_mapping.dart
//   lib/shared/models/ai_chat_models.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/services/ai/agent_message_mapping.dart';
import 'package:reveric/shared/services/ai/codemode/runtime.dart';
import 'package:reveric/shared/services/ai/tool_error_normalize.dart';

void main() {
  test('JS diagnostics survive metadata removal from model results', () {
    final payload = const CodemodeRuntimeResult(
      output: [],
      callCount: 0,
      completedCount: 0,
      failedCount: 0,
      errorCode: 'codemode_script_error',
      jsErrorMessage:
          "SyntaxError: Unexpected token ')'\n"
          '    at /Users/PRIVATE/script.js:12:4',
      diagnostics: {'failure_stage': 'script', 'failure_reason': 'syntax'},
    ).toJson();
    final history = convertAiMessageToAgentMessagesForModel(
      AiMessage.assistant(
        id: 'assistant',
        content: '',
        blocks: [
          AiToolCallBlock(
            id: 'block',
            callId: 'call',
            toolName: 'Codemode',
            arguments: const {'code': 'PRIVATE_SOURCE'},
            status: AiToolCallStatus.error,
            result: payload,
          ),
        ],
      ),
    );
    final toolResult = history
        .expand((message) => message.blocks)
        .whereType<ToolResultBlock>()
        .single;
    final result =
        jsonDecode((toolResult.content.single as TextBlock).text)
            as Map<String, dynamic>;

    expect(toolResult.isError, isTrue);
    expect(result.containsKey('_metadata'), isFalse);
    expect(result['js_error_message'], "SyntaxError: Unexpected token ')'");
    expect(result['error'], codemodeErrorMessage('codemode_script_error'));
    expect(result['call_count'], 0);
    expect(result['diagnostics']['failure_reason'], 'syntax');
    expect(result.toString(), isNot(contains('PRIVATE')));
  });

  test('model JS diagnostics redact credentials and keep the actual error', () {
    final result = const CodemodeRuntimeResult(
      output: [],
      callCount: 0,
      completedCount: 0,
      failedCount: 0,
      errorCode: 'codemode_script_error',
      jsErrorMessage: 'Error: api_key=PRIVATE_KEY password="PRIVATE_PASSWORD"',
    ).toJson()..remove('_metadata');

    expect(
      result['js_error_message'],
      'Error: api_key=<redacted> password=<redacted>',
    );
    expect(result.toString(), isNot(contains('PRIVATE')));
  });

  Map<String, dynamic> report(String message) => codemodeAnonymousFailure(
    {
      'error_code': 'codemode_script_error',
      '_metadata': {'codemode_js_error': message},
      'output': ['PRIVATE_OUTPUT'],
    },
    {'code': 'PRIVATE_SOURCE'},
  );

  test('reports the actual JavaScript message without its stack', () {
    final result = report(
      "TypeError: cannot read property 'content' of undefined\n"
      '    at /Users/private/script.js:12:4',
    );
    expect(
      result['exception_message'],
      "TypeError: cannot read property 'content' of undefined",
    );
    expect(result['error_code'], 'codemode_script_error');
    expect(result['stack_top'], '');
    expect(result.toString(), isNot(contains('PRIVATE')));
    expect(result.toString(), isNot(contains('/Users/private')));
  });

  test('redacts paths, URLs and common credentials in messages', () {
    for (final message in [
      'Error: failed to read /Users/PRIVATE/file.js',
      r'Error: failed to read C:\Users\PRIVATE\file.js',
      'Error: https://PRIVATE.invalid/?api_key=PRIVATE',
      'Error: Authorization: Bearer PRIVATE_TOKEN',
      'Error: api_key=PRIVATE_KEY password="PRIVATE_PASSWORD"',
      'Error: sk-PRIVATE1234567890',
    ]) {
      final result = report(message);
      expect(result['exception_message'], startsWith('Error:'));
      expect(result.toString(), isNot(contains('PRIVATE')));
    }
  });

  test('bounds JS error messages and leaves non-JS failures unchanged', () {
    final result = report('ReferenceError: ${'x' * 1000}');
    expect(
      (result['exception_message'] as String).length,
      lessThanOrEqualTo(500),
    );
    expect(result['exception_message'], startsWith('ReferenceError:'));
    expect(
      codemodeAnonymousFailure({
        'error_code': 'codemode_timeout',
        '_metadata': {'codemode_js_error': 'PRIVATE_IGNORED'},
      }, {})['exception_message'],
      'codemode_timeout',
    );
    expect(report('  ')['exception_message'], 'codemode_script_error');
  });

  test(
    'source, output and untrusted error overrides never enter diagnostics',
    () {
      final result = codemodeAnonymousFailure(
        {
          'error_code': 'PRIVATE_EXCEPTION',
          'error': 'PRIVATE_BODY',
          'exception_message': '/PRIVATE_HOST_PATH',
          'stack_top': 'PRIVATE_STACK',
          'tool_input': 'PRIVATE_OVERRIDE',
          'output': ['PRIVATE_OUTPUT'],
          'tool_error': {
            'error': 'PRIVATE_TOOL_ERROR',
            'hint': 'PRIVATE_HINT',
            'recovery': {
              'tool': 'Read',
              'input': {'path': 'PRIVATE_RESOURCE_PATH'},
            },
          },
          'call_count': 2,
          'diagnostics': {
            'phase': 'PRIVATE_PHASE',
            'failure_stage': 'PRIVATE_STAGE',
            'failure_reason': 'PRIVATE_REASON',
            'last_tool': 'PRIVATE_TOOL',
            'limit': 'PRIVATE_LIMIT',
            'observed': -1,
            'elapsed_ms': 1.5,
            'output_bytes': 9007199254740992,
          },
        },
        {'code': 'PRIVATE_SOURCE 中文'},
      );
      expect(result.toString(), isNot(contains('PRIVATE')));
      final safe =
          jsonDecode(result['tool_input'] as String) as Map<String, dynamic>;
      for (final key in [
        'failure_stage',
        'failure_reason',
        'last_tool',
        'limit',
        'observed',
        'elapsed_ms',
        'output_bytes',
      ]) {
        expect(safe.containsKey(key), isFalse);
      }
      expect(result['error_code'], 'codemode_runtime_failed');
      expect(result['tool_input'], contains('source_bytes'));
      expect(
        sanitizeToolInput('Codemode', {'code': 'PRIVATE_SOURCE'}),
        isNot(contains('PRIVATE')),
      );
    },
  );

  test('last_tool keeps every tool callable from scripts, including Run', () {
    final result = codemodeAnonymousFailure(
      {
        'error_code': 'codemode_script_error',
        'diagnostics': {
          'last_tool': 'Run',
          'tool_error_code': 'invalid_argument',
        },
      },
      {'code': 'PRIVATE_SOURCE'},
    );
    final safe =
        jsonDecode(result['tool_input'] as String) as Map<String, dynamic>;
    expect(safe['last_tool'], 'Run');
    expect(safe['tool_error_code'], 'invalid_argument');
  });
}
