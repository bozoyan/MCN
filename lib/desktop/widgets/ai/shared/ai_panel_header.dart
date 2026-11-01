// 职责: AI 子模式面板（monologue / theater / roleplay）共享标题栏 — 渐变头像、标题、操作按钮。
// 关联文件:
//   lib/desktop/features/monologue/panel.dart
//   lib/desktop/features/theater/panel.dart
//   lib/desktop/features/roleplay/panel.dart
//   lib/desktop/widgets/ai/chat/header.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';

import '../../../../shared/components/reveric_icon_button.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/theme/theme.dart';

/// 共享标题栏，复用 chat/council header 的视觉语言：
/// - 渐变圆形头像 + 模式专属图标
/// - 主标题 + 可选副标题
/// - 右侧动作按钮使用 [RevericIcons.close] / [RevericIcons.add]
class AiPanelHeader extends StatelessWidget {
  const AiPanelHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onNewSession,
    this.newSessionTooltip,
    this.onClose,
    this.gradientColors,
  });

  /// 头像内的图标（来自 [RevericIcons]）。
  final String icon;

  final String title;
  final String? subtitle;

  final VoidCallback? onNewSession;
  final String? newSessionTooltip;

  final VoidCallback? onClose;

  /// 自定义渐变色。默认使用 `[accent, accentWarm]`，与 chat 头像视觉一致。
  final List<Color>? gradientColors;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final sub = subtitle?.trim();
    final hasSubtitle = sub != null && sub.isNotEmpty;

    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RevericSpacing.x2l,
          0,
          RevericSpacing.lg,
          0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _GradientIconBadge(
              icon: icon,
              size: RevericSizes.aiAvatarSm,
              gradientColors:
                  gradientColors ?? [colors.accent, colors.accentWarm],
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            if (onNewSession != null) ...[
              RevericIconButton(
                tooltip:
                    newSessionTooltip ?? context.t(LocaleKeys.aiNewSession),
                icon: RevericIcons.add,
                onPressed: onNewSession,
              ),
              const SizedBox(width: RevericSpacing.xxs),
            ],
            if (onClose != null)
              RevericIconButton(
                tooltip: context.t(LocaleKeys.commonClose),
                icon: RevericIcons.close,
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}

class _GradientIconBadge extends StatelessWidget {
  const _GradientIconBadge({
    required this.icon,
    required this.size,
    required this.gradientColors,
  });

  final String icon;
  final double size;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: RevericIcon(icon, size: size * 0.55, color: Colors.white),
    );
  }
}
