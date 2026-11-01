// 职责: 将常见 mcpServers JSON 转换成待确认的配置，不启动连接。
// 关联文件:
//   lib/shared/models/mcp/config.dart
//   lib/shared/widgets/settings/mcp/server_editor.dart
import 'dart:convert';
import 'config.dart';

List<McpServerConfig> parseMcpImport(String text, {required bool enabled}) {
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic> ||
      decoded['mcpServers'] is! Map<String, dynamic>) {
    throw const FormatException('Expected mcpServers object');
  }
  final servers = <McpServerConfig>[];
  for (final entry in (decoded['mcpServers'] as Map<String, dynamic>).entries) {
    if (entry.value is! Map<String, dynamic>) {
      throw const FormatException('Invalid server configuration');
    }
    final raw = Map<String, dynamic>.from(entry.value as Map);
    if (raw.containsKey('url') == raw.containsKey('command')) {
      throw const FormatException('Specify URL or command');
    }
    final transport = raw.containsKey('url') ? 'streamable_http' : 'stdio';
    final type = raw['type'];
    if (type != null &&
        ![
          'stdio',
          'http',
          'streamable-http',
          'streamable_http',
        ].contains(type)) {
      throw const FormatException('Unsupported MCP transport');
    }
    servers.add(
      McpServerConfig.fromJson({
        ...raw,
        'name': entry.key,
        'transport': transport,
        'enabled': enabled,
        'authMode':
            raw['authMode'] ??
            (raw['headers'] is Map && (raw['headers'] as Map).isNotEmpty
                ? 'headers'
                : 'none'),
      }),
    );
  }
  if (servers.isEmpty) {
    throw const FormatException('No MCP servers found');
  }
  return McpSettings(servers).servers;
}
