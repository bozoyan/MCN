// dart format width=80
// ignore_for_file: type=lint
part of 'item_dao.dart';

mixin _$ItemDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $ItemsTable get items => attachedDatabase.items;
  ItemDaoManager get managers => ItemDaoManager(this);
}

class ItemDaoManager {
  final _$ItemDaoMixin _db;
  ItemDaoManager(this._db);
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db.attachedDatabase, _db.items);
}
