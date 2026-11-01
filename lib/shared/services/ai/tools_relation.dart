// 职责: 将关系生命周期、当前字段修正和历史资源映射到 AI 工具结果。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/models/entity_relation_history.dart
part of 'tools.dart';

Map<String, dynamic> _relationFailure(
  ParsedPath parsed,
  Object error,
  String operation,
) {
  final (code, message) = switch (error) {
    RelationServiceException e => (e.code, e.message),
    ScreenplayServiceException e => (e.errorCode, e.message),
    FormatException() => (
      'invalid_relation_history',
      'The relation history is invalid; no changes were saved.',
    ),
    _ => (
      'relation_operation_failed',
      'The relation operation failed; retry after refreshing.',
    ),
  };
  return AiToolManager._structuredWriteError(
    path: parsed.displayPath,
    errorCode: _serviceErrorCode(code),
    message: message,
    operation: operation,
    enumField: code == 'invalid_relation_type'
        ? 'relation_type'
        : code == 'invalid_relation_status'
        ? 'status'
        : null,
  );
}

RelationSummary _relationSummary(EntityRelation row) => RelationSummary(
  id: row.id,
  sourceType: row.sourceType,
  sourceId: row.sourceId,
  targetType: row.targetType,
  targetId: row.targetId,
  relationType: row.relationType,
  status: row.status,
  proof: row.proof,
  chapterId: row.chapterId,
  sceneId: row.sceneId,
  properties: row.properties,
  sortOrder: row.sortOrder,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
);

Map<String, dynamic> _relationMutationJson(RelationMutationResult result) => {
  ..._relationToJson(_relationSummary(result.relation)),
  'ok': true,
  'changed': result.changed,
  'history_appended': result.historyAppended,
};

Future<RelationMutationResult> _recordToolRelationChange(
  NovelContentService content,
  ParsedPath parsed,
  Map<String, dynamic> fields, {
  bool preview = false,
}) {
  for (final field in ['proof', 'reason']) {
    final value = fields[field];
    if (value is! String || value.trim().isEmpty) {
      throw const RelationServiceException(
        'missing_required_fields',
        'A change requires proof and reason.',
      );
    }
  }
  return content.entityRelationsService.recordChange(
    id: parsed.locator('relation_id')!,
    relationType: fields['relation_type'] as String?,
    status: fields['status'] as String?,
    proof: fields['proof'] as String,
    reason: fields['reason'] as String,
    chapterId: _relationEvidenceId(fields['chapter_id']),
    sceneId: _relationEvidenceId(fields['scene_id']),
    preview: preview,
  );
}

String? _relationEvidenceId(Object? value) =>
    value == null || value == '' ? null : value as String;

Future<Map<String, dynamic>> _writeToolRelation(
  NovelContentService content,
  ParsedPath parsed,
  Map<String, dynamic> fields,
) async {
  try {
    final result = await _recordToolRelationChange(content, parsed, fields);
    return {..._relationMutationJson(result), 'updated': result.changed};
  } catch (error) {
    final failure = _relationFailure(parsed, error, 'write');
    if (error is RelationServiceException &&
        error.code == 'missing_required_fields') {
      failure['missing_fields'] = [
        for (final field in ['proof', 'reason'])
          if (fields[field] is! String ||
              (fields[field] as String).trim().isEmpty)
            field,
      ];
      failure['required_fields'] = ['proof', 'reason'];
    }
    return failure;
  }
}

Future<RelationMutationResult> _editToolRelationValue(
  NovelContentService content,
  ParsedPath parsed,
  String oldText,
  String newText,
  bool all, {
  bool preview = false,
}) {
  if (parsed.field == 'relation_type') {
    final resolved = _resolveGraphSearchRelationType(newText);
    if (_isEnumResolverError(resolved)) {
      throw const RelationServiceException(
        'invalid_relation_type',
        'The replacement relation type is invalid.',
      );
    }
    newText = _finalizeEnumValue(newText, resolved);
  }
  return content.entityRelationsService.editCurrentField(
    id: parsed.locator('relation_id')!,
    field: parsed.field!,
    oldText: oldText,
    newText: newText,
    replaceAll: all,
    preview: preview,
  );
}

Future<Map<String, dynamic>> _editToolRelation(
  NovelContentService content,
  ParsedPath parsed,
  String oldText,
  String newText,
  bool all,
) async {
  try {
    final result = await _editToolRelationValue(
      content,
      parsed,
      oldText,
      newText,
      all,
    );
    return {
      ..._relationMutationJson(result),
      'edited': result.changed,
      'match_count': parsed.field == 'proof' && oldText.isNotEmpty
          ? oldText
                .allMatches(result.previous?.proof ?? result.relation.proof)
                .length
          : 1,
    };
  } catch (error) {
    return _relationFailure(parsed, error, 'edit');
  }
}

Future<Map<String, dynamic>> _readToolRelationHistory(
  NovelContentService content,
  ParsedPath parsed,
) async {
  final relationId = parsed.locator('relation_id')!;
  try {
    final row = await content.entityRelationsService.getRelationById(
      relationId,
    );
    if (row == null) {
      throw const RelationServiceException(
        'not_found',
        'Relation was not found.',
      );
    }
    Map<String, dynamic> snapshotJson(RelationStateSnapshot snapshot) => {
      ...snapshot.toJson(),
      'path': _resourceReferencePath(
        'relations/$relationId/change_logs/${snapshot.id}',
      ),
      'parent_path': _resourceReferencePath('relations/$relationId'),
    };
    final changeId = parsed.locator('change_id');
    if (changeId != null) {
      final snapshot = row.changeLogs
          .where((s) => s.id == changeId)
          .firstOrNull;
      if (snapshot == null) {
        throw const RelationServiceException(
          'not_found',
          'Relation change was not found.',
        );
      }
      return snapshotJson(snapshot);
    }
    return {
      'type': 'listing',
      'path': parsed.displayPath,
      'parent_path': _resourceReferencePath('relations/$relationId'),
      'entries': row.changeLogs.reversed.map(snapshotJson).toList(),
    };
  } catch (error) {
    return _relationFailure(parsed, error, 'read');
  }
}

Future<Map<String, dynamic>> _removeToolRelationChange(
  NovelContentService content,
  ParsedPath parsed,
  bool force,
) async {
  try {
    final result = await content.entityRelationsService.removeChange(
      id: parsed.locator('relation_id')!,
      snapshotId: parsed.locator('change_id')!,
      force: force,
    );
    return {
      'ok': true,
      'id': parsed.locator('change_id'),
      'path': parsed.displayPath,
      'removed': true,
      'changed': result.changed,
      'current_changed': result.currentChanged,
      'relation': _relationToJson(_relationSummary(result.relation)),
      if (!result.changed) 'missing': true,
    };
  } on RelationServiceException catch (error) {
    if (force && error.code == 'not_found') {
      return {
        'ok': true,
        'path': parsed.displayPath,
        'removed': true,
        'missing': true,
      };
    }
    return _relationFailure(parsed, error, 'delete');
  } catch (error) {
    return _relationFailure(parsed, error, 'delete');
  }
}
