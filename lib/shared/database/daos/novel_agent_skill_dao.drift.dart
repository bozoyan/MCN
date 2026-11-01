// dart format width=80
// ignore_for_file: type=lint
part of 'novel_agent_skill_dao.dart';

mixin _$NovelAgentSkillDaoMixin on DatabaseAccessor<AppDatabase> {
  $NovelAgentSkillsTable get novelAgentSkills =>
      attachedDatabase.novelAgentSkills;
  $NovelAgentSkillReferencesTable get novelAgentSkillReferences =>
      attachedDatabase.novelAgentSkillReferences;
  NovelAgentSkillDaoManager get managers => NovelAgentSkillDaoManager(this);
}

class NovelAgentSkillDaoManager {
  final _$NovelAgentSkillDaoMixin _db;
  NovelAgentSkillDaoManager(this._db);
  $$NovelAgentSkillsTableTableManager get novelAgentSkills =>
      $$NovelAgentSkillsTableTableManager(
        _db.attachedDatabase,
        _db.novelAgentSkills,
      );
  $$NovelAgentSkillReferencesTableTableManager get novelAgentSkillReferences =>
      $$NovelAgentSkillReferencesTableTableManager(
        _db.attachedDatabase,
        _db.novelAgentSkillReferences,
      );
}
