// 职责: 阅读模式背景主题调色板 — 将 ReadingBackgroundTheme 映射为背景/文字/分隔色，供 desktop 与 mobile reader 复用。
// 关联文件:
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/reading/reading_content_view.dart
//   lib/shared/theme/theme.dart

import 'package:flutter/material.dart';

import '../../providers/settings_providers.dart';

/// 阅读模式配色快照：背景、正文、次要文字、分隔线、章节标题。
class ReadingPalette {
  const ReadingPalette({
    required this.background,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.chapterTitle,
    required this.iconColor,
    required this.controlSurface,
    required this.isDark,
  });

  /// 阅读区背景色。
  final Color background;

  /// 正文文字颜色。
  final Color textPrimary;

  /// 次要文字（章节进度、目录等）颜色。
  final Color textSecondary;

  /// 分隔线颜色。
  final Color divider;

  /// 章节标题颜色。
  final Color chapterTitle;

  /// 工具栏图标颜色。
  final Color iconColor;

  /// 阅读控制栏与目录当前项的浅层表面色。
  final Color controlSurface;

  /// 是否为暗色主题（影响状态栏图标亮度）。
  final bool isDark;

  /// 根据背景主题返回对应调色板。
  factory ReadingPalette.of(ReadingBackgroundTheme theme) {
    switch (theme) {
      case ReadingBackgroundTheme.white:
        return const ReadingPalette(
          background: Color(0xFFFFFFFF),
          textPrimary: Color(0xFF1F1F1F),
          textSecondary: Color(0xFF6B6B6B),
          divider: Color(0xFFE5E5E5),
          chapterTitle: Color(0xFF111111),
          iconColor: Color(0xFF3D3D3D),
          controlSurface: Color(0xFFF5F5F5),
          isDark: false,
        );
      case ReadingBackgroundTheme.sepia:
        return const ReadingPalette(
          background: Color(0xFFF4ECD8),
          textPrimary: Color(0xFF5B4636),
          textSecondary: Color(0xFF8C7B68),
          divider: Color(0xFFE0D5BC),
          chapterTitle: Color(0xFF3D2F23),
          iconColor: Color(0xFF5B4636),
          controlSurface: Color(0xFFEBE0C6),
          isDark: false,
        );
      case ReadingBackgroundTheme.cream:
        return const ReadingPalette(
          background: Color(0xFFFBF7EE),
          textPrimary: Color(0xFF2A2A2A),
          textSecondary: Color(0xFF7A7468),
          divider: Color(0xFFEDE6D6),
          chapterTitle: Color(0xFF1A1A1A),
          iconColor: Color(0xFF3D3830),
          controlSurface: Color(0xFFF4EEDF),
          isDark: false,
        );
      case ReadingBackgroundTheme.eye_care:
        return const ReadingPalette(
          background: Color(0xFFEAF4DC),
          textPrimary: Color(0xFF344129),
          textSecondary: Color(0xFF66745A),
          divider: Color(0xFFD5E2C8),
          chapterTitle: Color(0xFF40552F),
          iconColor: Color(0xFF475B36),
          controlSurface: Color(0xFFDDE9CE),
          isDark: false,
        );
      case ReadingBackgroundTheme.dark:
        return const ReadingPalette(
          background: Color(0xFF1E1E1E),
          textPrimary: Color(0xFFD8D8D8),
          textSecondary: Color(0xFF9A9A9A),
          divider: Color(0xFF333333),
          chapterTitle: Color(0xFFEDEDED),
          iconColor: Color(0xFFC8C8C8),
          controlSurface: Color(0xFF292929),
          isDark: true,
        );
      case ReadingBackgroundTheme.night:
        return const ReadingPalette(
          background: Color(0xFF0A0A0A),
          textPrimary: Color(0xFFB8B8B8),
          textSecondary: Color(0xFF707070),
          divider: Color(0xFF1F1F1F),
          chapterTitle: Color(0xFFCCCCCC),
          iconColor: Color(0xFFA0A0A0),
          controlSurface: Color(0xFF161616),
          isDark: true,
        );
    }
  }

  /// 状态栏图标亮度（Brightness）。
  Brightness get iconBrightness => isDark ? Brightness.light : Brightness.dark;
}
