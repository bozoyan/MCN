// 职责: 校验预设查询契约、道具规格与实际 GLB 顶点及默认摆放一致。
// 关联文件:
//   lib/shared/models/director/prop_catalog.dart
//   lib/shared/models/director/schema.dart
//   lib/shared/services/director/commands.dart
//   lib/shared/services/director/prop_models.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/presets.dart';
import 'package:reveric/shared/models/director/schema.dart';
import 'package:reveric/shared/services/director/commands.dart';
import 'package:reveric/shared/services/director/prop_models.dart';

void main() {
  test('preset catalogs contain only IDs and details retain source values', () {
    final catalog = directorPresets();
    final expected = {
      'props': propPresets.map((p) => p.geometry).toList(),
      'poses': poseIds,
      'cameras': cameraPresets,
      'moves': moveKinds,
    };
    expect(catalog.keys, unorderedEquals(expected.keys));
    for (final entry in expected.entries) {
      expect(catalog[entry.key], [
        for (final id in entry.value) {'id': id},
      ]);
      expect(directorPresets(options: {'catalog': entry.key}), {
        entry.key: catalog[entry.key],
      });
    }
    final poses =
        directorPresets(options: {'catalog': 'poses', 'ids': poseIds})['poses']
            as List;
    for (final entry in poses) {
      expect(entry['variants'], [
        for (final geometry in actorGeometries)
          {
            'geometry_key': geometry,
            'pose': posePreset(entry['id'], geometry).toJson(),
          },
      ]);
    }
    expect(directorPresets(options: {'catalog': 'moves', 'ids': moveKinds}), {
      'moves': [
        for (final move in movePresets)
          {
            'id': move.id,
            'group': move.group,
            'subject_required': move.subject,
          },
      ],
    });
    expect(
      directorPresets(options: {'catalog': 'cameras', 'ids': cameraPresets}),
      {'cameras': catalog['cameras']},
    );
  });

  test('preset detail selection preserves order and rejects invalid input', () {
    expect(
      (directorPresets(
                options: {
                  'catalog': 'props',
                  'ids': ['prop.table.v1', 'prop.chair.v1'],
                },
              )['props']
              as List)
          .map((p) => p['id']),
      ['prop.table.v1', 'prop.chair.v1'],
    );
    for (final options in <Json>[
      {'catalog': null},
      {'catalog': 'unknown'},
      {
        'catalog': ['props'],
      },
      {
        'ids': ['sit'],
      },
      {'catalog': 'poses', 'ids': null},
      {'catalog': 'poses', 'ids': []},
      {'catalog': 'poses', 'ids': 'sit'},
      {
        'catalog': 'poses',
        'ids': [1],
      },
      {
        'catalog': 'poses',
        'ids': ['sit', 'unknown'],
      },
      {
        'catalog': 'props',
        'ids': ['sit'],
      },
    ]) {
      expect(
        () => directorPresets(options: options),
        throwsA(isA<DocumentError>()),
        reason: '$options',
      );
    }
  });

  test('all packaged props match their measured dimensions and origins', () {
    final paths = Directory(
      'assets/director/models/props',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.glb'));
    expect(paths.map((f) => f.path).toSet(), propModelAssets.values.toSet());
    expect(propModelAssets.length, propPresets.length);
    final queried =
        directorPresets(
              options: {
                'catalog': 'props',
                'ids': propModelAssets.keys.toList(),
              },
            )['props']
            as List;
    expect(queried.map((p) => p['id']).toSet(), propModelAssets.keys.toSet());
    for (final prop in propPresets) {
      expect(queried.singleWhere((p) => p['id'] == prop.geometry), {
        'id': prop.geometry,
        'group': prop.group,
        'dimensions_m': prop.size,
        'bbox_min_m': prop.minimum,
        'bbox_max_m': prop.maximum,
        'origin': prop.origin,
        'direction': prop.direction,
        'default_scale': [1, 1, 1],
        'default_position': prop.defaultPosition,
        'support_heights_m': prop.supportHeights,
      });
      final bytes = File(prop.asset).readAsBytesSync();
      validatePropGlb(bytes);
      final data = ByteData.sublistView(bytes);
      final jsonLength = data.getUint32(12, Endian.little);
      final gltf = jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)));
      final binary = 20 + jsonLength + 8;
      final min = List.filled(3, double.infinity);
      final max = List.filled(3, double.negativeInfinity);
      for (final mesh in gltf['meshes']) {
        for (final primitive in mesh['primitives']) {
          final accessor =
              gltf['accessors'][primitive['attributes']['POSITION']];
          final view = gltf['bufferViews'][accessor['bufferView']];
          expect(accessor['componentType'], 5126);
          final offset =
              binary +
              (view['byteOffset'] as int? ?? 0) +
              (accessor['byteOffset'] as int? ?? 0);
          final stride = view['byteStride'] as int? ?? 12;
          for (var i = 0; i < accessor['count']; i++) {
            for (var axis = 0; axis < 3; axis++) {
              final value = data.getFloat32(
                offset + i * stride + axis * 4,
                Endian.little,
              );
              min[axis] = math.min(min[axis], value);
              max[axis] = math.max(max[axis], value);
            }
          }
        }
      }
      for (var axis = 0; axis < 3; axis++) {
        expect(min[axis], closeTo(prop.minimum[axis], 1e-5), reason: prop.name);
        expect(
          max[axis] - min[axis],
          closeTo(prop.size[axis], 1e-5),
          reason: prop.name,
        );
      }
      final history = CommandHistory(DirectorDocument.blank(prop.name));
      try {
        history.addObject(prop.geometry, prop.name);
        final object = history.document.objects.single;
        expect(object['scale'], [1, 1, 1]);
        expect((object['position'][1] as num) + min[1], closeTo(0, 1e-5));
        expect(
          DirectorDocument.parse(history.document.encode()).objects.single,
          object,
        );
        for (final height in prop.supportHeights) {
          expect(height, inInclusiveRange(min[1] - 1e-5, max[1] + 1e-5));
        }
      } finally {
        history.dispose();
      }
    }
  });
}
