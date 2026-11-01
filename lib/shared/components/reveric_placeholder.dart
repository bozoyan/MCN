// 职责: 统一空态与错误占位的图标、文字层级和操作间距，布局与业务动作由调用方组合。
// 关联文件:
//   lib/shared/components/reveric_button.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// 接收已经本地化的文案；不决定居中、滚动、背景或数据状态。
class RevericPlaceholder extends StatelessWidget {
  const RevericPlaceholder.empty({
    super.key,
    required this.icon,
    this.title,
    this.description,
    this.action,
    this.compact = false,
  }) : _error = false;

  const RevericPlaceholder.error({
    super.key,
    required this.title,
    this.description,
    this.action,
    this.compact = false,
  }) : icon = RevericIcons.warning_circle,
       _error = true;

  final String icon;
  final String? title;
  final String? description;
  final Widget? action;
  final bool compact;
  final bool _error;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: RevericSizes.placeholderMaxWidth,
      ),
      child: Padding(
        padding: EdgeInsets.all(
          compact ? RevericSpacing.lg : RevericSpacing.x4l,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: RevericIcon(
                icon,
                size: compact
                    ? RevericSizes.placeholderIconSizeCompact
                    : RevericSizes.placeholderIconSize,
                color: _error ? colors.warningText : colors.textSubtle,
              ),
            ),
            if (title != null && title!.isNotEmpty) ...[
              SizedBox(
                height: compact ? RevericSpacing.sm : RevericSpacing.lg,
              ),
              Text(
                title!,
                textAlign: TextAlign.center,
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ],
            if (description != null && description!.isNotEmpty) ...[
              const SizedBox(height: RevericSpacing.sm),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: RevericSpacing.x2l),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
