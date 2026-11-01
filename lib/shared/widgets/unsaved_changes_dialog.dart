// 职责: 未保存变更确认弹窗 — 提供统一的取消/丢弃/保存三选一样式与决策枚举。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/localization/app_localization.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:flutter/material.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';
import '../components/reveric_dialog.dart';
import '../components/reveric_button.dart';

enum UnsavedChangesDecision { save, discard }

Future<UnsavedChangesDecision?> showUnsavedChangesDialog({
  required BuildContext context,
  required String titleKey,
  required String messageKey,
  bool showSave = true,
}) {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);
  return showRevericDialog<UnsavedChangesDecision>(
    context: context,
    builder: (dialogContext) {
      return RevericDialog(
        title: context.t(titleKey),
        content: Text(context.t(messageKey)),
        actions: [
          RevericButton.secondary(
            label: context.t(LocaleKeys.commonCancel),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(UnsavedChangesDecision.discard),
            child: Text(
              context.t(LocaleKeys.commonDiscard),
              style: typo.ui.copyWith(color: colors.warningText),
            ),
          ),
          if (showSave)
            RevericButton.primary(
              label: context.t(LocaleKeys.commonSave),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(UnsavedChangesDecision.save),
            ),
        ],
      );
    },
  );
}
