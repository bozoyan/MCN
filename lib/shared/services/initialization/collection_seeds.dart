// 职责: 在同一事务内幂等初始化作品库默认集合，保留既有及软删除记录。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/database/queries/collection_filter.dart
//   lib/shared/services/app_initialization.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
import 'package:drift/drift.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../database/app_database.dart';
import '../../database/queries/collection_filter.dart';
import '../../models/collections/filter.dart';
import '../../localization/locale_keys.dart';
import '../../logger/app_logger.dart';

Future<void> seedDefaultCollections(AppDatabase database) async {
  final keys = {
    'all': LocaleKeys.libraryAll,
    'in_progress': LocaleKeys.libraryStatusInProgress,
    'finished': LocaleKeys.libraryStatusFinished,
  };
  final names = {for (final entry in keys.entries) entry.key: tr(entry.value)};
  if (keys.entries.any((entry) => names[entry.key] == entry.value)) {
    throw StateError(
      'Collection seed translations must be loaded before initialization',
    );
  }
  await seedCollections(database, names: names);
}

Future<void> seedCollections(
  AppDatabase database, {
  required Map<String, String> names,
}) async {
  try {
    await database.transaction(() async {
      for (final seed in ['all', 'in_progress', 'finished']) {
        final id = 'collection:$seed';
        final existing = await (database.select(
          database.novelCollections,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (existing != null) {
          continue;
        }
        final name = names[seed];
        if (name == null || name.isEmpty) {
          throw StateError('Missing localized collection seed name: $seed');
        }
        await database
            .into(database.novelCollections)
            .insert(
              NovelCollectionsCompanion.insert(
                id: id,
                name: name,
                builtin: Value(seed == 'all'),
                filterMode: const Value('rule'),
                filter: Value(
                  seed == 'all'
                      ? null
                      : CollectionFilter.fromRoot(
                          CollectionCompare('novel.status', 'eq', seed),
                        ),
                ),
              ),
            );
      }
      final protected =
          await (database.select(database.novelCollections)..where(
                (t) =>
                    t.builtin.equals(true) &
                    t.deletedAt.equals(notDeletedSentinel),
              ))
              .get();
      if (protected.length != 1 || protected.single.id != 'collection:all') {
        throw StateError('Expected exactly one active builtin collection');
      }
      validateCollectionConfiguration(protected.single);
    });
  } catch (error, stackTrace) {
    AppLogger.forModule('CollectionSeeds').error(
      '[DB][novel_collections][INSERT] id=default_collections_v1',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}
