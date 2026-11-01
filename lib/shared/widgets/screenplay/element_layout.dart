// 职责: 统一剧本元素缩进、动作标记、对话折角与注释块排版。
// 关联文件:
//   lib/shared/widgets/screenplay/text_styles.dart
//   lib/shared/models/screenplay_element.dart

import 'package:flutter/material.dart';
import '../../models/screenplay_element.dart';
import '../../theme/theme.dart';
import 'text_styles.dart';

/// 一行元素的公共外壳：左侧光标定位线 + 按类型的缩进与装饰。
class ScreenplayElementLayout extends StatelessWidget {
  const ScreenplayElementLayout({
    super.key,
    required this.type,
    required this.isCaret,
    required this.child,
    this.topSpacing = 10,
    this.trailing,
  });

  final ScreenplayElementType type;
  final bool isCaret;
  final Widget child;
  final double topSpacing;

  /// 行尾的次要操作（删除等）。悬停才出现，不常驻占位。
  final Widget? trailing;

  /// 正文栏左侧留给光标定位线的沟槽宽度。
  static const double gutter = 20;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final styles = ScreenplayTextStyles.of(context);
    final indent = switch (type) {
      ScreenplayElementType.action => RevericSizes.screenplayActionIndent,
      ScreenplayElementType.parenthetical ||
      ScreenplayElementType.dialogue => RevericSizes.screenplayDialogIndent,
      _ => 0.0,
    };
    Widget content = Padding(
      padding: EdgeInsets.only(left: indent),
      child: child,
    );
    if (type == ScreenplayElementType.action) {
      // △ 悬挂在栏外，让动作行的正文与其它元素保持同一条左边界。
      content = Stack(
        children: [
          content,
          Positioned(
            left: 0,
            top: 6,
            child: Text('△', style: styles.actionMarker),
          ),
        ],
      );
    } else if (type == ScreenplayElementType.dialogue) {
      // 一段 1px 折角引线，替代截图里的 └ 字符。
      content = Stack(
        children: [
          content,
          Positioned(
            left: RevericSizes.screenplayActionIndent,
            top: 8,
            child: CustomPaint(
              size: const Size(10, 9),
              painter: _DialogueElbowPainter(color: colors.borderInput),
            ),
          ),
        ],
      );
    } else if (type == ScreenplayElementType.note) {
      content = Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.lg,
          vertical: RevericSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceDim,
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(RevericRadius.medium),
            bottomRight: Radius.circular(RevericRadius.medium),
          ),
          border: Border(
            left: BorderSide(color: colors.blockquoteBorder, width: 2),
          ),
        ),
        child: content,
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: topSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutter,
            child: isCaret
                ? Padding(
                    padding: const EdgeInsets.only(top: 4, right: 10),
                    child: Container(
                      width: 2,
                      height: 18,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(child: content),
          SizedBox(width: 24, child: trailing),
        ],
      ),
    );
  }
}

/// 各元素之间的垂直节奏，对应 css 里的 `margin-top`。
double screenplayElementTopSpacing(ScreenplayElementType type) {
  return switch (type) {
    ScreenplayElementType.scene_heading => 28,
    ScreenplayElementType.character => 16,
    ScreenplayElementType.parenthetical => 2,
    ScreenplayElementType.dialogue => 2,
    ScreenplayElementType.transition => 20,
    ScreenplayElementType.subtitle => 18,
    ScreenplayElementType.note => 12,
    ScreenplayElementType.action => 10,
  };
}

class _DialogueElbowPainter extends CustomPainter {
  const _DialogueElbowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..moveTo(0.5, 0)
      ..lineTo(0.5, size.height - 3.5)
      ..arcToPoint(
        Offset(3.5, size.height - 0.5),
        radius: const Radius.circular(3),
        clockwise: false,
      )
      ..lineTo(size.width, size.height - 0.5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DialogueElbowPainter oldDelegate) =>
      oldDelegate.color != color;
}
