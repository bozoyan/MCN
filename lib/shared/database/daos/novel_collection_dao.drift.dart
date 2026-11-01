// dart format width=80
// ignore_for_file: type=lint
part of 'novel_collection_dao.dart';

mixin _$NovelCollectionDaoMixin on DatabaseAccessor<AppDatabase> {
  $NovelCollectionsTable get novelCollections =>
      attachedDatabase.novelCollections;
  $NovelCollectionMembersTable get novelCollectionMembers =>
      attachedDatabase.novelCollectionMembers;
  $NovelsTable get novels => attachedDatabase.novels;
  NovelCollectionDaoManager get managers => NovelCollectionDaoManager(this);
}

class NovelCollectionDaoManager {
  final _$NovelCollectionDaoMixin _db;
  NovelCollectionDaoManager(this._db);
  $$NovelCollectionsTableTableManager get novelCollections =>
      $$NovelCollectionsTableTableManager(
        _db.attachedDatabase,
        _db.novelCollections,
      );
  $$NovelCollectionMembersTableTableManager get novelCollectionMembers =>
      $$NovelCollectionMembersTableTableManager(
        _db.attachedDatabase,
        _db.novelCollectionMembers,
      );
  $$NovelsTableTableManager get novels =>
      $$NovelsTableTableManager(_db.attachedDatabase, _db.novels);
}
