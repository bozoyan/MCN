// 职责: 三点跳动的「正在输入」动画，AI 模式消息卡片在还没出字时占位用。
// 关联文件:
//   lib/shared/widgets/ai/agent_message_card.dart
import 'package:flutter/material.dart';

class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.color});

  final Color color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final progress = (_controller.value * 3 - i).clamp(0.0, 1.0);
          final scale = 0.5 + 0.5 * (1 - (progress * 2 - 1).abs());
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.5),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
