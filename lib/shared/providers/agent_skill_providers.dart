// 职责: AgentSkill 的 Riverpod Provider — App DB 入口与 chat slash 已安装技能查询
// 关联文件:
//   lib/shared/models/agent_skill.dart
//   lib/shared/database/app_database.dart
//   lib/shared/services/ai/chat_turn_runner.dart
//   lib/shared/providers/novel_agent_skill_providers.dart (installedAgentSkillsProvider)
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../models/agent_skill.dart';

final agentSkillAppDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ── Chat Slash Skills ────────────────────────────────────────────────────────

/// 查询 chat slash 面板可选的应用全局已安装技能。
///
/// 仅返回可执行的 NovelAgentSkill；packaged bundled skills 仍由
/// `ChatTurnRunner._loadCurrentSkillContext` 提供给 AI 运行时，但不暴露在 slash 面板。
Future<List<SkillDefinition>> loadChatSlashSkills({
  required AppDatabase db,
}) async {
  final installed = await db.novelAgentSkillDao.getAll();
  final referencesBySkillId = await db.novelAgentSkillDao
      .getReferencesBySkillIds(installed.map((row) => row.id));
  final executable = installed
      .where((row) => row.enabled && row.executionBlockedReason == null)
      .toList(growable: false);

  return <SkillDefinition>[
    for (final row in executable)
      SkillDefinition(
        id: row.id,
        name: row.name,
        whenToUse: row.whenToUse,
        description: row.description,
        prompt: row.prompt,
        references: referencesBySkillId[row.id] ?? const [],
        enabled: true,
        sortOrder: row.sortOrder,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      ),
  ];
}

/// slash 面板数据源。订阅全局已安装技能表，确保导入、启停、
/// 重命名或 AI 工具写入后候选立即刷新。
final chatSlashSkillsProvider = StreamProvider<List<SkillDefinition>>((
  ref,
) async* {
  final db = ref.watch(agentSkillAppDatabaseProvider);
  await for (final _ in db.novelAgentSkillDao.watchAll()) {
    yield await loadChatSlashSkills(db: db);
  }
});
