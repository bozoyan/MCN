// 职责: 回归验证 vendored SDK 流式 abort 不再泄漏 unhandled 错误
//   （0.9.4 引入 2 分钟无事件 abort 后，AbortedException 逃逸成 uncaught_async）
// 关联文件:
//   third/ai_clients_dart/packages/openai_dart/lib/src/resources/streaming_resource.dart
//   third/ai_clients_dart/packages/open_responses/lib/src/resources/streaming_resource.dart
//   lib/shared/agent/agent.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/error-handling.md

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart';
import 'package:open_responses/open_responses.dart' as responses;

/// send() 会一直挂起，直到 close() 被调用（模拟 abort 关闭 dedicated client
/// 使 in-flight send() 失败的真实路径）。
class _HangingSendClient extends http.BaseClient {
  final _sendStarted = Completer<void>();
  final _sendError = Completer<Exception>();
  bool closed = false;

  Future<void> get sendStarted => _sendStarted.future;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _sendStarted.complete();
    await _sendError.future;
    throw http.ClientException(
      'Connection closed before full header was received',
      request.url,
    );
  }

  @override
  void close() {
    closed = true;
    if (!_sendError.isCompleted) {
      _sendError.complete(http.ClientException('closed by abort', Uri()));
    }
  }
}

class _BodyStreamClient extends http.BaseClient {
  final body = StreamController<List<int>>();
  final listening = Completer<void>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    body.onListen = () => listening.complete();
    return http.StreamedResponse(body.stream, 200, request: request);
  }

  @override
  void close() {
    if (closed) {
      return;
    }
    closed = true;
    body.addError(
      http.ClientException('Connection closed while receiving data'),
    );
    unawaited(body.close());
  }
}

OpenAIClient _clientWith(_HangingSendClient mock) => OpenAIClient.withApiKey(
  'sk-test',
  baseUrl: 'https://example.invalid',
  streamClientFactory: () => mock,
);

ChatCompletionCreateRequest _request() => ChatCompletionCreateRequest(
  model: 'gpt-4o-mini',
  messages: [ChatMessage.user('hi')],
);

void main() {
  group('SDK streaming abort containment', () {
    for (final useResponses in [false, true]) {
      for (final abortRequest in [false, true]) {
        test(
          '${useResponses ? 'Responses' : 'Chat'} after headers: ${abortRequest ? 'abort is contained' : 'network failure propagates'}',
          () async {
            final mock = _BodyStreamClient();
            final abort = Completer<void>();
            final Stream<Object> stream;
            if (useResponses) {
              final client = responses.OpenResponsesClient.withApiKey(
                'sk-test',
                baseUrl: 'https://example.invalid',
                streamClientFactory: () => mock,
              );
              addTearDown(client.close);
              stream = client.responses.createStream(
                responses.CreateResponseRequest.text(
                  model: 'test',
                  input: 'hi',
                ),
                abortTrigger: abort.future,
              );
            } else {
              final client = OpenAIClient.withApiKey(
                'sk-test',
                baseUrl: 'https://example.invalid',
                streamClientFactory: () => mock,
              );
              addTearDown(client.close);
              stream = client.chat.completions.createStream(
                _request(),
                abortTrigger: abort.future,
              );
            }
            final errors = <Object>[];
            final done = Completer<void>();
            final sub = stream.listen(
              (_) {},
              onError: errors.add,
              onDone: done.complete,
            );
            await mock.listening.future;
            if (abortRequest) {
              abort.complete();
            } else {
              mock.close();
            }
            await done.future.timeout(const Duration(seconds: 2));
            await sub.cancel();
            expect(
              errors,
              abortRequest ? isEmpty : [isA<http.ClientException>()],
            );
            expect(mock.closed, isTrue);
          },
        );
      }
    }

    test('abort 触发在 send 挂起期时返回空响应，不再抛 AbortedException', () async {
      final mock = _HangingSendClient();
      final client = _clientWith(mock);
      final abort = Completer<void>();
      final events = <Object>[];
      final errors = <Object>[];

      final stream = client.chat.completions.createStream(
        _request(),
        abortTrigger: abort.future,
      );
      final sub = stream.listen(events.add, onError: errors.add);
      await mock.sendStarted;
      abort.complete(); // abort → 关闭 client → send() 失败
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      // 修复前：SDK 抛 AbortedException 被 onError 收到；修复后：空响应正常结束。
      expect(errors, isEmpty, reason: 'abort 是主动取消，不应作为错误上抛');
      expect(events, isEmpty);
    });

    test('abort 与消费方取消并发时不产生 zone 级 unhandled 错误', () async {
      final mock = _HangingSendClient();
      final client = _clientWith(mock);
      final abort = Completer<void>();
      final unhandled = <Object>[];

      await runZonedGuarded(
        () async {
          final stream = client.chat.completions.createStream(
            _request(),
            abortTrigger: abort.future,
          );
          final sub = stream.listen((_) {});
          await mock.sendStarted;
          // 与真实超时路径一致：abort 与消费方拆除订阅几乎同时发生。
          abort.complete();
          await sub.cancel();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        },
        (error, stackTrace) {
          unhandled.add(error);
        },
      );

      expect(unhandled, isEmpty, reason: 'abort 引发的底层错误不得落入已取消的 async* 生成器');
    });
  });
}
