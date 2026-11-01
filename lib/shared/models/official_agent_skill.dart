// 职责: 定义本地打包官方技能的目录摘要与安装快照。
// 关联文件:
//   lib/shared/models/agent_skill_reference.dart
//   lib/shared/services/bundled_official_skills.dart
//   lib/shared/services/agent_skill_catalog_service.dart

import 'agent_skill_reference.dart';

export 'agent_skill_reference.dart' show AgentSkillReferenceFile;

/// 本地打包官方技能的目录摘要。
///
/// 用于目录浏览与搜索；不包含完整指令或使用条件。
///
/// 从客户端打包资源读取，仅作内存载体。
class OfficialAgentSkillSummary {
  const OfficialAgentSkillSummary({
    required this.listingId,
    required this.name,
    required this.description,
    required this.category,
    required this.tags,
    this.badge,
    required this.version,
    required this.updatedAt,
  });

  final String listingId;
  final String name;
  final String description;
  final String category;
  final List<String> tags;

  /// 打包规格表中的展示徽章；null/空表示无徽章。
  final String? badge;

  final int version;
  final String updatedAt;
}

/// 官方 AgentSkill 单条详情。
///
/// 仅在打开详情、安装或升级时按 listing_id（即技能 name）读取。
class OfficialAgentSkill extends OfficialAgentSkillSummary {
  const OfficialAgentSkill({
    required super.listingId,
    required super.name,
    required super.description,
    required super.category,
    required super.tags,
    super.badge,
    required super.version,
    required super.updatedAt,
    required this.whenToUse,
    required this.prompt,
    this.references = const [],
    required this.sortOrder,
  });

  final String whenToUse;
  final String prompt;

  /// `references/` 附件；安装/升级时写入本地技能快照。
  final List<AgentSkillReferenceFile> references;
  final int sortOrder;
}

/// 官方目录列表。本地打包目录固定十余条，无分页。
class OfficialAgentSkillCatalog {
  const OfficialAgentSkillCatalog({this.agentSkills = const []});

  final List<OfficialAgentSkillSummary> agentSkills;
}
