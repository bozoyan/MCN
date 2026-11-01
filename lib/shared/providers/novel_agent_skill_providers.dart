// 职责: AgentSkill 应用全局安装快照的 Riverpod Provider —— 全局可执行技能列表，
//   管理本地快照，并从打包官方目录安装、覆盖与升级技能。
// 关联文件:
//   lib/shared/database/daos/novel_agent_skill_dao.dart
//   lib/shared/database/daos/novel_agent_skill_revision_dao.dart
//   lib/shared/models/novel_agent_skill.dart
//   lib/shared/models/agent_skill_revision.dart
//   lib/shared/providers/agent_skill_providers.dart (复用 agentSkillAppDatabaseProvider)
//   lib/shared/providers/agent_skill_catalog_providers.dart
//   lib/shared/models/official_agent_skill.dart
//   lib/shared/services/agent_skill_catalog_service.dart
//   lib/shared/services/ai/chat_turn_runner.dart
//   lib/desktop/features/agent_skills/setup_panel.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/error-handling.md
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'async_read.dart';
import '../database/app_database.dart';
import '../logger/app_logger.dart';
import '../models/agent_skill_reference.dart';
import '../models/agent_skill_revision.dart';
import '../models/catalog_skill_installation_state.dart';
import '../models/novel_agent_skill.dart';
import '../models/official_agent_skill.dart';
import '../utils/random_id.dart';
import 'agent_skill_catalog_providers.dart';
import 'agent_skill_providers.dart' show agentSkillAppDatabaseProvider;

final _log = AppLogger.forModule('NovelAgentSkillProviders');

// ── 行 ↔ 领域模型映射 ────────────────────────────────────────────────────────

