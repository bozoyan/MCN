// dart format width=80
// ignore_for_file: type=lint
part of 'document_dao.dart';

mixin _$DocumentDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $DocumentsTable get documents => attachedDatabase.documents;
  DocumentDaoManager get managers => DocumentDaoManager(this);
}

class DocumentDaoManager {
  final _$DocumentDaoMixin _db;
  DocumentDaoManager(this._db);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db.attachedDatabase, _db.documents);
}
