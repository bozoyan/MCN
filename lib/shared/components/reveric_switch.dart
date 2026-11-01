// 职责: Reveric 开关控件 — 提供统一的紧凑 switch 外观。
// 关联文件:
//   lib/shared/theme/theme.dart
//   lib/desktop/widgets/settings/settings_dialog.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

class RevericSwitch extends StatelessWidget {
  const RevericSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.8,
      child: Switch(value: value, onChanged: onChanged),
    );
  }
}
