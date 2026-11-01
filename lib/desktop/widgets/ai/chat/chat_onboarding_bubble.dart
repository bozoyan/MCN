// 职责: 多步 AI 聊天引导气泡 — 渲染带步骤指示、标题、说明、主/次按钮、尾箭头的卡片
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/desktop/widgets/ai/chat/composer.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../shared/components/reveric_button.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/theme/theme.dart';

/// 气泡尾箭头朝向（指向目标的位置）
enum OnboardingBubbleTail {
  /// 尾巴在气泡下方，箭头朝下，水平方向上靠左
  bottomStart,

  /// 尾巴在气泡下方，箭头朝下，水平方向上居中
  bottomCenter,

  /// 尾巴在气泡下方，箭头朝下，水平方向上靠右
  bottomEnd,

  /// 尾巴在气泡上方，箭头朝上，水平方向上靠左
  topStart,

  /// 尾巴在气泡上方，箭头朝上，水平方向上居中
  topCenter,

  /// 尾巴在气泡上方，箭头朝上，水平方向上靠右
  topEnd,

  /// 尾巴在气泡右侧、垂直居中，箭头朝右
  rightCenter;

  /// 尾巴是否在气泡上方
  bool get isTop => switch (this) {
    topStart || topCenter || topEnd => true,
    _ => false,
  };

  /// 尾巴是否在气泡右方
  bool get isRight => this == rightCenter;
}

class ChatOnboardingBubble extends HookWidget {
  const ChatOnboardingBubble({
    super.key,
    required this.stepIndex,
    required this.totalSteps,
    required this.title,
    required this.message,
    required this.onDismiss,
    this.onNext,
    this.tail = OnboardingBubbleTail.bottomStart,
    this.width = 320,
  });

  /// 1-based 当前步骤
  final int stepIndex;

  /// 步骤总数
  final int totalSteps;

  final String title;
  final String message;

  /// 关闭整个引导流程的回调（"知道了"按钮 + 顶部 X 按钮 + 点击空白）
  final VoidCallback onDismiss;

  /// 进入下一步的回调；为 null 时不渲染"下一步"按钮
  final VoidCallback? onNext;

  final OnboardingBubbleTail tail;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final opacity = useState(0.0);

    useEffect(() {
      Future<void>(() async {
        await Future.delayed(const Duration(milliseconds: 60));
        opacity.value = 1.0;
      });
      return null;
    }, [stepIndex]);

    final card = Container(
      width: width,
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.10),
            blurRadius: 32,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(RevericRadius.pill),
                ),
                child: Text(
                  '$stepIndex/$totalSteps',
                  style: typo.uiTiny.copyWith(color: colors.textMuted),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(RevericRadius.small),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: RevericIcon(
                    RevericIcons.close_rounded,
                    size: 16,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.md),
          Text(title, style: typo.heading2.copyWith(color: colors.textPrimary)),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            message,
            style: typo.uiSmall.copyWith(
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: RevericSpacing.lg),
          Row(
            children: [
              RevericButton.primary(
                size: RevericButtonSize.compact,
                label: onNext == null
                    ? context.t(LocaleKeys.aiChatOnboardingDone)
                    : context.t(LocaleKeys.aiChatOnboardingDismiss),
                onPressed: onDismiss,
              ),
              const Spacer(),
              if (onNext != null)
                RevericButton.text(
                  size: RevericButtonSize.compact,
                  label: context.t(LocaleKeys.aiChatOnboardingNext),
                  icon: RevericIcons.arrow_forward,
                  onPressed: () {
                    onNext!();
                  },
                ),
            ],
          ),
        ],
      ),
    );

    final tailWidget = _BubbleTail(
      color: colors.surface,
      alignment: tail,
      bubbleWidth: width,
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: opacity.value,
      child: tail.isRight
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [card, tailWidget],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tail.isTop) tailWidget,
                card,
                if (!tail.isTop) tailWidget,
              ],
            ),
    );
  }
}

class _BubbleTail extends StatelessWidget {
  const _BubbleTail({
    required this.color,
    required this.alignment,
    required this.bubbleWidth,
  });

  final Color color;
  final OnboardingBubbleTail alignment;
  final double bubbleWidth;

  @override
  Widget build(BuildContext context) {
    const tailHalfSize = 8.0;

    if (alignment.isRight) {
      return CustomPaint(
        size: const Size(tailHalfSize, tailHalfSize * 2),
        painter: _ArrowTailPainter(color: color, pointRight: true),
      );
    }

    final double leftPadding;
    final bool flipVertical;
    switch (alignment) {
      case OnboardingBubbleTail.bottomStart:
      case OnboardingBubbleTail.topStart:
        leftPadding = 32;
        flipVertical = alignment.isTop;
        break;
      case OnboardingBubbleTail.bottomCenter:
      case OnboardingBubbleTail.topCenter:
        leftPadding = (bubbleWidth / 2) - tailHalfSize;
        flipVertical = alignment.isTop;
        break;
      case OnboardingBubbleTail.bottomEnd:
      case OnboardingBubbleTail.topEnd:
        leftPadding = bubbleWidth - 32 - (tailHalfSize * 2);
        flipVertical = alignment.isTop;
        break;
      case OnboardingBubbleTail.rightCenter:
        leftPadding = 0;
        flipVertical = false;
        break;
    }
    return Padding(
      padding: EdgeInsets.only(left: leftPadding),
      child: CustomPaint(
        size: const Size(tailHalfSize * 2, tailHalfSize),
        painter: _ArrowTailPainter(color: color, flipVertical: flipVertical),
      ),
    );
  }
}

class _ArrowTailPainter extends CustomPainter {
  const _ArrowTailPainter({
    required this.color,
    this.flipVertical = false,
    this.pointRight = false,
  });

  final Color color;
  final bool flipVertical;
  final bool pointRight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (pointRight) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(0, size.height)
        ..close();
    } else if (flipVertical) {
      path
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0)
        ..close();
    }

    canvas.drawPath(path, paint);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawPath(path, shadowPaint);
  }

  @override
  bool shouldRepaint(covariant _ArrowTailPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.flipVertical != flipVertical ||
      oldDelegate.pointRight != pointRight;
}
