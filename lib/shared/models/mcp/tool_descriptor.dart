// 职责: 保存 MCP 工具的显式路由身份、原始定义与稳定调用名称。
// 关联文件:
//   lib/shared/services/mcp/runtime.dart
//   lib/shared/services/ai/tool_catalog.dart
//   lib/shared/models/mcp/call_result.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'call_result.dart';

String canonicalMcpJson(Object? value) {
  Object? canonical(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(item[key])};
    }
    if (item is List) {
      return item.map(canonical).toList();
    }
    return item;
  }

  return jsonEncode(canonical(value));
}

/// 生成 `mcp__<server>__<tool>`；超长或 [isTaken] 报告名字已被其他工具占用时，截断并附加 hash。
String mcpToolName(
  String server,
  String tool, {
  bool Function(String name)? isTaken,
}) {
  // 不保留 `-`：Codemode 脚本常写 `tools.<name>(...)`，名字必须是合法的 JS 标识符。
  final name = 'mcp__${server}__$tool'.replaceAll(
    RegExp(r'[^a-zA-Z0-9_]'),
    '_',
  );
  if (name.length <= 64 && !(isTaken?.call(name) ?? false)) {
    return name;
  }
  final hash = sha256
      .convert(utf8.encode('$server\u0000$tool'))
      .toString()
      .substring(0, 8);
  return '${name.substring(0, min(name.length, 64 - hash.length - 1))}_$hash';
}

class McpToolDescriptor {
  McpToolDescriptor({
    required this.server,
    required this.name,
    required this.definition,
  }) : rawName = definition['name'] as String;
  final String server;
  final String rawName;
  final String name;
  final Map<String, dynamic> definition;
  String get description => definition['description'] as String? ?? '';
  Map<String, dynamic> get inputSchema =>
      Map<String, dynamic>.from(definition['inputSchema'] as Map);
  Map<String, dynamic> get outputSchema =>
      McpCallResult.outputSchema(definition['outputSchema']);
  Map<String, dynamic> toJson({bool full = false}) => {
    'name': name,
    'source': 'mcp',
    'server': server,
    'description': description,
    if (full) 'inputSchema': inputSchema,
    if (full) 'outputSchema': outputSchema,
    if (full && definition.containsKey('annotations'))
      'annotations': definition['annotations'],
  };
}
