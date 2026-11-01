// 职责: 同步官方技能目录，安装与升级快照、卸载目录外官方技能并保留用户删除选择。
// 关联文件:
//   lib/shared/providers/official_skill_sync_providers.dart
//   lib/shared/models/catalog_skill_installation_state.dart
//   lib/shared/models/novel_agent_skill.dart
//   lib/shared/models/official_agent_skill.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md

import '../logger/app_logger.dart';
import '../models/catalog_skill_installation_state.dart';
import '../models/novel_agent_skill.dart';
import '../models/official_agent_skill.dart';

final _log = AppLogger.forModule('OfficialSkillSync');

class OfficialSkillSyncResult {
  const OfficialSkillSyncResult({
    this.installed = 0,
    this.upgraded = 0,
    this.uninstalled = 0,
    this.failed = 0,
  });

  final int installed;
  final int upgraded;
  final int uninstalled;
  final int failed;
}

/// 每次启动对整个目录进行同步。已处理身份只控制首次安装，不阻止版本升级。
/// 完整目录是官方来源的真源，目录外的官方安装复用 notifier 卸载；
/// 本地和市场来源保留，安装冲突保留已有内容。
class OfficialSkillSyncOrchestrator {
  Future<OfficialSkillSyncResult> run({
    required Future<List<NovelAgentSkillModel>> Function() loadInstalledSkills,
    required Future<List<OfficialAgentSkillSummary>> Function()
    loadOfficialCatalog,
    required Future<Set<String>> Function() loadHandledNames,
    required Future<void> Function(String catalogName) markHandled,
    required Future<OfficialAgentSkill> Function(String listingId)
    loadOfficialSkill,
    // true 表示新装成功，false 表示安装时发生同名冲突、保留已有内容。
    required Future<bool> Function(OfficialAgentSkill source)
    installOfficialSkill,
    required Future<void> Function(String installedSkillId)
    upgradeOfficialSkill,
    required Future<void> Function(String installedSkillId)
    uninstallOfficialSkill,
  }) async {
    final List<NovelAgentSkillModel> installed;
    final List<OfficialAgentSkillSummary> catalog;
    final Set<String> handled;
    try {
      installed = [...await loadInstalledSkills()];
      catalog = await loadOfficialCatalog();
      handled = {...await loadHandledNames()};
    } catch (error, stackTrace) {
      _log.error(
        'load official skill sync state failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    var installedCount = 0;
    var upgradedCount = 0;
    var uninstalledCount = 0;
    var failedCount = 0;
    final catalogNames = {for (final entry in catalog) entry.name};
    final retired = installed.where((skill) {
      final name = officialSkillCatalogName(skill);
      return skill.sourceKind == AgentSkillSourceKind.official &&
          !catalogNames.contains(name);
    }).toList();
    final failedUninstallIds = <String>{};
    for (final skill in retired) {
      try {
        await uninstallOfficialSkill(skill.id);
        installed.removeWhere((entry) => entry.id == skill.id);
        uninstalledCount++;
        _log.info(
          'uninstalled retired official skill '
          'name=${officialSkillCatalogName(skill)} id=${skill.id}',
        );
      } catch (error, stackTrace) {
        failedUninstallIds.add(skill.id);
        failedCount++;
        _log.error(
          'uninstall retired official skill failed '
          'name=${officialSkillCatalogName(skill)} id=${skill.id}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    for (final entry in catalog) {
      // 未卸载成功的旧来源占用了新入口名称时，下次启动再安装，不能记为已处理。
      if (installed.any(
        (skill) =>
            failedUninstallIds.contains(skill.id) && skill.name == entry.name,
      )) {
        continue;
      }

      try {
        final matches = installed
            .where(
              (skill) =>
                  skill.sourceKind == AgentSkillSourceKind.official &&
                  officialSkillCatalogName(skill) == entry.name,
            )
            .toList();
        if (matches.isNotEmpty) {
          if (!handled.contains(entry.name)) {
            await markHandled(entry.name);
            handled.add(entry.name);
          }
          for (final skill in matches) {
            final version = int.tryParse(skill.sourceVersion ?? '') ?? 0;
            if (version >= entry.version) {
              continue;
            }
            try {
              await upgradeOfficialSkill(skill.id);
              upgradedCount++;
              _log.info(
                'upgraded official skill name=${entry.name} '
                'id=${skill.id} from=$version to=${entry.version}',
              );
            } catch (error, stackTrace) {
              failedCount++;
              _log.error(
                'upgrade official skill failed name=${entry.name} '
                'id=${skill.id}',
                error: error,
                stackTrace: stackTrace,
              );
            }
          }
          continue;
        }
        if (handled.contains(entry.name)) {
          continue;
        }
        if (!installed.any((skill) => skill.name == entry.name)) {
          final source = await loadOfficialSkill(entry.listingId);
          if (await installOfficialSkill(source)) {
            installedCount++;
            _log.info(
              'installed official skill name=${entry.name} '
              'version=${source.version}',
            );
          }
        }
        // 成功安装或确认已有同名内容后记录；失败不记完成，下次启动重试。
        await markHandled(entry.name);
        handled.add(entry.name);
      } catch (error, stackTrace) {
        failedCount++;
        _log.error(
          'sync official skill failed name=${entry.name}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return OfficialSkillSyncResult(
      installed: installedCount,
      upgraded: upgradedCount,
      uninstalled: uninstalledCount,
      failed: failedCount,
    );
  }
}
