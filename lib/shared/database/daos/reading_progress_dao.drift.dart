// dart format width=80
// ignore_for_file: type=lint
part of 'reading_progress_dao.dart';

mixin _$ReadingProgressDaoMixin on DatabaseAccessor<AppDatabase> {
  $ReadingProgressTable get readingProgress => attachedDatabase.readingProgress;
  ReadingProgressDaoManager get managers => ReadingProgressDaoManager(this);
}

class ReadingProgressDaoManager {
  final _$ReadingProgressDaoMixin _db;
  ReadingProgressDaoManager(this._db);
  $$ReadingProgressTableTableManager get readingProgress =>
      $$ReadingProgressTableTableManager(
        _db.attachedDatabase,
        _db.readingProgress,
      );
}
