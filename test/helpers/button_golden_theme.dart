// 职责: 为按钮黄金图注入已加载的真实字体，避免 ButtonStyle 使用测试环境的 Ahem 占位字形。
// 关联文件:
//   test/shared/components/reveric_button_golden_test.dart
//   test/shared/widgets/update/about_settings_test.dart
//   test/desktop/widgets/agent_management/agent_rule_copy_dialog_golden_test.dart
import 'package:flutter/material.dart';

ThemeData withGoldenButtonFont(
  ThemeData theme, {
  String family = 'ButtonTest',
}) {
  ButtonStyle apply(ButtonStyle style) => style.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) =>
          style.textStyle!.resolve(states)!.copyWith(fontFamily: family),
    ),
  );
  return theme.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: apply(theme.filledButtonTheme.style!),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: apply(theme.outlinedButtonTheme.style!),
    ),
    textButtonTheme: TextButtonThemeData(
      style: apply(theme.textButtonTheme.style!),
    ),
  );
}
