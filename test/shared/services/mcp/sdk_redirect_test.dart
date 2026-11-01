// 职责: 验证本地 SDK 默认回调限制不变，显式 native opt-in 不能放行非法 URI。
// 关联文件:
//   third/mcp_dart/lib/src/client/streamable_https.dart
//   lib/shared/services/mcp/oauth/callback.dart
//   lib/shared/services/mcp/oauth/provider.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import 'package:reveric/shared/services/mcp/oauth/callback.dart';
import 'package:reveric/shared/services/mcp/oauth/provider.dart';

void main() {
  test('application approval is exact and has no URI decorations', () {
    expect(
      McpOAuthCallbacks.acceptsRegisteredRedirect(
        Uri.parse('ai.reveric://mcp/oauth/callback'),
      ),
      true,
    );
    for (final value in [
      'ai.reveric://other/oauth/callback',
      'ai.reveric://mcp/other',
      'ai.reveric://mcp:123/oauth/callback',
      'ai.reveric://user@mcp/oauth/callback',
      'ai.reveric://mcp/oauth/callback?extra=1',
      'ai.reveric://mcp/oauth/callback#',
      'javascript:alert(1)',
    ]) {
      expect(
        McpOAuthCallbacks.acceptsRegisteredRedirect(Uri.parse(value)),
        false,
        reason: value,
      );
    }
  });
  for (final item in [
    (uri: 'ai.reveric://mcp/oauth/callback', optIn: false),
    (uri: 'ai.reveric://user@mcp/oauth/callback', optIn: true),
    (uri: 'ai.reveric://mcp/oauth/callback#fragment', optIn: true),
  ]) {
    test('SDK rejects ${item.uri} with optIn=${item.optIn}', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = 401;
        await request.response.close();
      });
      var browserOpened = false;
      final provider = McpOAuthProvider(
        clientId: 'client',
        redirectUri: Uri.parse(item.uri),
        scopes: [],
        persistTokens: (_) async {},
        registerClient: (_) async {},
        authorize: (_) async {
          browserOpened = true;
        },
      );
      final transport = sdk.StreamableHttpClientTransport(
        Uri.parse('http://127.0.0.1:${server.port}/mcp'),
        opts: sdk.StreamableHttpClientTransportOptions(
          authProvider: provider,
          oauthRedirectUriValidator: item.optIn ? (_) => true : null,
        ),
      );
      addTearDown(transport.close);
      await transport.start();
      await expectLater(
        transport.send(
          sdk.JsonRpcServerDiscoverRequest(
            id: 1,
            meta: sdk.buildProtocolRequestMeta(
              protocolVersion: sdk.defaultProtocolVersion,
              clientInfo: const sdk.Implementation(
                name: 'fixture',
                version: '1',
              ),
              clientCapabilities: const sdk.ClientCapabilities(),
            ),
          ),
        ),
        throwsA(
          predicate((error) => error.toString().contains('redirect URI')),
        ),
      );
      expect(browserOpened, false);
    });
  }
}
