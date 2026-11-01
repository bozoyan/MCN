// 职责: 验证 Codex 请求约束、Responses 流复用、非流式聚合与失败边界。
// 关联文件:
//   lib/shared/agent/client/codex_client.dart
//   lib/shared/agent/client/openai_responses_client.dart
//   lib/shared/services/ai/codex/credentials.dart

import 'package:reveric/shared/utils/ai_error.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_responses/open_responses.dart' as or;
import 'package:reveric/shared/agent/agent_config.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/agent/client.dart';
import 'package:reveric/shared/agent/client/codex_client.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/services/ai/codex/credentials.dart';

const _auth = CodexCredentials(
  accessToken: 'test-token',
  accountId: 'test-account',
);
final _messages = [AgentMessage.user(id: 'u', content: '你好')];

String _event(Map<String, dynamic> value) => 'data: ${jsonEncode(value)}\n\n';
Map<String, dynamic> _text(String value) => {
  'type': 'response.output_text.delta',
  'item_id': 'msg',
  'output_index': 0,
  'content_index': 0,
  'delta': value,
};
Map<String, dynamic> _terminal({
  String type = 'completed',
  List<Object> output = const [],
}) => {
  'type': 'response.$type',
  'response': {
    'id': 'resp',
    'status': type,
    'output': output,
    if (type == 'incomplete')
      'incomplete_details': {'reason': 'max_output_tokens'},
    'usage': {
      'input_tokens': 20,
      'output_tokens': 8,
      'total_tokens': 28,
      'input_tokens_details': {'cached_tokens': 10},
      'output_tokens_details': {'reasoning_tokens': 3},
    },
  },
};
Map<String, dynamic> _call(String arguments) => {
  'type': 'function_call',
  'id': 'fc',
  'call_id': 'call',
  'name': 'Read',
  'arguments': arguments,
};
CodexClient _make(
  List<Map<String, dynamic>> events, {
  void Function(http.Request)? inspect,
}) => CodexClient(
  model: 'test-model',
  credentials: () async => _auth,
  streamHttpClientFactory: () =>
      _SseClient(events.map(_event).join(), inspect: inspect),
);

