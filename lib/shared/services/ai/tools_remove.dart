// 职责: AI 删除工具 — 支持按路径删除资源（章节、角色、大纲、文档等）
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/working_overlay.dart
//   lib/shared/services/entity_relations_service.dart
part of 'tools.dart';

const _removeDescription = '''删除指定资源。

- 删除文件夹前先 AskUser，说明路径及会一并删掉的子项；用户同意后再 Remove 并传 recursive=true。不要在同一轮既问确认又执行删除。
- 删画布节点会一并删掉以它为端点的边。

示例：先 AskUser 确认，再 {"path": "lore/魔法系统", "recursive": true}
''';

final _removeInputSchema = const {
  'type': 'object',
  'properties': {
    'path': {'type': 'string', 'description': '要删除的资源路径。'},
    'recursive': {
      'type': 'boolean',
      'description':
          '是否递归删除文件夹及其子项，对应 rm -r。删除 lore/materials 文件夹时必须为 true。'
          '调用前须先 AskUser 获得用户确认。默认 false。',
    },
    'force': {
      'type': 'boolean',
      'description':
          '目标不存在时视为成功（返回 removed=true, missing=true），'
          '对应 rm -f。不能用来跳过 recursive。默认 false。',
    },
  },
  'required': ['path'],
  'additionalProperties': false,
};

