// 职责: 校验直接编辑目标及健康依赖，允许原本无效的未编辑依赖逐项恢复。
// 关联文件:
//   lib/shared/services/director/session.dart
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/sampling.dart
import 'package:collection/collection.dart';
import '../../models/director/document.dart';
import '../../models/director/sampling.dart';

void validateFrameEdit(
  DirectorDocument before,
  DirectorDocument next,
  int frame,
) {
  final prior = animationPlan(before), candidate = animationPlan(next);
  final oldFrame = frame.clamp(0, before.durationFrames);
  final nextFrame = frame.clamp(0, next.durationFrames);
  void check(
    void Function(AnimationPlan, int) sample,
    Object? Function(DirectorDocument) inputs, {
    bool allowDependencyRecovery = false,
  }) {
    try {
      sample(candidate, nextFrame);
    } on DocumentError catch (error) {
      // 直接编辑的目标必须求值成功，不能用原有错误码掩盖非法改动。
      if (!const DeepCollectionEquality().equals(
        inputs(before),
        inputs(next),
      )) {
        rethrow;
      }
      try {
        sample(prior, oldFrame);
      } on DocumentError catch (old) {
        // 相机自身未编辑且原本已无效时，上游修复可能揭露下一个
        // 残留错误。允许保留诊断，避免机位反向阻塞源对象的修复。
        if (allowDependencyRecovery ||
            old.path == error.path && old.reason == error.reason) {
          return;
        }
      }
      rethrow;
    }
  }

  // 独立检查全部目标，不能用整帧的首个异常掩盖后面的新增错误。
  for (final object in next.objects) {
    check(
      (plan, at) => plan.object(object['id'], at),
      (d) => _objectInputs(d, object['id']),
    );
  }
  for (final camera in next.cameras) {
    check(
      (plan, at) => plan.camera(camera['id'], at),
      (d) => _cameraOwnInputs(d, camera['id']),
      allowDependencyRecovery: true,
    );
  }
  check(
    (plan, at) => plan.lighting(at),
    (d) => {'lighting': d.lighting, 'tracks': _tracks(d, d.id)},
  );
}

List<Json> _tracks(DirectorDocument document, String id) =>
    document.tracks.where((t) => t['target_id'] == id).toList();

Json _objectInputs(DirectorDocument document, String id) => {
  'object': document.objects.where((o) => o['id'] == id).firstOrNull,
  'tracks': _tracks(document, id),
  'paths': document.paths.where((p) => p['target_id'] == id).toList(),
};

Json? _cameraOwnInputs(DirectorDocument document, String id) {
  final camera = document.camera(id);
  if (camera == null) {
    return null;
  }
  // 相机依赖由真实求值检查：基线成功而候选失败仍拒绝。
  // 这里只判断是否直接编辑了机位自身，不能把上游对象变化混入。
  return {
    'camera': camera,
    'tracks': _tracks(document, id),
    'moves': document.moves.where((m) => m['camera_id'] == id).toList(),
  };
}
