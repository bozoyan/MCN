// 职责: 代理规则数据访问对象 — 封装所有代理规则相关的数据库操作
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/providers/novel_providers.dart

import 'package:drift/drift.dart';

import '../novel_content_database.dart';

part 'agent_rule_dao.drift.dart';

@DriftAccessor(tables: [AgentRules])
class AgentRuleDao extends DatabaseAccessor<NovelContentDatabase>
    with _$AgentRuleDaoMixin {
  AgentRuleDao(super.db);

  Future<List<AgentRule>> getAll() async {
    return (select(agentRules)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.sortOrder,
              mode: OrderingMode.asc,
            ),
          ]))
        .get();
  }

  Stream<List<AgentRule>> watchAll() {
    return (select(agentRules)
          ..where((table) => table.deletedAt.equals(notDeletedSentinel))
          ..orderBy([
            (table) => OrderingTerm(
              expression: table.sortOrder,
              mode: OrderingMode.asc,
            ),
          ]))
        .watch();
  }

  Future<void> upsert(AgentRule rule) async {
    await into(agentRules).insertOnConflictUpdate(rule);
  }

  Future<int> softDelete(String id) async {
    return (update(agentRules)..where((table) => table.id.equals(id))).write(
      AgentRulesCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> restore(String id) async {
    return (update(agentRules)..where((table) => table.id.equals(id))).write(
      AgentRulesCompanion(deletedAt: Value(notDeletedSentinel)),
    );
  }

  Future<int> hardDelete(String id) async {
    return (delete(agentRules)..where((table) => table.id.equals(id))).go();
  }

  Future<void> reorder(List<String> ids) async {
    await transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (update(agentRules)..where((table) => table.id.equals(ids[i])))
            .write(AgentRulesCompanion(sortOrder: Value(i)));
      }
    });
  }
}
