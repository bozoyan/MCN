// 职责: 在移动端底部弹层中呈现共享导出表单与固定操作区。
// 关联文件:
//   lib/shared/widgets/novel_export_form.dart
//   lib/mobile/widgets/sheet.dart
//   lib/mobile/pages/library_page.dart
//   lib/shared/components/dialog_feedback.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';

import '../../shared/components/dialog_feedback.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/novel.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/novel_export_form.dart';
import 'sheet.dart';

Future<void> showNovelExportSheet(BuildContext context, Novel novel) {
  final theme = RevericTheme.of(context);
  return showMobileSheet<void>(
    context: context,
    builder: (_) => RevericTheme(
      data: theme,
      child: DialogFeedback.scope(
        builder: (_) => NovelExportForm(
          novel: novel,
          usesNativeSaveSheet: true,
          showNovelTitle: false,
          shellBuilder: (context, content, actions) => MobileSheetScaffold(
            showHeaderDivider: false,
            header: MobileSheetHeader(
              title: context.t(LocaleKeys.libraryExportNovel),
              subtitle: novel.title,
              leading: Container(
                width: RevericSizes.fieldHeight,
                height: RevericSizes.fieldHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colors.surfaceDim,
                  borderRadius: BorderRadius.circular(RevericRadius.large),
                ),
                child: RevericIcon(
                  RevericIcons.download,
                  size: RevericSizes.iconButtonIconSize,
                  color: theme.colors.textMuted,
                ),
              ),
            ),
            footer: Row(
              children: [
                for (final (index, action) in actions.indexed) ...[
                  if (index > 0) const SizedBox(width: RevericSpacing.sm),
                  Expanded(child: action),
                ],
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.lg,
                0,
                RevericSpacing.lg,
                RevericSpacing.lg,
              ),
              child: content,
            ),
          ),
        ),
      ),
    ),
  );
}
