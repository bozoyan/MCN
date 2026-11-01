// 职责: 画布连线生长动效 — 让连线沿自身路径长出来，并在头部带一枚亮点
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/canvas/canvas_ai_director.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
// 遵循的 Rules:
//   .agents/rules/performance.md

import 'dart:async';
import 'dart:ui';

import 'package:flutter/animation.dart' show Curve, Curves;

import '../../../../third/flow/vyuh_node_flow.dart' as flow;

/// 连线「长出来」的动效。
///
/// 库传进 `paint` 的 `animationValue` 是一条**循环锯齿波**(编辑器用 `repeat()`
/// 驱动),拿它当进度会让连线反复重长。所以进度由自己的 [Stopwatch] 算,
/// `animationValue` 只被用来白拿那份 60fps 重绘节拍。
///
/// 用完必须由调用方摘掉(`connection.animationEffect = null`),否则这条边会
/// 让整张画布常驻重绘 —— 见 [CanvasEdgeGrowEffect.start] 的 onDone。
class CanvasEdgeGrowEffect implements flow.ConnectionEffect {
  CanvasEdgeGrowEffect({
    this.duration = const Duration(milliseconds: 520),
    this.curve = Curves.easeOutCubic,
  });

  /// 生长时长。比节点入场慢一些 —— 线是「走」出来的,不是「弹」出来的。
  final Duration duration;

  final Curve curve;

  final Stopwatch _clock = Stopwatch();
  Timer? _doneTimer;

  /// 开始生长。[onDone] 在长完后回调一次,调用方在那里摘掉 effect。
  void start({VoidCallback? onDone}) {
    _clock
      ..reset()
      ..start();
    _doneTimer?.cancel();
    _doneTimer = Timer(duration, () {
      _clock.stop();
      onDone?.call();
    });
  }

  /// 提前停止(边被中途删除/用户接管时),不再回调 onDone。
  void stop() {
    _doneTimer?.cancel();
    _doneTimer = null;
    _clock.stop();
  }

  /// 当前生长进度 0..1。
  double get progress {
    if (duration.inMicroseconds <= 0) {
      return 1;
    }
    final raw = _clock.elapsedMicroseconds / duration.inMicroseconds;
    return curve.transform(raw.clamp(0.0, 1.0));
  }

  @override
  void paint(Canvas canvas, Path path, Paint basePaint, double animationValue) {
    final value = progress;
    if (value <= 0) {
      return;
    }

    for (final metric in path.computeMetrics()) {
      final grownLength = metric.length * value;
      if (grownLength <= 0) {
        continue;
      }
      canvas.drawPath(metric.extractPath(0, grownLength), basePaint);

      // 头部亮点:长到哪就亮到哪,视线跟着它走。长完就收起来。
      if (value >= 1) {
        continue;
      }
      final tangent = metric.getTangentForOffset(grownLength);
      if (tangent == null) {
        continue;
      }
      final headPaint = Paint()
        ..color = basePaint.color.withValues(alpha: _headAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(tangent.position, _headRadius, headPaint);
    }
  }
}

/// 头部亮点半径(画布坐标)。跟着缩放走,不做屏幕像素补偿 —— 跟随镜头
/// 全程在 0.3~1.1 之间,这个尺寸在两端都不突兀。
const double _headRadius = 4.5;

const double _headAlpha = 0.9;
