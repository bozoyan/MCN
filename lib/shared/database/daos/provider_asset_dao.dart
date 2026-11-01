// 职责: 读写本地素材在渠道私域素材库中的认证记录。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/provider_asset.dart
//   lib/shared/services/ai/assets/certification.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
import 'package:drift/drift.dart';
import '../../logger/app_logger.dart';
import '../../models/provider_asset.dart';
import '../../utils/random_id.dart';
import '../app_database.dart';
part 'provider_asset_dao.drift.dart';

final _log = AppLogger.forModule('ProviderAssetDao');

@DriftAccessor(tables: [ProviderAssets])
class ProviderAssetDao extends DatabaseAccessor<AppDatabase>
    with _$ProviderAssetDaoMixin {
  ProviderAssetDao(super.db);

  SimpleSelectStatement<$ProviderAssetsTable, ProviderAsset> _live() =>
      select(providerAssets)
        ..where((t) => t.deletedAt.equals(notDeletedSentinel));

  Future<ProviderAsset?> find(String assetId, String providerId) =>
      (_live()..where(
            (t) => t.assetId.equals(assetId) & t.providerId.equals(providerId),
          ))
          .getSingleOrNull();

  Stream<List<ProviderAsset>> watchByAssets(Iterable<String> assetIds) =>
      (_live()..where((t) => t.assetId.isIn(assetIds))).watch();

  Future<List<ProviderAsset>> processing() =>
      (_live()..where(
            (t) => t.status.equalsValue(ProviderAssetStatus.processing),
          ))
          .get();

  /// 开始一次认证：同一素材同一渠道只保留一条记录，重新认证时复用并清掉上次结果。
  Future<ProviderAsset> start(String assetId, String providerId) async {
    try {
      return await transaction(() async {
        final current = await find(assetId, providerId);
        if (current == null) {
          return into(providerAssets).insertReturning(
            ProviderAssetsCompanion.insert(
              id: buildRandomId('provider_asset'),
              assetId: assetId,
              providerId: providerId,
              status: ProviderAssetStatus.processing,
            ),
          );
        }
        await (update(
          providerAssets,
        )..where((t) => t.id.equals(current.id))).write(
          ProviderAssetsCompanion(
            remoteId: const Value(null),
            remoteTaskId: const Value(null),
            remoteGroupId: const Value(null),
            status: const Value(ProviderAssetStatus.processing),
            errorCode: const Value(null),
            errorMessage: const Value(null),
            updatedAt: Value(DateTime.now()),
          ),
        );
        return (await find(assetId, providerId))!;
      });
    } catch (error, stack) {
      _log.error(
        '[DB] table=provider_assets op=INSERT,UPDATE asset=$assetId provider=$providerId',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<void> write(String id, ProviderAssetsCompanion values) async {
    try {
      await (update(providerAssets)..where((t) => t.id.equals(id))).write(
        values.copyWith(updatedAt: Value(DateTime.now())),
      );
    } catch (error, stack) {
      _log.error(
        '[DB] table=provider_assets op=UPDATE id=$id',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }
}
