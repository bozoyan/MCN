// 职责: 验证现代 MCP 工具变化订阅只触发一次目录刷新并随连接释放。
// 关联文件:
//   lib/shared/services/mcp/client_adapter.dart
//   lib/shared/services/mcp/runtime.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/services/mcp/client_adapter.dart';
import 'package:reveric/shared/services/mcp/runtime.dart';
import 'adapter_test.dart' show reply;

void main() {
  test(
    '2026 subscription updates a ready directory exactly once',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscribed = Completer<({HttpResponse response, int id})>();
      final stop = Completer<void>();
      var generation = 0;
      var lists = 0;
      server.listen((request) async {
        if (request.method != 'POST') {
          request.response.statusCode = 405;
          await request.response.close();
          return;
        }
        final data =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        if (data['method'] == 'subscriptions/listen') {
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.bufferOutput = false;
          final id = data['id'] as int;
          final ack = sdk.JsonRpcSubscriptionsAcknowledgedNotification(
            acknowledgedParams: const sdk.SubscriptionsAcknowledgedNotification(
              notifications: sdk.SubscriptionFilter(toolsListChanged: true),
            ),
            meta: {sdk.McpMetaKey.subscriptionId: id},
          );
          request.response.write(
            'event: message\ndata: ${jsonEncode(ack.toJson())}\n\n',
          );
          await request.response.flush();
          subscribed.complete((response: request.response, id: id));
          await stop.future;
          try {
            await request.response.close();
          } catch (_) {
            /* Client owns cancellation. */
          }
          return;
        }
        final value = reply(data, modern: true);
        if (data['method'] == 'server/discover') {
          (value!['result'] as Map)['capabilities'] = {
            'tools': {'listChanged': true},
          };
        }
        if (data['method'] == 'tools/list') {
          lists++;
          value!['result'] = {
            'resultType': 'complete',
            'ttlMs': 0,
            'cacheScope': 'private',
            'tools': [
              {
                'name': generation == 0 ? 'old' : 'new',
                'inputSchema': {'type': 'object', 'properties': {}},
              },
            ],
          };
        }
        if (value == null) {
          request.response.statusCode = 202;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(value));
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
              connection: McpHttpConfig(
                url: 'http://127.0.0.1:${server.port}/mcp',
              ),
            ),
          ]),
        );
        await runtime.ensureReady('fixture');
        expect(runtime.tools.keys, ['mcp__fixture__old']);
        final next = runtime.changes.firstWhere(
          (states) =>
              states['fixture']!.tools.any((tool) => tool['name'] == 'new'),
        );
        final subscription = await subscribed.future;
        generation = 1;
        final changed = sdk.JsonRpcToolListChangedNotification(
          meta: {sdk.McpMetaKey.subscriptionId: subscription.id},
        );
        subscription.response.write(
          'event: message\ndata: ${jsonEncode(changed.toJson())}\n\n',
        );
        await subscription.response.flush();
        await next.timeout(const Duration(seconds: 2));
        expect(lists, 2);
        expect(runtime.tools.keys, ['mcp__fixture__new']);
      } finally {
        await runtime.close();
        stop.complete();
        await server.close(force: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
