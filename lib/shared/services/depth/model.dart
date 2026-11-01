// 职责: 定义深度任务的阶段、失败、尺寸预算和模型版本合同。
// 关联文件:
//   lib/shared/services/depth/model_service.dart
//   lib/shared/services/depth/orchestrator.dart
import 'dart:math' as math;
import '../production/ffmpeg_runner.dart';
import '../../models/production/media.dart';

enum DepthStage {
  preparing,
  connecting,
  downloading,
  verifying,
  decoding,
  inference,
  mapping,
  encoding,
  saving,
  complete,
  failed,
  cancelled,
  interrupted,
}

enum DepthFailure {
  unavailable,
  model_source,
  model_invalid,
  insufficient_space,
  invalid_video,
  native_failed,
  storage_failed,
}

class DepthException implements Exception {
  const DepthException(this.reason);
  final DepthFailure reason;
  @override
  String toString() => 'DepthException(${reason.name})';
}

void checkDepthCancellation(MediaCancellation token) {
  if (token.cancelled) {
    throw const MediaException(MediaFailure.cancelled);
  }
}

typedef DepthProgress = void Function(DepthStage stage, double? progress);

class DepthModelManifest {
  static const defaultSource =
      'https://huggingface.co/looplj/video-depth-anything-small-onnx/resolve/'
      'ff810849333df46d37ea18a885fc11689661fe96/'
      'video-depth-anything-small-dynamic-fp32.onnx';

  const DepthModelManifest({
    this.version = 'vda-small-dynamic-fp32-v1',
    this.bytes = 116528885,
    this.sha256 =
        'eb5926ad36741e911c43cb010cc2f74604aa524744feeaf57979c178ede4bb99',
    this.source = defaultSource,
  });
  final String version, sha256, source;
  final int bytes;
}

class DepthProfile {
  const DepthProfile(this.width, this.height);
  final int width, height;
  int get pixels => width * height;
  factory DepthProfile.forVideo(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw const DepthException(DepthFailure.invalid_video);
    }
    final scale = math.min(
      280 / math.min(width, height),
      math.sqrt(141120 / (width * height)),
    );
    int align(double value) => math.max(14, (value / 14).round() * 14);
    var w = math.min(952, align(width * scale));
    var h = math.min(952, align(height * scale));
    while (w * h > 141120) {
      if (w >= h) {
        w -= 14;
      } else {
        h -= 14;
      }
    }
    return DepthProfile(w, h);
  }
  // RGB + float depth + gray + PGM frames, file allocation, encoded output and
  // safety reserve. Original media is never copied into this workspace.
  int requiredBytes(int frames, int sourceBytes) =>
      pixels * frames * 9 + frames * 8192 + sourceBytes * 2 + 256 * 1024 * 1024;
}
