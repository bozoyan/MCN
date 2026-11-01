// 职责: 定义 Reveric 文字样式 token，并提供桌面（标题无衬线、正文 Georgia）与移动端系统字体两套排版预设。
// 关联文件:
//   lib/shared/theme/reveric_theme.dart
//   designs/SYSTEM.md
import 'package:flutter/material.dart';

class RevericTypography {
  final TextStyle display;
  final TextStyle heading2;
  final TextStyle body;
  final TextStyle bodySmall;
  final TextStyle bodyItalic;
  final TextStyle ui;
  final TextStyle uiMedium;
  final TextStyle uiSemibold;
  final TextStyle uiSmall;
  final TextStyle uiSmallSemibold;
  final TextStyle uiTiny;
  final TextStyle uiTinySemibold;

  /// 等宽小字：用于要原样示人的机器文本 —— 提示词正文、批次 id、尺寸、
  /// 缩放百分比这类「不是给人读的散文」的内容。
  final TextStyle mono;

  const RevericTypography({
    required this.display,
    required this.heading2,
    required this.body,
    required this.bodySmall,
    required this.bodyItalic,
    required this.ui,
    required this.uiMedium,
    required this.uiSemibold,
    required this.uiSmall,
    required this.uiSmallSemibold,
    required this.uiTiny,
    required this.uiTinySemibold,
    required this.mono,
  });

  /// 标题（display / heading2）用系统无衬线并略收字距；Georgia 只留给
  /// 正在阅读或写作的正文（body 系列）。
  static const desktop = RevericTypography(
    display: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.5,
    ),
    heading2: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.3,
    ),
    body: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      fontFamily: 'Georgia',
      fontFamilyFallback: _manuscriptCjkFallback,
      height: 1.75,
    ),
    bodySmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      fontFamily: 'Georgia',
      fontFamilyFallback: _manuscriptCjkFallback,
      height: 1.5,
    ),
    bodyItalic: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      fontFamily: 'Georgia',
      fontFamilyFallback: _manuscriptCjkFallback,
      height: 1.75,
      fontStyle: FontStyle.italic,
    ),
    ui: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
    uiMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    uiSemibold: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    uiSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    uiSmallSemibold: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    uiTiny: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
    uiTinySemibold: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    mono: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w400,
      fontFamily: 'Menlo',
      fontFamilyFallback: ['Consolas', 'DejaVu Sans Mono', 'monospace'],
      height: 1.75,
    ),
  );

  /// Georgia 没有中文字形；按设计稿 `--font-serif` 让中文落到宋体，
  /// 依次覆盖 macOS（Songti SC / STSong）与 Windows（SimSun）。
  static const _manuscriptCjkFallback = ['Songti SC', 'STSong', 'SimSun'];

  static const mobile = RevericTypography(
    display: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: -0.4,
    ),
    heading2: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.2,
    ),
    body: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.55),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.45,
    ),
    bodyItalic: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.55,
      fontStyle: FontStyle.italic,
    ),
    ui: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
    uiMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    uiSemibold: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    uiSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    uiSmallSemibold: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    uiTiny: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
    uiTinySemibold: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    mono: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w400,
      fontFamily: 'Menlo',
      fontFamilyFallback: ['Consolas', 'DejaVu Sans Mono', 'monospace'],
      height: 1.75,
    ),
  );
}
