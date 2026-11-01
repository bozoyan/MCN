// 职责: 全局背景感知布局面 — chrome 壳、elevated 卡片、composer 工具栏的统一 Container 封装。
// 关联文件:
//   lib/shared/widgets/app_background.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../theme/theme.dart';
import '../widgets/app_background.dart';

/// 布局 chrome 壳 — 启用全局背景时透明，否则使用 [fallback]。
class RevericChrome extends ConsumerWidget {
  const RevericChrome({
    super.key,
    required this.fallback,
    this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.alignment,
    this.clipBehavior,
  });

  final Color fallback;
  final Widget? child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final AlignmentGeometry? alignment;
  final Clip? clipBehavior;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final active = ref.watch(appBackgroundActiveProvider);

    return Container(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      alignment: alignment,
      clipBehavior: clipBehavior ?? Clip.none,
      color: appChromeBackgroundColor(colors, active, fallback),
      child: child,
    );
  }
}

/// Elevated 卡片 — 默认无描边 + 柔和投影（深色改极淡描边）；启用全局背景时为毛玻璃（[appElevatedGlassAlpha]）。
class RevericElevatedCard extends ConsumerWidget {
  const RevericElevatedCard({
    super.key,
    required this.fallback,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.borderColor,
    this.gradientColors,
    this.width,
    this.height,
    this.clipBehavior,
    this.alignment,
    this.image,
  });

  final Color fallback;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final List<Color> Function(Color fill, bool appBackgroundActive)?
  gradientColors;
  final double? width;
  final double? height;
  final Clip? clipBehavior;
  final AlignmentGeometry? alignment;
  final DecorationImage? image;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final active = ref.watch(appBackgroundActiveProvider);
    final fill = appElevatedBackgroundColor(colors, active, fallback);
    final radius = borderRadius ?? BorderRadius.circular(RevericRadius.card);
    final border = borderColor ?? revericCardBorder(colors);
    final gradientBuilder = gradientColors;

    return Container(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      alignment: alignment,
      clipBehavior: clipBehavior ?? Clip.none,
      decoration: BoxDecoration(
        color: gradientBuilder == null ? fill : null,
        gradient: gradientBuilder == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientBuilder(fill, active),
              ),
        borderRadius: radius,
        border: Border.all(color: border),
        boxShadow: revericCardShadows(colors),
        image: image,
      ),
      child: child,
    );
  }
}

/// Elevated 可点击卡片 — [RevericElevatedCard] + [InkWell]。
class RevericElevatedInkWell extends ConsumerWidget {
  const RevericElevatedInkWell({
    super.key,
    required this.fallback,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.borderRadius,
    this.borderColor,
    this.width,
    this.height,
    this.alignment,
  });

  final Color fallback;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final active = ref.watch(appBackgroundActiveProvider);
    final fill = appElevatedBackgroundColor(colors, active, fallback);
    final radius = borderRadius ?? BorderRadius.circular(RevericRadius.card);
    final border = borderColor ?? revericCardBorder(colors);

    return Container(
      margin: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Ink(
            width: width,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
              border: Border.all(color: border),
              boxShadow: revericCardShadows(colors),
            ),
            child: alignment == null
                ? child
                : Align(alignment: alignment!, child: child),
          ),
        ),
      ),
    );
  }
}
