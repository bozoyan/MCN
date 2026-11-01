// dart format width=80
// ignore_for_file: type=lint
part of 'editing_dao.dart';

mixin _$EditingDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $VideoEditingsTable get videoEditings => attachedDatabase.videoEditings;
  EditingDaoManager get managers => EditingDaoManager(this);
}

class EditingDaoManager {
  final _$EditingDaoMixin _db;
  EditingDaoManager(this._db);
  $$VideoEditingsTableTableManager get videoEditings =>
      $$VideoEditingsTableTableManager(_db.attachedDatabase, _db.videoEditings);
}
