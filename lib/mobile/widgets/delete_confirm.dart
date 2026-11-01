// 职责: 移动端「删除条目」确认弹窗 — 基于 [showConfirmDialog] 的薄封装。
// 关联文件:
//   lib/shared/widgets/confirm_dialog.dart
//   lib/mobile/widgets/section_scaffold.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/widgets/confirm_dialog.dart';

/// 弹出删除确认对话框。[title] 为被删条目的标题（空则回退到「未命名」）。
/// [blockedReason] 见 [ConfirmDialog.blockedReason]。
/// 返回 `true` 表示用户确认删除。
Future<bool> showMobileDeleteConfirm(
  BuildContext context, {
  required String title,
  Future<String?>? blockedReason,
}) {
  final displayTitle = title.trim().isEmpty
      ? context.t(LocaleKeys.commonUntitled)
      : title.trim();
  return showConfirmDialog(
    context,
    title: context.t(LocaleKeys.commonDelete),
    message: context.t(
      LocaleKeys.mobileEditorDeleteEntryMessage,
      namedArgs: {'title': displayTitle},
    ),
    confirmLabel: context.t(LocaleKeys.commonDelete),
    variant: ConfirmDialogVariant.error,
    blockedReason: blockedReason,
  );
}

/// 弹出删除文件夹确认对话框，说明会连同目录内全部内容一起删除。
Future<bool> showMobileDeleteFolderConfirm(
  BuildContext context, {
  required String title,
}) {
  final displayTitle = title.trim().isEmpty
      ? context.t(LocaleKeys.workspaceUntitledFolder)
      : title.trim();
  return showConfirmDialog(
    context,
    title: context.t(LocaleKeys.commonDelete),
    message: context.t(
      LocaleKeys.mobileEditorDeleteFolderMessage,
      namedArgs: {'title': displayTitle},
    ),
    confirmLabel: context.t(LocaleKeys.commonDelete),
    variant: ConfirmDialogVariant.error,
  );
}
