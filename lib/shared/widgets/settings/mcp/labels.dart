// 职责: 生成 MCP 服务连接方式与端点的展示文本。
// 关联文件:
//   lib/shared/models/mcp/config.dart
//   lib/shared/widgets/settings/mcp/server_row.dart
//   lib/shared/widgets/settings/mcp/server_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
import '../../../localization/locale_keys.dart';
import '../../../models/mcp/config.dart';

String mcpTransportLabelKey(McpTransportConfig connection) =>
    switch (connection) {
      McpStdioConfig() => LocaleKeys.settingsMcpStdio,
      McpHttpConfig() => LocaleKeys.settingsMcpHttp,
    };

String mcpEndpointLabel(McpTransportConfig connection) => switch (connection) {
  McpStdioConfig(:final command, :final args) => [command, ...args].join(' '),
  McpHttpConfig(:final url) => url,
};
