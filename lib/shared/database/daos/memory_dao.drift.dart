// dart format width=80
// ignore_for_file: type=lint
part of 'memory_dao.dart';

mixin _$MemoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $MemoriesTable get memories => attachedDatabase.memories;
  MemoryDaoManager get managers => MemoryDaoManager(this);
}

class MemoryDaoManager {
  final _$MemoryDaoMixin _db;
  MemoryDaoManager(this._db);
  $$MemoriesTableTableManager get memories =>
      $$MemoriesTableTableManager(_db.attachedDatabase, _db.memories);
}
