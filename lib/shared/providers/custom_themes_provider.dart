// 职责: 订阅未删除的自定义主题，让设置列表响应所有主题写入。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/settings/custom_themes_section.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import 'settings_providers.dart';

final customThemesProvider = StreamProvider.autoDispose<List<CustomTheme>>((
  ref,
) {
  final db = ref.watch(appSettingsDatabaseProvider);
  return (db.select(db.customThemes)
        ..where((table) => table.deletedAt.equals(notDeletedSentinel))
        ..orderBy([
          (table) => OrderingTerm.asc(table.createdAt),
          (table) => OrderingTerm.asc(table.id),
        ]))
      .watch();
});
