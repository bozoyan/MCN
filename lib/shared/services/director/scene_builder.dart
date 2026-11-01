// 职责: 将采样值应用到 GLB 演员、道具、照明与机位景深。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/sampling.dart
//   lib/shared/services/director/renderer.dart
//   lib/shared/services/director/actor_models.dart
import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as v;

import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/actor_models.dart';
import 'package:reveric/shared/services/director/camera.dart';
import 'package:reveric/shared/models/director/sampling.dart';

v.Vector3 vec(List a) => v.Vector3(
  (a[0] as num).toDouble(),
  (a[1] as num).toDouble(),
  (a[2] as num).toDouble(),
);
v.Quaternion quat(List a) => v.Quaternion(
  (a[0] as num).toDouble(),
  (a[1] as num).toDouble(),
  (a[2] as num).toDouble(),
  (a[3] as num).toDouble(),
);

class SceneBuilder {
  final Scene scene = Scene();
  final Map<String, Node> roots = {};
  final Map<String, ActorRig> actors = {};
  final Map<Node, String> owners = {};
  final Map<String, MeshGeometry> _geometry = {};
  SceneBuilder(
    DirectorDocument document, {
    bool showGround = true,
    Map<String, Node> props = const {},
  }) {
    scene.environmentIntensity = (document.lighting['ambient_intensity'] as num)
        .toDouble();
    scene.directionalLight = DirectionalLight(
      direction: normalizedDirection(document.lighting['key_direction']),
      intensity: (document.lighting['key_intensity'] as num).toDouble(),
    );
    scene.antiAliasingMode = AntiAliasingMode.msaa;
    if (showGround) {
      final ground = Node();
      _box(ground, 'ground', [20, 0.02, 20], [0, -0.01, 0], '#DDDDDD');
      scene.add(ground);
    }
    for (final o in document.objects) {
      final root = Node(name: o['id']);
      roots[o['id']] = root;
      scene.add(root);
      if (o['kind'] == 'actor') {
        final rig = ActorModels.instantiate(
          o['geometry_key'],
          _material(o['color']),
        );
        actors[o['id']] = rig;
        root.add(rig.model);
      } else {
        final key = o['geometry_key'];
        final model = props[key];
        if (model == null) {
          throw StateError('prop_not_loaded:$key');
        }
        root.add(model.clone());
      }
      void register(Node n) {
        owners[n] = o['id'];
        for (final c in n.children) {
          register(c);
        }
      }

      register(root);
    }
  }
  PhysicallyBasedMaterial _material(String color) {
    final c = int.parse(color.substring(1), radix: 16);
    return PhysicallyBasedMaterial()
      ..baseColorFactor = v.Vector4(
        ((c >> 16) & 255) / 255,
        ((c >> 8) & 255) / 255,
        (c & 255) / 255,
        1,
      )
      ..metallicFactor = 0
      ..roughnessFactor = 0.85;
  }

  Node _box(
    Node parent,
    String key,
    List<double> size,
    List<double> position,
    String color,
  ) {
    final geometry = _geometry.putIfAbsent(
      key,
      () => _rightHandGeometry(CuboidGeometry(vec(size))),
    );
    final node = Node(mesh: Mesh(geometry, _material(color)))
      ..position = vec(position);
    parent.add(node);
    return node;
  }

  DirectorCamera apply(DirectorDocument document, num frame, String cameraId) {
    final sample = sampleDocument(document, frame);
    for (final o in sample.objects) {
      final root = roots[o['id']]!;
      root.position = vec(o['position']);
      root.rotation = quat(o['rotation']);
      root.scale = vec(o['scale']);
      root.visible = o['visible'];
      void paint(Node node) {
        for (final primitive
            in node.mesh?.primitives ?? const <MeshPrimitive>[]) {
          primitive.material = _material(o['color'])
            ..doubleSided = primitive.material.doubleSided;
        }
        node.children.forEach(paint);
      }

      paint(root);
      final pose = sample.joints[o['id']];
      if (pose != null) {
        actors[o['id']]?.pose(
          pose,
          rootOffset: (o['pose']['root_offset_y'] as num).toDouble(),
        );
      }
    }
    scene.environmentIntensity = (sample.lighting['ambient_intensity'] as num)
        .toDouble();
    scene.directionalLight = DirectionalLight(
      direction: normalizedDirection(sample.lighting['key_direction']),
      intensity: (sample.lighting['key_intensity'] as num).toDouble(),
    );
    final c = sample.cameras[cameraId]!;
    scene.depthOfField
      ..enabled = (c['aperture_fstop'] as num) > 0
      ..focusDistance = (c['focus_distance_m'] as num).toDouble()
      ..fStop = math.max(0.1, (c['aperture_fstop'] as num).toDouble())
      ..focalLength = (c['focal_length_mm'] as num) / 1000
      ..sensorHeight = (c['sensor_height_mm'] as num) / 1000;
    scene.update(0);
    return DirectorCamera(
      position: vec(c['position']),
      target: vec(c['target']),
      fovRadiansY:
          2 * math.atan(c['sensor_height_mm'] / (2 * c['focal_length_mm'])),
      fovNear: (c['near'] as num).toDouble(),
      fovFar: (c['far'] as num).toDouble(),
    )..up = vec(c['up']);
  }

  void dispose() {
    scene.removeAll();
    scene.views.clear();
    scene.dispose();
    roots.clear();
    actors.clear();
    owners.clear();
    _geometry.clear();
  }
}

// The engine chooses triangle winding from model transforms after binding a
// material. Reverse each primitive's index winding to pair it with the
// document's right-handed camera; retain the outward normals unchanged.
MeshGeometry _rightHandGeometry(MeshGeometry source) {
  final data = source.extractMeshData();
  final indices = List<int>.from(data.indices!);
  for (var i = 0; i < indices.length; i += 3) {
    final t = indices[i + 1];
    indices[i + 1] = indices[i + 2];
    indices[i + 2] = t;
  }
  return MeshGeometry.fromArrays(
    positions: data.positions,
    normals: data.normals,
    texCoords: data.texCoords,
    indices: indices,
  );
}

v.Vector3 normalizedDirection(List values) {
  final maxComponent = values
      .map((e) => (e as num).abs().toDouble())
      .reduce(math.max);
  return (v.Vector3(
    (values[0] as num) / maxComponent,
    (values[1] as num) / maxComponent,
    (values[2] as num) / maxComponent,
  )..normalize());
}
