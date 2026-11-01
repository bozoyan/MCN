// dart format width=80
// ignore_for_file: type=lint
part of 'foreshadowing_dao.dart';

mixin _$ForeshadowingDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $ForeshadowingsTable get foreshadowings => attachedDatabase.foreshadowings;
  ForeshadowingDaoManager get managers => ForeshadowingDaoManager(this);
}

class ForeshadowingDaoManager {
  final _$ForeshadowingDaoMixin _db;
  ForeshadowingDaoManager(this._db);
  $$ForeshadowingsTableTableManager get foreshadowings =>
      $$ForeshadowingsTableTableManager(
        _db.attachedDatabase,
        _db.foreshadowings,
      );
}
