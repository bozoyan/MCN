// 职责: 对照迁移前的实际 Host 集合验证模式与子 Agent 禁用名单。
// 关联文件:
//   lib/shared/services/ai/builtin_agent_tools.dart
//   lib/shared/models/ai_session_mode.dart
//   lib/shared/services/ai/tools.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/builtin_agent_tools.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/models/ai_session_mode.dart';

void main() {
  final hostNames = {...aiToolCatalog.map((tool) => tool.name), 'Codemode'};
  test('special modes retain exactly the old Host read set', () {
    for (final mode in AiSessionMode.values.where((m) => m.isSpecialMode)) {
      expect(hostNames.where(mode.canUseTool).toSet(), {
        'Read',
        'Glob',
        'Grep',
        'GraphSearch',
      });
      expect(mode.canUseTool('PluginSearch'), true);
    }
  });
  test('only explorer changes actual generic subagent Host permissions', () {
    final previous = {
      'Run',
      'Read',
      'Glob',
      'Grep',
      'Create',
      'Write',
      'Remove',
      'Edit',
      'Replace',
      'GraphSearch',
      'TodoWrite',
      'AgentSkill',
      'Codemode',
    };
    for (final slug in builtinSubAgentSlugs) {
      final actual = hostNames.difference(
        builtinSubAgentDisabledToolNames(slug)!,
      );
      expect(
        actual,
        slug == 'explorer'
            ? {'Read', 'Glob', 'Grep', 'GraphSearch', 'AgentSkill', 'Codemode'}
            : previous,
        reason: slug,
      );
    }
  });
  test('retired primary names have no policy', () {
    expect(builtinPrimaryAgentDisabledToolNames('planner'), null);
    for (final slug in builtinPrimaryAgentSlugs) {
      expect(
        hostNames.difference(builtinPrimaryAgentDisabledToolNames(slug)!),
        {'Read', 'Glob', 'Grep', 'GraphSearch'},
      );
    }
  });
}
