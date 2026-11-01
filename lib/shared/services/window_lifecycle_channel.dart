// 职责: 读取 macOS 原生窗口/应用可见性实况，并请求把它回灌给 Flutter 引擎
// 关联文件:
//   macos/Runner/MainFlutterWindow.swift
//   lib/shared/services/lifecycle_visibility_guard.dart
//   lib/main.dart
import 'package:flutter/services.dart';

/// 一次原生可见性采样。
///
/// [windowVisible]（`NSWindow.isVisible`）区分不出遮挡 —— 被别的应用完全盖住时它
/// 依然是 true。[appOcclusionVisible] 能区分，但它由窗口服务器**异步**更新，窗口
/// order in 之后会滞后一段时间才变 true，滞后期内它是假阴性。所以两者都不能单独
/// 当可见性真值用，判据见 [shouldBeRendering]。
class WindowVisibilitySnapshot {
  const WindowVisibilitySnapshot({
    required this.appOcclusionVisible,
    required this.appActive,
    required this.windowVisible,
    required this.windowMiniaturized,
    required this.windowKey,
    required this.windowOcclusionVisible,
    required this.reseeded,
  });

  factory WindowVisibilitySnapshot.fromMap(Map<Object?, Object?> map) {
    bool read(String key) => map[key] == true;
    return WindowVisibilitySnapshot(
      appOcclusionVisible: read('appOcclusionVisible'),
      appActive: read('appActive'),
      windowVisible: read('windowVisible'),
      windowMiniaturized: read('windowMiniaturized'),
      windowKey: read('windowKey'),
      windowOcclusionVisible: read('windowOcclusionVisible'),
      reseeded: read('reseeded'),
    );
  }

  /// NSApp 认为应用至少有一部分像素在屏幕上。
  final bool appOcclusionVisible;
  final bool appActive;

  /// `NSWindow.isVisible` —— 被完全遮挡时依然为 true，不能当可见性真值用。
  final bool windowVisible;
  final bool windowMiniaturized;
  final bool windowKey;
  final bool windowOcclusionVisible;

  /// 本次调用是否真的把状态回灌给了引擎（`getVisibilityState` 恒为 false）。
  final bool reseeded;

  /// 窗口确实应该出帧。
  ///
  /// 判据按证据强度分三层，而不是一路 `&&` 到底 —— 后者会被 [appOcclusionVisible]
  /// 的假阴性一票否决，正是守卫在启动期漏纠正的原因：
  ///
  /// 1. 窗口没 order in 或已最小化 —— 不可见的**确凿**证据，直接停帧。
  /// 2. 应用 active 且本窗口是 key window —— 可见的**确凿**证据。前台且持有键盘焦点
  ///    的窗口物理上不可能被别的窗口盖住，此时 occlusion 的 false 只可能是它自己还
  ///    没更新完，不予采信。
  /// 3. 其余情况（应用在后台）才轮到 [appOcclusionVisible] 说话 —— 这时它是可信的，
  ///    也只有靠它才能区分「切到别的应用」和「窗口仍露在外面」。
  bool get shouldBeRendering {
    if (!windowVisible || windowMiniaturized) {
      return false;
    }
    if (appActive && windowKey) {
      return true;
    }
    return appOcclusionVisible;
  }

  @override
  String toString() =>
      'appOcclusionVisible=$appOcclusionVisible appActive=$appActive '
      'windowVisible=$windowVisible windowMiniaturized=$windowMiniaturized '
      'windowKey=$windowKey windowOcclusionVisible=$windowOcclusionVisible '
      'reseeded=$reseeded';
}

/// `reveric/window_lifecycle` 的封装。仅 macOS Runner 实现了该 channel。
class WindowLifecycleChannel {
  WindowLifecycleChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('reveric/window_lifecycle');

  final MethodChannel _channel;

  /// 让引擎重新读取 NSApp 的 occlusion / active 状态，并返回本次原生实况。
  ///
  /// 引擎内部据实分支，因此真被遮挡时不会被推成错误的可见状态。
  Future<WindowVisibilitySnapshot> reseedEngineVisibility() =>
      _invoke('reseedEngineVisibility');

  /// 只采样，不回灌。
  Future<WindowVisibilitySnapshot> getVisibilityState() =>
      _invoke('getVisibilityState');

  Future<WindowVisibilitySnapshot> _invoke(String method) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(method);
    if (result == null) {
      throw PlatformException(
        code: 'empty_response',
        message: 'reveric/window_lifecycle.$method returned null.',
      );
    }
    return WindowVisibilitySnapshot.fromMap(result);
  }
}
