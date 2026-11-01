// dart format width=80
// ignore_for_file: type=lint
part of 'image_asset_dao.dart';

mixin _$ImageAssetDaoMixin on DatabaseAccessor<AppDatabase> {
  $AssetsTable get assets => attachedDatabase.assets;
  $ImageBatchesTable get imageBatches => attachedDatabase.imageBatches;
  $ImageBatchSlotsTable get imageBatchSlots => attachedDatabase.imageBatchSlots;
  $ImageAssetReferencesTable get imageAssetReferences =>
      attachedDatabase.imageAssetReferences;
  ImageAssetDaoManager get managers => ImageAssetDaoManager(this);
}

class ImageAssetDaoManager {
  final _$ImageAssetDaoMixin _db;
  ImageAssetDaoManager(this._db);
  $$AssetsTableTableManager get assets =>
      $$AssetsTableTableManager(_db.attachedDatabase, _db.assets);
  $$ImageBatchesTableTableManager get imageBatches =>
      $$ImageBatchesTableTableManager(_db.attachedDatabase, _db.imageBatches);
  $$ImageBatchSlotsTableTableManager get imageBatchSlots =>
      $$ImageBatchSlotsTableTableManager(
        _db.attachedDatabase,
        _db.imageBatchSlots,
      );
  $$ImageAssetReferencesTableTableManager get imageAssetReferences =>
      $$ImageAssetReferencesTableTableManager(
        _db.attachedDatabase,
        _db.imageAssetReferences,
      );
}
