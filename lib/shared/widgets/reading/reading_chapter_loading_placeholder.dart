// 职责: 以短淡入的文本骨架占位展示尚未加载完成的阅读章节。
// 关联文件:
//   lib/shared/widgets/reading/reading_theme_palette.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'reading_theme_palette.dart';

class ReadingChapterLoadingPlaceholder extends StatelessWidget {
  const ReadingChapterLoadingPlaceholder({
    super.key,
    required this.padding,
    required this.palette,
    required this.fontSize,
    required this.lineHeight,
  });

  final EdgeInsetsGeometry padding;
  final ReadingPalette palette;
  final int fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    final lineHeightValue = fontSize * lineHeight;
    return Padding(
      padding: padding,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0, end: 0.52),
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReadingLoadingLine(
                widthFactor: 0.42,
                height: lineHeightValue * 0.9,
                color: palette.textSecondary,
              ),
              SizedBox(height: lineHeightValue * 1.8),
              _ReadingLoadingLine(
                widthFactor: 0.94,
                height: lineHeightValue * 0.72,
                color: palette.textPrimary,
              ),
              SizedBox(height: lineHeightValue * 0.72),
              _ReadingLoadingLine(
                widthFactor: 0.78,
                height: lineHeightValue * 0.72,
                color: palette.textPrimary,
              ),
              SizedBox(height: lineHeightValue * 0.72),
              _ReadingLoadingLine(
                widthFactor: 0.88,
                height: lineHeightValue * 0.72,
                color: palette.textPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingLoadingLine extends StatelessWidget {
  const _ReadingLoadingLine({
    required this.widthFactor,
    required this.height,
    required this.color,
  });

  final double widthFactor;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(RevericRadius.small),
        ),
        child: SizedBox(height: height),
      ),
    );
  }
}
