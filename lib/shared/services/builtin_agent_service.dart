// 职责: 系统内置 Agent 的初始化补种与用户触发恢复。
// 关联文件:
//   lib/shared/services/initialization/agent_seeds.dart
//   lib/shared/services/initialization/primary_agent_seeds.dart
//   lib/shared/services/initialization/subagent_seeds.dart
//   lib/shared/database/app_database.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md
import '../database/app_database.dart';
import '../logger/app_logger.dart';
import '../utils/random_id.dart';
import 'initialization/primary_agent_seeds.dart';
import 'initialization/subagent_seeds.dart';

final _log = AppLogger.forModule('BuiltinAgentService');

class BuiltinAgentService {
  BuiltinAgentService(this._database);

  final AppDatabase _database;

  Future<void> seedMissingGlobalAgents() async {
    await _applyGlobalDefaults(overwriteExisting: false);
  }

  /// 补回缺失的系统 Agent，或按当前版本默认值覆盖已有系统 Agent。
  ///
  /// 只处理系统 seed 中声明的 slug，不影响用户自定义 Agent。
  Future<int> restoreGlobalAgents({required bool overwriteExisting}) async {
    final before = await _database.globalAgentDao.getByScope(agentScopeGlobal);
    final builtinSlugs = builtinAgentSlugs();
    final beforeBuiltinCount = before
        .where((agent) => builtinSlugs.contains(agent.slug))
        .length;
    try {
      await _applyGlobalDefaults(overwriteExisting: overwriteExisting);
    } catch (error, stackTrace) {
      _log.error(
        '[DB][agents][RESTORE_DEFAULT] '
        'overwriteExisting=$overwriteExisting error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    final after = await _database.globalAgentDao.getByScope(agentScopeGlobal);
    final afterBuiltinCount = after
        .where((agent) => builtinSlugs.contains(agent.slug))
        .length;
    return overwriteExisting
        ? afterBuiltinCount
        : afterBuiltinCount - beforeBuiltinCount;
  }

  Future<void> _applyGlobalDefaults({required bool overwriteExisting}) async {
    final existingAgents = await _database.globalAgentDao.getByScope(
      agentScopeGlobal,
    );
    final existingBySlug = {
      for (final agent in existingAgents) agent.slug: agent,
    };
    var sortOrder = existingAgents.length;

    for (final seed in defaultPrimaryAgentSeeds()) {
      final existing = existingBySlug[seed.slug];
      if (existing != null && !overwriteExisting) {
        continue;
      }
      final now = DateTime.now();
      await _database.globalAgentDao.upsert(
        GlobalAgent(
          scope: agentScopeGlobal,
          id: existing?.id ?? buildRandomId('agent'),
          slug: seed.slug,
          name: seed.name,
          description: seed.description,
          prompt: seed.prompt,
          mode: seed.mode,
          category: 'primary',
          enabled: true,
          useCustomPrompt: false,
          sortOrder: existing?.sortOrder ?? sortOrder,
          novelId: '',
          allowedToolNames: const <String>[],
          ignoredSkillNames: const <String>[],
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
          deletedAt: notDeletedSentinel,
        ),
      );
      if (existing == null) {
        sortOrder += 1;
      }
    }

    for (final seed in defaultGlobalSubAgentSeeds()) {
      final existing = existingBySlug[seed.slug];
      if (existing != null && !overwriteExisting) {
        continue;
      }
      final now = DateTime.now();
      await _database.globalAgentDao.upsert(
        GlobalAgent(
          scope: agentScopeGlobal,
          id: existing?.id ?? buildRandomId('subagent'),
          slug: seed.slug,
          name: seed.name,
          description: seed.description,
          prompt: seed.prompt,
          mode: seed.mode,
          category: 'subagent',
          enabled: true,
          useCustomPrompt: false,
          sortOrder: existing?.sortOrder ?? sortOrder,
          novelId: '',
          allowedToolNames: const <String>[],
          ignoredSkillNames: const <String>[],
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
          deletedAt: notDeletedSentinel,
        ),
      );
      if (existing == null) {
        sortOrder += 1;
      }
    }
  }
}

/// 系统内置 Agent slug 集合（primary seed + subagent seed）。
Set<String> builtinAgentSlugs() {
  return {
    for (final seed in defaultPrimaryAgentSeeds()) seed.slug,
    for (final seed in defaultGlobalSubAgentSeeds()) seed.slug,
  };
}
