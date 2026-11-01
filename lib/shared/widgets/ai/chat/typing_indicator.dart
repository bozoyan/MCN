// 职责: AI 消息打字指示器 — 显示 AI 正在输入时的三点动画状态
// 关联文件:
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/components/status_animation_clock.dart
// 遵循的 Rules:
//   .agents/rules/performance.md
import 'package:flutter/widgets.dart';

import 'package:reveric/shared/components/status_animation_clock.dart';
import 'package:reveric/shared/theme/theme.dart';

class AiTypingIndicator extends StatefulWidget {
  const AiTypingIndicator({super.key, required this.colors});

  final RevericColors colors;

  @override
  State<AiTypingIndicator> createState() => _AiTypingIndicatorState();
}

class _AiTypingIndicatorState extends State<AiTypingIndicator>
    with StatusAnimationClockMixin {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: _TypingDotsPainter.size,
        painter: _TypingDotsPainter(
          clock: statusClock,
          animate: statusClockAttached,
          color: widget.colors.textMuted,
        ),
      ),
    );
  }
}

class _TypingDotsPainter extends CustomPainter {
  _TypingDotsPainter({
    required this.clock,
    required this.animate,
    required this.color,
  }) : super(repaint: animate ? clock : null);

  static const _dotSize = 10.0;
  static const _gap = RevericSpacing.xs;
  static const _lift = 4.0;
  static const _cycleSeconds = 0.9;
  static const _centers = [0.18, 0.5, 0.82];
  static const size = Size(_dotSize * 3 + _gap * 2, _dotSize);

  final StatusAnimationClock clock;
  final bool animate;
  final Color color;

  static double _phaseValue(double progress, double center) {
    final distance = (progress - center).abs();
    if (distance >= 0.22) {
      return 0;
    }
    return 1 - (distance / 0.22);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final progress = clock.seconds / _cycleSeconds % 1;
    final paint = Paint();
    const radius = _dotSize / 2;
    for (var index = 0; index < _centers.length; index++) {
      final phase = _phaseValue(progress, _centers[index]);
      paint.color = color.withValues(alpha: 0.28 + 0.5 * phase);
      canvas.drawCircle(
        Offset(
          radius + index * (_dotSize + _gap),
          size.height - radius - _lift * phase,
        ),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TypingDotsPainter oldDelegate) {
    return oldDelegate.animate != animate || oldDelegate.color != color;
  }
}
