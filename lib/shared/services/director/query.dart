// 职责: 对冻结导演快照执行有界采样并输出可定位诊断。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/models/director/sampling.dart
//   lib/shared/services/ai/stagings_run_command_handler.dart
import '../../models/director/document.dart';
import '../../models/director/sampling.dart';

Json _diagnostic(DocumentError error, int frame) {
  final path = error.path;
  final match = RegExp(
    r'frame\[[^\]]+\]\.(?:cameras\.)?([0-9a-fA-F-]{36})\.(.+)',
  ).firstMatch(path);
  return {
    'frame': frame,
    'path': path,
    'reason': error.reason,
    if (match != null) 'target_id': match.group(1),
    if (match != null) 'property': match.group(2),
  };
}

Json sampleDirector(DirectorDocument document, dynamic frames) {
  if (frames is! List || frames.isEmpty || frames.length > 12) {
    invalid('frames', 'one_to_twelve_frames_required');
  }
  for (final frame in frames) {
    number(frame, 'frames', 0, document.durationFrames, integer: true);
  }
  return {
    'samples': [for (final frame in frames) _sample(document, frame)],
  };
}

Json _sample(DirectorDocument document, int frame) {
  try {
    final sample = sampleDocument(document, frame);
    return {
      'frame': frame,
      'objects': sample.objects,
      'cameras': sample.cameras,
      'effective_camera_id': sample.cameraId,
      'effective_camera': sample.cameras[sample.cameraId],
      'lighting': sample.lighting,
      'diagnostics': <Json>[],
    };
  } on DocumentError catch (error) {
    return {
      'frame': frame,
      'diagnostics': [_diagnostic(error, frame)],
    };
  }
}
