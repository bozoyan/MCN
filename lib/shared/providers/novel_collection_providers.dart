// 职责: 分别订阅集合定义、聚合计数、当前作品和成员关系，并保存导航顺序。
// 关联文件:
//   lib/shared/database/daos/novel_collection_dao.dart
//   lib/shared/models/novel_collection.dart
//   lib/shared/providers/novel_providers.dart
import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../database/app_database.dart';
import '../logger/app_logger.dart';
import '../models/novel_collection.dart';
import 'novel_providers.dart';
part 'novel_collection_providers.g.dart';

@riverpod
Stream<List<LibraryCollection>> novelCollections(Ref ref) => ref
    .watch(appDatabaseProvider)
    .novelCollectionDao
    .watchDefinitions()
    .map((rows) => rows.map(LibraryCollection.new).toList());

/// [contentKind] 是作品区的类型筛选，null 表示全部类型。
@riverpod
Stream<Map<String, int?>> collectionCounts(Ref ref, String? contentKind) => ref
    .watch(appDatabaseProvider)
    .novelCollectionDao
    .watchCounts(contentKind: contentKind);

@riverpod
Stream<List<Novel>> collectionWorks(Ref ref, String id, String? contentKind) =>
    ref
        .watch(appDatabaseProvider)
        .novelCollectionDao
        .watchWorks(id, contentKind: contentKind);

String collectionWorkIdsKey(Iterable<String> ids) =>
    jsonEncode(ids.toSet().toList()..sort());

@riverpod
Stream<Map<String, Set<String>>> collectionMemberships(
  Ref ref,
  String workIdsKey,
) => ref
    .watch(appDatabaseProvider)
    .novelCollectionDao
    .watchMembership((jsonDecode(workIdsKey) as List).cast<String>().toSet());

const _collectionOrderKey = 'library.collection_order';

@riverpod
Stream<List<String>?> collectionOrder(Ref ref) => ref
    .watch(appDatabaseProvider)
    .appSettingsDao
    .watch(_collectionOrderKey)
    .map((raw) {
      if (raw == null) {
        return null;
      }
      final value = jsonDecode(raw);
      if (value is! List || value.any((id) => id is! String)) {
        throw const FormatException('Invalid collection navigation order');
      }
      return value.cast<String>();
    });

@riverpod
Future<List<LibraryCollection>> orderedCollections(Ref ref) async {
  final definitionsFuture = ref.watch(novelCollectionsProvider.future);
  final savedFuture = ref.watch(collectionOrderProvider.future);
  final definitions = await definitionsFuture;
  final saved = await savedFuture;
  return orderCollections(definitions, saved);
}

Future<void> saveCollectionOrder(AppDatabase database, List<String> ids) async {
  try {
    final definitions = await database.novelCollectionDao.getDefinitions();
    final normalized = orderCollections(
      definitions.map(LibraryCollection.new).toList(),
      ids,
    );
    await database.appSettingsDao.set(
      key: _collectionOrderKey,
      value: jsonEncode(normalized.map((c) => c.id).toList()),
    );
  } catch (error, stackTrace) {
    AppLogger.forModule('CollectionOrder').error(
      '[DB][app_settings][INSERT_OR_UPDATE] id=$_collectionOrderKey',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}
