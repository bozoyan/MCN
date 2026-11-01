// dart format width=80
// ignore_for_file: type=lint
part of 'novel_state_dao.dart';

mixin _$NovelStateDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $NovelStatesTable get novelStates => attachedDatabase.novelStates;
  NovelStateDaoManager get managers => NovelStateDaoManager(this);
}

class NovelStateDaoManager {
  final _$NovelStateDaoMixin _db;
  NovelStateDaoManager(this._db);
  $$NovelStatesTableTableManager get novelStates =>
      $$NovelStatesTableTableManager(_db.attachedDatabase, _db.novelStates);
}
