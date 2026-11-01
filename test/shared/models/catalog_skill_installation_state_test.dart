// 职责: 目录技能安装状态回归测试 — 确保同源安装会禁用安装，较旧快照会转为升级。
// 关联文件:
//   lib/shared/models/catalog_skill_installation_state.dart
//   lib/shared/models/novel_agent_skill.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/enum-naming.md
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/catalog_skill_installation_state.dart';
import 'package:reveric/shared/models/novel_agent_skill.dart';

void main() {
  const listingId = 'official-writing';

  NovelAgentSkillModel installed({
    required String id,
    required String? version,
    String sourceListingId = listingId,
    String catalogName = listingId,
  }) {
    return NovelAgentSkillModel(
      id: id,
      sourceKind: AgentSkillSourceKind.official,
      sourceListingPublicId: sourceListingId,
      sourceDisplayName: catalogName,
      sourceVersion: version,
      name: id,
      description: '',
      prompt: '',
    );
  }

  test(
    'keeps the install action disabled when the catalog version is installed',
    () {
      final state = resolveCatalogSkillInstallationState(
        installedSkills: [installed(id: 'installed-1', version: '3')],
        sourceKind: AgentSkillSourceKind.official,
        listingId: listingId,
        catalogVersion: 3,
      );

      expect(state.status, CatalogSkillInstallationStatus.installed);
      expect(state.canInstall, isFalse);
      expect(state.canUpgrade, isFalse);
    },
  );

  test('official leftover uuid listing still matches catalog name', () {
    final state = resolveCatalogSkillInstallationState(
      installedSkills: [
        installed(
          id: 'legacy',
          version: '1',
          sourceListingId: '09a34832-9cac-46a2-853c-d0d1679d1b74',
          catalogName: listingId,
        ),
      ],
      sourceKind: AgentSkillSourceKind.official,
      listingId: 'ignored-uuid',
      catalogName: listingId,
      catalogVersion: 1,
    );

    expect(state.status, CatalogSkillInstallationStatus.installed);
    expect(state.canInstall, isFalse);
    expect(state.canUpgrade, isFalse);
  });

  test(
    'offers one upgrade action for every stale installation of the source',
    () {
      final state = resolveCatalogSkillInstallationState(
        installedSkills: [
          installed(id: 'stale-1', version: '1'),
          installed(id: 'latest-2', version: '3'),
          installed(id: 'stale-3', version: null),
          installed(
            id: 'other-source',
            version: '1',
            sourceListingId: 'other-listing',
            catalogName: 'other-listing',
          ),
        ],
        sourceKind: AgentSkillSourceKind.official,
        listingId: listingId,
        catalogVersion: 3,
      );

      expect(state.status, CatalogSkillInstallationStatus.upgrade_available);
      expect(state.canInstall, isFalse);
      expect(state.canUpgrade, isTrue);
      expect(state.staleInstallationIds, ['stale-1', 'stale-3']);
    },
  );

  test('waits for installed skills before exposing an install action', () {
    final state = resolveCatalogSkillInstallationState(
      installedSkills: null,
      sourceKind: AgentSkillSourceKind.official,
      listingId: listingId,
      catalogVersion: 3,
    );

    expect(state.status, CatalogSkillInstallationStatus.loading);
    expect(state.canInstall, isFalse);
    expect(state.canUpgrade, isFalse);
  });
}
