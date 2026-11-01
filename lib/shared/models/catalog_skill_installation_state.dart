// 职责: 根据当前小说的已安装快照与目录版本，判断目录技能应安装、禁用或升级。
// 关联文件:
//   lib/shared/models/novel_agent_skill.dart
//   lib/shared/providers/novel_agent_skill_providers.dart
//   lib/desktop/features/agent_skills/official_catalog_tab.dart
//   lib/mobile/features/agent_skills/catalog_skill_detail_page.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/enum-naming.md
import 'novel_agent_skill.dart';

enum CatalogSkillInstallationStatus {
  loading,
  not_installed,
  installed,
  upgrade_available,
}

class CatalogSkillInstallationState {
  const CatalogSkillInstallationState._({
    required this.status,
    this.staleInstallationIds = const [],
  });

  const CatalogSkillInstallationState.loading()
    : this._(status: CatalogSkillInstallationStatus.loading);

  const CatalogSkillInstallationState.notInstalled()
    : this._(status: CatalogSkillInstallationStatus.not_installed);

  const CatalogSkillInstallationState.installed()
    : this._(status: CatalogSkillInstallationStatus.installed);

  const CatalogSkillInstallationState.upgradeAvailable(
    List<String> staleInstallationIds,
  ) : this._(
        status: CatalogSkillInstallationStatus.upgrade_available,
        staleInstallationIds: staleInstallationIds,
      );

  final CatalogSkillInstallationStatus status;

  /// 同一目录来源可因重命名安装出多个副本；升级时应同步更新所有旧副本。
  final List<String> staleInstallationIds;

  bool get canInstall => status == CatalogSkillInstallationStatus.not_installed;

  bool get canUpgrade =>
      status == CatalogSkillInstallationStatus.upgrade_available;

  bool get isInstalled => status == CatalogSkillInstallationStatus.installed;
}

/// 官方技能的稳定身份是目录 `name`：优先 `source_display_name`，否则当前 `name`。
String officialSkillCatalogName(NovelAgentSkillModel skill) {
  final displayName = skill.sourceDisplayName?.trim();
  if (displayName != null && displayName.isNotEmpty) {
    return displayName;
  }
  return skill.name;
}

CatalogSkillInstallationState resolveCatalogSkillInstallationState({
  required List<NovelAgentSkillModel>? installedSkills,
  required AgentSkillSourceKind sourceKind,
  required String listingId,
  required int catalogVersion,
  String? catalogName,
}) {
  if (installedSkills == null) {
    return const CatalogSkillInstallationState.loading();
  }

  final installations = installedSkills
      .where((skill) {
        if (skill.sourceKind != sourceKind) {
          return false;
        }
        if (sourceKind == AgentSkillSourceKind.official) {
          return officialSkillCatalogName(skill) == (catalogName ?? listingId);
        }
        return skill.sourceListingPublicId == listingId;
      })
      .toList(growable: false);
  if (installations.isEmpty) {
    return const CatalogSkillInstallationState.notInstalled();
  }

  final staleIds = <String>[
    for (final skill in installations)
      if ((int.tryParse(skill.sourceVersion ?? '') ?? 0) < catalogVersion)
        skill.id,
  ];
  if (staleIds.isNotEmpty) {
    return CatalogSkillInstallationState.upgradeAvailable(staleIds);
  }
  return const CatalogSkillInstallationState.installed();
}
