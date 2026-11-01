// 职责: 原子维护实体关系当前状态、变化历史、证据引用与查询。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/models/screenplay.dart
//   lib/shared/models/entity_relation_history.dart
//   lib/shared/utils/entity_relation_types.dart
import 'package:drift/drift.dart';

import '../database/novel_content_database.dart';
import '../database/type_converters.dart';
import '../logger/app_logger.dart';
import '../models/screenplay.dart';
import '../models/entity_relation_history.dart';
import '../utils/entity_relation_types.dart';
import '../utils/short_entity_id.dart';
import '../utils/short_entity_id_allocator.dart';

final _log = AppLogger.forModule('EntityRelations');

class EntityRelationsService {
  EntityRelationsService(
    this._database, {
    ShortEntityIdBuilder idBuilder = buildShortEntityId,
    DateTime Function()? clock,
  }) : _buildEntityId = idBuilder,
       _clock = clock ?? DateTime.now;

  final NovelContentDatabase _database;
  final ShortEntityIdBuilder _buildEntityId;
  final DateTime Function() _clock;

  DateTime _now() => DateTime.fromMillisecondsSinceEpoch(
    _clock().millisecondsSinceEpoch ~/ 1000 * 1000,
    isUtc: true,
  );

  Future<bool> _idExists(String id) async {
    final row =
        await (_database.selectOnly(_database.entityRelations)
              ..addColumns([_database.entityRelations.id])
              ..where(_database.entityRelations.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Selectable<RelationSummary> _summaries({Expression<bool>? where}) {
    final t = _database.entityRelations;
    final query = _database.selectOnly(t)
      ..addColumns([
        t.id,
        t.sourceType,
        t.sourceId,
        t.targetType,
        t.targetId,
        t.relationType,
        t.status,
        t.proof,
        t.chapterId,
        t.sceneId,
        t.properties,
        t.sortOrder,
        t.createdAt,
        t.updatedAt,
      ])
      ..orderBy([OrderingTerm(expression: t.sortOrder)]);
    if (where != null) {
      query.where(where);
    }
    return query.map((row) {
      final properties = row.read(t.properties);
      return RelationSummary(
        id: row.read(t.id)!,
        sourceType: row.read(t.sourceType)!,
        sourceId: row.read(t.sourceId)!,
        targetType: row.read(t.targetType)!,
        targetId: row.read(t.targetId)!,
        relationType: row.read(t.relationType)!,
        status: row.read(t.status)!,
        proof: row.read(t.proof)!,
        chapterId: row.read(t.chapterId),
        sceneId: row.read(t.sceneId),
        properties: properties == null
            ? null
            : const JsonMapConverter().fromSql(properties),
        sortOrder: row.read(t.sortOrder)!,
        createdAt: row.read(t.createdAt)!,
        updatedAt: row.read(t.updatedAt)!,
      );
    });
  }

  Expression<bool> _entityFilter(String type, String id) {
    final t = _database.entityRelations;
    return (t.sourceType.equals(type) & t.sourceId.equals(id)) |
        (t.targetType.equals(type) & t.targetId.equals(id));
  }

  Stream<List<RelationSummary>> watchRelationSummaries({
    String? entityType,
    String? entityId,
    String? relationType,
    String? status,
  }) {
    final t = _database.entityRelations;
    Expression<bool> filter = const Constant(true);
    if (entityType != null &&
        entityType.isNotEmpty &&
        entityId != null &&
        entityId.isNotEmpty) {
      filter = filter & _entityFilter(entityType, entityId);
    }
    if (relationType != null) {
      filter = filter & t.relationType.equals(relationType);
    }
    if (status != null) {
      filter = filter & t.status.equals(status);
    }
    return _summaries(where: filter).watch();
  }

  Stream<List<RelationSummary>> watchRelationsForEntity({
    required String entityType,
    required String entityId,
    String? relationType,
  }) => watchRelationSummaries(
    entityType: entityType,
    entityId: entityId,
    relationType: relationType,
  );
  Stream<List<RelationSummary>> watchAllRelations() => watchRelationSummaries();
  Future<List<RelationSummary>> getAllRelations() => queryRelationSummaries();
  Future<RelationSummary?> getRelationSummaryById(String id) => _summaries(
    where: _database.entityRelations.id.equals(id),
  ).getSingleOrNull();

  Stream<RelationSummary?> watchRelationSummaryById(String id) => _summaries(
    where: _database.entityRelations.id.equals(id),
  ).watchSingleOrNull();

  Future<EntityRelation?> getRelationById(String id) => (_database.select(
    _database.entityRelations,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<EntityRelation?> watchRelationById(String id) => (_database.select(
    _database.entityRelations,
  )..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<List<RelationSummary>> getRelationsForEntity({
    required String entityType,
    required String entityId,
    String? relationType,
    String? status,
  }) {
    var filter = _entityFilter(entityType, entityId);
    final t = _database.entityRelations;
    if (relationType != null) {
      filter = filter & t.relationType.equals(relationType);
    }
    if (status != null) {
      filter = filter & t.status.equals(status);
    }
    return _summaries(where: filter).get();
  }

  Future<List<RelationSummary>> getRelationsBetween({
    required String sourceType,
    required String sourceId,
    required String targetType,
    required String targetId,
  }) => queryRelationSummaries(
    sourceType: sourceType,
    sourceId: sourceId,
    targetType: targetType,
    targetId: targetId,
  );

  Future<List<RelationSummary>> getRelationsForPair({
    required String sourceType,
    required String sourceId,
    required String targetType,
    required String targetId,
  }) {
    final t = _database.entityRelations;
    return _summaries(
      where:
          (t.sourceType.equals(sourceType) &
              t.sourceId.equals(sourceId) &
              t.targetType.equals(targetType) &
              t.targetId.equals(targetId)) |
          (t.sourceType.equals(targetType) &
              t.sourceId.equals(targetId) &
              t.targetType.equals(sourceType) &
              t.targetId.equals(sourceId)),
    ).get();
  }

  Future<List<RelationSummary>> getRelationsForChapterEvidence(
    String chapterId,
  ) => queryRelationSummaries(chapterId: chapterId);
  Future<List<RelationSummary>> getRelationsForSceneEvidence(String sceneId) =>
      queryRelationSummaries(sceneId: sceneId);
  Future<List<RelationSummary>> queryRelationSummaries({
    String? sourceType,
    String? sourceId,
    String? targetType,
    String? targetId,
    String? relationType,
    String? chapterId,
    String? sceneId,
    String? status,
    List<String>? sceneIds,
    List<String>? relationIds,
  }) async {
    _validateEvidenceFields(chapterId: chapterId, sceneId: sceneId);
    final t = _database.entityRelations;
    Expression<bool> filter = const Constant(true);
    for (final entry in <GeneratedColumn<String>, String?>{
      t.sourceType: sourceType,
      t.sourceId: sourceId,
      t.targetType: targetType,
      t.targetId: targetId,
      t.relationType: relationType,
      t.chapterId: chapterId,
      t.sceneId: sceneId,
      t.status: status,
    }.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) {
        filter = filter & entry.key.equals(entry.value!);
      }
    }
    if (sceneId != null && sceneId.isNotEmpty) {
      await _requireScene(sceneId);
    }
    if (sceneIds != null || relationIds != null) {
      filter =
          filter &
          (t.sceneId.isIn(sceneIds ?? const []) |
              t.id.isIn(relationIds ?? const []));
    }
    return _summaries(where: filter).get();
  }

  Future<String> createRelation({
    required String sourceType,
    required String sourceId,
    required String targetType,
    required String targetId,
    required String relationType,
    String? chapterId,
    String? sceneId,
    String proof = '',
    String status = 'active',
    Map<String, dynamic>? properties,
  }) async {
    _validateType(sourceType, targetType, relationType);
    _validateStatus(status);
    await _validateEvidence(chapterId, sceneId);
    final now = _now();
    final nextSortOrder = await _nextSortOrder();

    String? insertingId;
    try {
      return await insertWithShortEntityId(
        type: ShortEntityIdType.relation,
        tableName: 'entity_relations',
        idExists: _idExists,
        buildId: _buildEntityId,
        insert: (id) {
          insertingId = id;
          return _database
              .into(_database.entityRelations)
              .insert(
                EntityRelationsCompanion.insert(
                  id: id,
                  sourceType: sourceType,
                  sourceId: sourceId,
                  targetType: targetType,
                  targetId: targetId,
                  relationType: relationType,
                  status: Value(status),
                  changeLogs: Value([
                    RelationStateSnapshot(
                      id: _buildEntityId(ShortEntityIdType.relationChange),
                      kind: RelationSnapshotKind.baseline,
                      relationType: relationType,
                      status: RelationStatus.values.byName(status),
                      proof: proof,
                      chapterId: chapterId,
                      sceneId: sceneId,
                      reason: '',
                      recordedAt: now,
                    ),
                  ]),
                  chapterId: Value(chapterId),
                  sceneId: Value(sceneId),
                  proof: Value(proof),
                  properties: Value(properties),
                  sortOrder: Value(nextSortOrder),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                ),
              );
        },
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] INSERT entity_relations id=$insertingId error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<RelationMutationResult> recordChange({
    required String id,
    String? relationType,
    String? status,
    required String proof,
    required String reason,
    String? chapterId,
    String? sceneId,
    bool preview = false,
    EntityRelation? expected,
  }) => _mutate(id, () async {
    final row = await _requireRelation(id);
    _assertExpected(row, expected);
    final type = relationType ?? row.relationType;
    final nextStatus = status ?? row.status;
    _validateType(row.sourceType, row.targetType, type);
    _validateStatus(nextStatus);
    if (proof.trim().isEmpty || reason.trim().isEmpty) {
      throw const RelationServiceException(
        'missing_required_fields',
        'A change requires proof and reason.',
      );
    }
    await _validateEvidence(chapterId, sceneId);
    final logs = row.changeLogs;
    if (type == row.relationType &&
        nextStatus == row.status &&
        proof == row.proof &&
        chapterId == row.chapterId &&
        sceneId == row.sceneId &&
        logs.isNotEmpty &&
        logs.last.reason == reason) {
      return RelationMutationResult(row, changed: false);
    }
    final fields = EntityRelationsCompanion(
      relationType: Value(type),
      status: Value(nextStatus),
      proof: Value(proof),
      chapterId: Value(chapterId),
      sceneId: Value(sceneId),
    );
    if (preview) {
      return RelationMutationResult(
        row.copyWithCompanion(fields),
        changed: true,
        previous: row,
      );
    }
    final now = _now();
    final change = RelationStateSnapshot(
      id: _buildEntityId(ShortEntityIdType.relationChange),
      kind: RelationSnapshotKind.change,
      relationType: type,
      status: RelationStatus.values.byName(nextStatus),
      proof: proof,
      chapterId: chapterId,
      sceneId: sceneId,
      reason: reason,
      recordedAt: now,
    );
    final next = [
      if (logs.isEmpty)
        _snapshot(row, RelationSnapshotKind.baseline, row.updatedAt),
      ...logs,
      change,
    ];
    await _writeState(
      id,
      fields.copyWith(changeLogs: Value(next), updatedAt: Value(now)),
    );
    return RelationMutationResult(
      await _requireRelation(id),
      changed: true,
      historyAppended: true,
      changeId: change.id,
      previous: row,
    );
  });

  Future<RelationMutationResult> correctCurrentFields({
    required String id,
    String? relationType,
    String? status,
    String? proof,
    Map<String, dynamic>? properties,
    bool preview = false,
    EntityRelation? expected,
    Value<String?> chapterId = const Value.absent(),
    Value<String?> sceneId = const Value.absent(),
  }) => _mutate(id, () async {
    final row = await _requireRelation(id);
    _assertExpected(row, expected);
    final type = relationType ?? row.relationType;
    final nextStatus = status ?? row.status;
    final nextProof = proof ?? row.proof;
    final chapter = chapterId.present ? chapterId.value : row.chapterId;
    final scene = sceneId.present ? sceneId.value : row.sceneId;
    _validateType(row.sourceType, row.targetType, type);
    _validateStatus(nextStatus);
    if (proof != null && proof.trim().isEmpty) {
      throw const RelationServiceException(
        'missing_required_fields',
        'Proof cannot be blank.',
      );
    }
    await _validateEvidence(chapter, scene);
    if (type == row.relationType &&
        nextStatus == row.status &&
        nextProof == row.proof &&
        chapter == row.chapterId &&
        scene == row.sceneId &&
        properties == null) {
      return RelationMutationResult(row, changed: false);
    }
    final fields = EntityRelationsCompanion(
      relationType: Value(type),
      status: Value(nextStatus),
      proof: Value(nextProof),
      chapterId: Value(chapter),
      sceneId: Value(scene),
    );
    if (preview) {
      return RelationMutationResult(
        row.copyWithCompanion(fields),
        changed: true,
        previous: row,
      );
    }
    final logs = [...row.changeLogs];
    if (logs.isNotEmpty) {
      final last = logs.last;
      // Evidence cleanup may leave a historical reference on the latest snapshot.
      // A correction only replaces evidence fields explicitly submitted by the caller.
      logs[logs.length - 1] = last.withState(
        relationType: type,
        status: nextStatus,
        proof: nextProof,
        chapterId: chapterId.present || scene != null
            ? chapter
            : last.chapterId,
        sceneId: sceneId.present || chapter != null ? scene : last.sceneId,
      );
    }
    await _writeState(
      id,
      fields.copyWith(
        changeLogs: Value(logs),
        updatedAt: Value(_now()),
        properties: properties == null
            ? const Value.absent()
            : Value(properties),
      ),
    );
    return RelationMutationResult(
      await _requireRelation(id),
      changed: true,
      previous: row,
    );
  });

  Future<RelationMutationResult> editCurrentField({
    required String id,
    required String field,
    required String oldText,
    required String newText,
    bool replaceAll = false,
    bool preview = false,
  }) => _mutate(id, () async {
    final row = await _requireRelation(id);
    final source = relationFieldValue(row, field) ?? '';
    String next;
    if (field != 'proof') {
      if (source != oldText) {
        throw const RelationServiceException(
          'old_text_not_found',
          'Read the complete current field value before editing.',
        );
      }
      next = newText;
    } else if (oldText.isEmpty) {
      if (source.isNotEmpty) {
        throw const RelationServiceException(
          'empty_old_text',
          'old_text must not be empty.',
        );
      }
      next = newText;
    } else {
      final matches = oldText.allMatches(source).length;
      if (matches == 0) {
        throw const RelationServiceException(
          'old_text_not_found',
          'old_text was not found; read the field before retrying.',
        );
      }
      if (matches > 1 && !replaceAll) {
        throw const RelationServiceException(
          'ambiguous_old_text',
          'Use more precise old_text or all=true.',
        );
      }
      next = replaceAll
          ? source.replaceAll(oldText, newText)
          : source.replaceFirst(oldText, newText);
    }
    return correctCurrentFields(
      id: id,
      preview: preview,
      relationType: field == 'relation_type' ? next : null,
      status: field == 'status' ? next : null,
      proof: field == 'proof' ? next : null,
      chapterId: field == 'chapter_id'
          ? Value(next.isEmpty ? null : next)
          : const Value.absent(),
      sceneId: field == 'scene_id'
          ? Value(next.isEmpty ? null : next)
          : const Value.absent(),
    );
  });

  static String? relationFieldValue(EntityRelation row, String field) =>
      switch (field) {
        'relation_type' => row.relationType,
        'status' => row.status,
        'proof' => row.proof,
        'chapter_id' => row.chapterId,
        'scene_id' => row.sceneId,
        _ => throw const RelationServiceException(
          'read_only_field',
          'This relation field cannot be edited.',
        ),
      };

  Future<RelationMutationResult> removeChange({
    required String id,
    required String snapshotId,
    EntityRelation? expected,
    bool force = false,
  }) => _mutate(id, () async {
    final row = await _requireRelation(id);
    _assertExpected(row, expected, includeHistory: true);
    final index = row.changeLogs.indexWhere((item) => item.id == snapshotId);
    if (index < 0) {
      if (force) {
        return RelationMutationResult(row, changed: false);
      }
      throw const RelationServiceException(
        'not_found',
        'Relation change was not found.',
      );
    }
    if (row.changeLogs[index].kind == RelationSnapshotKind.baseline) {
      throw const RelationServiceException(
        'initial_snapshot_not_removable',
        'Remove the parent relation to delete its initial record.',
      );
    }
    final remaining = [...row.changeLogs]..removeAt(index);
    final restore = index == row.changeLogs.length - 1 ? remaining.last : null;
    var fields = EntityRelationsCompanion(changeLogs: Value(remaining));
    if (restore != null) {
      final chapter =
          restore.chapterId != null && await _chapterExists(restore.chapterId!)
          ? restore.chapterId
          : null;
      final scene =
          restore.sceneId != null && await _sceneExists(restore.sceneId!)
          ? restore.sceneId
          : null;
      fields = fields.copyWith(
        relationType: Value(restore.relationType),
        status: Value(restore.status.name),
        proof: Value(restore.proof),
        chapterId: Value(chapter),
        sceneId: Value(scene),
      );
    }
    await _writeState(id, fields.copyWith(updatedAt: Value(_now())));
    return RelationMutationResult(
      await _requireRelation(id),
      changed: true,
      currentChanged: restore != null,
    );
  });

  RelationStateSnapshot _snapshot(
    EntityRelation row,
    RelationSnapshotKind kind,
    DateTime time,
  ) => RelationStateSnapshot(
    id: _buildEntityId(ShortEntityIdType.relationChange),
    kind: kind,
    relationType: row.relationType,
    status: RelationStatus.values.byName(row.status),
    proof: row.proof,
    chapterId: row.chapterId,
    sceneId: row.sceneId,
    reason: '',
    recordedAt: time,
  );

  void _assertExpected(
    EntityRelation row,
    EntityRelation? expected, {
    bool includeHistory = false,
  }) {
    if (expected != null &&
        (row.id != expected.id ||
            row.relationType != expected.relationType ||
            row.status != expected.status ||
            row.proof != expected.proof ||
            row.chapterId != expected.chapterId ||
            row.sceneId != expected.sceneId ||
            row.changeLogs.lastOrNull?.id !=
                expected.changeLogs.lastOrNull?.id ||
            !row.updatedAt.isAtSameMomentAs(expected.updatedAt) ||
            (includeHistory &&
                const RelationStateSnapshotListConverter().toSql(
                      row.changeLogs,
                    ) !=
                    const RelationStateSnapshotListConverter().toSql(
                      expected.changeLogs,
                    )))) {
      throw const RelationServiceException(
        'relation_changed',
        'The relation changed; refresh before confirming again.',
      );
    }
  }

  Future<T> _mutate<T>(String id, Future<T> Function() action) async {
    try {
      return await _database.transaction(action);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] UPDATE entity_relations id=$id error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<EntityRelation> _requireRelation(String id) async {
    EntityRelation? row;
    try {
      row = await getRelationById(id);
    } on FormatException {
      throw const RelationServiceException(
        'invalid_relation_history',
        'The relation history is invalid.',
      );
    }
    if (row == null) {
      throw const RelationServiceException(
        'not_found',
        'Relation was not found.',
      );
    }
    return row;
  }

  Future<void> _writeState(String id, EntityRelationsCompanion fields) async {
    await (_database.update(
      _database.entityRelations,
    )..where((t) => t.id.equals(id))).write(fields);
  }

  void _validateType(String source, String target, String type) {
    if (!validRelationTypesFor(source, target).contains(type)) {
      throw RelationServiceException(
        'invalid_relation_type',
        'The relation type is invalid for $source → $target. Allowed values: ${validRelationTypesFor(source, target).join(', ')}.',
      );
    }
  }

  void _validateStatus(String status) {
    if (!RelationStatus.values.any((value) => value.name == status)) {
      throw const RelationServiceException(
        'invalid_relation_status',
        'Relation status must be active or ended.',
      );
    }
  }

  Future<void> _validateEvidence(String? chapter, String? scene) async {
    _validateEvidenceFields(chapterId: chapter, sceneId: scene);
    if (chapter != null && !await _chapterExists(chapter)) {
      throw const RelationServiceException(
        'invalid_chapter_ref',
        'Chapter evidence must reference an active chapter in this work.',
      );
    }
    if (scene != null) {
      await _requireScene(scene);
    }
  }

  // 与证据候选（relationEvidenceChoicesProvider）一致：只有正文章节和番外算证据，卷不算。
  Future<bool> _chapterExists(String id) async =>
      await _database.chapterDao.getById(
        id,
        types: const {nodeTypeChapter, nodeTypeExtra},
      ) !=
      null;

  Future<bool> _sceneExists(String id) async =>
      await (_database.selectOnly(_database.screenplayScenes)
            ..addColumns([_database.screenplayScenes.id])
            ..where(
              _database.screenplayScenes.id.equals(id) &
                  _database.screenplayScenes.deletedAt.equals(
                    notDeletedSentinel,
                  ),
            ))
          .getSingleOrNull() !=
      null;

  Future<void> deleteRelation(String id) async {
    try {
      await (_database.delete(
        _database.entityRelations,
      )..where((table) => table.id.equals(id))).go();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] DELETE entity_relations id=$id error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> deleteRelationsForEntity({
    required String entityType,
    required String entityId,
  }) async {
    try {
      await (_database.delete(_database.entityRelations)..where(
            (table) =>
                (table.sourceType.equals(entityType) &
                    table.sourceId.equals(entityId)) |
                (table.targetType.equals(entityType) &
                    table.targetId.equals(entityId)),
          ))
          .go();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] DELETE entity_relations for entity type=$entityType id=$entityId error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> clearChapterReferences(String chapterId) async {
    try {
      await (_database.update(
        _database.entityRelations,
      )..where((table) => table.chapterId.equals(chapterId))).write(
        EntityRelationsCompanion(
          chapterId: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] UPDATE entity_relations clear chapter_id=$chapterId error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Structural scene edits only maintain the current link; original history evidence is retained.
  Future<void> maintainSceneReference({
    required String id,
    required String? sceneId,
  }) => _mutate(id, () async {
    final row = await getRelationSummaryById(id);
    if (row == null) {
      throw const RelationServiceException(
        'not_found',
        'Relation was not found.',
      );
    }
    await _validateEvidence(row.chapterId, sceneId);
    await (_database.update(
      _database.entityRelations,
    )..where((t) => t.id.equals(id))).write(
      EntityRelationsCompanion(
        sceneId: Value(sceneId),
        updatedAt: Value(_now()),
      ),
    );
  });

  Future<void> clearSceneReferences(String sceneId) async {
    try {
      await (_database.update(
        _database.entityRelations,
      )..where((table) => table.sceneId.equals(sceneId))).write(
        EntityRelationsCompanion(
          sceneId: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=entity_relations operation=UPDATE clear_scene_id=$sceneId',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void _validateEvidenceFields({String? chapterId, String? sceneId}) {
    if (chapterId != null && sceneId != null) {
      throw const ScreenplayServiceException(
        'mutually_exclusive_fields',
        'chapter_id and scene_id cannot both be set.',
      );
    }
  }

  Future<void> _requireScene(String sceneId) async {
    final scene =
        await (_database.select(_database.screenplayScenes)..where(
              (table) =>
                  table.id.equals(sceneId) &
                  table.deletedAt.equals(notDeletedSentinel),
            ))
            .getSingleOrNull();
    if (scene == null) {
      throw const ScreenplayServiceException(
        'invalid_scene_ref',
        'Scene evidence must reference an active scene.',
      );
    }
  }

  Future<void> batchCreateRelations(
    List<EntityRelationsCompanion> relations,
  ) async {
    try {
      await _database.batch((batch) {
        batch.insertAll(_database.entityRelations, relations);
      });
    } catch (error, stackTrace) {
      _log.error(
        '[DB] INSERT entity_relations ids=${relations.map((r) => r.id.value).join(',')} error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> reorderRelations(List<String> ids) async {
    await _mutate(ids.join(','), () async {
      for (var i = 0; i < ids.length; i++) {
        await (_database.update(_database.entityRelations)
              ..where((table) => table.id.equals(ids[i])))
            .write(EntityRelationsCompanion(sortOrder: Value(i)));
      }
    });
  }

  Future<Map<String, List<RelationSummary>>> getCharacterNetwork(
    String characterId,
  ) async {
    final relations = await getRelationsForEntity(
      entityType: entityTypeCharacter,
      entityId: characterId,
      status: 'active',
    );

    return {
      'characters': relations
          .where(
            (r) =>
                r.sourceType == entityTypeCharacter ||
                r.targetType == entityTypeCharacter,
          )
          .toList(),
      'factions': relations
          .where(
            (r) =>
                r.sourceType == entityTypeFaction ||
                r.targetType == entityTypeFaction,
          )
          .toList(),
      'skills': relations
          .where(
            (r) =>
                r.sourceType == entityTypeSkill ||
                r.targetType == entityTypeSkill,
          )
          .toList(),
      'items': relations
          .where(
            (r) =>
                r.sourceType == entityTypeItem ||
                r.targetType == entityTypeItem,
          )
          .toList(),
      'chapters': relations
          .where(
            (r) =>
                r.sourceType == entityTypeChapter ||
                r.targetType == entityTypeChapter,
          )
          .toList(),
    };
  }

  Future<List<RelationSummary>> getFactionMembers(
    String factionId, {
    String? relationType,
  }) => queryRelationSummaries(
    targetType: entityTypeFaction,
    targetId: factionId,
    sourceType: entityTypeCharacter,
    relationType: relationType,
    status: 'active',
  );

  Future<List<RelationSummary>> getSkillLearners(
    String skillId, {
    List<String>? relationTypes,
  }) {
    final t = _database.entityRelations;
    return _summaries(
      where:
          t.targetType.equals(entityTypeSkill) &
          t.targetId.equals(skillId) &
          t.sourceType.equals(entityTypeCharacter) &
          t.status.equals('active') &
          t.relationType.isIn(
            relationTypes ??
                [
                  characterSkillLearned,
                  characterSkillMastering,
                  characterSkillMastered,
                ],
          ),
    ).get();
  }

  Future<List<RelationSummary>> getChapterLocations(
    String chapterId, {
    String? relationType,
  }) => queryRelationSummaries(
    sourceType: entityTypeChapter,
    sourceId: chapterId,
    targetType: entityTypeLocation,
    relationType: relationType,
    status: 'active',
  );

  Future<int> _nextSortOrder() async {
    final row = await _database
        .customSelect(
          'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM entity_relations',
        )
        .getSingle();
    return row.read<int>('max_order') + 1;
  }

  Future<GraphSearchResult> graphSearch({
    required String entityType,
    required String entityId,
    String? relationType,
    int depth = 1,
  }) async {
    final effectiveDepth = depth.clamp(1, 5);
    final visitedEntities = <String>{};
    final visitedRelations = <String>{};
    final result = <GraphSearchLayer>[];
    var currentEntities = [(entityType, entityId)];

    for (var d = 0; d < effectiveDepth; d++) {
      final layerRelations = <RelationSummary>[];
      final nextEntities = <(String, String)>[];

      for (final (type, id) in currentEntities) {
        final key = '$type:$id';
        if (visitedEntities.contains(key)) {
          continue;
        }
        visitedEntities.add(key);

        final relations = await _getDirectRelations(
          entityType: type,
          entityId: id,
          relationType: relationType,
        );

        for (final relation in relations) {
          if (visitedRelations.contains(relation.id)) {
            continue;
          }
          visitedRelations.add(relation.id);
          layerRelations.add(relation);

          final sourceKey = '${relation.sourceType}:${relation.sourceId}';
          final targetKey = '${relation.targetType}:${relation.targetId}';

          if (!visitedEntities.contains(sourceKey)) {
            nextEntities.add((relation.sourceType, relation.sourceId));
          }
          if (!visitedEntities.contains(targetKey)) {
            nextEntities.add((relation.targetType, relation.targetId));
          }
        }
      }

      if (layerRelations.isEmpty) {
        break;
      }

      result.add(GraphSearchLayer(depth: d + 1, relations: layerRelations));
      currentEntities = nextEntities;
    }

    return GraphSearchResult(
      startEntityType: entityType,
      startEntityId: entityId,
      layers: result,
      totalRelations: result.fold(
        0,
        (sum, layer) => sum + layer.relations.length,
      ),
    );
  }

  Future<List<RelationSummary>> _getDirectRelations({
    required String entityType,
    required String entityId,
    String? relationType,
  }) => getRelationsForEntity(
    entityType: entityType,
    entityId: entityId,
    relationType: relationType,
    status: 'active',
  );
}

class GraphSearchLayer {
  const GraphSearchLayer({required this.depth, required this.relations});

  final int depth;
  final List<RelationSummary> relations;
}

class GraphSearchResult {
  const GraphSearchResult({
    required this.startEntityType,
    required this.startEntityId,
    required this.layers,
    required this.totalRelations,
  });

  final String startEntityType;
  final String startEntityId;
  final List<GraphSearchLayer> layers;
  final int totalRelations;
}

class RelationMutationResult {
  const RelationMutationResult(
    this.relation, {
    required this.changed,
    this.historyAppended = false,
    this.changeId,
    this.currentChanged = false,
    this.previous,
  });
  final EntityRelation relation;
  final bool changed;
  final bool historyAppended;
  final String? changeId;
  final bool currentChanged;
  final EntityRelation? previous;
}
