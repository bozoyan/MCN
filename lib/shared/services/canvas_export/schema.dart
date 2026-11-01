// 职责: 定义无需联网的严格 JSON Schema Draft 2020-12 画布 v1 契约。
// 关联文件:
//   lib/shared/models/canvas_export.dart
//   lib/shared/services/canvas_export/format.dart
//   lib/shared/services/canvas_export/resources.dart

import '../../models/canvas_export.dart';
import '../../models/canvas_layout.dart';

Map<String, dynamic> _object(Map<String, dynamic> properties) => {
  'type': 'object',
  'properties': properties,
  'required': properties.keys.toList(),
  'additionalProperties': false,
};
Map<String, dynamic> _ref(String name) => {r'$ref': '#/${r'$defs'}/$name'};
const _text = {'type': 'string'},
    _integer = {'type': 'integer'},
    _nullableText = {
      'type': ['string', 'null'],
    };
Map<String, dynamic> _array(Object items) => {'type': 'array', 'items': items};
const _colorValue = {
  'anyOf': [
    {'enum': canvasExportColorKeys},
    {'type': 'string', 'pattern': canvasExportCustomColorPattern},
  ],
};

Map<String, dynamic> canvasExportSchema() {
  final payloads = <String, Map<String, dynamic>>{
    'chapter': _object({
      'node_kind': _text,
      'parent_id': _nullableText,
      'sibling_order': _integer,
      'content': _text,
      'outline': _text,
      'brief': _text,
      'status': _text,
      'word_count': _integer,
    }),
    'outline': _object({
      'content': _text,
      'status': _text,
      'start_chapter_num': _integer,
      'beats': _array(_ref('beat')),
    }),
    'character': _object({
      for (final key in [
        'role',
        'gender',
        'biography',
        'appearance',
        'description',
        'current_state',
        'identity',
        'age',
        'motivation',
        'arc',
        'personality',
      ])
        key: _text,
      'aliases': _array(_text),
      'tags': _array(_text),
      'behavior_tags': _array(_object({'tag': _text, 'context': _text})),
      'first_appear_chapter_id': _nullableText,
    }),
    'foreshadowing': _object({
      'setup': _text,
      'payoff': _text,
      'status': _text,
      for (final key in [
        'setup_chapter_id',
        'payoff_chapter_id',
        'setup_scene_id',
        'payoff_scene_id',
      ])
        key: _nullableText,
    }),
    'location': _object({
      'description': _text,
      'location_type': _text,
      'tags': _text,
      'status': _text,
      'parent_id': _nullableText,
    }),
    for (final type in ['item', 'faction', 'skill', 'creature'])
      type: _object({'content': _text, 'category': _text, 'status': _text}),
    'document': _object({
      'document_type': _text,
      'content': _text,
      'category': _text,
      'tags': _text,
      'status': _text,
      'parent_id': _nullableText,
      'is_folder': {'type': 'boolean'},
    }),
    'screenplay_scene': _object({
      'season': _ref('container'),
      'episode': _ref('container'),
      'scene_number': _integer,
      'synopsis': _text,
      'stage': _text,
      'elements': _array(_ref('element')),
    }),
  };
  final node =
      _object({
          'id': _text,
          'type': {
            'enum': ['sticky', 'reference'],
          },
          'title': _text,
          'content': _nullableText,
          'ref_type': {
            'enum': [null, ...canvasExportResourceTypes],
          },
          'ref_id': _nullableText,
          'x': {'type': 'number'},
          'y': {'type': 'number'},
          'width': {'type': 'number', 'exclusiveMinimum': 0},
          'height': {'type': 'number', 'exclusiveMinimum': 0},
          'sort_order': _integer,
          'z_index': _integer,
          'color_key': {
            'anyOf': [
              {'type': 'null'},
              _colorValue,
            ],
          },
        })
        ..['oneOf'] = [
          {
            'properties': {
              'type': {'const': 'sticky'},
              'content': _text,
              'ref_type': {'type': 'null'},
              'ref_id': {'type': 'null'},
              'color_key': _colorValue,
            },
          },
          {
            'properties': {
              'type': {'const': 'reference'},
              'content': {'type': 'null'},
              'ref_type': {'enum': canvasExportResourceTypes},
              'ref_id': _text,
            },
          },
        ];
  final schema = _object({
    'format': {'const': 'reveric.canvas'},
    'format_version': {'const': 1},
    'exported_at': {'type': 'string', 'format': 'date-time'},
    'source': _ref('source'),
    'canvas': _ref('canvas'),
    'nodes': _array(_ref('node')),
    'edges': _array(_ref('edge')),
    'resources': _array(_ref('resource')),
    'analysis': _ref('analysis'),
  });
  schema[r'$schema'] = 'https://json-schema.org/draft/2020-12/schema';
  schema[r'$defs'] = {
    'source': _object({
      'work_id': _text,
      'content_kind': {
        'enum': ['novel', 'screenplay'],
      },
      'canvas_id': _text,
    }),
    'canvas': _object({
      'title': _text,
      'description': _text,
      'layout': {
        'enum': [null, ...canvasExportLayoutModes],
      },
    }),
    'node': node,
    'edge':
        _object({
            'id': _text,
            'source_node_id': _text,
            'target_node_id': _text,
            'type': {'enum': canvasExportEdgeTypes},
            'directed': {'type': 'boolean'},
            'label': _text,
          })
          ..['oneOf'] = [
            for (final directed in [true, false])
              {
                'properties': {
                  'type': {
                    'enum': [
                      for (final type in canvasExportEdgeTypes)
                        if (isCanvasEdgeDirected(type) == directed) type,
                    ],
                  },
                  'directed': {'const': directed},
                },
              },
          ],
    'resource': {
      'oneOf': [
        _object({
          'type': {'enum': canvasExportResourceTypes},
          'id': _text,
          'title': _text,
          'status': {
            'enum': ['available', 'missing'],
          },
          'detail_level': {'const': 'identity'},
          'payload': {'type': 'null'},
        }),
        for (final type in payloads.keys)
          _object({
            'type': {'const': type},
            'id': _text,
            'title': _text,
            'status': {'const': 'available'},
            'detail_level': {'const': 'content'},
            'payload': _ref('payload_$type'),
          }),
      ],
    },
    for (final entry in payloads.entries) 'payload_${entry.key}': entry.value,
    'beat': _object({
      'id': _text,
      'title': _text,
      'content': _text,
      'status': _text,
      'chapter_count': _integer,
      'sort_order': _integer,
    }),
    'container': _object({'id': _text, 'number': _integer, 'title': _text}),
    'element':
        _object({
            'id': _text,
            'type': {'enum': canvasExportElementTypes},
            'text': _text,
            'character_id': _nullableText,
            'extension': _text,
            'location_id': _nullableText,
            'interior_exterior': {
              'enum': [null, 'interior', 'exterior', 'interior_exterior'],
            },
            'time_label': _nullableText,
          })
          ..['oneOf'] = [
            {
              'properties': {
                'type': {'const': 'scene_heading'},
                'text': {'const': ''},
                'character_id': {'type': 'null'},
                'extension': {'const': ''},
                'time_label': _text,
              },
            },
            {
              'properties': {
                'type': {'const': 'character'},
                'text': {'const': ''},
                'character_id': _text,
                for (final key in [
                  'location_id',
                  'interior_exterior',
                  'time_label',
                ])
                  key: {'type': 'null'},
              },
            },
            {
              'properties': {
                'type': {
                  'enum': [
                    'action',
                    'parenthetical',
                    'dialogue',
                    'transition',
                    'subtitle',
                    'note',
                  ],
                },
                'extension': {'const': ''},
                for (final key in [
                  'character_id',
                  'location_id',
                  'interior_exterior',
                  'time_label',
                ])
                  key: {'type': 'null'},
              },
            },
          ],
    'analysis': _object({
      'root_node_ids': _array(_text),
      'terminal_node_ids': _array(_text),
      'cycle_groups': _array(_array(_text)),
      'isolated_node_ids': _array(_text),
    }),
  };
  return schema;
}
