// 职责: 在桌面对话框中呈现共享导出表单。
// 关联文件:
//   lib/shared/widgets/novel_export_form.dart
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/dialog_feedback.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../shared/components/dialog_feedback.dart';
import '../../shared/components/reveric_dialog.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/novel.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/novel_export_form.dart';

Future<void> showNovelExportDialog(BuildContext context, Novel novel) {
  return showRevericDialog<void>(
    context: context,
    builder: (_) =>
        DialogFeedback.scope(builder: (_) => NovelExportDialog(novel: novel)),
  );
}

class NovelExportDialog extends StatelessWidget {
  const NovelExportDialog({super.key, required this.novel});

  final Novel novel;

  @override
  Widget build(BuildContext context) {
    return NovelExportForm(
      novel: novel,
      usesNativeSaveSheet: false,
      shellBuilder: (context, content, actions) => RevericDialog.panel(
        title: Text(context.t(LocaleKeys.libraryExportNovel)),
        content: content,
        actions: actions,
        width: 520 + RevericSpacing.x4l * 2,
      ),
    );
  }
}
