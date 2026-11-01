// 职责: 加载并缓存角色 glb 人偶模板，按角色克隆出使用显式姿态高度的骨骼实例。
// 关联文件:
//   lib/shared/services/director/scene_builder.dart
//   lib/shared/models/director/sampling.dart
//   lib/shared/models/director/presets.dart
//   assets/director/models/quaternius-standard-male.glb
//   assets/director/models/quaternius-standard-female.glb
import 'package:reveric/shared/models/director/rig.dart';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as v;

import 'package:reveric/shared/models/director/presets.dart';

/// 角色几何 key → glb 资源。资源已离线反转三角形绕序，配合导演台的右手投影。
const actorModelAssets = {
  'actor.male.v1': 'assets/director/models/quaternius-standard-male.glb',
  'actor.female.v1': 'assets/director/models/quaternius-standard-female.glb',
};

class ActorModels {
  static final Map<String, Node> _templates = {};
  static Future<void>? _loading;

  /// 幂等加载全部角色模板；失败后允许下次重试。
  static Future<void> load() => _loading ??= _load().catchError((Object e) {
    _loading = null;
    throw e;
  });

  static Future<void> _load() async {
    for (final entry in actorModelAssets.entries) {
      final model = await Node.fromGlbAsset(entry.value);
      // 导入器为左手引擎套了 Z 翻转；文档与 glTF 同为右手系，去掉它。
      model.localTransform = v.Matrix4.identity();
      // 人偶风格：隐藏眼睛与眉毛。
      for (final name in ['Eyes', 'Eyebrows']) {
        model.getChildByName(name)?.visible = false;
      }
      _templates[entry.key] = model;
    }
  }

  static ActorRig instantiate(String geometryKey, Material material) {
    final template = _templates[geometryKey];
    if (template == null) {
      throw StateError('actor_model_not_loaded:$geometryKey');
    }
    final model = template.clone();
    void paint(Node n) {
      for (final p in n.mesh?.primitives ?? const <MeshPrimitive>[]) {
        p.material = material;
      }
      n.children.forEach(paint);
    }

    paint(model);
    return ActorRig._(model, geometryKey);
  }
}

class ActorRig {
  final Node model;
  final Map<String, Node> _bones = {};
  final Map<String, v.Quaternion> _rest = {};
  final String geometryKey;

  ActorRig._(this.model, this.geometryKey) {
    rigBoneNames.forEach((bone, name) {
      final node = model.getChildByName(name)!;
      _bones[bone] = node;
      _rest[bone] = node.rotation;
    });
  }

  /// 骨骼增量、固定模型基准和显式姿态高度各应用一次。
  void pose(Map<String, BoneEuler> deltas, {double rootOffset = 0}) {
    _bones.forEach((bone, node) {
      final delta = boneRotation(deltas[bone] ?? [0, 0, 0]);
      node.rotation =
          _rest[bone]! * v.Quaternion(delta.x, delta.y, delta.z, delta.w);
    });
    model.position = v.Vector3(0, rigBaseline(geometryKey) + rootOffset, 0);
  }
}
