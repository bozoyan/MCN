// 职责: 系统 UI 服务 — 统一切换跨平台沉浸式全屏与普通系统栏。
// 关联文件:
//   lib/shared/components/fullscreen_system_ui.dart
//   android/app/src/main/kotlin/ai/reveric/MainActivity.kt

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final systemUiServiceProvider = Provider<SystemUiService>((ref) {
  return const SystemUiService();
});

class SystemUiService {
  const SystemUiService();

  static const MethodChannel _channel = MethodChannel('reveric/system_ui');

  Future<void> enterFullscreen() {
    return _setFullscreen(enabled: true);
  }

  Future<void> exitFullscreen() {
    return _setFullscreen(enabled: false);
  }

  void setOverlayStyle(SystemUiOverlayStyle style) {
    SystemChrome.setSystemUIOverlayStyle(style);
  }

  Future<void> _setFullscreen({required bool enabled}) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _channel.invokeMethod<void>('setFullscreen', {'enabled': enabled});
    }
    return SystemChrome.setEnabledSystemUIMode(
      enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }
}
