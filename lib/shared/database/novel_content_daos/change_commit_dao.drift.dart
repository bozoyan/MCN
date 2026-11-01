// dart format width=80
// ignore_for_file: type=lint
part of 'change_commit_dao.dart';

mixin _$ChangeCommitDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $ChangeCommitsTable get changeCommits => attachedDatabase.changeCommits;
  $ChangeCommitItemsTable get changeCommitItems =>
      attachedDatabase.changeCommitItems;
  ChangeCommitDaoManager get managers => ChangeCommitDaoManager(this);
}

class ChangeCommitDaoManager {
  final _$ChangeCommitDaoMixin _db;
  ChangeCommitDaoManager(this._db);
  $$ChangeCommitsTableTableManager get changeCommits =>
      $$ChangeCommitsTableTableManager(_db.attachedDatabase, _db.changeCommits);
  $$ChangeCommitItemsTableTableManager get changeCommitItems =>
      $$ChangeCommitItemsTableTableManager(
        _db.attachedDatabase,
        _db.changeCommitItems,
      );
}
