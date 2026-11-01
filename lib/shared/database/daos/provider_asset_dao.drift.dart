// dart format width=80
// ignore_for_file: type=lint
part of 'provider_asset_dao.dart';

mixin _$ProviderAssetDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProviderAssetsTable get providerAssets => attachedDatabase.providerAssets;
  ProviderAssetDaoManager get managers => ProviderAssetDaoManager(this);
}

class ProviderAssetDaoManager {
  final _$ProviderAssetDaoMixin _db;
  ProviderAssetDaoManager(this._db);
  $$ProviderAssetsTableTableManager get providerAssets =>
      $$ProviderAssetsTableTableManager(
        _db.attachedDatabase,
        _db.providerAssets,
      );
}
