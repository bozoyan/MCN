// 职责: Agent 编辑面板保存合同 — 定义规则面板提交给父级保存的草稿数据。
// 关联文件:
//   lib/desktop/widgets/agent_management/agent_rule_edit_panel.dart
//   lib/desktop/pages/novel_editor_agent_editing.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import '../../../shared/models/agent_rule.dart';

class AgentRuleEditDraft {
  const AgentRuleEditDraft({
    required this.original,
    required this.name,
    required this.content,
    required this.enabled,
  });

  final AgentRule original;
  final String name;
  final String content;
  final bool enabled;

  AgentRule toRule({DateTime? updatedAt}) {
    return original.copyWith(
      name: name,
      content: content,
      enabled: enabled,
      updatedAt: updatedAt,
    );
  }
}

typedef AgentRuleEditSaver =
    Future<AgentRule?> Function(AgentRuleEditDraft draft);
