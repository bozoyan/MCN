// 职责: AI 实体关系图工具，负责 Create /relations 的关系写入及 GraphSearch 逻辑。
// 关联文件:
//   lib/shared/agent/tools.dart
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/database/novel_content_database.dart
part of 'tools.dart';

const _graphSearchDescription = '''搜索实体在关系图中的关联资源。

行为：
- 实体作为 source 和 target 的关系都会返回。
- 只返回当前生效的关系；已结束关系及历史变化请用 Read 查看。
- 返回按深度分层的关系列表，每层包含该深度的所有关系；同一实体不会重复出现。

输出：
- layers：按深度分组的关系列表
- total_relations：总关系数量
- start_entity_type：起始实体类型
- start_entity_id：起始实体 ID''';

/// 从 GraphSearch 参数中取起始实体类型。
///
/// `type` 是 schema 字段；`entity_type` 只兼容模型误用的别名，同 SpawnAgent 的 `agent_name`。
String graphSearchTypeFromInput(Map<String, dynamic> input) {
  for (final key in const ['type', 'entity_type']) {
    final value = _parseStringArgument(input[key]);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

/// 从 GraphSearch 参数中取起始实体 ID。
///
/// `id` 是 schema 字段；`entity_id` 只兼容模型误用的别名。
String graphSearchIdFromInput(Map<String, dynamic> input) {
  for (final key in const ['id', 'entity_id']) {
    final value = _parseStringArgument(input[key]);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

final _graphSearchInputSchema = const {
  'type': 'object',
  'properties': {
    'type': {
      'type': 'string',
      'description':
          '起始实体类型：character、faction、skill、item、location、chapter 或 foreshadowing。',
    },
    'id': {
      'type': 'string',
      'description': '起始实体 ID，来自 Read 或 GraphSearch 结果。',
    },
    'relation_type': {
      'type': 'string',
      'description': '可选过滤。不知道合法值时不要传，禁止猜测；省略则返回所有关系类型。',
    },
    'depth': {
      'type': 'integer',
      'description': '搜索深度，默认 1。1 返回直接关联，2 包含二度关联，以此类推；最大 5。',
      'minimum': 1,
      'maximum': 5,
    },
    'work_id': {
      'type': 'string',
      'description':
          '可选目标作品 ID，原样取自已提供的作品路径 /works/{work_id}，'
          '或 Read /works 的 entries[].id；省略时搜索当前作品。',
    },
  },
  'required': ['type', 'id'],
  'additionalProperties': false,
};

mixin _AiToolManagerGraphMixin on _AiToolManagerBase {
  Future<Map<String, dynamic>> _handleCreateRelation(
    ParsedPath parsed,
    Map<String, dynamic> input,
  ) async {
    final finalSourceType = input['source_type'] as String;
    final sourceId = input['source_id'] as String;
    final finalTargetType = input['target_type'] as String;
    final targetId = input['target_id'] as String;
    final relationType = input['relation_type'] as String;
    final chapterValue = input['chapter_id'] as String?;
    final sceneValue = input['scene_id'] as String?;
    final chapterId = chapterValue == null || chapterValue.isEmpty
        ? null
        : chapterValue;
    final sceneId = sceneValue == null || sceneValue.isEmpty
        ? null
        : sceneValue;
    final proof = input['proof'] as String;

    if (proof.trim().isEmpty) {
      return AiToolManager._structuredWriteError(
        path: parsed.displayPath,
        errorCode: ToolErrorCode.invalid_argument,
        message: 'Create requires non-empty proof.',
        operation: 'create',
        missingFields: const ['proof'],
        requiredFields: const ['proof'],
      );
    }

    // relation_type 的公共枚举是并集；方向与端点类型组合仍由业务表约束。
    final relationTypeError = _validateRelationTypePair(
      finalSourceType,
      finalTargetType,
      relationType,
    );
    if (relationTypeError != null) {
      return AiToolManager._structuredWriteError(
        path: parsed.displayPath,
        errorCode: ToolErrorCode.invalid_argument,
        message: relationTypeError,
        operation: 'create',
        enumField: 'relation_type',
      );
    }

    late final String newId;
    try {
      newId = await _contentService.entityRelationsService.createRelation(
        sourceType: finalSourceType,
        sourceId: sourceId,
        targetType: finalTargetType,
        targetId: targetId,
        relationType: relationType,
        chapterId: chapterId,
        sceneId: sceneId,
        proof: proof,
        status: input['status'] as String? ?? 'active',
      );
    } catch (error) {
      return _relationFailure(parsed, error, 'create');
    }

    // 与其他 create handler 一致：path 是新资源的权威路径，由 _handleCreate 的
    // _attachCreateResourcePath 统一收口。
    return {
      'path': 'relations/$newId',
      'id': newId,
      'source_type': finalSourceType,
      'source_id': sourceId,
      'target_type': finalTargetType,
      'target_id': targetId,
      'relation_type': relationType,
      'chapter_id': chapterId,
      'scene_id': sceneId,
      'proof': proof,
      'created': true,
      'status': input['status'] ?? 'active',
      'history_path': _resourceReferencePath('relations/$newId/change_logs'),
      'has_evidence_location': chapterId != null || sceneId != null,
    };
  }

  Future<Map<String, dynamic>> _handleGraphSearch(
    Map<String, dynamic> input,
  ) async {
    final entityType = graphSearchTypeFromInput(input);
    final entityId = graphSearchIdFromInput(input);
    final rawRelationType = _parseStringArgument(input['relation_type']);
    final depthInput = _parseIntArgument(input['depth']);
    final depth = (depthInput == null || depthInput < 1 || depthInput > 5)
        ? 1
        : depthInput;

    if (entityType.isEmpty || entityId.isEmpty) {
      return AiToolManager._structuredWriteError(
        path: '/graph-search',
        errorCode: ToolErrorCode.invalid_argument,
        message: 'GraphSearch requires type and id',
        operation: 'read',
        missingFields: [
          if (entityType.isEmpty) 'type',
          if (entityId.isEmpty) 'id',
        ],
        requiredFields: ['type', 'id'],
      );
    }

    final correctedEntityType = _resolveEntityType(entityType);
    if (_isEnumResolverError(correctedEntityType)) {
      return AiToolManager._structuredWriteError(
        path: '/graph-search',
        errorCode: ToolErrorCode.invalid_argument,
        message: 'Invalid entity type: $correctedEntityType',
        operation: 'read',
        enumField: 'entity_type',
      );
    }
    final finalEntityType = _finalizeEnumValue(entityType, correctedEntityType);

    String? relationType;
    if (rawRelationType.isNotEmpty) {
      final correctedRelationType = _resolveGraphSearchRelationType(
        rawRelationType,
      );
      if (_isEnumResolverError(correctedRelationType)) {
        return AiToolManager._structuredWriteError(
          path: '/graph-search',
          errorCode: ToolErrorCode.invalid_argument,
          message: correctedRelationType!,
          operation: 'read',
          enumField: 'relation_type',
          hint:
              '不知道合法值时省略 relation_type，禁止猜测。'
              '合法值：${AiToolManager._allValidRelationTypes.join(' | ')}。',
        );
      }
      relationType = _finalizeEnumValue(rawRelationType, correctedRelationType);
    }

    final result = await _contentService.entityRelationsService.graphSearch(
      entityType: finalEntityType,
      entityId: entityId,
      relationType: relationType,
      depth: depth,
    );

    return {
      'start_entity_type': result.startEntityType,
      'start_entity_id': result.startEntityId,
      'depth': depth,
      'total_relations': result.totalRelations,
      'layers': result.layers
          .map(
            (layer) => {
              'depth': layer.depth,
              'relations': layer.relations.map(_relationToJson).toList(),
            },
          )
          .toList(),
    };
  }
}

Map<String, dynamic> _relationToJson(RelationSummary relation) {
  return {
    'id': relation.id,
    'path': _resourceReferencePath('relations/${relation.id}'),
    if (_currentResourceCallContext?.scope.absolutePaths == true)
      'work_id': _currentResourceCallContext!.scope.targetWorkId,
    'source_type': relation.sourceType,
    'source_id': relation.sourceId,
    'target_type': relation.targetType,
    'target_id': relation.targetId,
    'relation_type': relation.relationType,
    'status': relation.status,
    'history_path': _resourceReferencePath(
      'relations/${relation.id}/change_logs',
    ),
    'has_evidence_location':
        relation.chapterId != null || relation.sceneId != null,
    'chapter_id': relation.chapterId,
    'scene_id': relation.sceneId,
    'proof': relation.proof,
  };
}
