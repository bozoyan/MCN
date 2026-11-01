// dart format width=80
// ignore_for_file: type=lint
part of 'agent_rule_dao.dart';

mixin _$AgentRuleDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $AgentRulesTable get agentRules => attachedDatabase.agentRules;
  AgentRuleDaoManager get managers => AgentRuleDaoManager(this);
}

class AgentRuleDaoManager {
  final _$AgentRuleDaoMixin _db;
  AgentRuleDaoManager(this._db);
  $$AgentRulesTableTableManager get agentRules =>
      $$AgentRulesTableTableManager(_db.attachedDatabase, _db.agentRules);
}
