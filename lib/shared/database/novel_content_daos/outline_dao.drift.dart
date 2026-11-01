// dart format width=80
// ignore_for_file: type=lint
part of 'outline_dao.dart';

mixin _$OutlineDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $OutlinesTable get outlines => attachedDatabase.outlines;
  $OutlineBeatsTable get outlineBeats => attachedDatabase.outlineBeats;
  OutlineDaoManager get managers => OutlineDaoManager(this);
}

class OutlineDaoManager {
  final _$OutlineDaoMixin _db;
  OutlineDaoManager(this._db);
  $$OutlinesTableTableManager get outlines =>
      $$OutlinesTableTableManager(_db.attachedDatabase, _db.outlines);
  $$OutlineBeatsTableTableManager get outlineBeats =>
      $$OutlineBeatsTableTableManager(_db.attachedDatabase, _db.outlineBeats);
}
