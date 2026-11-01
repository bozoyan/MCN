// dart format width=80
// ignore_for_file: type=lint
part of 'novel_agent_skill_revision_dao.dart';

mixin _$NovelAgentSkillRevisionDaoMixin on DatabaseAccessor<AppDatabase> {
  $NovelAgentSkillsTable get novelAgentSkills =>
      attachedDatabase.novelAgentSkills;
  $NovelAgentSkillRevisionsTable get novelAgentSkillRevisions =>
      attachedDatabase.novelAgentSkillRevisions;
  $NovelAgentSkillRevisionFilesTable get novelAgentSkillRevisionFiles =>
      attachedDatabase.novelAgentSkillRevisionFiles;
  $NovelAgentSkillBlobsTable get novelAgentSkillBlobs =>
      attachedDatabase.novelAgentSkillBlobs;
  NovelAgentSkillRevisionDaoManager get managers =>
      NovelAgentSkillRevisionDaoManager(this);
}

class NovelAgentSkillRevisionDaoManager {
  final _$NovelAgentSkillRevisionDaoMixin _db;
  NovelAgentSkillRevisionDaoManager(this._db);
  $$NovelAgentSkillsTableTableManager get novelAgentSkills =>
      $$NovelAgentSkillsTableTableManager(
        _db.attachedDatabase,
        _db.novelAgentSkills,
      );
  $$NovelAgentSkillRevisionsTableTableManager get novelAgentSkillRevisions =>
      $$NovelAgentSkillRevisionsTableTableManager(
        _db.attachedDatabase,
        _db.novelAgentSkillRevisions,
      );
  $$NovelAgentSkillRevisionFilesTableTableManager
  get novelAgentSkillRevisionFiles =>
      $$NovelAgentSkillRevisionFilesTableTableManager(
        _db.attachedDatabase,
        _db.novelAgentSkillRevisionFiles,
      );
  $$NovelAgentSkillBlobsTableTableManager get novelAgentSkillBlobs =>
      $$NovelAgentSkillBlobsTableTableManager(
        _db.attachedDatabase,
        _db.novelAgentSkillBlobs,
      );
}
