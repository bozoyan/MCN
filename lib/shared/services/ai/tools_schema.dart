// 职责: 从静态资源声明生成全局集合索引和按集合、分组查询的完整契约。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_support.dart
//   lib/shared/services/ai/tools_cross_work.dart
part of 'tools.dart';

Map<String, dynamic> _schemaError(ToolErrorCode code, String message) => {
  'ok': false,
  'error_code': code.name,
  'error': message,
  'hint': 'Read /_schema.',
};

Map<String, dynamic> _readSchemaContract(ParsedPath parsed) {
  if (parsed.workId != null || parsed.hasQuery) {
    return _schemaError(
      ToolErrorCode.invalid_argument,
      'Use global contract paths without query parameters.',
    );
  }
  final parts = parsed.originalPath.split('/');
  if (parts.length == 1) {
    return {
      'type': 'listing',
      'path': '/_schema',
      'entries': [
        for (final schema in _resourceDefinitions.values)
          {
            'collection': schema.name,
            'group': schema.group,
            'description': schema.description,
            'path': '/_schema/${schema.name}',
          },
      ],
    };
  }
  if (parts.length == 3 &&
      parts[1] == 'groups' &&
      _collectionGroups.contains(parts[2])) {
    return {
      'path': parsed.displayPath,
      'group': parts[2],
      'contracts': [
        for (final schema in _resourceDefinitions.values)
          if (schema.group == parts[2]) _collectionContract(schema),
      ],
    };
  }
  final schema = parts.length == 2 ? _resourceDefinitions[parts[1]] : null;
  if (schema == null) {
    return _schemaError(
      ToolErrorCode.invalid_argument,
      'Unknown collection, group, or contract path.',
    );
  }
  return _collectionContract(schema);
}

Map<String, dynamic> _collectionContract(_ResourceDefinition schema) => {
  'collection': schema.segment,
  'group': schema.group,
  'description': schema.description,
  'path': '/_schema/${schema.segment}',
  'listing_path': schema.isSingleton ? null : schema.segment,
  'singleton': schema.isSingleton,
  'exclusive_fields': schema.exclusiveFields,
  ..._nodeContract(schema, _resourcePathTemplate(schema)),
};

Map<String, dynamic> _nodeContract(_ResourceDefinition node, String path) => {
  'resource_path': path,
  'address': {
    'kind': node.address.kind.name,
    if (node.address.itemToken != null) 'item_token': node.address.itemToken,
    if (node.address.nameField != null) 'name_field': node.address.nameField,
  },
  'operations': [
    for (final tool in _ResourceTool.values)
      if (node.operations.any((operation) => operation.tool == tool))
        _resourceToolName(tool),
  ],
  'fields': {
    for (final entry in node.fields.entries)
      entry.key: {
        ...entry.value.value.toJson(),
        'read': entry.value.canRead,
        'create': node.createFields.contains(entry.key),
        'write': entry.value.canWrite,
        'edit': entry.value.canEdit,
        'read_path': entry.value.readPath,
        'write_path':
            node.operation(
              _ResourceTool.write,
              _ResourceTargetKind.field,
              entry.key,
            ) !=
            null,
        'detail': entry.value.read?.detail ?? false,
        'listing': entry.value.read?.listing ?? false,
        if (entry.value.read?.constraints.isNotEmpty == true)
          'read_constraints': entry.value.read!.constraints
              .map((rule) => rule.toJson())
              .toList(),
        'required_on_create': entry.value.requiredOnCreate,
        'nullable': entry.value.nullable,
        if (entry.value.description.isNotEmpty)
          'description': entry.value.description,
        if ((node.isSingleton ? entry.value.write : entry.value.create)
                ?.hasDefault ==
            true)
          'create_default':
              (node.isSingleton ? entry.value.write : entry.value.create)!
                  .defaultValue,
        if (entry.value.write?.hasDefault == true)
          'write_default': entry.value.write!.defaultValue,
        if (entry.value.search.isNotEmpty)
          'search': entry.value.search.map((use) => use.name).toList(),
        if (entry.value.write?.constraints.isNotEmpty == true)
          'write_constraints': entry.value.write!.constraints
              .map((rule) => rule.toJson())
              .toList(),
        if ((node.isSingleton ? entry.value.write : entry.value.create)
                ?.value !=
            null)
          'create_value':
              (node.isSingleton ? entry.value.write : entry.value.create)!
                  .value!
                  .toJson(),
        if (entry.value.write?.value != null)
          'write_value': entry.value.write!.value!.toJson(),
      },
  },
  'query': node.queryFields,
  'query_contracts': {
    for (final entry in node.fields.entries)
      if (entry.value.query != null)
        entry.key: {
          'match': entry.value.query!.match.name,
          'normalization': entry.value.query!.normalization.name,
        },
    for (final entry
        in node
                .operation(_ResourceTool.read, _ResourceTargetKind.listing)
                ?.parameters
                .entries ??
            const <MapEntry<String, _OperationParameter>>[])
      if (entry.value.query != null)
        entry.key: {
          'match': entry.value.query!.match.name,
          'normalization': entry.value.query!.normalization.name,
        },
  },
  'create_exclusive': node.createExclusive,
  'write_exclusive': node.writeExclusive,
  if (node.listingWriteField != null)
    'listing_write_field': node.listingWriteField,
  'operation_contracts': [
    for (final operation in node.operations)
      _operationContract(node, operation),
  ],
  'subresources': [
    for (final child in node.children)
      _nodeContract(
        child,
        child.isSingleton
            ? '$path/${child.segment}'
            : '$path/${child.segment}/{${child.itemToken}}',
      ),
  ],
};

