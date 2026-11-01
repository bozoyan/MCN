// 职责: 验证 MCP 目录身份、发现结果契约、中文检索和摘要隔离。
// 关联文件:
//   lib/shared/services/ai/tool_catalog.dart
//   lib/shared/models/mcp/tool_descriptor.dart
//   lib/shared/services/ai/mcp/run_command_handler.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' as sdk;
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/models/mcp/tool_descriptor.dart';
import 'package:reveric/shared/services/ai/tool_catalog.dart';
import 'package:reveric/shared/services/ai/mcp/run_command_handler.dart';
import 'package:reveric/shared/services/mcp/runtime.dart';
import 'runtime_test.dart' show FakeConnection;

void main() {
  test(
    'both describe entrances declare the actual MCP result envelope',
    () async {
      final runtime = McpRuntime(connect: (_) async => _SearchConnection());
      addTearDown(runtime.close);
      await runtime.configure(
        McpSettings([
          McpServerConfig(
            name: 'notes',
            enabled: true,
            connection: McpHttpConfig(url: 'https://example.test'),
          ),
        ]),
      );
      await runtime.ensureReady('notes');
      final catalog = AgentToolCatalog(runtime: runtime, builtins: () => []);
      final handler = McpRunCommandHandler(catalog);
      final definition = await catalog.describeTool('mcp__notes__search');
      final described = await handler.execute('describe', {
        'name': 'mcp__notes__search',
      }, null);
      expect(described['outputSchema'], definition['outputSchema']);
      final schema = definition['outputSchema'] as Map<String, dynamic>;
      final properties = schema['properties'] as Map;
      expect(properties, contains('structuredContent'));
      expect(properties, isNot(contains('results')));
      final result = await handler.execute('call', {
        'name': 'mcp__notes__search',
        'arguments': <String, dynamic>{},
      }, null);
      sdk.JsonSchema.fromJson(schema).validate(result);
      expect((result['structuredContent'] as Map)['results'], ['found']);
      // The advertised payload schema must reject a malformed payload too.
      expect(
        () => sdk.JsonSchema.fromJson(schema).validate({
          ...result,
          'structuredContent': {'results': 42},
        }),
        throwsA(anything),
      );
      expect(
        runtime.tools['mcp__notes__search']!.definition['outputSchema'],
        _searchOutputSchema,
      );
    },
  );

  test(
    'tools without output schemas still declare content and optional data',
    () {
      final definition = McpToolDescriptor(
        server: 'notes',
        name: 'plain',
        definition: {'name': 'plain', 'inputSchema': <String, dynamic>{}},
      ).toJson(full: true);
      final schema = definition['outputSchema'] as Map<String, dynamic>;
      final properties = schema['properties'] as Map;
      expect(properties, contains('content'));
      expect(properties, contains('structuredContent'));
      expect(schema['required'], isNot(contains('structuredContent')));
    },
  );

  test(
    'schema nesting relocates references without rewriting literal data',
    () {
      const literal = {r'$ref': '#/literal'};
      final descriptor = McpToolDescriptor(
        server: 'notes',
        name: 'search',
        definition: {
          'name': 'search',
          'inputSchema': <String, dynamic>{},
          'outputSchema': {
            'type': 'object',
            'properties': {
              'child': {r'$ref': '#'},
              r'$ref': {'type': 'string', 'default': '#/literal'},
              'data': {
                'const': literal,
                'examples': [literal],
              },
              'external': {r'$ref': 'https://example.test/schema'},
              'scoped': {r'$id': 'https://example.test/scoped', r'$ref': '#'},
            },
          },
        },
      );
      final nested =
          (descriptor.outputSchema['properties'] as Map)['structuredContent']
              as Map;
      final fields = nested['properties'] as Map;
      expect(fields['child'], {r'$ref': '#/properties/structuredContent'});
      expect(fields[r'$ref'], {'type': 'string', 'default': '#/literal'});
      expect(fields['data'], {
        'const': literal,
        'examples': [literal],
      });
      expect(fields['external'], {r'$ref': 'https://example.test/schema'});
      expect(fields['scoped'], {
        r'$id': 'https://example.test/scoped',
        r'$ref': '#',
      });
    },
  );

  test(
    'verified descriptions survive disconnect and foreground transitions',
    () async {
      final connections = <FakeConnection>[];
      final runtime = McpRuntime(
        connect: (_) async {
          final connection = FakeConnection();
          connections.add(connection);
          return connection;
        },
      );
      addTearDown(runtime.close);
      final config = McpServerConfig(
        name: 'notes',
        enabled: true,
        connection: McpHttpConfig(url: 'https://example.test'),
      );
      await runtime.configure(McpSettings([config]));
      await runtime.ensureReady('notes');
      final catalog = AgentToolCatalog(runtime: runtime, builtins: () => []);
      final prompt = catalog.summaryPrompt();
      connections.last.onClosed?.call();
      expect(catalog.summaryPrompt(), prompt);
      await runtime.ensureReady('notes');
      expect(catalog.summaryPrompt(), prompt);
      await runtime.suspend();
      expect(catalog.summaryPrompt(), prompt);
      await runtime.resume();
      expect(catalog.summaryPrompt(), prompt);
      await runtime.ensureReady('notes');
      expect(catalog.summaryPrompt(), prompt);
      await runtime.configure(
        McpSettings([
          config.copyWith(connection: McpHttpConfig(url: 'https://new.test')),
        ]),
      );
      expect(catalog.summaryPrompt(), isNot(prompt));
    },
  );
  test('names are sanitized and only hashed when too long', () {
    final valid = RegExp(r'^[a-zA-Z0-9_]+$');
    expect(mcpToolName('notes', 'search'), 'mcp__notes__search');
    expect(mcpToolName('my-notes', 'get-issue'), 'mcp__my_notes__get_issue');
    final long = mcpToolName('a' * 100, 'b' * 100);
    expect(long.length, 64);
    expect(valid.hasMatch(long), true);
    expect(valid.hasMatch(mcpToolName('资料', '搜索')), true);
  });
  test('tools whose sanitized names collide all get distinct hashes', () async {
    final tools = {
      'notes': ['a-b', 'a_b', 'search'],
      'a': ['b__c'],
      'a__b': ['c'],
    };
    final runtime = McpRuntime(
      connect: (config) async => _ToolsConnection(tools[config.name]!),
    );
    addTearDown(runtime.close);
    await runtime.configure(
      McpSettings([
        for (final name in tools.keys)
          McpServerConfig(
            name: name,
            enabled: true,
            connection: McpHttpConfig(url: 'https://example.test/$name'),
          ),
      ]),
    );
    await runtime.startEnabled();
    final names = runtime.tools.keys.toSet();
    expect(names, hasLength(5));
    expect(names, contains('mcp__notes__search'));
    expect(names, isNot(contains('mcp__notes__a_b')));
    expect(names, isNot(contains('mcp__a__b__c')));
    expect(names.where((n) => n.startsWith('mcp__notes__a_b_')), hasLength(2));
    expect(names.where((n) => n.startsWith('mcp__a__b__c_')), hasLength(2));
    for (final entry in runtime.tools.entries) {
      expect(entry.value.name, entry.key);
    }
  });
  test(
    'partial directory is explicit and only configured summaries enter prompt',
    () async {
      final runtime = McpRuntime(connect: (_) async => FakeConnection());
      addTearDown(runtime.close);
      await runtime.configure(
        McpSettings([
          McpServerConfig(
            name: 'notes',
            enabled: true,
            description: '搜索笔记',
            connection: McpHttpConfig(
              url: 'https://example.test',
              bearerToken: 'private-token',
            ),
          ),
          McpServerConfig(
            name: 'slow',
            enabled: true,
            connection: McpHttpConfig(url: 'https://example.test'),
          ),
        ]),
      );
      await runtime.ensureReady('notes');
      final catalog = AgentToolCatalog(runtime: runtime, builtins: () => []);
      final before = catalog.summaryPrompt();
      final found = await catalog.searchTool('笔记');
      expect(found['complete'], false);
      expect((found['tools'] as List).single['name'], 'mcp__notes__search');
      expect(found['pendingServers'], [
        {'name': 'slow', 'status': 'disconnected'},
      ]);
      expect(catalog.summaryPrompt(), before);
      expect(before, isNot(contains('private-token')));
      expect(before, isNot(contains('https://')));
      await expectLater(catalog.listTools(mcpServer: ''), throwsArgumentError);
      await expectLater(
        catalog.searchTool('notes', source: 'builtin', mcpServer: 'notes'),
        throwsArgumentError,
      );
    },
  );
}

const _searchOutputSchema = <String, dynamic>{
  'type': 'object',
  r'$defs': {
    'hit': {'type': 'string'},
  },
  'properties': {
    'results': {
      'type': 'array',
      'items': {r'$ref': r'#/$defs/hit'},
    },
  },
  'required': ['results'],
};

class _SearchConnection extends FakeConnection {
  @override
  Future<List<Map<String, dynamic>>> listTools() async => [
    {
      'name': 'search',
      'inputSchema': {'type': 'object'},
      'outputSchema': _searchOutputSchema,
    },
  ];

  @override
  Future<Map<String, dynamic>> callTool(
    String name,
    Map<String, dynamic> arguments, {
    sdk.AbortSignal? signal,
    void Function(sdk.Progress)? onProgress,
  }) async => {
    'content': [
      {'type': 'text', 'text': '{"results":["found"]}'},
    ],
    'structuredContent': {
      'results': ['found'],
    },
  };
}

class _ToolsConnection extends FakeConnection {
  _ToolsConnection(this.names);
  final List<String> names;
  @override
  Future<List<Map<String, dynamic>>> listTools() async => [
    for (final name in names)
      {
        'name': name,
        'inputSchema': {'type': 'object'},
      },
  ];
}
