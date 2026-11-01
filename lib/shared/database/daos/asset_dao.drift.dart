// dart format width=80
// ignore_for_file: type=lint
part of 'asset_dao.dart';

mixin _$AssetDaoMixin on DatabaseAccessor<AppDatabase> {
  $AssetsTable get assets => attachedDatabase.assets;
  AssetDaoManager get managers => AssetDaoManager(this);
}

class AssetDaoManager {
  final _$AssetDaoMixin _db;
  AssetDaoManager(this._db);
  $$AssetsTableTableManager get assets =>
      $$AssetsTableTableManager(_db.attachedDatabase, _db.assets);
}