NovelAgentSkillModel _mapNovelAgentSkill(
  NovelAgentSkill row,
  List<AgentSkillReferenceFile> references,
) {
  return NovelAgentSkillModel(
    id: row.id,
    sourceKind: AgentSkillSourceKind.fromDbValue(row.sourceKind),
    sourceListingPublicId: row.sourceListingPublicId,
    sourceVersion: row.sourceVersion,
    sourceDisplayName: row.sourceDisplayName,
    name: row.name,
    whenToUse: row.whenToUse,
    description: row.description,
    prompt: row.prompt,
    agentScopes: row.agentScopes,
    category: row.category,
    tags: row.tags,
    references: references,
    enabled: row.enabled,
    sortOrder: row.sortOrder,
    executionBlockedReason: row.executionBlockedReason,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

NovelAgentSkillsCompanion _novelAgentSkillToCompanion(
  NovelAgentSkillModel model,
) {
  return NovelAgentSkillsCompanion(
    id: Value(model.id),
    sourceKind: Value(model.sourceKind.dbValue),
    sourceListingPublicId: Value(model.sourceListingPublicId),
    sourceVersion: Value(model.sourceVersion),
    sourceDisplayName: Value(model.sourceDisplayName),
    name: Value(model.name),
    whenToUse: Value(model.whenToUse),
    description: Value(model.description),
    prompt: Value(model.prompt),
    agentScopes: Value(model.agentScopes),
    category: Value(model.category),
    tags: Value(model.tags),
    enabled: Value(model.enabled),
    sortOrder: Value(model.sortOrder),
    executionBlockedReason: Value(model.executionBlockedReason),
    createdAt: Value(model.createdAt ?? DateTime.now()),
    updatedAt: Value(model.updatedAt ?? DateTime.now()),
  );
}

// ── 异常 ─────────────────────────────────────────────────────────────────────

class NovelSkillNameConflictException implements Exception {
  NovelSkillNameConflictException(this.name);
  final String name;

  @override
  String toString() => 'NovelSkillNameConflictException: $name';
}

// ── 应用全局可执行快照(NovelAgentSkill)──────────────────────────────────────

/// 安装输入，区分本地官方目录与技能市场来源。
class InstallSkillInput {
  const InstallSkillInput({
    required this.sourceKind,
    this.sourceListingPublicId,
    this.sourceVersion,
    this.sourceDisplayName,
    required this.name,
    required this.description,
    required this.prompt,
    this.whenToUse = '',
    this.agentScopes = const [],
    this.category = '',
    this.tags = const [],
    this.references = const [],
    this.enabled = true,
  });

  final AgentSkillSourceKind sourceKind;
  final String? sourceListingPublicId;
  final String? sourceVersion;
  final String? sourceDisplayName;

  /// 应用全局唯一的工具名。
  final String name;
  final String whenToUse;
  final String description;
  final String prompt;
  final List<String> agentScopes;
  final String category;
  final List<String> tags;
  final List<AgentSkillReferenceFile> references;
  final bool enabled;
}

class InstalledAgentSkillsNotifier
    extends AsyncNotifier<List<NovelAgentSkillModel>> {
  @override
  Future<List<NovelAgentSkillModel>> build() async {
    final db = ref.watch(agentSkillAppDatabaseProvider);
    final rows = await db.novelAgentSkillDao.getAll();
    final refs = await db.novelAgentSkillDao.getReferencesBySkillIds(
      rows.map((row) => row.id),
    );
    return [
      for (final row in rows)
        _mapNovelAgentSkill(row, refs[row.id] ?? const []),
    ];
  }

  /// 安装技能。name 冲突时抛 [NovelSkillNameConflictException],
  /// 由 UI 决定覆盖或重命名后再次调用 [installOverwrite] / [installRename]。
  Future<NovelAgentSkillModel> install(InstallSkillInput input) async {
    final current = state.value ?? await future;
    final name = input.name.trim();
    final conflict = _findByName(current, name);
    if (conflict != null) {
      throw NovelSkillNameConflictException(name);
    }
    return _persistInstall(input, name, current);
  }

  /// 覆盖现有同名安装:替换目标记录,旧来源关联消失。
  Future<NovelAgentSkillModel> installOverwrite(InstallSkillInput input) async {
    final current = state.value ?? await future;
    final name = input.name.trim();
    final conflict = _findByName(current, name);
    final db = ref.read(agentSkillAppDatabaseProvider);
    if (conflict != null) {
      await db.novelAgentSkillDao.hardDelete(conflict.id);
    }
    final withoutConflict = conflict == null
        ? current
        : current.where((item) => item.id != conflict.id).toList();
    return _persistInstall(input, name, withoutConflict);
  }

  /// 以新名称安装:保留两条独立安装,不破坏新来源的升级关联。
  Future<NovelAgentSkillModel> installRename(
    InstallSkillInput input,
    String name,
  ) async {
    final current = state.value ?? await future;
    final trimmed = name.trim();
    if (_findByName(current, trimmed) != null) {
      throw NovelSkillNameConflictException(trimmed);
    }
    return _persistInstall(input, trimmed, current);
  }

  Future<NovelAgentSkillModel> _persistInstall(
    InstallSkillInput input,
    String name,
    List<NovelAgentSkillModel> current,
  ) async {
    final now = DateTime.now();
    final model = NovelAgentSkillModel(
      id: buildRandomId('nas'),
      sourceKind: input.sourceKind,
      sourceListingPublicId: input.sourceListingPublicId,
      sourceVersion: input.sourceVersion,
      sourceDisplayName: input.sourceDisplayName,
      name: name,
      whenToUse: input.whenToUse,
      description: input.description,
      prompt: input.prompt,
      agentScopes: input.agentScopes,
      category: input.category,
      tags: input.tags,
      references: AgentSkillReferences.sanitize(input.references),
      enabled: input.enabled,
      sortOrder: current.length,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _writeUpdate(
        model,
        previous: null,
        changeSource: SkillRevisionSource.install,
        changeNote: input.sourceVersion,
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] INSERT novel_agent_skills failed id=${model.id}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    if (!ref.mounted) {
      return model;
    }
    state = AsyncValue.data([...current, model]);
    return model;
  }

  /// 直接创建本地技能(source_kind=novel_local)。
  Future<NovelAgentSkillModel> createNovelLocalSkill(InstallSkillInput input) {
    return install(input.copyWith(sourceKind: AgentSkillSourceKind.novelLocal));
  }

  Future<void> toggleEnabled(String id) async {
    final current = state.value ?? await future;
    final target = _findById(current, id);
    if (target == null) {
      return;
    }
    final updated = target.copyWith(
      enabled: !target.enabled,
      updatedAt: DateTime.now(),
    );
    await _writeUpdate(updated, previous: target);
    _replaceInState(current, updated);
  }

  Future<void> rename(
    String id,
    String name, {
    SkillRevisionSource changeSource = SkillRevisionSource.user_edit,
    String? turnId,
  }) async {
    final current = state.value ?? await future;
    final trimmed = name.trim();
    if (_findByName(current, trimmed)?.id == id) {
      return; // 未变化。
    }
    if (_findByName(current, trimmed) != null) {
      throw NovelSkillNameConflictException(trimmed);
    }
    final target = _findById(current, id);
    if (target == null) {
      return;
    }
    final updated = target.copyWith(name: trimmed, updatedAt: DateTime.now());
    await _writeUpdate(
      updated,
      previous: target,
      changeSource: changeSource,
      turnId: turnId,
    );
    _replaceInState(current, updated);
  }

  Future<void> updateSnapshotFields(
    NovelAgentSkillModel updated, {
    SkillRevisionSource changeSource = SkillRevisionSource.user_edit,
    String? turnId,
    String? changeNote,
  }) async {
    final current = state.value ?? await future;
    final name = updated.name.trim();
    final conflict = _findByName(current, name);
    if (conflict != null && conflict.id != updated.id) {
      throw NovelSkillNameConflictException(name);
    }
    final withTimestamp = updated.copyWith(
      name: name,
      updatedAt: DateTime.now(),
    );
    await _writeUpdate(
      withTimestamp,
      previous: _findById(current, updated.id),
      changeSource: changeSource,
      turnId: turnId,
      changeNote: changeNote,
    );
    _replaceInState(current, withTimestamp);
  }

  /// 替换指定 Skill 的全部 references；调用方负责以语义化操作构造目标列表。
  ///
  /// 统一在此处严格校验并持久化，避免 AI 工具或 UI 绕过全局技能缓存直接写 DAO。
  Future<NovelAgentSkillModel> replaceReferencesByName({
    required String name,
    required Iterable<AgentSkillReferenceFile> references,
    SkillRevisionSource changeSource = SkillRevisionSource.user_edit,
    String? turnId,
  }) async {
    final current = state.value ?? await future;
    final target = _findByName(current, name);
    if (target == null) {
      throw StateError('NovelAgentSkill not found: ${name.trim()}');
    }
    final normalized = AgentSkillReferences.normalizeOrThrow(references);
    final updated = target.copyWith(
      references: normalized,
      updatedAt: DateTime.now(),
    );
    await _writeUpdate(
      updated,
      previous: target,
      changeSource: changeSource,
      turnId: turnId,
    );
    _replaceInState(current, updated);
    return updated;
  }

  /// 显式升级:覆盖来源追溯与快照内容,保留 id/name/enabled/sortOrder。
  Future<NovelAgentSkillModel> upgradeSnapshot({
    required String id,
    required String sourceVersion,
    required String sourceDisplayName,
    required String whenToUse,
    required String description,
    required String prompt,
    required List<String> agentScopes,
    required String category,
    required List<String> tags,
  }) async {
    final current = state.value ?? await future;
    final target = _findById(current, id);
    if (target == null) {
      throw StateError('NovelAgentSkill not found: $id');
    }
    final upgraded = target.withUpgradedSnapshot(
      sourceVersion: sourceVersion,
      sourceDisplayName: sourceDisplayName,
      whenToUse: whenToUse,
      description: description,
      prompt: prompt,
      agentScopes: agentScopes,
      category: category,
      tags: tags,
      updatedAt: DateTime.now(),
    );
    await _writeUpdate(
      upgraded,
      previous: target,
      changeSource: SkillRevisionSource.upgrade,
      changeNote: sourceVersion,
    );
    _replaceInState(current, upgraded);
    return upgraded;
  }

  /// 设置/清除运行时阻止原因(用于紧急撤销)。null 表示清除阻止。
  Future<void> setExecutionBlockedReason(String id, String? reason) async {
    final current = state.value ?? await future;
    final target = _findById(current, id);
    if (target == null) {
      return;
    }
    final updated = target.copyWith(
      executionBlockedReason: reason,
      updatedAt: DateTime.now(),
    );
    await _writeUpdate(updated, previous: target);
    _replaceInState(current, updated);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? await future;
    final db = ref.read(agentSkillAppDatabaseProvider);
    // hardDelete 已在同一事务里清掉 references 与历史版本；这里只回收
    // 因此产生的孤儿附件正文。GC 失败不该阻断删除，只记日志。
    await db.novelAgentSkillDao.hardDelete(id);
    try {
      await db.novelAgentSkillRevisionDao.gcBlobs();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] gc novel_agent_skill_blobs failed id=$id',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (!ref.mounted) {
      return;
    }
    state = AsyncValue.data([
      for (final item in current)
        if (item.id != id) item,
    ]);
  }

  Future<void> reorder(List<String> ids) async {
    final current = state.value ?? await future;
    final db = ref.read(agentSkillAppDatabaseProvider);
    await db.novelAgentSkillDao.reorder(ids);
    if (!ref.mounted) {
      return;
    }
    final byId = {for (final item in current) item.id: item};
    state = AsyncValue.data([
      for (final id in ids)
        if (byId[id] != null) byId[id]!.copyWith(sortOrder: ids.indexOf(id)),
    ]);
  }

  /// 将已安装的官方/市场技能断开来源关联,保留当前快照为本地技能。
  Future<NovelAgentSkillModel> convertToNovelLocal(String id) async {
    final current = state.value ?? await future;
    final target = _findById(current, id);
    if (target == null) {
      throw StateError('NovelAgentSkill not found: $id');
    }
    if (target.sourceKind == AgentSkillSourceKind.novelLocal) {
      return target;
    }
    final converted = _asNovelLocal(target, DateTime.now());
    try {
      await _writeUpdate(converted, previous: target);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] UPDATE novel_agent_skills failed op=convertToNovelLocal '
        'id=${target.id}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    _replaceInState(current, converted);
    return converted;
  }

  // ── 目录安装/覆盖/升级 ─────────────────────────────────

  /// 从官方目录安装。name 冲突时返回 [InstallFromCatalogConflict],
  /// 不写入;由 UI 决定调用 [overwriteInstall] 或以新 name 重试。
  Future<InstallFromCatalogResult> installFromOfficial({
    required OfficialAgentSkill source,
    String? overrideName,
  }) async {
    final current = state.value ?? await future;
    final name = (overrideName ?? source.name).trim();
    final conflict = _findByName(current, name);
    if (conflict != null) {
      return InstallFromCatalogConflict(conflict.id, conflict.name);
    }
    final input = InstallSkillInput(
      sourceKind: AgentSkillSourceKind.official,
      sourceListingPublicId: source.listingId,
      sourceVersion: source.version.toString(),
      sourceDisplayName: source.name,
      name: name,
      whenToUse: source.whenToUse,
      description: source.description,
      prompt: source.prompt,
      category: source.category,
      tags: source.tags,
      references: _sanitizeCatalogReferences(source.references),
      enabled: true,
    );
    final installed = await _persistInstall(input, name, current);
    return InstallFromCatalogSuccess(installed.id);
  }

  /// 覆盖安装:用新来源的快照替换 existing 记录,保留 id/name/enabled/
  /// sort_order/created_at,清空 execution_blocked_reason。
  /// 用于 UI 收到 [InstallFromCatalogConflict] 后用户选择覆盖。
  Future<String> overwriteInstall({
    required String existingNovelAgentSkillId,
    required InstallFromCatalogSource source,
  }) async {
    final current = state.value ?? await future;
    final target = _findById(current, existingNovelAgentSkillId);
    if (target == null) {
      throw StateError('NovelAgentSkill not found: $existingNovelAgentSkillId');
    }
    final now = DateTime.now();
    final updated = switch (source) {
      InstallFromOfficialSource(:final dto) => target.copyWith(
        sourceKind: AgentSkillSourceKind.official,
        sourceListingPublicId: dto.listingId,
        sourceVersion: dto.version.toString(),
        sourceDisplayName: dto.name,
        whenToUse: dto.whenToUse,
        description: dto.description,
        prompt: dto.prompt,
        category: dto.category,
        tags: dto.tags,
        references: _sanitizeCatalogReferences(dto.references),
        executionBlockedReason: null,
        updatedAt: now,
      ),
    };
    await _writeUpdate(
      updated,
      previous: target,
      changeSource: SkillRevisionSource.install,
      changeNote: updated.sourceVersion,
    );
    _replaceInState(current, updated);
    return updated.id;
  }

  /// 更新 source_version/source_display_name,保留 id/name/enabled/sort_order。
  Future<UpgradeResult> upgradeNovelAgentSkill({
    required String novelAgentSkillId,
  }) async {
    final current = state.value ?? await future;
    final target = _findById(current, novelAgentSkillId);
    if (target == null) {
      throw StateError('NovelAgentSkill not found: $novelAgentSkillId');
    }
    final currentVersion = int.tryParse(target.sourceVersion ?? '');
    switch (target.sourceKind) {
      case AgentSkillSourceKind.official:
        final officialList = await ref.readFuture(
          officialAgentSkillsProvider(agentSkillCatalogFilter()).future,
        );
        if (!ref.mounted) {
          return const UpgradeNotTraceable();
        }
        final match = _findOfficialByName(
          officialList.agentSkills,
          officialSkillCatalogName(target),
        );
        if (match == null) {
          return const UpgradeNotTraceable();
        }
        if (currentVersion != null && match.version <= currentVersion) {
          return AlreadyLatestVersion(currentVersion);
        }
        final detail = await ref.readFuture(
          officialAgentSkillDetailProvider(match.listingId).future,
        );
        if (!ref.mounted) {
          return const UpgradeNotTraceable();
        }
        final upgraded = target.withUpgradedSnapshot(
          sourceListingPublicId: detail.listingId,
          sourceVersion: detail.version.toString(),
          sourceDisplayName: detail.name,
          whenToUse: detail.whenToUse,
          description: detail.description,
          prompt: detail.prompt,
          // 目录详情不包含 agent_scopes，升级时保留本地已有值。
          agentScopes: target.agentScopes,
          category: detail.category,
          tags: detail.tags,
          references: _sanitizeCatalogReferences(detail.references),
          updatedAt: DateTime.now(),
        );
        await _writeUpdate(
          upgraded,
          previous: target,
          changeSource: SkillRevisionSource.upgrade,
          changeNote: 'v${currentVersion ?? 0} -> v${detail.version}',
        );
        _replaceInState(current, upgraded);
        return UpgradeSuccess(currentVersion ?? 0, detail.version);
      case AgentSkillSourceKind.marketplace:
      case AgentSkillSourceKind.novelLocal:
        return const UpgradeNotTraceable();
    }
  }

  /// 检测可升级(供 UI 显示「有新版本」标记)。不写入,仅返回结果。
  Future<UpgradeAvailability> checkUpgradeAvailable({
    required String novelAgentSkillId,
  }) async {
    final current = state.value ?? await future;
    final target = _findById(current, novelAgentSkillId);
    if (target == null) {
      throw StateError('NovelAgentSkill not found: $novelAgentSkillId');
    }
    final currentVersion = int.tryParse(target.sourceVersion ?? '');
    switch (target.sourceKind) {
      case AgentSkillSourceKind.official:
        final officialList = await ref.readFuture(
          officialAgentSkillsProvider(agentSkillCatalogFilter()).future,
        );
        final match = _findOfficialByName(
          officialList.agentSkills,
          officialSkillCatalogName(target),
        );
        if (match == null) {
          return const UpgradeAvailabilityNotTraceable();
        }
        if (currentVersion != null && match.version <= currentVersion) {
          return UpgradeAvailabilityUpToDate(currentVersion);
        }
        return UpgradeAvailabilityAvailable(currentVersion ?? 0, match.version);
      case AgentSkillSourceKind.marketplace:
      case AgentSkillSourceKind.novelLocal:
        return const UpgradeAvailabilityNotTraceable();
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────

  NovelAgentSkillModel _asNovelLocal(
    NovelAgentSkillModel target,
    DateTime now,
  ) {
    return NovelAgentSkillModel(
      id: target.id,
      sourceKind: AgentSkillSourceKind.novelLocal,
      sourceListingPublicId: null,
      sourceVersion: null,
      sourceDisplayName: null,
      name: target.name,
      whenToUse: target.whenToUse,
      description: target.description,
      prompt: target.prompt,
      agentScopes: target.agentScopes,
      category: target.category,
      tags: target.tags,
      references: target.references,
      enabled: target.enabled,
      sortOrder: target.sortOrder,
      executionBlockedReason: null,
      createdAt: target.createdAt,
      updatedAt: now,
    );
  }

  Future<void> _writeUpdate(
    NovelAgentSkillModel model, {
    required NovelAgentSkillModel? previous,
    SkillRevisionSource changeSource = SkillRevisionSource.user_edit,
    String? turnId,
    String? changeNote,
  }) async {
    final db = ref.read(agentSkillAppDatabaseProvider);
    final revisionDao = db.novelAgentSkillRevisionDao;
    try {
      await db.transaction(() async {
        // 懒回填：v29 之前安装的技能没有基线版本，首次编辑时先把「改之前」
        // 补记一条，否则历史里只剩改之后、看不到对比。
        if (previous != null && !await revisionDao.hasAnyRevision(model.id)) {
          await revisionDao.appendRevision(
            content: previous,
            changeSource: SkillRevisionSource.baseline,
          );
        }
        await db.novelAgentSkillDao.upsertWithReferences(
          skill: _novelAgentSkillToCompanion(model),
          references: model.references,
        );
        final latestHash = await revisionDao.latestContentHash(model.id);
        if (latestHash != model.contentHash) {
          await revisionDao.appendRevision(
            content: model,
            changeSource: changeSource,
            turnId: turnId,
            changeNote: changeNote,
          );
        }
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] UPSERT novel_agent_skills failed id=${model.id}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    await _pruneRevisions(model.id);
  }

  /// 裁剪超限历史并回收孤儿附件。
  ///
  /// 放在写入事务之外：裁剪失败不该让用户的这次编辑回滚，而 GC 是幂等扫描，
  /// 下一次写入会自动补上。
  Future<void> _pruneRevisions(String skillId) async {
    final db = ref.read(agentSkillAppDatabaseProvider);
    try {
      final pruned = await db.novelAgentSkillRevisionDao.pruneRevisions(
        skillId,
      );
      if (pruned > 0) {
        await db.novelAgentSkillRevisionDao.gcBlobs();
      }
    } catch (error, stackTrace) {
      _log.error(
        '[DB] prune novel_agent_skill_revisions failed id=$skillId',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _replaceInState(
    List<NovelAgentSkillModel> current,
    NovelAgentSkillModel updated,
  ) {
    if (!ref.mounted) {
      return;
    }
    state = AsyncValue.data([
      for (final item in current)
        if (item.id == updated.id) updated else item,
    ]);
  }

  NovelAgentSkillModel? _findById(List<NovelAgentSkillModel> items, String id) {
    for (final item in items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  NovelAgentSkillModel? _findByName(
    List<NovelAgentSkillModel> items,
    String name,
  ) {
    final trimmed = name.trim();
    for (final item in items) {
      if (item.name == trimmed) {
        return item;
      }
    }
    return null;
  }

  OfficialAgentSkillSummary? _findOfficialByName(
    List<OfficialAgentSkillSummary> list,
    String name,
  ) {
    for (final dto in list) {
      if (dto.name == name) {
        return dto;
      }
    }
    return null;
  }
}

final installedAgentSkillsProvider =
    AsyncNotifierProvider<
      InstalledAgentSkillsNotifier,
      List<NovelAgentSkillModel>
    >(InstalledAgentSkillsNotifier.new);

// ── InstallSkillInput 扩展 ───────────────────────────────────────────────────

extension InstallSkillInputCopy on InstallSkillInput {
  InstallSkillInput copyWith({
    AgentSkillSourceKind? sourceKind,
    String? sourceListingPublicId,
    String? sourceVersion,
    String? sourceDisplayName,
    String? name,
    String? description,
    String? prompt,
    String? whenToUse,
    List<String>? agentScopes,
    String? category,
    List<String>? tags,
    List<AgentSkillReferenceFile>? references,
    bool? enabled,
  }) {
    return InstallSkillInput(
      sourceKind: sourceKind ?? this.sourceKind,
      sourceListingPublicId:
          sourceListingPublicId ?? this.sourceListingPublicId,
      sourceVersion: sourceVersion ?? this.sourceVersion,
      sourceDisplayName: sourceDisplayName ?? this.sourceDisplayName,
      name: name ?? this.name,
      description: description ?? this.description,
      prompt: prompt ?? this.prompt,
      whenToUse: whenToUse ?? this.whenToUse,
      agentScopes: agentScopes ?? this.agentScopes,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      references: references ?? this.references,
      enabled: enabled ?? this.enabled,
    );
  }
}

// ── 安装/升级结果类型 ───────────────────────────────────────────

/// [InstalledAgentSkillsNotifier.overwriteInstall] 的本地官方目录来源。
sealed class InstallFromCatalogSource {
  const InstallFromCatalogSource();
}

class InstallFromOfficialSource extends InstallFromCatalogSource {
  const InstallFromOfficialSource(this.dto);
  final OfficialAgentSkill dto;
}

/// [InstalledAgentSkillsNotifier.installFromOfficial] 的结果。
sealed class InstallFromCatalogResult {
  const InstallFromCatalogResult();
}

class InstallFromCatalogSuccess extends InstallFromCatalogResult {
  const InstallFromCatalogSuccess(this.novelAgentSkillId);
  final String novelAgentSkillId;
}

class InstallFromCatalogConflict extends InstallFromCatalogResult {
  const InstallFromCatalogConflict(this.existingId, this.conflictingName);
  final String existingId;
  final String conflictingName;
}

/// [InstalledAgentSkillsNotifier.upgradeNovelAgentSkill] 的结果。
sealed class UpgradeResult {
  const UpgradeResult();
}

class UpgradeSuccess extends UpgradeResult {
  const UpgradeSuccess(this.oldVersion, this.newVersion);
  final int oldVersion;
  final int newVersion;
}

class AlreadyLatestVersion extends UpgradeResult {
  const AlreadyLatestVersion(this.currentVersion);
  final int currentVersion;
}

class UpgradeNotTraceable extends UpgradeResult {
  const UpgradeNotTraceable();
}

/// [InstalledAgentSkillsNotifier.checkUpgradeAvailable] 的结果。
sealed class UpgradeAvailability {
  const UpgradeAvailability();
}

class UpgradeAvailabilityAvailable extends UpgradeAvailability {
  const UpgradeAvailabilityAvailable(this.currentVersion, this.latestVersion);
  final int currentVersion;
  final int latestVersion;
}

class UpgradeAvailabilityUpToDate extends UpgradeAvailability {
  const UpgradeAvailabilityUpToDate(this.currentVersion);
  final int currentVersion;
}

class UpgradeAvailabilityNotTraceable extends UpgradeAvailability {
  const UpgradeAvailabilityNotTraceable();
}

List<AgentSkillReferenceFile> _sanitizeCatalogReferences(
  List<AgentSkillReferenceFile> refs,
) {
  return AgentSkillReferences.sanitize(refs);
}

// ── 历史版本读取 ─────────────────────────────────────────────────────────────

/// 某个技能的历史版本列表（只含摘要，不含 prompt 与附件正文）。
///
/// 用 autoDispose family：只有历史面板打开时才需要，关闭即释放，
/// 避免每个访问过的 skillId 常驻内存。
final skillRevisionsProvider = FutureProvider.autoDispose
    .family<List<AgentSkillRevisionSummary>, String>((ref, skillId) async {
      // 依赖已安装列表：任何一次写入都会刷新 state，历史列表随之重查。
      await ref.watch(installedAgentSkillsProvider.future);
      final db = ref.watch(agentSkillAppDatabaseProvider);
      return db.novelAgentSkillRevisionDao.listRevisions(skillId);
    });

/// 单个历史版本的全量快照，供 diff 与复制使用。
final skillRevisionDetailProvider = FutureProvider.autoDispose
    .family<AgentSkillRevisionDetail?, String>((ref, revisionId) async {
      final db = ref.watch(agentSkillAppDatabaseProvider);
      return db.novelAgentSkillRevisionDao.getRevision(revisionId);
    });
