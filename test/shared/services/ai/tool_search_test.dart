// 职责: 验证精准名称优先、BM25 中英文排序、目录更新和服务隔离。
// 关联文件:
//   lib/shared/services/ai/tool_catalog.dart
//   lib/shared/services/ai/tool_search.dart
//   test/fixtures/mcp/evaluation_cases.json
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/services/ai/tool_search.dart';
import 'package:reveric/shared/services/ai/mcp/run_command_handler.dart';
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/services/ai/tool_catalog.dart';
import 'package:reveric/shared/services/mcp/runtime.dart';
import '../mcp/runtime_test.dart' show FakeConnection;

class SearchConnection extends FakeConnection {
  SearchConnection(this.field);
  final String field;
  @override
  Future<List<Map<String, dynamic>>> listTools() async => [
    {
      'name': 'search',
      'description': 'Search lookup',
      'inputSchema': {
        'type': 'object',
        'properties': {
          field: {'type': 'string'},
        },
      },
    },
  ];
}

ToolSearchDocument document(
  String name,
  String description, {
  String? rawName,
  Map<String, dynamic> schema = const {},
}) => ToolSearchDocument(
  name: name,
  rawName: rawName,
  description: description,
  inputSchema: schema,
);

class UpdatingSearchConnection extends FakeConnection {
  String name = 'read-notes';
  @override
  Future<List<Map<String, dynamic>>> listTools() async => [
    {
      'name': name,
      'description': 'Read documents',
      'inputSchema': <String, dynamic>{},
    },
  ];
}

