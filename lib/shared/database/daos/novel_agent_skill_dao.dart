// 职责: 应用级全局 AgentSkill 可执行快照的增删改查。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/providers/novel_agent_skill_providers.dart
//   lib/shared/models/novel_agent_skill.dart
// 遵循的 Rules:
//   .agents/rules/db-migration.md
//   .agents/rules/db-query-aggregation.md
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../../models/agent_skill_reference.dart';

part 'novel_agent_skill_dao.drift.dart';

@DriftAccessor(tables: [NovelAgentSkills, NovelAgentSkillReferences])
class NovelAgentSkillDao extends DatabaseAccessor<AppDatabase>
    with _$NovelAgentSkillDaoMixin {
  NovelAgentSkillDao(super.db);

  Future<List<NovelAgentSkill>> getAll() {
    return (select(novelAgentSkills)..orderBy([
          (t) => OrderingTerm(expression: t.sortOrder, mode: OrderingMode.asc),
        ]))
        .get();
  }

  /// 主列表与 references 一起读取，仅用于管理界面和导入导出等需要完整快照的场景。
  Future<Map<String, List<AgentSkillReferenceFile>>> getReferencesBySkillIds(
    Iterable<String> skillIds,
  ) async {
    final ids = skillIds.toList(growable: false);
    if (ids.isEmpty) {
      return const {};
    }
    final rows =
        await (select(novelAgentSkillReferences)
              ..where((t) => t.skillId.isIn(ids))
              ..orderBy([(t) => OrderingTerm.asc(t.path)]))
            .get();
    final result = <String, List<AgentSkillReferenceFile>>{};
    for (final row in rows) {
      (result[row.skillId] ??= <AgentSkillReferenceFile>[]).add(
        AgentSkillReferenceFile(path: row.path, content: row.content),
      );
    }
    return result;
  }

  Stream<List<NovelAgentSkill>> watchAll() {
    return (select(novelAgentSkills)..orderBy([
          (t) => OrderingTerm(expression: t.sortOrder, mode: OrderingMode.asc),
        ]))
        .watch();
  }

  /// 运行时读取:全局可执行技能,过滤 enabled=false 与被撤销条目。
  Future<List<NovelAgentSkill>> getExecutable() {
    return (select(novelAgentSkills)
          ..where((t) => t.enabled.equals(true))
          ..where((t) => t.executionBlockedReason.isNull())
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.sortOrder, mode: OrderingMode.asc),
          ]))
        .get();
  }

  Future<NovelAgentSkill?> getById(String id) {
    return (select(
      novelAgentSkills,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<NovelAgentSkill?> getByName(String name) {
    return (select(
      novelAgentSkills,
    )..where((t) => t.name.equals(name))).getSingleOrNull();
  }

  /// 按 source_listing_public_id 查询,用于撤销状态批量更新。
  Future<List<NovelAgentSkill>> getByListingPublicId(String publicId) {
    return (select(
      novelAgentSkills,
    )..where((t) => t.sourceListingPublicId.equals(publicId))).get();
  }

  Future<void> upsert(NovelAgentSkillsCompanion entry) {
    return into(novelAgentSkills).insertOnConflictUpdate(entry);
  }

  /// 原子写入技能快照并替换其 references 子表内容。
  Future<void> upsertWithReferences({
    required NovelAgentSkillsCompanion skill,
    required Iterable<AgentSkillReferenceFile> references,
  }) async {
    await transaction(() async {
      await into(novelAgentSkills).insertOnConflictUpdate(skill);
      await (delete(
        novelAgentSkillReferences,
      )..where((t) => t.skillId.equals(skill.id.value))).go();
      final now = DateTime.now();
      for (final ref in references) {
        await into(novelAgentSkillReferences).insert(
          NovelAgentSkillReferencesCompanion.insert(
            skillId: skill.id.value,
            path: ref.path,
            content: ref.content,
            byteSize: utf8.encode(ref.content).length,
            sha256: Value(sha256.convert(utf8.encode(ref.content)).toString()),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// 删除技能及其全部子表数据。
  ///
  /// 显式删子表而不依赖表定义上的 `onDelete: cascade` —— 本库没有开启
  /// `PRAGMA foreign_keys`，外键级联不会真的执行，只删主表会在
  /// `novel_agent_skill_references` 与历史表里留下永久孤儿行。
  Future<int> hardDelete(String id) async {
    return transaction(() async {
      await (delete(
        novelAgentSkillReferences,
      )..where((t) => t.skillId.equals(id))).go();
      await attachedDatabase.novelAgentSkillRevisionDao.deleteForSkill(id);
      return (delete(novelAgentSkills)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<void> reorder(List<String> ids) async {
    await transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (update(novelAgentSkills)..where((t) => t.id.equals(ids[i])))
            .write(NovelAgentSkillsCompanion(sortOrder: Value(i)));
      }
    });
  }
}
