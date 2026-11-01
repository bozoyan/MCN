// 职责: Reveric 通用自定义颜色弹窗 — HSV 色盘 + hex 输入，取消返回 null
// 关联文件:
//   lib/shared/widgets/settings/editor_settings_section.dart
//   lib/desktop/features/canvas/widgets/canvas_node_color_picker.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';

/// 弹出颜色选择弹窗；保存返回所选颜色，取消或点空白处返回 null。
Future<Color?> showRevericColorPickerDialog({
  required BuildContext context,
  required Color initialColor,
  bool enableAlpha = true,
}) {
  var pending = initialColor;
  return showDialog<Color>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        contentPadding: const EdgeInsets.all(RevericSpacing.lg),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pending,
            onColorChanged: (c) => pending = c,
            enableAlpha: enableAlpha,
            hexInputBar: true,
            portraitOnly: true,
            paletteType: PaletteType.hsvWithHue,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.t(LocaleKeys.commonCancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(pending),
            child: Text(context.t(LocaleKeys.commonSave)),
          ),
        ],
      );
    },
  );
}
