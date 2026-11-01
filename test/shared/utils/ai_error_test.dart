// 职责: 验证共享 AI 错误解析保留上游结构化信息，并拒绝把本地异常当成供应商错误。
// 关联文件:
//   lib/shared/utils/ai_error.dart
//   lib/shared/models/ai_run_failure.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/ai_error.dart';
import 'package:reveric/shared/models/ai_run_failure.dart';

void main() {
  const code = 'InputImageSensitiveContentDetected.PrivacyInformation';
  const message = 'The input image may contain real person.';
  final body = {
    'error': {'code': code, 'message': message},
  };
  test('SDK, JSON, SSE and HTTP wrappers preserve code and message', () {
    for (final error in <Object>[
      body,
      {'task': body},
      jsonEncode(body),
      (message: jsonEncode(body)),
      (message: 'data: ${jsonEncode(body)}'),
      (message: 'HTTP 400: ${jsonEncode(body)}'),
      (body: body),
      (code: code, message: message, statusCode: 400),
      {
        'ResponseMetadata': {
          'Error': {'Code': code, 'Message': message},
        },
      },
      {
        'error': {
          'code': 400,
          'message': 'Provider returned error',
          'metadata': {'raw': jsonEncode(body)},
        },
      },
    ]) {
      expect(tryReadProviderErrorCode(error), code, reason: '$error');
      expect(tryReadProviderMessage(error), message, reason: '$error');
    }
    expect(tryReadStatusCode((statusCode: 400)), 400);
    expect(tryReadStatusCode((message: 'HTTP 400')), isNull);
  });
  test('code-only errors work without inventing a message', () {
    expect(
      tryReadProviderErrorCode({
        'error': {'code': code},
      }),
      code,
    );
    expect(
      tryReadProviderMessage({
        'error': {'code': code},
      }),
      isNull,
    );
  });
  test('local exceptions and malformed or cyclic payloads are bounded', () {
    final cyclic = <String, Object?>{};
    cyclic['error'] = cyclic;
    for (final error in <Object>[
      const FormatException(code),
      const SocketException(code),
      StateError(code),
      {'code': 'private key https://example.test/'},
      {'code': 400},
      (message: '{broken'),
      (message: 'data: broken'),
      (message: '<html>$code</html>'),
      cyclic,
    ]) {
      expect(tryReadProviderErrorCode(error), isNull);
    }
    expect(tryReadProviderMessage(cyclic), isNull);
    expect(tryReadProviderMessage(StateError('private detail')), isNull);
  });
  test('failure serialization and provider assignment retain the code', () {
    const failure = AiRunFailure.http(
      statusCode: 400,
      providerCode: code,
      providerMessage: message,
    );
    final restored = AiRunFailure.fromJson(failure.toJson());
    expect(restored, failure);
    expect(restored.withProviderId('openrouter').providerCode, code);
    expect(
      AiRunFailure.fromJson({'kind': 'http', 'status_code': 400}).providerCode,
      isNull,
    );
  });
}
