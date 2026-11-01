// dart format width=80
// ignore_for_file: type=lint
part of 'novel_state_snapshot_dao.dart';

mixin _$NovelStateSnapshotDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $NovelStateSnapshotsTable get novelStateSnapshots =>
      attachedDatabase.novelStateSnapshots;
  NovelStateSnapshotDaoManager get managers =>
      NovelStateSnapshotDaoManager(this);
}

class NovelStateSnapshotDaoManager {
  final _$NovelStateSnapshotDaoMixin _db;
  NovelStateSnapshotDaoManager(this._db);
  $$NovelStateSnapshotsTableTableManager get novelStateSnapshots =>
      $$NovelStateSnapshotsTableTableManager(
        _db.attachedDatabase,
        _db.novelStateSnapshots,
      );
}
