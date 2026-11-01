// 职责: 验证 Reveric 跨端主题的字体契约与开关状态对比度。
// 关联文件:
//   lib/shared/theme/reveric_theme.dart
//   lib/shared/theme/reveric_typography.dart
//   designs/SYSTEM.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  const presets = {
    'classic': RevericThemeData.classic,
    'classicDark': RevericThemeData.classicDark,
    'ivory': RevericThemeData.ivory,
    'ivoryDark': RevericThemeData.ivoryDark,
    'reveric': RevericThemeData.reveric,
    'revericDark': RevericThemeData.revericDark,
  };

  for (final preset in presets.entries) {
    test('${preset.key} switch thumb remains visible in both states', () {
      final theme = preset.value.toThemeData().switchTheme;
      for (final selected in [false, true]) {
        final states = <WidgetState>{if (selected) WidgetState.selected};
        final thumb = theme.thumbColor!.resolve(states)!;
        final track = theme.trackColor!.resolve(states)!;
        final luminances = [thumb.computeLuminance(), track.computeLuminance()]
          ..sort();
        final contrast = (luminances.last + 0.05) / (luminances.first + 0.05);

        expect(
          contrast,
          greaterThanOrEqualTo(3),
          reason: 'Switch thumb must be distinguishable; selected=$selected',
        );
      }
    });
  }

  test('default theme keeps Georgia only for manuscript prose tokens', () {
    final themeData = RevericThemeData.reveric;
    final theme = themeData.toThemeData();

    expect(themeData.typography.body.fontFamily, 'Georgia');
    // Georgia 无中文字形，macOS 与 Windows 都要能落到宋体。
    expect(
      themeData.typography.body.fontFamilyFallback,
      containsAll(<String>['Songti SC', 'SimSun']),
    );
    expect(theme.textTheme.displayLarge?.fontFamily, isNot('Georgia'));
    expect(theme.textTheme.headlineMedium?.fontFamily, isNot('Georgia'));
    // Material 输入框默认取 bodyLarge，属于界面元素。
    expect(theme.textTheme.bodyLarge?.fontFamily, isNot('Georgia'));
    expect(theme.textTheme.bodyMedium?.fontFamily, isNot('Georgia'));
    expect(theme.textTheme.labelLarge?.fontFamily, isNot('Georgia'));
  });

  test('mobile typography does not pin mobile text to Georgia', () {
    final themeData = RevericThemeData.reveric.copyWith(
      typography: RevericTypography.mobile,
    );
    final theme = themeData.toThemeData(fontFamily: null);

    expect(theme.textTheme.displayLarge?.fontFamily, isNot('Georgia'));
    expect(theme.textTheme.headlineMedium?.fontFamily, isNot('Georgia'));
    expect(theme.textTheme.bodyLarge?.fontFamily, isNot('Georgia'));
    expect(themeData.typography.body.fontFamily, isNull);
    expect(themeData.typography.bodyItalic.fontFamily, isNull);
    expect(themeData.typography.ui.fontFamily, isNull);
    expect(themeData.typography.display.fontSize, 22);
    expect(themeData.typography.heading2.fontSize, 18);
    expect(themeData.typography.body.fontSize, 14);
    expect(themeData.typography.bodySmall.fontSize, 12);
    expect(themeData.typography.ui.fontSize, 13);
  });
}
