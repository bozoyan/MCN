// 职责: 统一纯图标操作的主题、无障碍名称及桌面和移动端点击区域。
// 关联文件:
//   lib/shared/theme/reveric_theme.dart
//   lib/shared/theme/reveric_spacing.dart
//   lib/shared/theme/reveric_icons.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// 普通图标操作；图标继承 IconButton 的前景与禁用色。
class RevericIconButton extends StatelessWidget {
  const RevericIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final String icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final mobile = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    final size = mobile
        ? RevericSizes.touchTargetSize
        : RevericSizes.iconButtonSize;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size.square(size)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      ),
      icon: RevericIcon(
        icon,
        size: mobile
            ? RevericSizes.iconButtonIconSizeMobile
            : RevericSizes.iconButtonIconSize,
      ),
    );
  }
}
