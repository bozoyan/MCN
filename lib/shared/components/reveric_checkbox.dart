// 职责: 统一复选框的主题外观、禁用反馈和跨平台点击区域，保留原生键盘与无障碍交互。
// 关联文件:
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../theme/theme.dart';

class RevericCheckbox extends StatelessWidget {
  const RevericCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.indeterminate = false,
  });

  final bool value;
  final bool indeterminate;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final mobile = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };

    return Checkbox(
      value: indeterminate ? null : value,
      tristate: indeterminate,
      onChanged: onChanged == null
          ? null
          : (next) => onChanged!(indeterminate ? true : next!),
      semanticLabel: semanticLabel,
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return states.contains(WidgetState.disabled)
            ? colors.textSubtle
            : colors.accent;
      }),
      checkColor: onChanged == null ? colors.surface : colors.onAccent,
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return BorderSide.none;
        }
        final color = states.contains(WidgetState.disabled)
            ? colors.textSubtle
            : states.contains(WidgetState.focused)
            ? colors.accent
            : colors.textMuted;
        return BorderSide(color: color, width: RevericSizes.dividerThickness);
      }),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RevericRadius.small),
      ),
      materialTapTargetSize: mobile
          ? MaterialTapTargetSize.padded
          : MaterialTapTargetSize.shrinkWrap,
      visualDensity: mobile ? VisualDensity.standard : VisualDensity.compact,
    );
  }
}
