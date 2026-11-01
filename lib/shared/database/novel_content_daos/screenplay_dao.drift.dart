// dart format width=80
// ignore_for_file: type=lint
part of 'screenplay_dao.dart';

mixin _$ScreenplayDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $ScreenplaysTable get screenplays => attachedDatabase.screenplays;
  $ScreenplaySeasonsTable get screenplaySeasons =>
      attachedDatabase.screenplaySeasons;
  $ScreenplayEpisodesTable get screenplayEpisodes =>
      attachedDatabase.screenplayEpisodes;
  $ScreenplayScenesTable get screenplayScenes =>
      attachedDatabase.screenplayScenes;
  $VideoStagingsTable get videoStagings => attachedDatabase.videoStagings;
  $RevisionsTable get revisions => attachedDatabase.revisions;
  $ScreenplayBeatsTable get screenplayBeats => attachedDatabase.screenplayBeats;
  $ScreenplaySceneCharactersTable get screenplaySceneCharacters =>
      attachedDatabase.screenplaySceneCharacters;
  $ScreenplaySceneElementsTable get screenplaySceneElements =>
      attachedDatabase.screenplaySceneElements;
  ScreenplayDaoManager get managers => ScreenplayDaoManager(this);
}

class ScreenplayDaoManager {
  final _$ScreenplayDaoMixin _db;
  ScreenplayDaoManager(this._db);
  $$ScreenplaysTableTableManager get screenplays =>
      $$ScreenplaysTableTableManager(_db.attachedDatabase, _db.screenplays);
  $$ScreenplaySeasonsTableTableManager get screenplaySeasons =>
      $$ScreenplaySeasonsTableTableManager(
        _db.attachedDatabase,
        _db.screenplaySeasons,
      );
  $$ScreenplayEpisodesTableTableManager get screenplayEpisodes =>
      $$ScreenplayEpisodesTableTableManager(
        _db.attachedDatabase,
        _db.screenplayEpisodes,
      );
  $$ScreenplayScenesTableTableManager get screenplayScenes =>
      $$ScreenplayScenesTableTableManager(
        _db.attachedDatabase,
        _db.screenplayScenes,
      );
  $$VideoStagingsTableTableManager get videoStagings =>
      $$VideoStagingsTableTableManager(_db.attachedDatabase, _db.videoStagings);
  $$RevisionsTableTableManager get revisions =>
      $$RevisionsTableTableManager(_db.attachedDatabase, _db.revisions);
  $$ScreenplayBeatsTableTableManager get screenplayBeats =>
      $$ScreenplayBeatsTableTableManager(
        _db.attachedDatabase,
        _db.screenplayBeats,
      );
  $$ScreenplaySceneCharactersTableTableManager get screenplaySceneCharacters =>
      $$ScreenplaySceneCharactersTableTableManager(
        _db.attachedDatabase,
        _db.screenplaySceneCharacters,
      );
  $$ScreenplaySceneElementsTableTableManager get screenplaySceneElements =>
      $$ScreenplaySceneElementsTableTableManager(
        _db.attachedDatabase,
        _db.screenplaySceneElements,
      );
}
