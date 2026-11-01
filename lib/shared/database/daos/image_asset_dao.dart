// 职责: 统一图片库数据访问 — 写入图片、批次和参考关系，并以流提供有效资产列表。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/services/image_library_service.dart
// 遵循的 Rules:
//   .agents/rules/db-migration.md
//   .agents/rules/data-deletion.md

import 'package:drift/drift.dart';

import '../../logger/app_logger.dart';
import '../app_database.dart';

part 'image_asset_dao.drift.dart';

final _log = AppLogger.forModule('ImageAssetDao');

@DriftAccessor(
  tables: [Assets, ImageBatches, ImageBatchSlots, ImageAssetReferences],
)
class ImageAssetDao extends DatabaseAccessor<AppDatabase>
    with _$ImageAssetDaoMixin {
  ImageAssetDao(super.db);

  Stream<List<AssetRow>> watchAssets({String? novelId, String? purpose}) {
    final query = select(assets)
      ..where(
        (table) =>
            table.type.equals('image') &
            table.deletedAt.equals(notDeletedSentinel),
      )
      ..orderBy([
        (table) => OrderingTerm.desc(table.createdAt),
        (table) => OrderingTerm.desc(table.id),
      ]);
    if (novelId != null) {
      query.where(
        (table) => table.novelId.equals(novelId) | table.novelId.isNull(),
      );
    }
    if (purpose != null) {
      query.where((table) => table.purpose.equals(purpose));
    }
    return query.watch();
  }

  Future<AssetRow?> getAsset(String id) {
    return (select(assets)..where(
          (table) =>
              table.id.equals(id) &
              table.type.equals('image') &
              table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Future<void> insertAsset(AssetsCompanion asset) async {
    if (asset.type.value != 'image') {
      throw ArgumentError('ImageAssetDao only accepts image assets');
    }
    await attachedDatabase.assetDao.insertAsset(asset);
  }

  Future<void> updateMetadata(String id, Map<String, dynamic> metadata) async {
    try {
      await (update(assets)..where(
            (table) =>
                table.id.equals(id) &
                table.type.equals('image') &
                table.deletedAt.equals(notDeletedSentinel),
          ))
          .write(
            AssetsCompanion(
              metadataJson: Value(metadata),
              updatedAt: Value(DateTime.now()),
            ),
          );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] assets UPDATE metadata id=$id',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 批次列表。封面工作台的生成记录直接读它，而不是从 assets 的 batchId 反推 —
  /// 反推看不到零产物的批次，也拿不到状态机。
  Stream<List<ImageBatchRow>> watchBatches({String? novelId, String? purpose}) {
    final query = select(imageBatches)
      ..where((table) => table.deletedAt.equals(notDeletedSentinel))
      ..orderBy([
        (table) => OrderingTerm.desc(table.createdAt),
        (table) => OrderingTerm.desc(table.id),
      ]);
    if (novelId != null) {
      query.where((table) => table.novelId.equals(novelId));
    }
    if (purpose != null) {
      query.where((table) => table.purpose.equals(purpose));
    }
    return query.watch();
  }

  Future<ImageBatchRow?> getBatch(String id) {
    return (select(imageBatches)..where(
          (table) =>
              table.id.equals(id) & table.deletedAt.equals(notDeletedSentinel),
        ))
        .getSingleOrNull();
  }

  Future<void> insertBatch(ImageBatchesCompanion batch) {
    return into(imageBatches).insert(batch);
  }

  Future<void> insertSlots(Iterable<ImageBatchSlotsCompanion> slots) async {
    await batch((batch) => batch.insertAll(imageBatchSlots, slots));
  }

  Stream<List<ImageBatchSlotRow>> watchSlots(String batchId) {
    return (select(imageBatchSlots)
          ..where((table) => table.batchId.equals(batchId))
          ..orderBy([(table) => OrderingTerm.asc(table.ordinal)]))
        .watch();
  }

  Future<List<ImageBatchSlotRow>> getSlots(String batchId) {
    return (select(imageBatchSlots)
          ..where((table) => table.batchId.equals(batchId))
          ..orderBy([(table) => OrderingTerm.asc(table.ordinal)]))
        .get();
  }

  /// 按 (batchId, ordinal) 定位格子并落状态。重出走的也是这里：同一个格子改写，
  /// 不追加新行，所以 previousAssetId 必须由调用方显式传入。
  Future<void> updateSlot({
    required String batchId,
    required int ordinal,
    required String status,
    String? assetId,
    String? previousAssetId,
    String? errorCode,
    String? errorMessage,
  }) {
    return (update(imageBatchSlots)..where(
          (table) =>
              table.batchId.equals(batchId) & table.ordinal.equals(ordinal),
        ))
        .write(
          ImageBatchSlotsCompanion(
            status: Value(status),
            assetId: Value(assetId),
            previousAssetId: Value(previousAssetId),
            errorCode: Value(errorCode),
            errorMessage: Value(errorMessage),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> updateBatch({
    required String id,
    required String status,
    required int completedCount,
    String? errorMessage,
  }) {
    return (update(imageBatches)..where((table) => table.id.equals(id))).write(
      ImageBatchesCompanion(
        status: Value(status),
        completedCount: Value(completedCount),
        errorMessage: Value(errorMessage),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> insertReferences(
    Iterable<ImageAssetReferencesCompanion> references,
  ) async {
    await batch((batch) => batch.insertAll(imageAssetReferences, references));
  }

  Future<void> softDeleteAsset(String id) {
    return (update(assets)
          ..where((table) => table.id.equals(id) & table.type.equals('image')))
        .write(AssetsCompanion(deletedAt: Value(DateTime.now())));
  }

  /// 只软删这条批次记录，出的图留在图片库里 —— 它可能已被设为作品封面或挂成
  /// 参考图，收走一条生成记录不该把图一起带走。要删图走 [softDeleteAsset]。
  Future<void> softDeleteBatch(String id) {
    return (update(imageBatches)..where((table) => table.id.equals(id))).write(
      ImageBatchesCompanion(deletedAt: Value(DateTime.now())),
    );
  }
}
