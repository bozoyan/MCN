// dart format width=80
// ignore_for_file: type=lint
part of 'location_dao.dart';

mixin _$LocationDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $LocationsTable get locations => attachedDatabase.locations;
  LocationDaoManager get managers => LocationDaoManager(this);
}

class LocationDaoManager {
  final _$LocationDaoMixin _db;
  LocationDaoManager(this._db);
  $$LocationsTableTableManager get locations =>
      $$LocationsTableTableManager(_db.attachedDatabase, _db.locations);
}
