// 职责: 应用全局背景 — 根据设置渲染纯色或图片背景层，供桌面窗口框架复用。
// 关联文件:
//   lib/shared/providers/settings_providers.dart
//   lib/desktop/widgets/desktop_window_frame.dart
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/settings_providers.dart';
import '../theme/theme.dart';

/// 是否已配置全局背景（纯色主题色或图片）。
final appBackgroundActiveProvider = Provider<bool>((ref) {
  final imagePath = ref.watch(appBackgroundImagePathProvider);
  final theme = ref.watch(appBackgroundThemeProvider);
  return theme != null || imagePath.isNotEmpty;
});

Color appChromeBackgroundColor(
  RevericColors colors,
  bool appBackgroundActive,
  Color fallback,
) {
  if (appBackgroundActive) {
    return Colors.transparent;
  }
  return fallback;
}

Color appScaffoldBackgroundColor(
  RevericColors colors,
  bool appBackgroundActive,
) {
  return appChromeBackgroundColor(colors, appBackgroundActive, colors.canvas);
}

Color appSidebarBackgroundColor(
  RevericColors colors,
  bool appBackgroundActive,
) {
  return appChromeBackgroundColor(
    colors,
    appBackgroundActive,
    colors.surfaceDim,
  );
}

/// 启用全局背景时 elevated 卡片/面板的默认毛玻璃 alpha。
const double appElevatedGlassAlpha = 0.85;

/// Elevated 层背景：无全局背景时用 [fallback]；启用时用 fallback 的半透明毛玻璃。
Color appElevatedBackgroundColor(
  RevericColors colors,
  bool appBackgroundActive,
  Color fallback, {
  double alpha = appElevatedGlassAlpha,
}) {
  if (appBackgroundActive) {
    return fallback.withValues(alpha: alpha);
  }
  return fallback;
}

/// 仅渲染背景层，不含前景内容。
class AppBackgroundLayer extends ConsumerWidget {
  const AppBackgroundLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagePath = ref.watch(appBackgroundImagePathProvider);
    final fit = ref.watch(appBackgroundFitProvider);
    final backgroundTheme = ref.watch(appBackgroundThemeProvider);
    final colors = RevericTheme.colorsOf(context);
    final backgroundFile = File(imagePath);
    final hasAssetBackground = isAppBackgroundAsset(imagePath);
    final backgroundColor = backgroundTheme == null
        ? null
        : appBackgroundColorForTheme(
            backgroundTheme,
            brightness: colors.brightness,
          );
    final hasBackgroundImage =
        backgroundColor == null &&
        imagePath.isNotEmpty &&
        (hasAssetBackground || backgroundFile.existsSync());
    if (backgroundColor == null && !hasBackgroundImage) {
      return const SizedBox.expand();
    }

    final backgroundImageProvider = hasBackgroundImage
        ? ResizeImage(imageProviderForAppBackground(imagePath), width: 1440)
        : null;
    final useBlurredBackdrop =
        backgroundImageProvider != null && fit != AppBackgroundFit.cover;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (backgroundColor != null)
          ColoredBox(color: backgroundColor)
        else if (backgroundImageProvider != null) ...[
          if (useBlurredBackdrop)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Image(
                image: backgroundImageProvider,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ColoredBox(color: colors.canvas.withValues(alpha: 0.18)),
          Image(
            image: backgroundImageProvider,
            fit: boxFitForAppBackground(fit),
            width: double.infinity,
            height: double.infinity,
          ),
        ],
      ],
    );
  }
}

bool isAppBackgroundAsset(String path) {
  return path.startsWith('assets/images/background/');
}

ImageProvider imageProviderForAppBackground(String path) {
  if (isAppBackgroundAsset(path)) {
    return AssetImage(path);
  }
  return FileImage(File(path));
}

BoxFit boxFitForAppBackground(AppBackgroundFit fit) {
  return switch (fit) {
    AppBackgroundFit.cover => BoxFit.cover,
    AppBackgroundFit.contain => BoxFit.contain,
    AppBackgroundFit.fill => BoxFit.fill,
  };
}
