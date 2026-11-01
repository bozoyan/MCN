// 职责: AI 快捷方式 Provider — 全局快捷方式 CRUD、内置恢复与按适用位置查询。
// 关联文件:
//   lib/shared/models/ai_shortcut_action.dart
//   lib/shared/database/daos/ai_shortcut_action_dao.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../models/ai_shortcut_action.dart';
import '../utils/random_id.dart';

AiShortcutActionDefinition _mapShortcutAction(AiShortcutAction row) {
  return AiShortcutActionDefinition(
    id: row.id,
    builtinId: row.builtinId,
    name: row.name,
    prompt: row.prompt,
    locations: row.locations
        .map(AiShortcutActionLocation.maybeFromDbValue)
        .whereType<AiShortcutActionLocation>()
        .toList(growable: false),
    enabled: row.enabled,
    autoSend: row.autoSend,
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

class AiShortcutActionNameConflictException implements Exception {
  AiShortcutActionNameConflictException(this.name);

  final String name;

  @override
  String toString() => 'AiShortcutActionNameConflictException: $name';
}

class AiShortcutActions
    extends AsyncNotifier<List<AiShortcutActionDefinition>> {
  @override
  Future<List<AiShortcutActionDefinition>> build() async {
    final db = AppDatabase();
    final rows = await db.aiShortcutActionDao.getAll();
    return rows.map(_mapShortcutAction).toList();
  }

  Future<void> createAction(AiShortcutActionDraft draft) async {
    final current = state.value ?? const <AiShortcutActionDefinition>[];
    if (_nameExists(current, draft.name, '')) {
      throw AiShortcutActionNameConflictException(draft.name);
    }
    final db = AppDatabase();
    final now = DateTime.now();
    await db.aiShortcutActionDao.upsert(
      AiShortcutAction(
        id: buildRandomId('ai_shortcut'),
        builtinId: null,
        name: draft.name,
        prompt: draft.prompt,
        locations: draft.locations
            .map((location) => location.dbValue)
            .toList(growable: false),
        enabled: draft.enabled,
        autoSend: draft.autoSend,
        sortOrder: current.length,
        createdAt: now,
        updatedAt: now,
        deletedAt: notDeletedSentinel,
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> updateAction(AiShortcutActionDefinition action) async {
    final current = state.value ?? const <AiShortcutActionDefinition>[];
    if (_nameExists(current, action.name, action.id)) {
      throw AiShortcutActionNameConflictException(action.name);
    }
    final db = AppDatabase();
    final existing = await db.aiShortcutActionDao.getById(action.id);
    final now = DateTime.now();
    await db.aiShortcutActionDao.upsert(
      AiShortcutAction(
        id: action.id,
        builtinId: action.builtinId,
        name: action.name,
        prompt: action.prompt,
        locations: action.locations
            .map((location) => location.dbValue)
            .toList(growable: false),
        enabled: action.enabled,
        autoSend: action.autoSend,
        sortOrder: action.sortOrder,
        createdAt: action.createdAt ?? existing?.createdAt ?? now,
        updatedAt: now,
        deletedAt: existing?.deletedAt ?? notDeletedSentinel,
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> deleteAction(String id) async {
    final db = AppDatabase();
    final existing = await db.aiShortcutActionDao.getById(id);
    if (existing?.builtinId?.isNotEmpty == true) {
      return;
    }
    await db.aiShortcutActionDao.softDelete(id);
    ref.invalidateSelf();
  }

  Future<void> restoreBuiltin(String builtinId) async {
    final seed = _builtinById(builtinId);
    if (seed == null) {
      return;
    }
    final db = AppDatabase();
    final existing = await db.aiShortcutActionDao.getByBuiltinId(builtinId);
    final now = DateTime.now();
    final sortOrder =
        existing?.sortOrder ??
        (state.value ?? const <AiShortcutActionDefinition>[]).length;
    await db.aiShortcutActionDao.upsert(
      AiShortcutAction(
        id: existing?.id ?? 'builtin_${seed.id}',
        builtinId: seed.id,
        name: seed.name,
        prompt: seed.prompt,
        locations: seed.locations
            .map((location) => location.dbValue)
            .toList(growable: false),
        enabled: seed.enabled,
        autoSend: seed.autoSend,
        sortOrder: sortOrder,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        deletedAt: notDeletedSentinel,
      ),
    );
    ref.invalidateSelf();
  }
}

BuiltinAiShortcutAction? _builtinById(String builtinId) {
  for (final action in builtinAiShortcutActions) {
    if (action.id == builtinId) {
      return action;
    }
  }
  return null;
}

final aiShortcutActionsProvider =
    AsyncNotifierProvider<AiShortcutActions, List<AiShortcutActionDefinition>>(
      AiShortcutActions.new,
    );

final enabledAiShortcutActionsForLocationProvider =
    Provider.family<List<AiShortcutActionDefinition>, AiShortcutActionLocation>(
      (ref, location) {
        final actions =
            ref.watch(aiShortcutActionsProvider).asData?.value ??
            const <AiShortcutActionDefinition>[];
        return actions
            .where(
              (action) => action.enabled && action.locations.contains(location),
            )
            .toList(growable: false);
      },
    );

bool _nameExists(
  Iterable<AiShortcutActionDefinition> items,
  String name,
  String currentId,
) {
  final normalized = name.trim();
  return items.any(
    (item) => item.name.trim() == normalized && item.id != currentId,
  );
}
