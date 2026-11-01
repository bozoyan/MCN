// 职责: Slash 命令面板的统一条目模型 — 区分 subagent / skill 两类，供桌面与移动端匹配与渲染复用
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/providers/agent_skill_providers.dart
//   lib/shared/models/novel_workspace.dart

import 'novel_workspace.dart';

/// Slash 面板条目类别。选中后统一落到 `attachedReferences` 的 chip：
/// subagent → 软偏好提示；skill → 直接加载完整指令。
enum SlashEntryKind { subagent, skill }

/// `/` 命令面板里的一条候选（subagent 或 skill）。
class SlashEntry {
  const SlashEntry({
    required this.kind,
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });

  final SlashEntryKind kind;

  /// subagent.id / skill.id — 用于选择去重与定位。
  final String id;

  /// 展示 + chip 标签 + 发送时解析键（subagent.name / skill.name）。
  final String label;

  final String description;

  /// RevericIcons.* 图标名。
  final String icon;

  /// 面板里展示的命令形态，如 `/summary`（空格转下划线）。
  String get command => '/${label.replaceAll(' ', '_')}';

  /// 选中后落到 `attachedReferences` 的 chip。section 用占位（overview），
  /// 真正信息在 kind + itemId(id) + label(name)，与 agent_rule chip 同款。
  AiContextReference toReference() {
    return AiContextReference(
      kind: kind == SlashEntryKind.skill
          ? AiContextReferenceKind.skill
          : AiContextReferenceKind.subagent,
      section: NovelWorkspaceSection.overview,
      itemId: id,
      label: label,
    );
  }
}
