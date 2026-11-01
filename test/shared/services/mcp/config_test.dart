// 职责: 验证 MCP 配置的身份冲突与备份恢复边界。
// 关联文件:
//   lib/shared/models/mcp/config.dart
//   lib/shared/models/mcp/call_result.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/models/mcp/config_import.dart';
import 'package:reveric/shared/models/mcp/call_result.dart';

void main() {
  test('runtime load isolates all collisions and malformed entries', () {
    Map<String, dynamic> config(String name) => {
      'name': name,
      'transport': 'stdio',
      'command': 'test',
    };
    final raw = jsonEncode({
      'formatVersion': 1,
      'servers': [
        config('good'),
        config('docs-api'),
        config('docs_api'),
        config('duplicate'),
        config('duplicate'),
        {...config('broken'), 'command': 123},
      ],
    });
    final loaded = McpSettingsLoad.decode(raw);
    expect(loaded.settings.servers.map((s) => s.name), ['good']);
    expect(
      loaded.errors.keys,
      unorderedEquals(['docs-api', 'docs_api', 'duplicate', 'broken']),
    );
    expect(() => McpSettings.decode(raw), throwsFormatException);
    expect(
      McpSettingsLoad.decode('broken').error,
      'Invalid MCP configuration JSON',
    );
    expect(
      McpSettingsLoad.decode('{"formatVersion":2,"servers":[]}').error,
      'Unsupported MCP configuration version',
    );
  });
  McpServerConfig server(String name) => McpServerConfig(
    name: name,
    enabled: true,
    connection: McpHttpConfig(
      url: 'https://example.test/mcp',
      bearerToken: 'private',
      headers: {'X-Key': 'secret'},
      oauth: {
        'clientId': 'client',
        'accessToken': 'token',
        'refreshToken': 'refresh',
      },
    ),
  );
  test(
    'import preserves arguments and credentials without enabling before confirmation',
    () {
      final imported = parseMcpImport(
        '{"mcpServers":{"local":{"command":"python3","args":["a b.py"],"env":{"KEY":"secret"}},"remote":{"url":"https://example.test/mcp","headers":{"Authorization":"Bearer secret"}}}}',
        enabled: false,
      );
      expect(imported.every((server) => !server.enabled), true);
      expect((imported.first.connection as McpStdioConfig).args, ['a b.py']);
      expect(
        (imported.last.connection as McpHttpConfig).authMode,
        McpAuthMode.headers,
      );
      expect(
        () => parseMcpImport(
          '{"mcpServers":{"bad":{"url":"https://example.test","command":"python3"}}}',
          enabled: true,
        ),
        throwsFormatException,
      );
    },
  );
  test('rejects namespace collisions before persistence', () {
    Matcher conflict(String name, String existing) => throwsA(
      isA<McpServerNameConflict>()
          .having((e) => e.name, 'name', name)
          .having((e) => e.existing, 'existing', existing),
    );
    expect(
      () => McpSettings([server('docs-api'), server('docs_api')]),
      conflict('docs_api', 'docs-api'),
    );
    expect(
      () => McpSettings([server('notes'), server('notes')]),
      conflict('notes', 'notes'),
    );
  });
  test(
    'round trip and restore preserve credentials but disable every server',
    () {
      final original = McpSettings([server('notes')]);
      final restored = McpSettings.decode(
        original.encode(),
      ).disabledForRestore();
      expect(restored.servers.single.enabled, false);
      expect(
        restored.servers.single.connection.toJson(),
        original.servers.single.connection.toJson(),
      );
    },
  );
  test('unknown version and malformed data fail instead of becoming empty', () {
    expect(
      () => McpSettings.decode('{"formatVersion":2,"servers":[]}'),
      throwsFormatException,
    );
    expect(() => McpSettings.decode('broken'), throwsFormatException);
    expect(McpSettings.decode(null).servers, isEmpty);
  });
  test('rejects URL credentials and header injection', () {
    expect(
      () => McpHttpConfig(url: 'https://u:p@example.test'),
      throwsFormatException,
    );
    expect(
      () => McpHttpConfig(
        url: 'https://example.test',
        headers: {'X-Key': 'a\r\nb'},
      ),
      throwsFormatException,
    );
  });
  test('remote business fields cannot change successful host result', () {
    final result = McpCallResult(
      executionState: McpExecutionState.succeeded,
      structuredContent: {'ok': false, 'error': 'business'},
    );
    expect(result.toJson()['ok'], true);
    expect(result.toJson().containsKey('error'), false);
  });
}
