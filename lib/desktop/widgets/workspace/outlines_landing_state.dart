// 职责: 大纲分区默认落地页 — 引导查看全局大纲或新建单个大纲
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

class OutlinesLandingState extends StatelessWidget {
  const OutlinesLandingState({
    super.key,
    required this.onViewAll,
    required this.onCreate,
  });

  final VoidCallback onViewAll;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.x6l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericIcon(
                RevericIcons.timeline_outlined,
                size: 32,
                color: colors.textSubtle,
              ),
              const SizedBox(height: RevericSpacing.lg),
              Text(
                context.t(LocaleKeys.workspaceOutlines),
                style: typo.heading2.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: RevericSpacing.sm),
              Text(
                context.t(LocaleKeys.workspaceOutlinesHint),
                textAlign: TextAlign.center,
                style: typo.ui.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: RevericSpacing.x2l),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: onViewAll,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RevericIcon(
                          RevericIcons.account_tree_outlined,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: RevericSpacing.xs),
                        Text(context.t(LocaleKeys.workspaceViewGlobalOutlines)),
                      ],
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.md),
                  FilledButton(
                    onPressed: onCreate,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const RevericIcon(RevericIcons.add, size: 16),
                        const SizedBox(width: RevericSpacing.xs),
                        Text(context.t(LocaleKeys.workspaceNewOutline)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
