// 职责: 锁定 Subagents Run handler 的字段约束与内置 SubAgent 保护边界。
// 关联文件:
//   lib/shared/services/ai/subagents_run_command_handler.dart
//   lib/shared/providers/subagent_providers.dart
//   lib/shared/services/ai/builtin_agent_tools.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/models/subagent.dart';
import 'package:reveric/shared/providers/subagent_providers.dart';
import 'package:reveric/shared/services/ai/subagents_run_command_handler.dart';

const _builtinAgent = SubAgent(
  id: 'builtin-writer',
  slug: 'writer',
  name: '正文写手',
  description: '内置正文写作专家',
  prompt: '',
  scope: SubAgentScope.global,
  sortOrder: 0,
);

const _customAgent = SubAgent(
  id: 'custom-continuity',
  slug: 'continuity_auditor',
  name: '连续性审查',
  description: '检查连续性',
  prompt: '审查上下文并报告问题',
  scope: SubAgentScope.global,
  sortOrder: 1,
  useCustomPrompt: true,
);

class _TestGlobalSubAgents extends GlobalSubAgents {
  static List<SubAgent> agents = [];
  static List<SubAgent> updated = [];
  static List<String> deletedIds = [];

  @override
  Future<List<SubAgent>> build() async => agents;

  @override
  Future<void> updateSubAgent(SubAgent agent) async {
    updated.add(agent);
  }

  @override
  Future<void> deleteSubAgent(String id) async {
    deletedIds.add(id);
  }
}

void main() {
  late ProviderContainer container;
  late SubagentsRunCommandHandler handler;

  setUp(() {
    _TestGlobalSubAgents.agents = [_builtinAgent, _customAgent];
    _TestGlobalSubAgents.updated = [];
    _TestGlobalSubAgents.deletedIds = [];
    container = ProviderContainer(
      overrides: [
        globalSubAgentsProvider.overrideWith(_TestGlobalSubAgents.new),
      ],
    );
    handler = SubagentsRunCommandHandler(container: container);
  });

  tearDown(() {
    container.dispose();
  });

  test('create requires slug', () async {
    final result = await handler.run({
      'action': 'create',
      'name': '连续性审查',
      'description': '检查连续性',
      'prompt': '审查上下文并报告问题',
    });

    expect(result['ok'], isFalse);
    expect(result['error_code'], 'invalid_argument');
  });

  test('delete requires id', () async {
    final result = await handler.run({'action': 'delete'});

    expect(result['ok'], isFalse);
    expect(result['error_code'], 'invalid_argument');
  });

  test('list only exposes custom subagents', () async {
    final result = await handler.run({'action': 'list'});
    final entries = result['entries']! as List<Map<String, dynamic>>;

    expect(result['ok'], isTrue);
    expect(entries, hasLength(1));
    expect(entries.single, containsPair('id', _customAgent.id));
    expect(entries.single, containsPair('slug', _customAgent.slug));
  });

  test('built-in subagents cannot be updated or deleted', () async {
    final update = await handler.run({
      'action': 'update',
      'id': _builtinAgent.id,
      'enabled': false,
    });
    final delete = await handler.run({
      'action': 'delete',
      'id': _builtinAgent.id,
      'confirm': true,
    });

    expect(update['error_code'], 'permission_denied');
    expect(delete['error_code'], 'permission_denied');
    expect(_TestGlobalSubAgents.updated, isEmpty);
    expect(_TestGlobalSubAgents.deletedIds, isEmpty);
  });

  test(
    'built-in slugs cannot be created or assigned to custom subagents',
    () async {
      final create = await handler.run({
        'action': 'create',
        'slug': _builtinAgent.slug,
        'name': '另一个正文写手',
        'description': '应被拒绝',
        'prompt': '应被拒绝',
      });
      final update = await handler.run({
        'action': 'update',
        'id': _customAgent.id,
        'slug': _builtinAgent.slug,
      });

      expect(create['error_code'], 'invalid_argument');
      expect(update['error_code'], 'invalid_argument');
      expect(_TestGlobalSubAgents.updated, isEmpty);
    },
  );

  test('custom deletion requires confirmation', () async {
    final unconfirmed = await handler.run({
      'action': 'delete',
      'id': _customAgent.id,
    });
    final invalidNumber = await handler.run({
      'action': 'delete',
      'id': _customAgent.id,
      'confirm': 2,
    });
    final confirmed = await handler.run({
      'action': 'delete',
      'id': _customAgent.id,
      'confirm': true,
    });

    expect(unconfirmed['error_code'], 'failed_precondition');
    expect(invalidNumber['error_code'], 'failed_precondition');
    expect(confirmed['ok'], isTrue);
    expect(_TestGlobalSubAgents.deletedIds, [_customAgent.id]);
  });
}
