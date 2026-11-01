// 职责: 定义导演画幅选项，并将视口比例换算为可编码的输出尺寸。
// 关联文件:
//   lib/shared/models/director/document.dart
//   lib/shared/services/director/commands.dart
//   lib/shared/widgets/director/aspect.dart

import 'dart:math' as math;

enum DirectorAspectRatio {
  adaptive('auto', 720, 1280),
  cinematic('21:9', 1680, 720),
  landscape('16:9', 1280, 720),
  classic('4:3', 960, 720),
  square('1:1', 720, 720),
  portrait('3:4', 720, 960),
  vertical('9:16', 720, 1280);

  const DirectorAspectRatio(this.label, this.width, this.height);
  final String label;
  final int width;
  final int height;

  double get ratio => width / height;
}

/// 以 720 像素短边为基准，长边不超过 1920；H.264 输出使用偶数尺寸。
(int, int) adaptiveOutputSize(double width, double height) {
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    throw ArgumentError('Viewport dimensions must be finite and positive');
  }
  final scale = math.min(
    720 / math.min(width, height),
    1920 / math.max(width, height),
  );
  int even(double value) => ((value * scale / 2).round() * 2).clamp(2, 1920);
  return (even(width), even(height));
}
