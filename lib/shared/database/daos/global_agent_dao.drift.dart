// dart format width=80
// ignore_for_file: type=lint
part of 'global_agent_dao.dart';

mixin _$GlobalAgentDaoMixin on DatabaseAccessor<AppDatabase> {
  $AgentsTable get agents => attachedDatabase.agents;
  GlobalAgentDaoManager get managers => GlobalAgentDaoManager(this);
}

class GlobalAgentDaoManager {
  final _$GlobalAgentDaoMixin _db;
  GlobalAgentDaoManager(this._db);
  $$AgentsTableTableManager get agents =>
      $$AgentsTableTableManager(_db.attachedDatabase, _db.agents);
}
