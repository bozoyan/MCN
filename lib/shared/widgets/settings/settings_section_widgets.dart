// 职责: 共享设置区布局原语 — section 标题块、卡片容器、行布局、分隔线，供各设置 section 复用。
// 关联文件:
//   lib/shared/widgets/settings/editor_settings_section.dart
//   lib/shared/widgets/settings/ai_agents_settings_section.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/app_localization.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../localization/app_localization.dart';
import '../../theme/theme.dart';

/// 设置 section 标题块：标题 + 描述 + 可选 trailing 控件，下方挂 child 内容。
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.titleKey,
    this.descriptionKey,
    required this.child,
    this.trailing,
  });

  final String titleKey;

  /// 同一页连续多个 section 时，只在首个 section 写说明，避免重复。
  final String? descriptionKey;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(titleKey),
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                  ),
                  if (descriptionKey case final descriptionKey?) ...[
                    const SizedBox(height: RevericSpacing.xxs),
                    Text(
                      context.t(descriptionKey),
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: RevericSpacing.lg),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: RevericSpacing.lg),
        child,
      ],
    );
  }
}

/// 设置卡片容器：带边框的圆角面板，纵向排列 children。
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(
      horizontal: RevericSpacing.lg,
      vertical: RevericSpacing.md,
    ),
  });

  final List<Widget> children;

  /// 整行可点击的列表传 [EdgeInsets.zero]，由行自身留白，悬停底色才能铺满卡片。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// 设置行：左侧标签 + 描述，右侧控件，2:3 比例。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.labelKey,
    required this.child,
    this.descriptionKey,
  });

  final String labelKey;
  final String? descriptionKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RevericSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t(labelKey),
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
                if (descriptionKey != null) ...[
                  const SizedBox(height: RevericSpacing.xxs),
                  Text(
                    context.t(descriptionKey!),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: RevericSpacing.x2l),
          Expanded(flex: 3, child: child),
        ],
      ),
    );
  }
}

/// 设置行之间的细分隔线。
class SettingsRowDivider extends StatelessWidget {
  const SettingsRowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Divider(height: 1, thickness: 1, color: colors.borderSubtle);
  }
}
