// dart format width=80
// ignore_for_file: type=lint
part of 'app_state_dao.dart';

mixin _$AppStateDaoMixin on DatabaseAccessor<AppDatabase> {
  $AppStatesTable get appStates => attachedDatabase.appStates;
  AppStateDaoManager get managers => AppStateDaoManager(this);
}

class AppStateDaoManager {
  final _$AppStateDaoMixin _db;
  AppStateDaoManager(this._db);
  $$AppStatesTableTableManager get appStates =>
      $$AppStatesTableTableManager(_db.attachedDatabase, _db.appStates);
}
