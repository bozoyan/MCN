// 职责: 验证真实 Streamable HTTP 并发调用中取消一个请求不会关闭共享连接。
// 关联文件:
//   lib/shared/services/mcp/client_adapter.dart
//   lib/shared/services/mcp/tool_dispatcher.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/models/mcp/call_result.dart';
import 'package:reveric/shared/services/mcp/client_adapter.dart';
import 'package:reveric/shared/services/mcp/runtime.dart';
import 'package:reveric/shared/services/mcp/tool_dispatcher.dart';
import 'adapter_test.dart' show reply;

void main() {
  test(
    'continuous HTTP progress cannot extend the absolute call deadline',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var calls = 0;
      server.listen((request) async {
        if (request.method != 'POST') {
          request.response.statusCode = 405;
          await request.response.close();
          return;
        }
        final data =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        if (data['method'] == 'tools/call') {
          calls++;
          request.response.bufferOutput = false;
          final token = (data['params'] as Map)['_meta']['progressToken'];
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          try {
            for (var i = 0; i < 40; i++) {
              request.response.write(
                'event: message\ndata: ${jsonEncode({
                  'jsonrpc': '2.0',
                  'method': 'notifications/progress',
                  'params': {'progressToken': token, 'progress': i},
                })}\n\n',
              );
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
            await request.response.close();
          } catch (_) {
            /* The deadline closes the response. */
          }
          return;
        }
        final response = reply(data, modern: true);
        if (response == null) {
          request.response.statusCode = 202;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(response));
        }
        await request.response.close();
      });
      final runtime = McpRuntime(connect: McpClientAdapter.connect);
      try {
        await runtime.configure(
          McpSettings([
            McpServerConfig(
              name: 'fixture',
              enabled: true,
              callTimeoutSeconds: 1,
              connection: McpHttpConfig(
                url: 'http://127.0.0.1:${server.port}/mcp',
              ),
            ),
          ]),
        );
        await runtime.ensureReady('fixture');
        final progress = <Map<String, dynamic>>[];
        final clock = Stopwatch()..start();
        final result = await McpToolDispatcher(
          runtime,
        ).call('mcp__fixture__first', {}, onProgress: progress.add);
        expect(progress, isNotEmpty);
        expect(clock.elapsedMilliseconds, lessThan(1800));
        expect(result.executionState, McpExecutionState.unknown);
        expect(result.errorCode, 'mcp_timeout');
        expect(calls, 1);
      } finally {
        await runtime.close();
        await server.close(force: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test(
    'cancelling HTTP A keeps pending B and never replays A',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final started = {
        for (final id in ['a', 'b']) id: Completer<void>(),
      };
      final finish = {
        for (final id in ['a', 'b']) id: Completer<void>(),
      };
      var calls = 0;
      server.listen((request) async {
        if (request.method != 'POST') {
          request.response.statusCode = 405;
          await request.response.close();
          return;
        }
        final data =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        if (data['method'] == 'tools/call') {
          calls++;
          final delay = (data['params'] as Map)['arguments']?['delay'];
          if (delay is String) {
            started[delay]!.complete();
            await finish[delay]!.future;
          }
        }
        final value = reply(data, modern: true);
        if (value == null) {
          request.response.statusCode = 202;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(value));
        }
        try {
          await request.response.close();
        } catch (_) {
          /* A's client deliberately aborted this response. */
        }
      });
      final runtime = McpRuntime(connect: McpClientAdapter.connect);
      try {
        await runtime.configure(
          McpSettings([
            McpServerConfig(
              name: 'fixture',
              enabled: true,
              connection: McpHttpConfig(
                url: 'http://127.0.0.1:${server.port}/mcp',
              ),
            ),
          ]),
        );
        await runtime.ensureReady('fixture');
        final dispatcher = McpToolDispatcher(runtime);
        final cancel = sdk.BasicAbortController();
        final a = dispatcher.call('mcp__fixture__first', {
          'delay': 'a',
        }, signal: cancel.signal);
        final b = dispatcher.call('mcp__fixture__first', {'delay': 'b'});
        await Future.wait(started.values.map((c) => c.future));
        cancel.abort();
        expect(
          (await a.timeout(const Duration(seconds: 2))).executionState,
          McpExecutionState.unknown,
        );
        finish['b']!.complete();
        expect((await b).executionState, McpExecutionState.succeeded);
        expect(calls, 2);
        expect(runtime.states['fixture']!.status, McpConnectionStatus.ready);
      } finally {
        for (final gate in finish.values) {
          if (!gate.isCompleted) {
            gate.complete();
          }
        }
        await runtime.close();
        await server.close(force: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