void main() {
  test('exact names outrank BM25 even with long descriptions', () {
    final documents = [
      document('mcp__app__queue_read', 'Read a queued message of this thread.'),
      document(
        'mcp__dev_app__thread_read',
        'Read a thread. ${'timeline pagination history ' * 200}',
        rawName: 'thread_read',
      ),
    ];
    for (final query in [
      'thread_read',
      'THREAD_READ',
      'thread read',
      'dev-app__thread_read',
      'mcp__dev_app__thread_read',
    ]) {
      expect(
        rankToolSearch(query, documents).first,
        'mcp__dev_app__thread_read',
        reason: query,
      );
    }
    expect(rankToolSearch('read', documents).first, 'mcp__app__queue_read');
  });

  test('full calling name precedes a raw name with the same spelling', () {
    final name = 'mcp__notes__read';
    expect(
      rankToolSearch(name, [
        document('mcp__other__read', '', rawName: name),
        document(name, 'Read notes. ${'context ' * 100}', rawName: 'read'),
      ]),
      [name, 'mcp__other__read'],
    );
  });

  test('raw names remain searchable after sanitizing or hashing', () {
    final documents = [
      document('mcp__x__abc_12345678', '', rawName: '读取笔记'),
      document('mcp__x__a_b_abcdef12', '', rawName: 'a-b'),
      document('mcp__x__a_b_98765432', '', rawName: 'a_b'),
    ];
    expect(rankToolSearch('读取笔记', documents).first, 'mcp__x__abc_12345678');
    expect(rankToolSearch('a-b', documents).first, 'mcp__x__a_b_abcdef12');
    expect(rankToolSearch('a_b', documents).first, 'mcp__x__a_b_98765432');
  });

  test('BM25 favors rare terms and shorter relevant descriptions', () {
    final documents = [
      document('rare', 'quasar'),
      for (var i = 0; i < 8; i++) document('common_$i', 'search'),
    ];
    expect(rankToolSearch('search quasar', documents).first, 'rare');
    expect(
      rankToolSearch('quasar', [
        document('long', 'quasar ${'unrelated ' * 100}'),
        document('short', 'quasar'),
      ]),
      ['short', 'long'],
    );
  });

  test('BM25 saturates repeated keywords instead of rewarding stuffing', () {
    expect(
      rankToolSearch('quasar nebula', [
        document('stuffed', 'quasar ' * 100),
        document('balanced', 'quasar nebula'),
      ]).first,
      'balanced',
    );
  });

  test('name, description and parameter matches retain field priority', () {
    expect(
      rankToolSearch('quasar', [
        document('parameter', '', schema: {'description': 'quasar'}),
        document('description', 'quasar'),
        document('quasar_action', ''),
      ]),
      ['quasar_action', 'description', 'parameter'],
    );
  });

  test('camelCase, acronyms, plurals and partial names are discoverable', () {
    final documents = [
      document(
        'listIssues',
        'Queries HTTPServer',
        schema: {
          'properties': {
            'documentId': {'type': 'string'},
          },
        },
      ),
    ];
    for (final query in [
      'list issue',
      'query',
      'http server',
      'document id',
      'docum',
      'Issu',
    ]) {
      expect(rankToolSearch(query, documents), ['listIssues'], reason: query);
    }
  });

  test('Chinese bigrams and single characters preserve partial recall', () {
    final documents = [
      document('notes', '搜索笔记内容'),
      document('people', '搜索角色设定'),
    ];
    for (final query in ['笔记', '笔', '请查找笔记', '笔记 search']) {
      expect(rankToolSearch(query, documents).first, 'notes', reason: query);
    }
  });

  test('nested schema semantics are searchable without structural noise', () {
    final documents = [
      document(
        'lookup',
        '',
        schema: {
          'type': 'object',
          'properties': {
            'records': {
              'type': 'array',
              'items': {
                'anyOf': [
                  {
                    'properties': {
                      'documentId': {'description': 'Archived manuscripts'},
                    },
                  },
                  {
                    'enum': ['published'],
                  },
                ],
              },
            },
          },
        },
      ),
    ];
    for (final query in ['document id', 'manuscript', 'published']) {
      expect(rankToolSearch(query, documents), ['lookup'], reason: query);
    }
    expect(rankToolSearch('object', documents), isEmpty);
    expect(rankToolSearch('properties', documents), isEmpty);
  });

  test(
    'empty corpus, unknown terms, duplicate queries and ties are stable',
    () {
      final documents = [document('z', 'quasar'), document('a', 'quasar')];
      expect(rankToolSearch('quasar', []), isEmpty);
      expect(rankToolSearch('unknown', documents), isEmpty);
      expect(rankToolSearch('quasar', documents), ['a', 'z']);
      expect(rankToolSearch('quasar quasar', documents), ['a', 'z']);
      expect(() => rankToolSearch('  ', documents), throwsArgumentError);
    },
  );

  test(
    'Run search shares ranking, filtering, limits and fresh tool metadata',
    () async {
      final connection = UpdatingSearchConnection();
      final runtime = McpRuntime(connect: (_) async => connection);
      addTearDown(runtime.close);
      final config = McpServerConfig(
        name: 'notes',
        enabled: true,
        connection: McpHttpConfig(url: 'https://notes.example.test'),
      );
      await runtime.configure(McpSettings([config]));
      await runtime.startEnabled();
      final catalog = AgentToolCatalog(
        runtime: runtime,
        builtins: () => [
          const ToolDef(
            name: 'read_notes',
            description: 'Read documents',
            inputSchema: {},
          ),
        ],
      );
      final handler = McpRunCommandHandler(catalog);
      final result = await handler.execute('search', {
        'query': 'read-notes',
        'limit': 1,
      }, null);
      expect(
        (result['tools'] as List).single['name'],
        'mcp__notes__read_notes',
      );
      expect(result['exit_code'], 0);
      final builtins = await catalog.searchTool(
        'read notes',
        source: 'builtin',
      );
      expect((builtins['tools'] as List).single['name'], 'read_notes');
      final limited = await catalog.searchTool('read notes', limit: 1);
      expect(limited['truncated'], true);
      final scoped = await catalog.searchTool('read notes', mcpServer: 'notes');
      expect(
        (scoped['tools'] as List).single['name'],
        'mcp__notes__read_notes',
      );
      final session = McpSession(runtime);
      final isolated = AgentToolCatalog(
        runtime: runtime,
        builtins: () => [],
        session: session,
      );
      session.failures['notes'] = McpSessionFailure(
        'mcp_connection_failed',
        'unavailable',
        server: 'notes',
      );
      final unavailable = await isolated.searchTool('read-notes');
      expect(unavailable['tools'], isEmpty);
      expect(unavailable['complete'], false);
      expect(
        (await catalog.searchTool('read-notes', source: 'mcp'))['tools'],
        isNotEmpty,
      );
      connection.name = 'archive';
      await connection.onToolsChanged!();
      expect(
        (await catalog.searchTool('read-notes', source: 'mcp'))['tools'],
        isNot(contains(containsPair('name', 'mcp__notes__read_notes'))),
      );
      expect(
        (await catalog.searchTool('archive', source: 'mcp'))['tools'],
        contains(containsPair('name', 'mcp__notes__archive')),
      );
      await runtime.configure(McpSettings([config.copyWith(enabled: false)]));
      expect(
        (await catalog.searchTool('archive', source: 'mcp'))['tools'],
        isEmpty,
      );
      for (final limit in [0, 21]) {
        await expectLater(
          catalog.searchTool('notes', limit: limit),
          throwsArgumentError,
        );
      }
    },
  );

  test('MCP-E02/E03: twenty bilingual queries preserve tool identity', () async {
    final fixture =
        jsonDecode(
              await File(
                'test/fixtures/mcp/evaluation_cases.json',
              ).readAsString(),
            )
            as Map;
    final runtime = McpRuntime(
      connect: (config) async => SearchConnection(
        config.name == 'notes' ? 'documentId' : 'characterId',
      ),
    );
    addTearDown(runtime.close);
    final settings = McpSettings([
      McpServerConfig(
        name: 'notes',
        enabled: true,
        description:
            'Search notes, find documents and read note archive. 搜索笔记 查询资料 检索文档 读取笔记 查找资料',
        connection: McpHttpConfig(url: 'https://notes.example.test'),
      ),
      McpServerConfig(
        name: 'people',
        enabled: true,
        description:
            'Search characters, find people and person name cast lookup. 搜索角色 查询人物 查找角色 人物名字 角色设定',
        connection: McpHttpConfig(url: 'https://people.example.test'),
      ),
    ]);
    await runtime.configure(settings);
    await runtime.startEnabled();
    final catalog = AgentToolCatalog(runtime: runtime, builtins: () => []);
    for (final query in fixture['searchQueries'] as List) {
      final result = await catalog.searchTool(query['query'] as String);
      final names = (result['tools'] as List)
          .map((t) => (t as Map)['name'])
          .toList();
      expect(
        names.take(8),
        contains(query['expected']),
        reason: query['id'] as String,
      );
      expect(names.first, query['expected'], reason: query['id'] as String);
    }
    expect(
      runtime.tools.keys,
      containsAll(['mcp__notes__search', 'mcp__people__search']),
    );
    await runtime.configure(
      McpSettings([
        settings.servers.first.copyWith(enabled: false),
        settings.servers.last,
      ]),
    );
    expect((await catalog.searchTool('notes'))['tools'], isEmpty);
  });
}
