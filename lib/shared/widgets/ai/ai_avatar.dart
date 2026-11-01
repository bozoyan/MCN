// 职责: AI 会话标题栏的渐变圆形头像，可选点击打开助手权限
// 关联文件:
//   lib/desktop/widgets/ai/chat/header.dart
//   lib/mobile/widgets/mobile_ai_session_app_bar.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../../theme/theme.dart';

class AiAvatar extends StatelessWidget {
  const AiAvatar({
    super.key,
    required this.size,
    this.icon = RevericIcons.auto_awesome,
    this.tooltip,
    this.onTap,
    this.hitPadding = EdgeInsets.zero,
  });

  final double size;
  final String icon;
  final String? tooltip;

  /// 为空时头像只做展示。
  final VoidCallback? onTap;

  /// 点击区外扩，移动端用来凑够触控目标。
  final EdgeInsets hitPadding;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.accent, colors.accentWarm],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: RevericIcon(icon, size: size * 0.5, color: Colors.white),
    );
    if (onTap == null) return Padding(padding: hitPadding, child: avatar);
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: hitPadding, child: avatar),
        ),
      ),
    );
  }
}
