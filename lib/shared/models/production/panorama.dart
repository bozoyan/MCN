// 职责: 校验全景视角并提供与着色器一致的球面投影公式。
// 关联文件:
//   lib/shared/widgets/production/panorama/viewer.dart
//   lib/shared/services/production/canvas_service.dart
//   shaders/equirect_view.frag
import 'dart:math' as math;

class PanoramaView {
  const PanoramaView({this.yaw = 0, this.pitch = 0, this.fov = 75});
  final double yaw, pitch, fov;
  double get displayYaw => (yaw + 180) % 360 - 180;
  PanoramaView changed({double? yaw, double? pitch, double? fov}) {
    final next = PanoramaView(
      yaw: yaw ?? this.yaw,
      pitch: (pitch ?? this.pitch).clamp(-85, 85),
      fov: (fov ?? this.fov).clamp(30, 100),
    );
    next.validate();
    return next;
  }

  void validate() {
    if (!yaw.isFinite ||
        !pitch.isFinite ||
        !fov.isFinite ||
        pitch < -85 ||
        pitch > 85 ||
        fov < 30 ||
        fov > 100) {
      throw const FormatException('Invalid panorama view');
    }
  }

  Map<String, dynamic> toJson() {
    validate();
    return {'yaw': yaw, 'pitch': pitch, 'fov': fov};
  }

  static PanoramaView? fromStyle(Map<String, dynamic>? style) {
    final value = style?['panorama'];
    if (value == null) {
      return null;
    }
    final map = value as Map;
    final view = PanoramaView(
      yaw: (map['yaw'] as num).toDouble(),
      pitch: (map['pitch'] as num).toDouble(),
      fov: (map['fov'] as num).toDouble(),
    );
    view.validate();
    return view;
  }

  @override
  bool operator ==(Object other) =>
      other is PanoramaView &&
      yaw == other.yaw &&
      pitch == other.pitch &&
      fov == other.fov;
  @override
  int get hashCode => Object.hash(yaw, pitch, fov);
}

/// 水平 FOV；输出坐标为 [0, 1]，纹理中心对应 yaw=0、pitch=0。
({double x, double y, double z}) panoramaRay(
  PanoramaView view,
  double x,
  double y,
  double aspect,
) {
  final scale = math.tan(view.fov * math.pi / 360);
  final dx = (2 * x - 1) * scale;
  final dy = (1 - 2 * y) * scale / aspect;
  final length = math.sqrt(dx * dx + dy * dy + 1);
  final pitch = view.pitch * math.pi / 180;
  final yaw = view.displayYaw * math.pi / 180;
  final py = dy / length * math.cos(pitch) + 1 / length * math.sin(pitch);
  final pz = 1 / length * math.cos(pitch) - dy / length * math.sin(pitch);
  return (
    x: dx / length * math.cos(yaw) + pz * math.sin(yaw),
    y: py,
    z: pz * math.cos(yaw) - dx / length * math.sin(yaw),
  );
}

({double u, double v}) panoramaUv(
  PanoramaView view,
  double x,
  double y,
  double aspect,
) {
  final ray = panoramaRay(view, x, y, aspect);
  return (
    u: (math.atan2(ray.x, ray.z) / (2 * math.pi) + .5) % 1,
    v: .5 - math.asin(ray.y.clamp(-1, 1)) / math.pi,
  );
}
