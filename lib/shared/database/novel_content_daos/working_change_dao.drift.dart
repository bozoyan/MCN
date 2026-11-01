// dart format width=80
// ignore_for_file: type=lint
part of 'working_change_dao.dart';

mixin _$WorkingChangeDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $WorkingChangesTable get workingChanges => attachedDatabase.workingChanges;
  WorkingChangeDaoManager get managers => WorkingChangeDaoManager(this);
}

class WorkingChangeDaoManager {
  final _$WorkingChangeDaoMixin _db;
  WorkingChangeDaoManager(this._db);
  $$WorkingChangesTableTableManager get workingChanges =>
      $$WorkingChangesTableTableManager(
        _db.attachedDatabase,
        _db.workingChanges,
      );
}
