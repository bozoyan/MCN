// 职责: 桌面端技能目录 tab(官方 / 广场)共用的加载 / 错误 / 空状态占位构件,
//   消除 official_catalog_tab 与 marketplace_catalog_tab 的重复实现。
// 关联文件:
//   lib/desktop/features/agent_skills/official_catalog_tab.dart
//   lib/desktop/features/agent_skills/marketplace_catalog_tab.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

/// 目录加载中占位。
class CatalogLoadingState extends StatelessWidget {
  const CatalogLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(colors.textMuted),
        ),
      ),
    );
  }
}

/// 目录加载失败 + 重试。
class CatalogErrorState extends StatelessWidget {
  const CatalogErrorState({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;

  /// 已本地化的失败说明;null 时用通用加载失败文案。
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x6l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.warning_circle,
              size: 30,
              color: colors.warningText,
            ),
            const SizedBox(height: RevericSpacing.md),
            Text(
              message ?? context.t(LocaleKeys.agentSkillLoadFailed),
              style: typo.heading2.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RevericSpacing.lg),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textSecondary,
                minimumSize: const Size(0, RevericSizes.buttonHeightSm),
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.x2l,
                ),
              ),
              child: Text(context.t(LocaleKeys.agentSkillRetry)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 目录为空占位。
class CatalogEmptyState extends StatelessWidget {
  const CatalogEmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x6l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.layers_outlined,
              size: 30,
              color: colors.textSubtle,
            ),
            const SizedBox(height: RevericSpacing.md),
            Text(
              message,
              style: typo.heading2.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
