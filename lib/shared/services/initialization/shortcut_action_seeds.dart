// 职责: AI 快捷方式初始化 — 写入全局内置快捷方式默认配置。
// 关联文件:
//   lib/shared/models/ai_shortcut_action.dart
//   lib/shared/database/daos/ai_shortcut_action_dao.dart
//   lib/shared/services/app_initialization.dart
import '../../database/app_database.dart';
import '../../models/ai_shortcut_action.dart';

Future<void> seedDefaultAiShortcutActions(AppDatabase database) async {
  final existing = await database.aiShortcutActionDao.getAll();
  final existingBuiltinIds = existing
      .map((action) => action.builtinId)
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet();
  var sortOrder = existing.length;

  for (final seed in builtinAiShortcutActions) {
    if (existingBuiltinIds.contains(seed.id)) {
      continue;
    }
    final now = DateTime.now();
    await database.aiShortcutActionDao.upsert(
      AiShortcutAction(
        id: 'builtin_${seed.id}',
        builtinId: seed.id,
        name: seed.name,
        prompt: seed.prompt,
        locations: seed.locations.map((location) => location.dbValue).toList(),
        enabled: seed.enabled,
        autoSend: seed.autoSend,
        sortOrder: sortOrder,
        createdAt: now,
        updatedAt: now,
        deletedAt: notDeletedSentinel,
      ),
    );
    sortOrder += 1;
  }
}
