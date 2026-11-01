// 职责: 解析内置主题与受校验的自定义颜色覆盖，供所有窗口共用。
// 关联文件:
//   lib/shared/theme/reveric_colors.dart
//   lib/shared/theme/reveric_theme.dart
//   lib/shared/services/themes_orchestrator.dart
import 'package:flutter/material.dart';
import 'reveric_colors.dart';
import 'reveric_theme.dart';

const builtinThemePalettes = <String, (RevericThemeData, RevericThemeData)>{
  'reveric': (RevericThemeData.reveric, RevericThemeData.revericDark),
  'classic': (RevericThemeData.classic, RevericThemeData.classicDark),
  'ivory': (RevericThemeData.ivory, RevericThemeData.ivoryDark),
};

const editableThemeColorNames = <String>{
  'canvas',
  'surface',
  'surfaceDim',
  'surfaceContainer',
  'surfaceContainerHigh',
  'border',
  'borderSubtle',
  'borderInput',
  'textPrimary',
  'textSecondary',
  'textMuted',
  'textSubtle',
  'accent',
  'accentWarm',
  'accentAmber',
  'selected',
  'hover',
  'blockquoteBorder',
  'onAccent',
  'textTertiary',
};

Map<String, String> themeColorValues(RevericColors colors) => {
  'canvas':
      '#${colors.canvas.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'surface':
      '#${colors.surface.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'surfaceDim':
      '#${colors.surfaceDim.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'surfaceContainer':
      '#${colors.surfaceContainer.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'surfaceContainerHigh':
      '#${colors.surfaceContainerHigh.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'border':
      '#${colors.border.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'borderSubtle':
      '#${colors.borderSubtle.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'borderInput':
      '#${colors.borderInput.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'textPrimary':
      '#${colors.textPrimary.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'textSecondary':
      '#${colors.textSecondary.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'textMuted':
      '#${colors.textMuted.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'textSubtle':
      '#${colors.textSubtle.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'accent':
      '#${colors.accent.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'accentWarm':
      '#${colors.accentWarm.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'accentAmber':
      '#${colors.accentAmber.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'selected':
      '#${colors.selected.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'hover':
      '#${colors.hover.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'deletionBg':
      '#${colors.deletionBg.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'deletionBorder':
      '#${colors.deletionBorder.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'additionBg':
      '#${colors.additionBg.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'additionBorder':
      '#${colors.additionBorder.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'warningBg':
      '#${colors.warningBg.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'warningText':
      '#${colors.warningText.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'success':
      '#${colors.success.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'error':
      '#${colors.error.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'blockquoteBorder':
      '#${colors.blockquoteBorder.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'onAccent':
      '#${colors.onAccent.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  'textTertiary':
      '#${colors.textTertiary.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
};

RevericThemeData resolveThemePalette({
  required String baseTheme,
  required Brightness brightness,
  Map<String, String> overrides = const {},
}) {
  final pair = builtinThemePalettes[baseTheme];
  if (pair == null) {
    throw FormatException('baseTheme must name a built-in theme.');
  }
  for (final entry in overrides.entries) {
    if (!editableThemeColorNames.contains(entry.key) ||
        !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(entry.value)) {
      throw FormatException(
        'Invalid theme color: ${entry.key}. Use an editable token and #RRGGBB.',
      );
    }
  }
  final base = brightness == Brightness.dark ? pair.$2 : pair.$1;
  if (overrides.isEmpty) {
    return base;
  }
  final c = base.colors;
  Color color(String key, Color fallback) {
    final value = overrides[key];
    return value == null
        ? fallback
        : Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
  }

  return RevericThemeData(
    brightness: brightness,
    typography: base.typography,
    colors: RevericColors(
      brightness: brightness,
      canvas: color('canvas', c.canvas),
      surface: color('surface', c.surface),
      surfaceDim: color('surfaceDim', c.surfaceDim),
      surfaceContainer: color('surfaceContainer', c.surfaceContainer),
      surfaceContainerHigh: color(
        'surfaceContainerHigh',
        c.surfaceContainerHigh,
      ),
      border: color('border', c.border),
      borderSubtle: color('borderSubtle', c.borderSubtle),
      borderInput: color('borderInput', c.borderInput),
      textPrimary: color('textPrimary', c.textPrimary),
      textSecondary: color('textSecondary', c.textSecondary),
      textMuted: color('textMuted', c.textMuted),
      textSubtle: color('textSubtle', c.textSubtle),
      accent: color('accent', c.accent),
      accentWarm: color('accentWarm', c.accentWarm),
      accentAmber: color('accentAmber', c.accentAmber),
      selected: color('selected', c.selected),
      hover: color('hover', c.hover),
      deletionBg: color('deletionBg', c.deletionBg),
      deletionBorder: color('deletionBorder', c.deletionBorder),
      additionBg: color('additionBg', c.additionBg),
      additionBorder: color('additionBorder', c.additionBorder),
      warningBg: color('warningBg', c.warningBg),
      warningText: color('warningText', c.warningText),
      success: color('success', c.success),
      error: color('error', c.error),
      blockquoteBorder: color('blockquoteBorder', c.blockquoteBorder),
      onAccent: color('onAccent', c.onAccent),
      textTertiary: color('textTertiary', c.textTertiary),
    ),
  );
}

/// 只拦截新覆盖导致的低对比度，不追溯修改已有内置主题。
void validateThemeContrast(
  String baseTheme,
  Brightness brightness,
  Map<String, String> overrides,
) {
  final colors = themeColorValues(
    resolveThemePalette(
      baseTheme: baseTheme,
      brightness: brightness,
      overrides: overrides,
    ).colors,
  );
  for (final pair in [
    ('textPrimary', 'canvas'),
    ('textPrimary', 'surface'),
    ('textPrimary', 'surfaceDim'),
    ('textPrimary', 'surfaceContainer'),
    ('textPrimary', 'surfaceContainerHigh'),
    ('textPrimary', 'selected'),
    ('textPrimary', 'hover'),
    ('onAccent', 'accent'),
  ]) {
    if (!overrides.containsKey(pair.$1) && !overrides.containsKey(pair.$2)) {
      continue;
    }
    double luminance(String key) => Color(
      0xFF000000 | int.parse(colors[key]!.substring(1), radix: 16),
    ).computeLuminance();
    final a = luminance(pair.$1);
    final b = luminance(pair.$2);
    final contrast = ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
    if (contrast < 4.5) {
      throw FormatException(
        '${brightness.name}: ${pair.$1}/${pair.$2} contrast ${contrast.toStringAsFixed(2)} is below 4.5.',
      );
    }
  }
}
