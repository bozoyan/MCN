// 职责: 验证 trace 错误分类标签能区分 HTTP/网络/schema/未知类型，且不透出原始文本
// 关联文件:
//   lib/shared/services/ai/trace_reporter_service.dart
//   lib/shared/agent/client.dart
//   lib/shared/agent/client/provider_history_preflight.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/client.dart';
import 'package:reveric/shared/agent/client/provider_history_preflight.dart';
import 'package:reveric/shared/services/ai/trace_reporter_service.dart';

/// 与 openai_dart [StreamException] 同名，用于验证按类型名分类。
class StreamException implements Exception {
  const StreamException(this.message);
  final String message;
}

class _StatusCodeException implements Exception {
  const _StatusCodeException(this.statusCode);
  final int statusCode;
}

void main() {
  group('classifyRequestError', () {
    test('maps HTTP status codes', () {
      expect(classifyRequestError(const _StatusCodeException(429)), 'http_429');
      expect(classifyRequestError(const _StatusCodeException(500)), 'http_5xx');
      expect(classifyRequestError(const _StatusCodeException(404)), 'http_404');
    });

    test('maps network failures', () {
      expect(
        classifyRequestError(TimeoutException('timed out')),
        'network_timeout',
      );
      expect(
        classifyRequestError(const SocketException('Connection refused')),
        'network_connection',
      );
    });

    test('maps schema / stream inline without leaking text', () {
      expect(
        classifyRequestError(const FormatException('bad json at offset 12')),
        'schema_parse',
      );
      expect(
        classifyRequestError(const StreamException('Token limit exceeded')),
        'stream_inline_error',
      );
      expect(classifyRequestError(_responsesSseTypeError()), 'schema_parse');
    });

    test('unknown keeps type name only', () {
      expect(
        classifyRequestError(ArgumentError('secret path /Users/me/novel')),
        'unknown:ArgumentError',
      );
      final label = classifyRequestError(StateError('unexpected boom'));
      expect(label, startsWith('unknown:'));
      expect(label.contains('boom'), isFalse);
    });

    test('maps provider history issues without exposing message data', () {
      const error = ProviderHistoryValidationException(
        protocol: ProviderHistoryProtocol.anthropic,
        issue: ProviderHistoryIssue.emptyToolResultId,
        messageIndex: 4,
        blockIndex: 1,
        pendingCallCount: 2,
      );

      expect(classifyRequestError(error), 'history_empty_tool_result_id');
      expect(error.toString(), contains('message_index=4'));
      expect(error.toString(), isNot(contains('secret-tool-id')));
    });

    test(
      'separates thinking-only exhaustion from a single incomplete round',
      () {
        // 「连续多轮只思考不产出」与「单轮没产出」排查方向不同，统计里不能混在
        // 一起，否则下个版本无法判断自动续跑到底救回了多少。
        const single = IncompleteModelResponseException(
          reason: IncompleteResponseReason.outputLimit,
          finishReason: StreamFinishReason.length,
          textChars: 0,
          thinkingChars: 80000,
        );
        const exhausted = IncompleteModelResponseException(
          reason: IncompleteResponseReason.outputLimit,
          finishReason: StreamFinishReason.length,
          textChars: 0,
          thinkingChars: 80000,
          thinkingOnlyRounds: 5,
        );

        expect(classifyRequestError(single), 'response_incomplete_length');
        expect(
          classifyRequestError(exhausted),
          'response_incomplete_thinking_loop',
        );
        // 轮次数要进 exception_message，匿名侧才看得到陷了几轮。
        expect(exhausted.toString(), contains('thinkingOnlyRounds=5'));
        expect(single.toString(), isNot(contains('thinkingOnlyRounds')));
      },
    );
  });

  group('classifyStreamError', () {
    test('keeps known retry kinds and types unknown', () {
      expect(
        classifyStreamError(const _StatusCodeException(503)),
        'stream_retry_http_5xx',
      );
      expect(
        classifyStreamError(const SocketException('reset')),
        'stream_retry_network',
      );
      expect(
        classifyStreamError(const StreamException('Token limit exceeded')),
        'stream_retry_inline_error',
      );
      expect(
        classifyStreamError(ArgumentError('x')),
        'stream_retry_unknown:ArgumentError',
      );
    });
  });

  group('shouldReportRequestError', () {
    test('drops expected HTTP rejections and network noise', () {
      expect(shouldReportRequestError('http_401'), isFalse);
      expect(shouldReportRequestError('http_402'), isFalse);
      expect(shouldReportRequestError('http_403'), isFalse);
      expect(shouldReportRequestError('http_429'), isFalse);
      expect(shouldReportRequestError('http_404'), isFalse);
      expect(shouldReportRequestError('network_connection'), isFalse);
      expect(shouldReportRequestError('http_400'), isTrue);
      expect(shouldReportRequestError('http_5xx'), isTrue);
      expect(shouldReportRequestError('history_empty_tool_call_id'), isTrue);
      expect(shouldReportRequestError('stream_inline_error'), isTrue);
      expect(shouldReportRequestError('unknown:ArgumentError'), isTrue);
    });
  });
}

Object _responsesSseTypeError() {
  try {
    final String value = null as dynamic;
    return value;
  } catch (error) {
    return error;
  }
}