mixin _AiToolManagerRemoveMixin
    on
        _AiToolManagerBase,
        _AiToolManagerCanvasMixin,
        _AiToolManagerOutlineMixin,
        _AiToolManagerPathHintsMixin {
  Future<Map<String, dynamic>> _handleRemove(Map<String, dynamic> input) async {
    final rawPath = _parseStringArgument(input['path'], trim: true);
    final recursive = _parseBoolArgument(input['recursive']);
    final force = _parseBoolArgument(input['force']);
    if (rawPath.isEmpty) {
      return AiToolManager._structuredWriteError(
        path: rawPath,
        errorCode: ToolErrorCode.invalid_argument,
        message: 'Remove requires path',
        operation: 'delete',
        missingFields: const ['path'],
        requiredFields: const ['path'],
      );
    }

    final parsed = ParsedPath.parse(
      rawPath,
      schemaLookup: _getCollectionSchema,
    );

    if (parsed.isRoot) {
      return AiToolManager._structuredWriteError(
        path: rawPath,
        errorCode: ToolErrorCode.invalid_argument,
        message: 'Cannot remove root collection',
        operation: 'delete',
      );
    }

    final contentKindError = _contentKindGate(parsed);
    if (contentKindError != null) {
      return contentKindError;
    }
    final operationError = _resourceOperationGate(parsed, _ResourceTool.remove);
    if (operationError != null) {
      return operationError;
    }

    if (isScreenplayPath(parsed)) {
      return _executeScreenplay(
        parsed,
        parsed._resource!.operation(_ResourceTool.remove)!,
        force: force,
      );
    }

    if (isCanvasPath(parsed)) {
      return _attachMutationResourcePath(
        parsed,
        await _executeCanvas(
          parsed,
          parsed._resource!.operation(_ResourceTool.remove)!,
          force: force,
        ),
      );
    }

    if (parsed.isOutlineBeat) {
      final located = await _locateOutline(parsed);
      if (located.error != null) {
        return _removeNotFound(
          parsed: parsed,
          path: parsed.displayPath,
          message:
              located.error!['error'] as String? ?? 'Outline beat not found',
          force: force,
          hint: located.error!['hint'] as String?,
        );
      }
      return _attachMutationResourcePath(
        parsed,
        await _removeOutlineBeat(located.target!),
      );
    }

    if (parsed.collection == 'relations') {
      if (parsed.resourceSegment == 'change_logs') {
        return _removeToolRelationChange(_contentService, parsed, force);
      }
      final relationId = parsed.id!;

      final relation = await _contentService.entityRelationsService
          .getRelationSummaryById(relationId);
      if (relation == null) {
        return _removeNotFound(
          parsed: parsed,
          path: rawPath,
          message: 'Relation not found: $relationId',
          force: force,
        );
      }

      await _contentService.entityRelationsService.deleteRelation(relationId);

      return _attachMutationResourcePath(parsed, {
        'ok': true,
        'path': 'relations/$relationId',
        'removed': true,
      });
    }

    final schema = parsed._resource!.schema;

    // Resolve resource ID for deletion
    String resourceId;
    String resourcePath;

    if (schema.isItemCollection) {
      final id = parsed.id!;
      final entry = await _contentService.getItemById(id);
      if (entry == null || entry.type != schema.itemType) {
        return _enrichNotFoundError(
          parsed,
          _removeNotFound(
            parsed: parsed,
            path: parsed.displayPath,
            message: '${parsed.collection} not found: $id',
            force: force,
          ),
        );
      }
      resourceId = entry.id;
      resourcePath = parsed.displayPath;

      await _contentService.deleteItem(resourceId);
    } else if (schema.usesNamePath) {
      // Document collections (lore, outlines, materials)
      final documentType = schema.documentType!;

      if (documentType == 'outline') {
        final outline = await _contentService.outlineService.getByTitle(
          parsed.locator('title')!,
        );
        if (outline == null) {
          return _removeNotFound(
            parsed: parsed,
            path: parsed.displayPath,
            message: 'Outline not found: ${parsed.namePath.join('/')}',
            force: force,
          );
        }
        resourceId = outline.documentId;
        resourcePath = parsed.displayPath;

        await _contentService.outlineService.deleteOutline(resourceId);
      } else {
        final document = await _contentService.documentsService
            .getDocumentByNamePath(
              type: documentType,
              namePath: parsed.namePath,
            );
        if (document == null) {
          return _removeNotFound(
            parsed: parsed,
            path: parsed.displayPath,
            message:
                '${parsed.collection} not found: ${parsed.namePath.join('/')}',
            force: force,
          );
        }
        resourceId = document.id;
        resourcePath = parsed.displayPath;

        if (document.isFolder) {
          if (!recursive) {
            return AiToolManager._structuredWriteError(
              path: parsed.displayPath,
              errorCode: ToolErrorCode.failed_precondition,
              message:
                  'Remove refused to delete folder "${document.title}" without recursive=true',
              operation: 'delete',
              hint:
                  'AskUser to confirm with the user first, then retry Remove with recursive=true to delete the folder and all nested documents.',
            );
          }
          await _contentService.documentsService.deleteDocumentRecursive(
            resourceId,
          );
        } else {
          // is_folder 标记可能过期（并发建子节点，或历史数据标记不准），此时
          // deleteDocument 会抛裸 Exception 冒泡成 runtime error。转成与上面
          // 同款的结构化错误，让模型拿到可执行的下一步。
          try {
            await _contentService.documentsService.deleteDocument(resourceId);
          } on Exception {
            final children = await _contentService.documentsService.getChildren(
              resourceId,
            );
            if (children.isEmpty) {
              rethrow;
            }
            return AiToolManager._structuredWriteError(
              path: parsed.displayPath,
              errorCode: ToolErrorCode.failed_precondition,
              message:
                  'Remove refused to delete "${document.title}" because it still has ${children.length} nested document(s)',
              operation: 'delete',
              hint:
                  'AskUser to confirm with the user first, then retry Remove with recursive=true to delete it and all nested documents.',
            );
          }
        }
      }
    } else {
      // Standard collections
      resourceId = parsed.id!;
      resourcePath = '${parsed.collection}/$resourceId';

      switch (parsed.collection) {
        case 'chapters':
        case 'volumes':
          final chapter = await _contentService.getChapterById(
            resourceId,
            types: parsed.collection == 'volumes'
                ? const {nodeTypeVolume}
                : const {nodeTypeChapter, nodeTypeExtra},
          );
          if (chapter == null) {
            return _removeNotFound(
              parsed: parsed,
              path: rawPath,
              message: 'Resource not found: $resourceId',
              force: force,
            );
          }
          await _contentService.deleteChapter(resourceId);
        case 'characters':
          final character = await _contentService.getCharacterProfileById(
            resourceId,
          );
          if (character == null) {
            return _removeNotFound(
              parsed: parsed,
              path: rawPath,
              message: 'Resource not found: $resourceId',
              force: force,
            );
          }
          await _contentService.deleteCharacterProfile(resourceId);
        case 'foreshadowing':
          final foreshadowing = await _contentService.getForeshadowingById(
            resourceId,
          );
          if (foreshadowing == null) {
            return _removeNotFound(
              parsed: parsed,
              path: rawPath,
              message: 'Resource not found: $resourceId',
              force: force,
            );
          }
          await _contentService.deleteForeshadowing(resourceId);
        case 'locations':
          final location = await _contentService.locationsService
              .getLocationById(resourceId);
          if (location == null) {
            return _removeNotFound(
              parsed: parsed,
              path: rawPath,
              message: 'Resource not found: $resourceId',
              force: force,
            );
          }
          await _contentService.locationsService.deleteLocation(resourceId);
        default:
          return AiToolManager._structuredWriteError(
            path: rawPath,
            errorCode: ToolErrorCode.unsupported,
            message: 'Remove does not support collection: ${parsed.collection}',
            operation: 'delete',
          );
      }
    }

    return _attachMutationResourcePath(parsed, {
      'ok': true,
      'path': resourcePath,
      'removed': true,
    });
  }

  Map<String, dynamic> _removeNotFound({
    required ParsedPath parsed,
    required String path,
    required String message,
    required bool force,
    String? hint,
  }) {
    if (force) {
      return _attachMutationResourcePath(parsed, {
        'ok': true,
        'path': path,
        'removed': true,
        'missing': true,
      });
    }
    return AiToolManager._structuredWriteError(
      path: path,
      errorCode: ToolErrorCode.not_found,
      message: message,
      operation: 'delete',
      hint: hint,
    );
  }
}
