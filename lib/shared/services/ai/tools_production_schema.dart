// 职责: 声明按集制片画布和片段生成记录的静态资源契约。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_production.dart
part of 'tools.dart';

const _productionJson = _ValueSchema(
  _ValueType.object,
  additionalProperties: true,
);
const _productionRead = _ResourceOperation(
  _ResourceTool.read,
  _ResourceTargetKind.resource,
);
const _productionList = _ResourceOperation(
  _ResourceTool.read,
  _ResourceTargetKind.listing,
);
const _productionWrite = _ResourceOperation(
  _ResourceTool.write,
  _ResourceTargetKind.resource,
  input: _ResourceInput(_ResourceInputKind.resource_fields),
);
const _productionCreate = _ResourceOperation(
  _ResourceTool.create,
  _ResourceTargetKind.listing,
  input: _ResourceInput(_ResourceInputKind.create_fields),
);
const _productionRemove = _ResourceOperation(
  _ResourceTool.remove,
  _ResourceTargetKind.resource,
);
const _productionId = _ResourceField(
  value: _ValueSchema(_ValueType.string),
  read: _FieldRead(listing: true, path: true),
);
const _productionNodes = _ResourceDefinition(
  segment: 'nodes',
  address: _ResourceAddress(_AddressKind.id, itemToken: 'node_id'),
  description: '制片节点',
  group: contentKindScreenplay,
  hidden: true,
  listing: _ResourceListing(),
  fields: {
    'id': _productionId,
    'type': _ResourceField(
      value: _ValueSchema(
        _ValueType.string,
        enumValues: ['video', 'image', 'audio', 'staging', 'media'],
      ),
      read: _FieldRead(listing: true, path: true),
      create: _FieldInputUse(
        required: true,
        value: _ValueSchema(
          _ValueType.string,
          enumValues: ['video', 'image', 'audio', 'staging', 'media'],
        ),
      ),
    ),
    'asset_id': _ResourceField(
      value: _ValueSchema(_ValueType.string),
      create: _FieldInputUse(),
    ),
    'path': _ResourceField(
      value: _ValueSchema(_ValueType.string),
      create: _FieldInputUse(),
    ),
    'ref_type': _ResourceField(
      value: _ValueSchema(_ValueType.string),
      read: _FieldRead(listing: true, path: true),
      create: _FieldInputUse(),
    ),
    'ref_id': _ResourceField(
      value: _ValueSchema(_ValueType.string),
      read: _FieldRead(listing: true, path: true),
      create: _FieldInputUse(),
    ),
    'panorama': _ResourceField(
      value: _ValueSchema(
        _ValueType.object,
        nullable: true,
        additionalProperties: true,
      ),
      read: _FieldRead(listing: true, path: true),
    ),
    'image_method': _ResourceField(
      value: _ValueSchema(_ValueType.string, nullable: true),
      read: _FieldRead(listing: true, path: true),
    ),
    'group': _ResourceField(
      value: _productionJson,
      read: _FieldRead(listing: true, path: true),
    ),
    'title': _ResourceField(
      value: _ValueSchema(_ValueType.string),
      read: _FieldRead(listing: true, path: true),
      create: _FieldInputUse(),
      write: _FieldInputUse(field: true),
    ),
    'x': _ResourceField(
      value: _ValueSchema(_ValueType.number),
      read: _FieldRead(listing: true, path: true),
      create: _FieldInputUse(),
      write: _FieldInputUse(field: true),
    ),
    'y': _ResourceField(
      value: _ValueSchema(_ValueType.number),
      read: _FieldRead(listing: true, path: true),
      create: _FieldInputUse(),
      write: _FieldInputUse(field: true),
    ),
    'width': _ResourceField(
      value: _ValueSchema(_ValueType.number, nullable: true),
      read: _FieldRead(listing: true, path: true),
    ),
    'height': _ResourceField(
      value: _ValueSchema(_ValueType.number, nullable: true),
      read: _FieldRead(listing: true, path: true),
    ),
  },
  operations: [
    _productionRead,
    _productionList,
    _productionCreate,
    _productionWrite,
    _productionRemove,
  ],
);
const _productionEdges = _ResourceDefinition(
  segment: 'edges',
  address: _ResourceAddress(_AddressKind.id, itemToken: 'edge_id'),
  description: '制片连线',
  group: contentKindScreenplay,
  hidden: true,
  listing: _ResourceListing(),
  fields: {
    'id': _productionId,
    'data': _ResourceField(
      value: _productionJson,
      read: _FieldRead(path: true),
    ),
  },
  operations: [_productionRead, _productionList],
);
const _productionCanvas = _ResourceDefinition(
  segment: 'canvas',
  optionalChild: true,
  address: _ResourceAddress(_AddressKind.singleton),
  description: '制片画布',
  group: contentKindScreenplay,
  hidden: true,
  fields: {
    'id': _productionId,
    'positions': _ResourceField(
      value: _ValueSchema(_ValueType.array, items: _productionJson),
      write: _FieldInputUse(),
    ),
    'remove_types': _ResourceField(
      value: _ValueSchema(
        _ValueType.array,
        items: _ValueSchema(
          _ValueType.string,
          enumValues: ['video', 'image', 'audio', 'staging', 'media'],
        ),
      ),
      write: _FieldInputUse(),
    ),
  },
  children: [_productionNodes, _productionEdges],
  operations: [_productionRead, _productionWrite],
);
const _episodeProductionDefinition = _ResourceDefinition(
  segment: 'production',
  address: _ResourceAddress(_AddressKind.singleton),
  description: '制片',
  group: contentKindScreenplay,
  hidden: true,
  discoverable: false,
  fields: {'id': _productionId},
  children: [_productionCanvas],
  operations: [_productionRead],
);

const _clipGenerations = _ResourceDefinition(
  segment: 'generations',
  address: _ResourceAddress(_AddressKind.id, itemToken: 'task_id'),
  description: '生成记录',
  group: contentKindScreenplay,
  discoverable: false,
  listing: _ResourceListing(),
  fields: {
    'id': _productionId,
    'kind': _productionId,
    'status': _productionId,
    'cancel_requested_at': _ResourceField(
      value: _ValueSchema(_ValueType.string, nullable: true),
      read: _FieldRead(listing: true, path: true),
    ),
    'result_asset_id': _ResourceField(
      value: _ValueSchema(_ValueType.string, nullable: true),
      read: _FieldRead(listing: true, path: true),
    ),
    'result_file_path': _ResourceField(
      value: _ValueSchema(_ValueType.string, nullable: true),
      read: _FieldRead(listing: true, path: true),
    ),
    'result_applied': _ResourceField(
      value: _ValueSchema(_ValueType.boolean),
      read: _FieldRead(listing: true, path: true),
    ),
    'model_id': _productionId,
  },
  operations: [_productionRead, _productionList],
);
