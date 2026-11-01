// 职责: AgentSkill 历史版本领域模型 —— 变更来源枚举、列表摘要与全量快照。
// 关联文件:
//   lib/shared/database/daos/novel_agent_skill_revision_dao.dart
//   lib/shared/models/novel_agent_skill.dart
//   lib/shared/models/agent_skill_reference.dart
//   lib/shared/providers/novel_agent_skill_providers.dart
// 遵循的 Rules:
//   .agents/rules/enum-naming.md

import 'agent_skill_reference.dart';

/// 历史版本的产生来源。
///
/// [baseline] 专指 v29 之前就已存在的技能在首次编辑时懒回填出来的
/// 「最早已知状态」，与 [install] 区分开，便于 UI 说明它不是安装快照。
enum SkillRevisionSource {
  baseline,
  install,
  user_edit,
  ai_edit,
  upgrade;

  String get dbValue => name;

  static SkillRevisionSource fromDbValue(String value) {
    for (final source in SkillRevisionSource.values) {
      if (source.name == value) {
        return source;
      }
    }
    return SkillRevisionSource.user_edit;
  }
}

/// 历史版本列表项。不含 prompt 与附件正文，供列表查询使用。
class AgentSkillRevisionSummary {
  const AgentSkillRevisionSummary({
    required this.id,
    required this.skillId,
    required this.revision,
    required this.name,
    required this.description,
    required this.changeSource,
    required this.createdAt,
    this.turnId,
    this.changeNote,
    this.fileCount = 0,
  });

  final String id;
  final String skillId;
  final int revision;
  final String name;
  final String description;
  final SkillRevisionSource changeSource;
  final DateTime createdAt;
  final String? turnId;
  final String? changeNote;
  final int fileCount;
}

/// 历史版本全量快照，供 diff 与复制使用。
class AgentSkillRevisionDetail {
  const AgentSkillRevisionDetail({
    required this.summary,
    required this.whenToUse,
    required this.prompt,
    required this.category,
    required this.tags,
    required this.agentScopes,
    required this.contentHash,
    this.references = const [],
  });

  final AgentSkillRevisionSummary summary;
  final String whenToUse;
  final String prompt;
  final String category;
  final List<String> tags;
  final List<String> agentScopes;
  final String contentHash;
  final List<AgentSkillReferenceFile> references;

  String get id => summary.id;
  int get revision => summary.revision;
  String get name => summary.name;
  String get description => summary.description;
}
