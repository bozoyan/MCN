// 职责: 展示草稿作品加入书库的提示与确认入口。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

class NovelEditorAddToLibraryBanner extends StatelessWidget {
  const NovelEditorAddToLibraryBanner({super.key, required this.onAdd});

  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Material(
      color: colors.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(RevericRadius.pill),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.only(
          left: RevericSpacing.xl,
          right: RevericSpacing.sm,
          top: RevericSpacing.sm,
          bottom: RevericSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RevericRadius.pill),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.auto_awesome,
              size: 18,
              color: colors.accent,
            ),
            const SizedBox(width: RevericSpacing.md),
            Flexible(
              child: Text(
                context.t(LocaleKeys.libraryDraftShelfHint),
                style: typo.uiSmall.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: RevericSpacing.lg),
            Material(
              color: colors.accent,
              borderRadius: BorderRadius.circular(RevericRadius.pill),
              child: InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(RevericRadius.pill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.lg,
                    vertical: RevericSpacing.sm,
                  ),
                  child: Text(
                    context.t(LocaleKeys.libraryAddToLibrary),
                    style: typo.uiSmallSemibold.copyWith(
                      color: colors.onAccent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
