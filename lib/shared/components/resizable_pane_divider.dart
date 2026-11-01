// 职责: 将桌面分栏的细分隔线与覆盖在边界两侧的拖拽热区分开布局。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// 放在分栏 Row 中的可见边界，只占一条线的宽度。
class ResizablePaneDividerAnchor extends StatelessWidget {
  const ResizablePaneDividerAnchor({super.key, required this.link});

  final LayerLink link;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: link,
      child: SizedBox(
        width: ResizablePaneDivider.width,
        height: double.infinity,
        child: ColoredBox(color: RevericTheme.colorsOf(context).border),
      ),
    );
  }
}

/// 放在覆盖整个分栏区域的 Stack 中，并在 anchor 之后绘制。
/// 热区跟随实际边界（包括宽度动画），不占用 Row 的空间。
class ResizablePaneDivider extends StatelessWidget {
  const ResizablePaneDivider({
    super.key,
    required this.link,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  static const double width = RevericSizes.dividerThickness;
  static const double hitAreaWidth = RevericSpacing.md;

  final LayerLink link;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      offset: const Offset((width - hitAreaWidth) / 2, 0),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            onDragUpdate(details.delta.dx);
          },
          onHorizontalDragEnd: (_) {
            onDragEnd();
          },
          onHorizontalDragCancel: onDragEnd,
          child: SizedBox(width: hitAreaWidth, height: double.infinity),
        ),
      ),
    );
  }
}