void main() {
  test(
    'chat uses one SSE request with Codex auth and allowed parameters',
    () async {
      var requests = 0;
      final client = _make(
        [_text('你'), _text('好'), _terminal()],
        inspect: (request) {
          requests++;
          expect(request.url.toString(), '$codexBaseUrl/responses');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.headers['Chatgpt-Account-Id'], 'test-account');
          expect(request.headers['Originator'], 'codex_cli_rs');
          expect(request.headers['OpenAI-Beta'], 'responses=experimental');
          expect(request.headers['User-Agent'], startsWith('codex_cli_rs/'));
          expect(
            request.headers['conversation_id'],
            request.headers['session_id'],
          );
          final body = jsonDecode(request.body) as Map;
          expect(body['prompt_cache_key'], isNotEmpty);
          expect(body['prompt_cache_key'], request.headers['session_id']);
          expect(body['stream'], true);
          expect(body['store'], false);
          expect(body.containsKey('temperature'), false);
          expect(body.containsKey('max_output_tokens'), false);
          expect(body['instructions'], '请用中文');
          expect((body['input'] as List).single['role'], 'user');
          expect((body['tools'] as List).single['name'], 'Read');
        },
      );
      final result = await client.chat(
        messages: [
          AgentMessage.system(id: 's', content: '请用中文'),
          ..._messages,
        ],
        tools: [
          const ToolDef(
            name: 'Read',
            description: 'Read',
            inputSchema: {'type': 'object'},
          ),
        ],
        options: const AgentConfig(temperature: 0.8, maxTokens: 200),
      );
      expect(requests, 1);
      expect(result.text, '你好');
      expect(result.usage?.inputTokens, 20);
      expect(result.usage?.cacheReadTokens, 10);
      expect(result.usage?.reasoningTokens, 3);
    },
  );

  test(
    'session identity survives client recreation and follows child sessions',
    () async {
      final requests = <http.Request>[];
      CodexClient makeClient() =>
          _make([_text('ok'), _terminal()], inspect: requests.add);
      const parent = AgentConfig(sessionId: 'reveric-parent');
      await makeClient().chat(messages: _messages, options: parent);
      final recreated = makeClient();
      await recreated.chatStream(messages: _messages, options: parent).toList();
      await recreated.chat(
        messages: _messages,
        options: const AgentConfig(
          sessionId: 'reveric-child',
          sessionParentId: 'reveric-parent',
        ),
      );
      expect(requests, hasLength(3));
      for (var i = 0; i < requests.length; i++) {
        final expected = i < 2 ? 'reveric-parent' : 'reveric-child';
        final request = requests[i];
        expect(request.headers['session_id'], expected);
        expect(request.headers['conversation_id'], expected);
        expect(jsonDecode(request.body)['prompt_cache_key'], expected);
        expect(request.headers.containsKey('Session-Id'), false);
        expect(request.headers.containsKey('Conversation-Id'), false);
      }
    },
  );

  test(
    'reads current session identity from the application on each request',
    () async {
      String? sessionId;
      final requests = <http.Request>[];
      final client = CodexClient(
        model: 'test-model',
        credentials: () async => _auth,
        sessionIdProvider: () => sessionId,
        streamHttpClientFactory: () => _SseClient(
          [_text('ok'), _terminal()].map(_event).join(),
          inspect: requests.add,
        ),
      );
      await client.chat(messages: _messages);
      sessionId = 'materialized-session';
      await client.chat(messages: _messages);
      sessionId = 'child-session';
      await client.chat(
        messages: _messages,
        options: const AgentConfig(sessionId: 'parent-session'),
      );
      expect(requests[0].headers['session_id'], isNotEmpty);
      for (var i = 1; i < requests.length; i++) {
        final expected = i == 1 ? 'materialized-session' : 'child-session';
        expect(requests[i].headers['session_id'], expected);
        expect(requests[i].headers['conversation_id'], expected);
        expect(jsonDecode(requests[i].body)['prompt_cache_key'], expected);
      }
    },
  );

  test(
    'standalone calls keep a temporary identity without inheriting a session',
    () async {
      final requests = <http.Request>[];
      final client = _make([_text('ok'), _terminal()], inspect: requests.add);
      await client.chat(messages: _messages);
      await client.chat(
        messages: _messages,
        options: const AgentConfig(sessionId: 'named'),
      );
      await client.chat(
        messages: _messages,
        options: const AgentConfig(sessionId: ''),
      );
      final temporary = requests.first.headers['session_id'];
      expect(temporary, isNotEmpty);
      expect(temporary, isNot('named'));
      expect(requests[1].headers['session_id'], 'named');
      expect(requests[2].headers['session_id'], temporary);
      for (final request in requests) {
        expect(
          request.headers['conversation_id'],
          request.headers['session_id'],
        );
        expect(
          jsonDecode(request.body)['prompt_cache_key'],
          request.headers['session_id'],
        );
      }
    },
  );

  test(
    'deduplicates tool done and terminal events and retains reasoning',
    () async {
      final result = await _make([
        {
          'type': 'response.output_item.added',
          'output_index': 0,
          'item': _call(''),
        },
        {
          'type': 'response.function_call_arguments.delta',
          'item_id': 'fc',
          'output_index': 0,
          'delta': '{"path":"/chapters"}',
        },
        {
          'type': 'response.function_call_arguments.done',
          'item_id': 'fc',
          'output_index': 0,
          'arguments': '{"path":"/chapters"}',
        },
        {
          'type': 'response.reasoning_summary_text.delta',
          'item_id': 'r',
          'output_index': 1,
          'summary_index': 0,
          'delta': '思考',
        },
        _terminal(
          output: [
            _call('{"path":"/chapters"}'),
            {
              'type': 'reasoning',
              'id': 'r',
              'summary': [
                {'type': 'summary_text', 'text': '思考'},
              ],
              'encrypted_content': 'opaque',
            },
          ],
        ),
      ]).chat(messages: _messages);
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.arguments, {'path': '/chapters'});
      expect(result.thinking, '思考');
      expect(result.encryptedContents, ['opaque']);
    },
  );

  test('chatStream preserves incremental events', () async {
    final events = await _make([
      _text('a'),
      _text('b'),
      _terminal(),
    ]).chatStream(messages: _messages).toList();
    expect(events.whereType<TextDelta>().map((e) => e.text), ['a', 'b']);
    expect(events.whereType<StreamComplete>(), hasLength(1));
  });

  test('terminal-only text is returned without relying on deltas', () async {
    final result = await _make([
      _terminal(
        output: [
          {
            'type': 'message',
            'id': 'msg',
            'role': 'assistant',
            'status': 'completed',
            'content': [
              {'type': 'output_text', 'text': 'answer', 'annotations': []},
            ],
          },
        ],
      ),
    ]).chat(messages: _messages);
    expect(result.text, 'answer');
  });

  test('early EOF never returns a successful partial response', () async {
    await expectLater(
      _make([_text('partial')]).chat(messages: _messages),
      throwsStateError,
    );
  });

  test('SSE error event cannot be hidden by a later completion', () async {
    await expectLater(
      _make([
        {
          'type': 'error',
          'error': {'type': 'server_error', 'message': 'failed'},
        },
        _text('must not succeed'),
        _terminal(),
      ]).chat(messages: _messages),
      throwsA(
        isA<ProviderStreamException>()
            .having((e) => e.type, 'type', 'server_error')
            .having(tryReadProviderMessage, 'provider message', 'failed'),
      ),
    );
  });

  for (final type in ['failed', 'incomplete']) {
    test('$type terminal never returns a successful response', () async {
      await expectLater(
        _make([
          _text('partial'),
          _terminal(type: type),
        ]).chat(messages: _messages),
        type == 'failed'
            ? throwsA(isA<ProviderStreamException>())
            : throwsA(isA<IncompleteModelResponseException>()),
      );
    });
  }

  test('rejects malformed final tool arguments', () async {
    await expectLater(
      _make([
        _terminal(output: [_call('{"path":')]),
      ]).chat(messages: _messages),
      throwsA(
        isA<IncompleteModelResponseException>().having(
          (e) => e.hadIncompleteToolCall,
          'partial tool',
          true,
        ),
      ),
    );
  });

  test('cancellation during auth does not send an inference request', () async {
    final auth = Completer<CodexCredentials>();
    final started = Completer<void>();
    final client = CodexClient(
      model: 'test',
      credentials: () {
        started.complete();
        return auth.future;
      },
      streamHttpClientFactory: () => throw StateError('must not send'),
    );
    final future = client.chat(messages: _messages);
    final assertion = expectLater(future, throwsA(isA<or.AbortedException>()));
    await started.future;
    client.cancel();
    auth.complete(_auth);
    await assertion;
  });

  test(
    'cancel closes a pending request and chat reports cancellation',
    () async {
      final transport = _BlockingClient();
      final client = CodexClient(
        model: 'test',
        credentials: () async => _auth,
        streamHttpClientFactory: () => transport,
      );
      final assertion = expectLater(
        client.chat(messages: _messages),
        throwsA(isA<or.AbortedException>()),
      );
      await transport.started.future;
      client.cancel();
      await assertion;
      expect(transport.closed, true);
    },
  );

  test('reloads credentials for each request', () async {
    var reads = 0;
    final client = CodexClient(
      model: 'test',
      credentials: () async {
        reads++;
        return CodexCredentials(
          accessToken: 'token-$reads',
          accountId: 'account',
        );
      },
      streamHttpClientFactory: () => _SseClient(
        [_text('ok'), _terminal()].map(_event).join(),
        inspect: (request) {
          expect(request.headers['Authorization'], 'Bearer token-$reads');
        },
      ),
    );
    await client.chat(messages: _messages);
    await client.chat(messages: _messages);
    expect(reads, 2);
  });

  test('fetchModels reads the Codex catalog and preserves priority', () async {
    final httpClient = MockClient((request) async {
      expect(request.url.path, '/backend-api/codex/models');
      expect(request.url.queryParameters['client_version'], isNotEmpty);
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.headers['Originator'], 'codex_cli_rs');
      expect(request.headers['OpenAI-Beta'], 'responses=experimental');
      expect(request.headers['User-Agent'], startsWith('codex_cli_rs/'));
      return http.Response(
        jsonEncode({
          'models': [
            {'slug': 'second', 'visibility': 'list', 'priority': 2},
            {'slug': 'hidden', 'visibility': 'hidden', 'priority': 0},
            {'slug': 'first', 'visibility': 'list', 'priority': 1},
          ],
        }),
        200,
      );
    });
    addTearDown(httpClient.close);
    expect(
      await CodexClient.fetchModels(
        client: httpClient,
        credentials: () async => _auth,
      ),
      ['first', 'second'],
    );
  });

  test('model authentication failure retains HTTP status', () async {
    final httpClient = MockClient((_) async => http.Response('denied', 401));
    addTearDown(httpClient.close);
    await expectLater(
      CodexClient.fetchModels(
        client: httpClient,
        credentials: () async => _auth,
      ),
      throwsA(
        isA<CodexHttpException>().having((e) => e.statusCode, 'status', 401),
      ),
    );
  });
}

class _SseClient extends http.BaseClient {
  _SseClient(this.body, {this.inspect});
  final String body;
  final void Function(http.Request)? inspect;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    inspect?.call(request as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

class _BlockingClient extends http.BaseClient {
  final started = Completer<void>();
  final response = Completer<http.StreamedResponse>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    started.complete();
    return response.future;
  }

  @override
  void close() {
    closed = true;
    if (!response.isCompleted) {
      response.completeError(http.ClientException('closed'));
    }
  }
}
