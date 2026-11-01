// 职责: 校验插件工具定义并计算来源覆盖后的有效工具。
// 关联文件:
//   lib/shared/services/plugins/host.dart
import 'dart:convert';
import 'package:mcp_dart/mcp_dart.dart' show JsonSchema;
// 本地 MCP SDK 的编译入口先校验定义；公开 validate 会同时校验实例。
// ignore: implementation_imports
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart'
    show compileJsonSchemaValidator;
import '../../agent/agent_tool_dispatcher.dart';

class PluginTool {
  PluginTool(this.pluginId, this.pluginName, this.source, this.definition) {
    final name = definition['name'];
    final schema = definition['inputSchema'];
    final display = definition['display'];
    if (name is! String ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(name) ||
        name.startsWith('mcp__') ||
        definition['description'] is! String ||
        (definition['description'] as String).trim().isEmpty ||
        schema is! Map<String, dynamic> ||
        schema['type'] != 'object') {
      throw const FormatException('Invalid tool definition');
    }
    compileJsonSchemaValidator(JsonSchema.fromJson(schema));
    if (display != null) {
      if (display is! Map<String, dynamic>) {
        throw const FormatException('Invalid display');
      }
      for (final key in ['title', 'summaryArg', 'resultPath']) {
        if (display.containsKey(key) && display[key] is! String) {
          throw FormatException('Invalid display.$key');
        }
      }
      if (display.containsKey('result') &&
          !['items', 'text', 'json'].contains(display['result'])) {
        throw const FormatException('Invalid display.result');
      }
      if (display.containsKey('summaryArg') &&
          (schema['properties'] is! Map ||
              !(schema['properties'] as Map).containsKey(
                display['summaryArg'],
              ))) {
        throw const FormatException('Unknown summary argument');
      }
    }
  }
  final String pluginId, pluginName, source;
  final Map<String, dynamic> definition;
  String get name => definition['name'] as String;
  Map<String, dynamic>? get display =>
      definition['display'] as Map<String, dynamic>?;
  ToolDef get toolDef => ToolDef(
    name: name,
    description: definition['description'] as String,
    inputSchema: definition['inputSchema'] as Map<String, dynamic>,
  );
}

class PluginRegistry {
  PluginRegistry({required this.hostToolNames});
  final Set<String> hostToolNames;
  final Map<String, List<PluginTool>> _plugins = {};
  final Set<String> knownToolNames = {};
  List<PluginTool> toolsFor(String pluginId) =>
      List.unmodifiable(_plugins[pluginId] ?? []);
  List<PluginTool> get effectiveTools {
    final result = <String, PluginTool>{};
    for (final tools in _plugins.values) {
      for (final tool in tools) {
        if (result[tool.name] == null || tool.source == 'local') {
          result[tool.name] = tool;
        }
      }
    }
    return List.unmodifiable(result.values);
  }

  PluginTool? resolve(String name) {
    for (final tool in effectiveTools) {
      if (tool.name == name) {
        return tool;
      }
    }
    return null;
  }

  void register(String pluginId, List<PluginTool> tools) {
    final names = <String>{};
    for (final tool in tools) {
      if (!names.add(tool.name) || hostToolNames.contains(tool.name)) {
        throw StateError('Reserved or duplicate tool: ${tool.name}');
      }
      for (final other in _plugins.entries) {
        if (other.key == pluginId) {
          continue;
        }
        for (final registered in other.value) {
          if (registered.name == tool.name &&
              registered.source == tool.source) {
            throw StateError(
              'Tool conflict: ${tool.name} (${registered.pluginId})',
            );
          }
        }
      }
    }
    _plugins[pluginId] = List.unmodifiable(tools);
    knownToolNames.addAll(names);
  }

  void remove(String pluginId) {
    _plugins.remove(pluginId);
  }
}

String canonicalPluginJson(Object? value) {
  Object? sort(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sort(v[key])};
    }
    if (v is List) {
      return v.map(sort).toList();
    }
    return v;
  }

  return jsonEncode(sort(value));
}
