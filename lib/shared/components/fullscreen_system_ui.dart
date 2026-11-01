// 职责: 全屏系统 UI 组件 — 在页面生命周期内启用沉浸式全屏并应用系统栏样式。
// 关联文件:
//   lib/shared/services/system_ui_service.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../services/system_ui_service.dart';

class FullscreenSystemUi extends HookConsumerWidget {
  const FullscreenSystemUi({
    super.key,
    required this.overlayStyle,
    required this.child,
  });

  final SystemUiOverlayStyle overlayStyle;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemUi = ref.read(systemUiServiceProvider);

    useEffect(() {
      unawaited(systemUi.enterFullscreen());
      return () {
        unawaited(systemUi.exitFullscreen());
      };
    }, [systemUi]);

    useEffect(() {
      systemUi.setOverlayStyle(overlayStyle);
      return null;
    }, [systemUi, overlayStyle]);

    return child;
  }
}
