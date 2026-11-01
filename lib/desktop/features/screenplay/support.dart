// 职责: 桌面剧本区域共享的标签格式化与轻量命名弹窗。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/desktop/features/screenplay/context_panel.dart
//   lib/desktop/features/screenplay/scenes.dart
//   lib/shared/models/screenplay.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';

import '../../../shared/components/reveric_text_field.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_button.dart';

export '../../../shared/widgets/screenplay/labels.dart';

Future<String?> showScreenplayNameDialog(
  BuildContext context, {
  required String title,
  required String label,
}) async {
  final controller = TextEditingController();
  final result = await showRevericDialog<String>(
    context: context,
    builder: (dialogContext) => RevericDialog(
      title: title,
      content: RevericTextField(
        controller: controller,
        autofocus: true,
        label: label,
        onSubmitted: (_) {
          final value = controller.text.trim();
          if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
        },
      ),
      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        RevericButton.primary(
          label: context.t(LocaleKeys.commonCreate),
          onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
          },
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
