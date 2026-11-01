// 职责: 桌面端小说编辑页 — 保存 Agent Rule 编辑草稿并返回已保存实体。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/widgets/agent_management/agent_edit_save_contract.dart
//   lib/shared/services/novel_content.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/error-handling.md
part of 'novel_editor.dart';

Future<AgentRule?> _saveAgentRuleEditDraft({
  required WidgetRef ref,
  required String? databasePath,
  required AgentRuleEditDraft draft,
}) async {
  final path = databasePath;
  if (path == null) {
    return null;
  }

  final service = ref.read(novelContentServiceProvider(path));
  final existingRules = await service.getAgentRules();
  final nameConflict = existingRules.any(
    (rule) => rule.name == draft.name && rule.id != draft.original.id,
  );
  if (nameConflict) {
    throw AgentRuleNameConflictException(draft.name);
  }

  final savedRule = draft.toRule(updatedAt: DateTime.now());
  await service.upsertAgentRule(savedRule);
  return savedRule;
}