String _resourceToolName(_ResourceTool tool) => switch (tool) {
  _ResourceTool.read => 'Read',
  _ResourceTool.create => 'Create',
  _ResourceTool.write => 'Write',
  _ResourceTool.edit => 'Edit',
  _ResourceTool.remove => 'Remove',
};

Map<String, dynamic> _operationContract(
  _ResourceDefinition node,
  _ResourceOperation operation,
) {
  final properties = node.inputProperties(operation);
  final defaults = <String, Object?>{
    for (final entry in operation.parameters.entries)
      if (entry.value.hasDefault) entry.key: entry.value.defaultValue,
    for (final entry in node.fields.entries)
      if (operation.input.kind == _ResourceInputKind.create_fields &&
          entry.value.create?.hasDefault == true)
        entry.key: entry.value.create!.defaultValue,
    for (final entry in node.fields.entries)
      if ((operation.tool == _ResourceTool.write ||
              (node.isSingleton && operation.tool == _ResourceTool.create)) &&
          entry.value.write?.hasDefault == true)
        entry.key: entry.value.write!.defaultValue,
  };
  return {
    'tool': _resourceToolName(operation.tool),
    'target': operation.target.name,
    if (operation.field != null) 'field': operation.field,
    'input': {
      'kind': operation.input.kind.name,
      if (node.inputValue(operation) != null)
        'value': node.inputValue(operation)!.toJson(),
      if (operation.input.field != null) 'field': operation.input.field,
      if (properties.isNotEmpty)
        'properties': {
          for (final entry in properties.entries)
            entry.key: {
              ...entry.value.value.toJson(),
              if (defaults.containsKey(entry.key))
                'default': defaults[entry.key],
              if (entry.value.description.isNotEmpty)
                'description': entry.value.description,
            },
        },
      'required': [
        for (final entry in properties.entries)
          if (entry.value.required) entry.key,
      ],
    },
    'constraints': [
      for (final constraint in operation.constraints) constraint.toJson(),
    ],
    'missing_target': operation.missingTarget.name,
    'result': {
      'kind': operation.result.kind.name,
      if (operation.tool == _ResourceTool.read)
        'output_schema': _resourceReadOutputSchema(node, operation),
      if (operation.result.value != null)
        'value': operation.result.value!.toJson(),
      'references': operation.result.references,
    },
  };
}

/// 参数与路径类错误才引导查契约；指向作品本身的访问错误与资源契约无关。
bool _isContractValidationError(Map<String, dynamic> result) =>
    !toolResultIsSuccess(result) &&
    !_isWorkLevelPath(result['path']) &&
    (result['validation_errors'] is List ||
        {
          ToolErrorCode.invalid_argument.name,
          ToolErrorCode.unsupported.name,
        }.contains(result['error_code']));

bool _isWorkLevelPath(Object? path) =>
    path is String && RegExp(r'^/works(/[^/]+)?$').hasMatch(path);

Map<String, dynamic> _withContractHint(
  Map<String, dynamic> result,
  Map<String, dynamic> input,
) {
  if (!_isContractValidationError(result)) {
    return result;
  }
  final parsed = parseAiToolPath(_parseStringArgument(input['path']));
  if (parsed.collection == '_schema' || parsed.isRoot) {
    return result;
  }
  final schema = _resourceDefinitions[parsed.collection];
  final contract = schema == null ? '/_schema' : '/_schema/${schema.name}';
  final hint = result['hint'] as String? ?? '';
  if (hint.contains('Read $contract')) {
    return result;
  }
  return {...result, 'hint': '${hint.isEmpty ? "" : "$hint "}Read $contract.'};
}
