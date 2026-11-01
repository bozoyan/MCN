// 职责: 绘制长时运行状态的不定进度环，由共享限帧时钟驱动。
// 关联文件:
//   lib/shared/components/status_animation_clock.dart
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/widgets/ai/tools/tool_card_common.dart
//   lib/desktop/widgets/ai/chat/floating.dart
// 遵循的 Rules:
//   .agents/rules/performance.md

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'status_animation_clock.dart';

/// Indeterminate ring for status that can stay visible for a whole agent turn.
///
/// Unlike `CircularProgressIndicator`, it does not own a vsync ticker; it runs
/// on [StatusAnimationClock] and each tick only repaints its own layer.
class RevericSpinner extends StatefulWidget {
  const RevericSpinner({
    super.key,
    required this.color,
    this.strokeWidth = 2,
    this.backgroundColor,
    this.value,
  }) : assert(value == null || (value >= 0 && value <= 1));

  final Color color;
  final double strokeWidth;
  final Color? backgroundColor;

  /// Non-null draws a static arc covering this fraction, e.g. for reduced motion.
  final double? value;

  @override
  State<RevericSpinner> createState() => _RevericSpinnerState();
}

class _RevericSpinnerState extends State<RevericSpinner>
    with StatusAnimationClockMixin {
  @override
  bool get animatesStatus => widget.value == null;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size.square(36),
        painter: _SpinnerPainter(
          clock: statusClock,
          animate: statusClockAttached,
          color: widget.color,
          backgroundColor: widget.backgroundColor,
          strokeWidth: widget.strokeWidth,
          value: widget.value,
        ),
      ),
    );
  }
}

const _cycleSeconds = 1.333;
const _rotationSeconds = 2.4;
const _minSweepTurns = 0.08;
const _maxSweepTurns = 0.75;

/// Indeterminate arc at [seconds]: start angle and clockwise sweep in radians.
///
/// Each cycle the head advances while the tail waits, then the tail catches up,
/// on top of a steady rotation. Both ends only ever move clockwise; driving the
/// sweep with a sine instead makes the head run backwards while it shrinks.
@visibleForTesting
({double start, double sweep}) spinnerArcAt(double seconds) {
  const growTurns = _maxSweepTurns - _minSweepTurns;
  final cycles = seconds / _cycleSeconds;
  final phase = cycles % 1;
  final head = Curves.fastOutSlowIn.transform(math.min(phase * 2, 1));
  final tail = Curves.fastOutSlowIn.transform(math.max(phase * 2 - 1, 0));
  final tailTurns =
      (cycles - phase + tail) * growTurns + seconds / _rotationSeconds;
  return (
    start: -math.pi / 2 + math.pi * 2 * (tailTurns % 1),
    sweep: math.pi * 2 * (_minSweepTurns + (head - tail) * growTurns),
  );
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({
    required this.clock,
    required this.animate,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
    required this.value,
  }) : super(repaint: animate ? clock : null);

  final StatusAnimationClock clock;
  final bool animate;
  final Color color;
  final Color? backgroundColor;
  final double strokeWidth;
  final double? value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final track = backgroundColor;
    if (track != null) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    }

    final double start;
    final double sweep;
    final fixed = value;
    if (fixed != null) {
      start = -math.pi / 2;
      sweep = math.pi * 2 * fixed;
    } else {
      (:start, :sweep) = spinnerArcAt(clock.seconds);
    }
    if (sweep > 0) {
      canvas.drawArc(rect, start, sweep, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) {
    return oldDelegate.animate != animate ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.value != value;
  }
}
