// 职责: ToolDef → JSON Schema 转换 — provider client 工具格式适配
// 关联文件:
//   lib/shared/agent/agent_tool_dispatcher.dart
//   lib/shared/agent/client/openai_client.dart
//   lib/shared/agent/client/anthropic_client.dart
//   lib/shared/agent/client/gemini_client.dart

import '../agent_tool_dispatcher.dart' show ToolDef;

Map<String, dynamic> toolDefToJsonSchema(ToolDef tool) => {
  'type': 'object',
  'properties': <String, dynamic>{},
  ...tool.inputSchema,
};
