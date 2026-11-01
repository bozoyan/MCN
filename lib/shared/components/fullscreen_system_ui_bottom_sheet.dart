// 职责: 全屏系统栏 Bottom Sheet — 在弹层期间显示系统栏，关闭后恢复沉浸式页面。
// 关联文件:
//   lib/shared/components/fullscreen_system_ui.dart
//   lib/shared/services/system_ui_service.dart

import 'package:flutter/material.dart';

import '../services/system_ui_service.dart';

Future<T?> showFullscreenSystemUiBottomSheet<T>({
  required BuildContext context,
  required SystemUiService systemUi,
  required Color backgroundColor,
  required WidgetBuilder builder,
  BoxConstraints? constraints,
  ShapeBorder? shape,
  bool showDragHandle = true,
}) async {
  try {
    await systemUi.exitFullscreen();
    if (!context.mounted) {
      return null;
    }
    return await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: false,
      showDragHandle: showDragHandle,
      backgroundColor: backgroundColor,
      constraints: constraints,
      shape: shape,
      builder: builder,
    );
  } finally {
    if (context.mounted) {
      await systemUi.enterFullscreen();
    }
  }
}
