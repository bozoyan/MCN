// 职责: 从资源定义生成 Read 按需返回契约。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_schema.dart
//   lib/shared/services/ai/tools_support.dart
part of 'tools.dart';

const _outputString = <String, dynamic>{'type': 'string'};
const _outputInteger = <String, dynamic>{'type': 'integer'};
const _outputBoolean = <String, dynamic>{'type': 'boolean'};
const _outputTrue = <String, dynamic>{'type': 'boolean', 'const': true};
const _outputFalse = <String, dynamic>{'type': 'boolean', 'const': false};

Map<String, dynamic> _outputObject(
  Map<String, dynamic> properties,
  List<String> required,
) => {
  'type': 'object',
  'properties': properties,
  'required': required,
  'additionalProperties': true,
};

const _outputPagination = <String, dynamic>{
  'total': _outputInteger,
  'offset': _outputInteger,
  'limit': _outputInteger,
  'has_more': _outputBoolean,
};
const _outputTextPagination = <String, dynamic>{
  'total_lines': _outputInteger,
  'start_line': _outputInteger,
  'end_line': _outputInteger,
  'limit': _outputInteger,
  'has_more': _outputBoolean,
  'next_offset': _outputInteger,
};

/// 输出只描述读取形状；输入枚举校验、别名、引用与创建默认值不复制进输出。
Map<String, dynamic> _readValueSchema(_ValueSchema value) => {
  'type': value.nullable ? [value.type.name, 'null'] : value.type.name,
  if (value.type == _ValueType.object) ...{
    'properties': {
      for (final entry in value.objectProperties.entries)
        entry.key: _readValueSchema(entry.value.value),
    },
    'required': [
      for (final entry in value.objectProperties.entries)
        if (value.fieldReference != null &&
                (value.projection == _FieldProjection.detail ||
                    value.projection == _FieldProjection.listing)
            ? _requiredReadField(
                value.fieldReference![entry.key]!,
                value.projection == _FieldProjection.listing,
              )
            : entry.value.required)
          entry.key,
    ],
  },
  if (value.items != null) 'items': _readValueSchema(value.items!),
};

// 读取的必有性与创建必填无关；有条件可见的字段不作无条件 required。
bool _requiredReadField(_ResourceField field, bool listing) {
  final read = field.read!;
  return read.constraints.isEmpty &&
      (listing ? read.requiredInListing : read.requiredInDetail);
}

Map<String, dynamic> _resourceReadObject(
  _ResourceDefinition node, {
  required bool listing,
}) {
  final fields = node.project(
    listing ? _FieldProjection.listing : _FieldProjection.detail,
  );
  return _outputObject(
    {
      'path': _outputString,
      'work_id': _outputString,
      for (final entry in fields.entries)
        entry.key: _readValueSchema(entry.value.value),
    },
    [
      'path',
      for (final key in fields.keys)
        if (_requiredReadField(node.fields[key]!, listing)) key,
    ],
  );
}

/// 按需公开资源的精确返回字段，避免将全量资源字段常驻在 Read 工具描述中。
Map<String, dynamic> _resourceReadOutputSchema(
  _ResourceDefinition node,
  _ResourceOperation operation,
) {
  if (operation.target == _ResourceTargetKind.listing) {
    return _outputObject(
      {
        'type': {'const': 'listing'},
        'entries': {
          'type': 'array',
          'items': _resourceReadObject(node, listing: true),
        },
        ..._outputPagination,
      },
      ['type', 'entries'],
    );
  }
  if (operation.target == _ResourceTargetKind.field) {
    final field = operation.field!;
    final value = operation.result.value ?? node.fields[field]?.value;
    return _outputObject(
      {
        'value': value == null ? <String, dynamic>{} : _readValueSchema(value),
        ..._outputPagination,
        ..._outputTextPagination,
      },
      ['value'],
    );
  }
  final detail = _resourceReadObject(node, listing: false);
  if (node.documentType != null && node.segment != 'outlines') {
    final entry = _resourceReadObject(node, listing: true);
    return {
      'anyOf': [
        {
          ...detail,
          'properties': {
            ...detail['properties'] as Map,
            'is_folder': _outputFalse,
          },
        },
        _outputObject(
          {
            ...entry['properties'] as Map,
            'is_folder': _outputTrue,
            'type': {'const': 'folder'},
            'entries': {'type': 'array', 'items': entry},
            ..._outputPagination,
          },
          [...entry['required'] as List<String>, 'type', 'entries'],
        ),
      ],
    };
  }
  return detail;
}
