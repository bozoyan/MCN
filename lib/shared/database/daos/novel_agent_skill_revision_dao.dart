// 职责: AgentSkill 历史版本的写入、读取、裁剪与孤儿 blob 回收。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/agent_skill_revision.dart
//   lib/shared/models/novel_agent_skill.dart
//   lib/shared/providers/novel_agent_skill_providers.dart
// 遵循的 Rules:
//   .agents/rules/db-migration.md
//   .agents/rules/db-query-aggregation.md
//   .agents/rules/data-deletion.md
import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../../models/agent_skill_reference.dart';
import '../../models/agent_skill_revision.dart';
import '../../models/novel_agent_skill.dart';
import '../../utils/random_id.dart';

part 'novel_agent_skill_revision_dao.drift.dart';

@DriftAccessor(
  tables: [
    NovelAgentSkillRevisions,
    NovelAgentSkillRevisionFiles,
    NovelAgentSkillBlobs,
  ],
)
class NovelAgentSkillRevisionDao extends DatabaseAccessor<AppDatabase>
    with _$NovelAgentSkillRevisionDaoMixin {
  NovelAgentSkillRevisionDao(super.db);

  /// 每个技能保留的历史版本上限，超出后物理删除最旧条目。
  static const int retainedRevisionsPerSkill = 50;

  Future<bool> hasAnyRevision(String skillId) async {
    final row =
        await (select(novelAgentSkillRevisions)
              ..where((t) => t.skillId.equals(skillId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// 最新一条版本的内容指纹，用于判断本次写入是否真的改了内容。
  Future<String?> latestContentHash(String skillId) async {
    final row =
        await (select(novelAgentSkillRevisions)
              ..where((t) => t.skillId.equals(skillId))
              ..orderBy([(t) => OrderingTerm.desc(t.revision)])
              ..limit(1))
            .getSingleOrNull();
    return row?.contentHash;
  }

  Future<List<AgentSkillRevisionSummary>> listRevisions(
    String skillId, {
    int limit = retainedRevisionsPerSkill,
    int offset = 0,
  }) async {
    // 列表不读 prompt / 附件正文：只 select 摘要列，避免把全部历史指令拉进内存。
    final revisions = novelAgentSkillRevisions;
    final query = selectOnly(revisions)
      ..addColumns([
        revisions.id,
        revisions.skillId,
        revisions.revision,
        revisions.turnId,
        revisions.name,
        revisions.description,
        revisions.changeSource,
        revisions.changeNote,
        revisions.createdAt,
      ])
      ..where(revisions.skillId.equals(skillId))
      ..orderBy([OrderingTerm.desc(revisions.revision)])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    if (rows.isEmpty) {
      return const [];
    }

    final ids = [for (final row in rows) row.read(revisions.id)!];
    final fileCounts = await _fileCountsByRevisionId(ids);
    return [
      for (final row in rows)
        AgentSkillRevisionSummary(
          id: row.read(revisions.id)!,
          skillId: row.read(revisions.skillId)!,
          revision: row.read(revisions.revision)!,
          turnId: row.read(revisions.turnId),
          name: row.read(revisions.name)!,
          description: row.read(revisions.description) ?? '',
          changeSource: SkillRevisionSource.fromDbValue(
            row.read(revisions.changeSource) ?? '',
          ),
          changeNote: row.read(revisions.changeNote),
          createdAt: row.read(revisions.createdAt)!,
          fileCount: fileCounts[row.read(revisions.id)!] ?? 0,
        ),
    ];
  }

  Future<AgentSkillRevisionDetail?> getRevision(String id) async {
    final row = await (select(
      novelAgentSkillRevisions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    final references = await _referencesForRevision(id);
    return AgentSkillRevisionDetail(
      summary: AgentSkillRevisionSummary(
        id: row.id,
        skillId: row.skillId,
        revision: row.revision,
        turnId: row.turnId,
        name: row.name,
        description: row.description,
        changeSource: SkillRevisionSource.fromDbValue(row.changeSource),
        changeNote: row.changeNote,
        createdAt: row.createdAt,
        fileCount: references.length,
      ),
      whenToUse: row.whenToUse,
      prompt: row.prompt,
      category: row.category,
      tags: row.tags,
      agentScopes: row.agentScopes,
      contentHash: row.contentHash,
      references: references,
    );
  }

  /// 追加一条历史版本。
  ///
  /// [turnId] 非空且该技能下已存在同 turn 的版本时**覆盖那一条**（保留其 id、
  /// revision 与 created_at），使 AI 一轮内的多次工具调用只留一条记录。
  /// 返回写入后的版本号。
  Future<int> appendRevision({
    required NovelAgentSkillModel content,
    required SkillRevisionSource changeSource,
    String? turnId,
    String? changeNote,
  }) async {
    return transaction(() async {
      final existing = turnId == null || turnId.isEmpty
          ? null
          : await _findByTurnId(content.id, turnId);
      final hash = content.contentHash;

      if (existing != null) {
        await (update(
          novelAgentSkillRevisions,
        )..where((t) => t.id.equals(existing.id))).write(
          NovelAgentSkillRevisionsCompanion(
            name: Value(content.name),
            whenToUse: Value(content.whenToUse),
            description: Value(content.description),
            prompt: Value(content.prompt),
            category: Value(content.category),
            tags: Value(content.tags),
            agentScopes: Value(content.agentScopes),
            contentHash: Value(hash),
            changeNote: Value(changeNote ?? existing.changeNote),
          ),
        );
        await _writeFiles(existing.id, content.references);
        return existing.revision;
      }

      final nextRevision = await _nextRevisionNumber(content.id);
      final revisionId = buildRandomId('nasr');
      await into(novelAgentSkillRevisions).insert(
        NovelAgentSkillRevisionsCompanion.insert(
          id: revisionId,
          skillId: content.id,
          revision: nextRevision,
          turnId: Value(turnId == null || turnId.isEmpty ? null : turnId),
          name: content.name,
          whenToUse: Value(content.whenToUse),
          description: Value(content.description),
          prompt: Value(content.prompt),
          category: Value(content.category),
          tags: Value(content.tags),
          agentScopes: Value(content.agentScopes),
          contentHash: hash,
          changeSource: changeSource.dbValue,
          changeNote: Value(changeNote),
          createdAt: Value(DateTime.now()),
        ),
      );
      await _writeFiles(revisionId, content.references);
      return nextRevision;
    });
  }

  /// 裁剪超出上限的最旧版本。物理删除，范围仅限历史表。
  ///
  /// 显式删除子表而不依赖 `onDelete: cascade` —— 本库没有开启
  /// `PRAGMA foreign_keys`，外键级联不会真的执行。
  Future<int> pruneRevisions(
    String skillId, {
    int keep = retainedRevisionsPerSkill,
  }) async {
    final ids =
        await (select(novelAgentSkillRevisions)
              ..where((t) => t.skillId.equals(skillId))
              ..orderBy([(t) => OrderingTerm.desc(t.revision)]))
            .map((row) => row.id)
            .get();
    if (ids.length <= keep) {
      return 0;
    }
    final stale = ids.sublist(keep);
    return transaction(() async {
      await (delete(
        novelAgentSkillRevisionFiles,
      )..where((t) => t.revisionId.isIn(stale))).go();
      return (delete(
        novelAgentSkillRevisions,
      )..where((t) => t.id.isIn(stale))).go();
    });
  }

  /// 删除某个技能的全部历史。技能本身被删除时调用。
  Future<int> deleteForSkill(String skillId) async {
    final ids = await (select(
      novelAgentSkillRevisions,
    )..where((t) => t.skillId.equals(skillId))).map((row) => row.id).get();
    if (ids.isEmpty) {
      return 0;
    }
    return transaction(() async {
      await (delete(
        novelAgentSkillRevisionFiles,
      )..where((t) => t.revisionId.isIn(ids))).go();
      return (delete(
        novelAgentSkillRevisions,
      )..where((t) => t.skillId.equals(skillId))).go();
    });
  }

  /// 回收不再被任何历史版本引用的附件正文。
  ///
  /// 用扫描而非引用计数：计数在异常路径上容易漏减，扫描是幂等的，
  /// 上一次失败会在下一次触发时自动补上。
  Future<int> gcBlobs() async {
    final referenced = selectOnly(novelAgentSkillRevisionFiles, distinct: true)
      ..addColumns([novelAgentSkillRevisionFiles.sha256]);
    return (delete(
      novelAgentSkillBlobs,
    )..where((t) => t.sha256.isNotInQuery(referenced))).go();
  }

  // ── helpers ───────────────────────────────────────────────────────────

  Future<NovelAgentSkillRevision?> _findByTurnId(
    String skillId,
    String turnId,
  ) {
    return (select(novelAgentSkillRevisions)
          ..where((t) => t.skillId.equals(skillId) & t.turnId.equals(turnId))
          ..orderBy([(t) => OrderingTerm.desc(t.revision)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> _nextRevisionNumber(String skillId) async {
    final revisions = novelAgentSkillRevisions;
    final maxRevision = revisions.revision.max();
    final row =
        await (selectOnly(revisions)
              ..addColumns([maxRevision])
              ..where(revisions.skillId.equals(skillId)))
            .getSingle();
    return (row.read(maxRevision) ?? 0) + 1;
  }

  Future<void> _writeFiles(
    String revisionId,
    List<AgentSkillReferenceFile> references,
  ) async {
    await (delete(
      novelAgentSkillRevisionFiles,
    )..where((t) => t.revisionId.equals(revisionId))).go();
    for (final reference in references) {
      final hash = agentSkillBlobHash(reference.content);
      // 同一份正文无论被多少版本引用都只存一行；重复写入天然幂等。
      await into(novelAgentSkillBlobs).insertOnConflictUpdate(
        NovelAgentSkillBlobsCompanion.insert(
          sha256: hash,
          content: reference.content,
          byteSize: utf8.encode(reference.content).length,
          createdAt: Value(DateTime.now()),
        ),
      );
      await into(novelAgentSkillRevisionFiles).insert(
        NovelAgentSkillRevisionFilesCompanion.insert(
          revisionId: revisionId,
          path: reference.path,
          sha256: hash,
        ),
      );
    }
  }

  Future<List<AgentSkillReferenceFile>> _referencesForRevision(
    String revisionId,
  ) async {
    final files = novelAgentSkillRevisionFiles;
    final blobs = novelAgentSkillBlobs;
    final rows =
        await (select(files).join([
                leftOuterJoin(blobs, blobs.sha256.equalsExp(files.sha256)),
              ])
              ..where(files.revisionId.equals(revisionId))
              ..orderBy([OrderingTerm.asc(files.path)]))
            .get();
    return [
      for (final row in rows)
        AgentSkillReferenceFile(
          path: row.readTable(files).path,
          content: row.readTableOrNull(blobs)?.content ?? '',
        ),
    ];
  }

  Future<Map<String, int>> _fileCountsByRevisionId(List<String> ids) async {
    if (ids.isEmpty) {
      return const {};
    }
    final files = novelAgentSkillRevisionFiles;
    final count = files.path.count();
    final rows =
        await (selectOnly(files)
              ..addColumns([files.revisionId, count])
              ..where(files.revisionId.isIn(ids))
              ..groupBy([files.revisionId]))
            .get();
    return {
      for (final row in rows) row.read(files.revisionId)!: row.read(count) ?? 0,
    };
  }
}
