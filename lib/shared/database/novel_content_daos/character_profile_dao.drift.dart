// dart format width=80
// ignore_for_file: type=lint
part of 'character_profile_dao.dart';

mixin _$CharacterProfileDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $CharacterProfilesTable get characterProfiles =>
      attachedDatabase.characterProfiles;
  CharacterProfileDaoManager get managers => CharacterProfileDaoManager(this);
}

class CharacterProfileDaoManager {
  final _$CharacterProfileDaoMixin _db;
  CharacterProfileDaoManager(this._db);
  $$CharacterProfilesTableTableManager get characterProfiles =>
      $$CharacterProfilesTableTableManager(
        _db.attachedDatabase,
        _db.characterProfiles,
      );
}
