// 职责: 合并内置与 MCP 工具目录，提供分页发现、搜索和服务摘要。
// 关联文件:
//   lib/shared/services/mcp/runtime.dart
//   lib/shared/models/mcp/tool_descriptor.dart
//   lib/shared/services/ai/tool_search.dart
//   lib/shared/agent/agent_tool_dispatcher.dart
import 'dart:convert';
import '../../agent/agent_tool_dispatcher.dart';
import '../../models/mcp/config.dart';
import '../../models/mcp/tool_descriptor.dart';
import '../mcp/runtime.dart';
import 'tool_search.dart';

class AgentToolCatalog {
  AgentToolCatalog({
    required this.runtime,
    required this.builtins,
    this.session,
  });
  final McpRuntime runtime;
  final McpSession? session;
  Map<String, McpToolDescriptor> get tools => session?.tools ?? runtime.tools;
  final declarationErrors = <String, String>{};
  final List<ToolDef> Function() builtins;
  List<McpServerConfig> get servers =>
      runtime.configs
          .where(
            (s) =>
                s.enabled &&
                (runtime.supportsStdio || s.connection is McpHttpConfig),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  String? description(McpServerConfig config) =>
      config.description?.trim().isNotEmpty == true
      ? config.description
      : runtime.serverDescription(config.name);
  Map<String, dynamic> listMcpServers({String? cursor}) => _page(
    [
      for (final config in servers)
        {
          'name': config.name,
          if (description(config) != null)
            'description': _short(description(config)!, 250),
          'status': session?.failure(config.name) != null
              ? 'error'
              : runtime.states[config.name]?.status.name ?? 'disconnected',
          if (session?.failure(config.name) case final failure?)
            'error': _short(failure.toString(), 500),
          'transport': config.connection is McpStdioConfig
              ? 'stdio'
              : 'streamable_http',
          'exposure': config.exposure.name,
        },
    ],
    key: 'servers',
    extra: _status(null),
    cursor: cursor,
  );

  Future<void> _target(String? server) async {
    if (server == null) {
      return;
    }
    if (session?.failure(server) case final failure?) {
      throw failure;
    }
    if (server.isEmpty || !servers.any((s) => s.name == server)) {
      throw ArgumentError('Unknown or empty MCP server');
    }
    await (session?.ensureReady(server) ?? runtime.ensureReady(server));
  }

  Map<String, dynamic> _status(String? server) {
    final pending = <Map<String, dynamic>>[];
    session?.captureConfigurationErrors();
    final failed = <Map<String, dynamic>>[
      if (session?.configurationFailure case final failure?)
        {
          'status': 'error',
          'error_code': failure.code,
          'error': _short(failure.toString(), 500),
        },
      for (final entry
          in (session?.failures ?? <String, McpSessionFailure>{}).entries)
        if (server == null || server == entry.key)
          {
            'name': entry.key,
            'status': 'error',
            'error_code': entry.value.code,
            'error': _short(entry.value.toString(), 500),
          },
    ];
    for (final config in servers.where(
      (s) => server == null || s.name == server,
    )) {
      if (session?.failure(config.name) != null) {
        continue;
      }
      final state = runtime.states[config.name];
      final status = state?.status ?? McpConnectionStatus.disconnected;
      final entry = {
        'name': config.name,
        'status': status.name,
        if (state?.error != null) 'error': _short(state!.error!, 500),
      };
      if ([
        McpConnectionStatus.error,
        McpConnectionStatus.needs_auth,
      ].contains(status)) {
        failed.add(entry);
      } else if (status != McpConnectionStatus.ready) {
        pending.add(entry);
      }
    }
    return {
      'complete': pending.isEmpty && failed.isEmpty,
      'pendingServers': pending,
      'failedServers': failed,
    };
  }

  List<Map<String, dynamic>> _definitions({String? server, String? source}) {
    final result = <Map<String, dynamic>>[
      if (server == null && source != 'mcp')
        for (final tool in builtins())
          {
            'name': tool.name,
            'description': tool.description,
            'source': 'builtin',
            'inputSchema': tool.inputSchema,
            if (tool.outputSchema != null) 'outputSchema': tool.outputSchema,
          },
      if (source != 'builtin')
        for (final tool in tools.values.where(
          (t) => server == null || t.server == server,
        ))
          {
            ...tool.toJson(full: true),
            if (declarationErrors.containsKey(tool.name))
              'declarationError': declarationErrors[tool.name],
          },
    ];
    result.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return result;
  }

  Map<String, dynamic> _summary(Map<String, dynamic> tool) => {
    for (final key in ['name', 'source', 'server', 'declarationError'])
      if (tool.containsKey(key)) key: tool[key],
    'description': _short(tool['description'] as String, 500),
  };
  Future<Map<String, dynamic>> listTools({
    String? mcpServer,
    String? cursor,
  }) async {
    await _target(mcpServer);
    return _page(
      _definitions(server: mcpServer).map(_summary).toList(),
      key: 'tools',
      cursor: cursor,
      extra: {
        ..._status(mcpServer),
        if (mcpServer != null &&
            runtime.states[mcpServer]?.instructions != null)
          'instructions': _short(
            runtime.states[mcpServer]!.instructions!,
            1000,
          ),
      },
    );
  }

  Future<Map<String, dynamic>> searchTool(
    String query, {
    String? mcpServer,
    String? source,
    int limit = 8,
  }) async {
    if (query.trim().isEmpty ||
        limit < 1 ||
        limit > 20 ||
        (source != null && !['builtin', 'mcp'].contains(source)) ||
        (source == 'builtin' && mcpServer != null)) {
      throw ArgumentError('Invalid tool search options');
    }
    await _target(mcpServer);
    final definitions = {
      for (final tool in _definitions(server: mcpServer, source: source))
        tool['name'] as String: tool,
    };
    final serverDescriptions = {
      for (final server in servers) server.name: description(server) ?? '',
    };
    final currentTools = tools;
    final matches = rankToolSearch(query, [
      for (final tool in definitions.values)
        ToolSearchDocument(
          name: tool['name'] as String,
          rawName: tool['source'] == 'mcp'
              ? currentTools[tool['name']]?.rawName
              : null,
          description:
              '${tool['description']} ${serverDescriptions[tool['server']] ?? ''}',
          inputSchema: tool['inputSchema'] as Map<String, dynamic>,
        ),
    ]);
    final result = _page(
      matches.take(limit).map((name) => _summary(definitions[name]!)).toList(),
      key: 'tools',
      extra: source == 'builtin'
          ? {'complete': true, 'pendingServers': [], 'failedServers': []}
          : _status(mcpServer),
    );
    result['truncated'] = result['truncated'] == true || matches.length > limit;
    result.remove('nextCursor');
    return result;
  }

  Future<Map<String, dynamic>> describeTool(String name) async {
    if (session?.toolFailure(name) case final failure?) {
      throw failure;
    }
    final known = runtime.tools[name] ?? runtime.knownTools[name];
    if (known != null) {
      await _target(known.server);
    }
    final found = _definitions().where((t) => t['name'] == name).firstOrNull;
    if (found == null) {
      throw StateError('Tool not found; discover current tools.');
    }
    return found;
  }

  String summaryPrompt() {
    String escape(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final failed = _status(null)['failedServers'] as List;
    final failures = failed.isEmpty
        ? ''
        : '<unavailable_mcp_servers>${escape(jsonEncode(failed))}</unavailable_mcp_servers>\n';
    final available = servers
        .where((s) => session?.failure(s.name) == null)
        .toList();
    if (available.isEmpty) {
      return failures;
    }
    return '$failures<available_mcp_servers>\n${available.map((s) => '<mcp_server><name>${escape(s.name)}</name>${description(s) == null ? '' : '<description>${escape(_short(description(s)!, 250))}</description>'}</mcp_server>').join('\n')}\n</available_mcp_servers>\n'
        '使用 Run mcp list/search/describe 或 Codemode listTools/searchTool/describeTool 发现实际工具定义。名称使用发现结果中的 name。';
  }

  static String _short(String text, int length) =>
      String.fromCharCodes(text.runes.take(length));
  Map<String, dynamic> _page(
    List<Map<String, dynamic>> entries, {
    required String key,
    String? cursor,
    Map<String, dynamic> extra = const {},
  }) {
    final offset = cursor == null ? 0 : int.tryParse(cursor);
    if (offset == null || offset < 0 || offset > entries.length) {
      throw ArgumentError('Invalid catalog cursor');
    }
    final selected = <Map<String, dynamic>>[];
    var next = offset;
    Map<String, dynamic> envelope() => {
      key: selected,
      ...extra,
      'truncated': next < entries.length,
      if (next < entries.length) 'nextCursor': '$next',
    };
    while (next < entries.length) {
      selected.add(entries[next]);
      next++;
      if (jsonEncode(envelope()).runes.length > 4096) {
        selected.removeLast();
        next--;
        break;
      }
    }
    if (next == offset && next < entries.length) {
      throw StateError('Catalog entry exceeds page budget');
    }
    return envelope();
  }
}
