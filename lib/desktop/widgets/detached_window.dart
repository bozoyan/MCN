// 职责: 用 Flutter 原生多窗口承载编辑页的独立子窗口 — 管理创建、激活、关闭、布局持久化与主题。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_outline_window.dart
//   lib/desktop/features/reading/reading_window.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/logger/app_logger.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

// Flutter 原生多窗口仍是实验性内部 API；项目通过 .fvmrc 固定兼容 revision。
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_macos.dart';
import 'package:flutter/src/widgets/_window_win32.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/logger/app_logger.dart';
import '../../shared/providers/settings_providers.dart';
import '../../shared/theme/theme.dart';

@visibleForTesting
typedef DetachedWindowPlacement = ({Size size, Offset? position});

@visibleForTesting
DetachedWindowPlacement? decodeDetachedWindowPlacement(
  String? raw, {
  required Size minimumSize,
}) {
  if (raw == null) {
    return null;
  }
  try {
    final value = jsonDecode(raw);
    if (value is! Map) {
      return null;
    }
    final rawWidth = value['width'];
    final rawHeight = value['height'];
    if (rawWidth is! num || rawHeight is! num) {
      return null;
    }
    final width = rawWidth.toDouble();
    final height = rawHeight.toDouble();
    if (!width.isFinite ||
        !height.isFinite ||
        width < minimumSize.width ||
        height < minimumSize.height) {
      return null;
    }

    final rawX = value['x'];
    final rawY = value['y'];
    final x = rawX is num ? rawX.toDouble() : null;
    final y = rawY is num ? rawY.toDouble() : null;
    final position = x != null && y != null && x.isFinite && y.isFinite
        ? Offset(x, y)
        : null;
    return (size: Size(width, height), position: position);
  } on FormatException {
    return null;
  }
}

@visibleForTesting
String encodeDetachedWindowPlacement({required Size size, Offset? position}) {
  return jsonEncode(<String, double>{
    'width': size.width,
    'height': size.height,
    if (position != null) ...{'x': position.dx, 'y': position.dy},
  });
}

class _NativeWindowChannel {
  const _NativeWindowChannel();

  static const _channel = MethodChannel('reveric/window_position');

  bool get isSupported => Platform.isMacOS || Platform.isWindows;

  Future<Offset> get(WindowController controller) async {
    final value = await _channel.invokeMapMethod<String, Object?>(
      'getPosition',
      <String, Object?>{'windowHandle': _windowHandle(controller)},
    );
    final x = (value?['x'] as num?)?.toDouble();
    final y = (value?['y'] as num?)?.toDouble();
    if (x == null || y == null || !x.isFinite || !y.isFinite) {
      throw StateError('Native window position is missing or invalid.');
    }
    return Offset(x, y);
  }

  Future<void> setAlwaysOnTop(WindowController controller, bool value) {
    return _channel.invokeMethod<void>('setAlwaysOnTop', <String, Object?>{
      'windowHandle': _windowHandle(controller),
      'value': value,
    });
  }

  Future<void> set(WindowController controller, Offset position) {
    return _channel.invokeMethod<void>('setPosition', <String, Object?>{
      'windowHandle': _windowHandle(controller),
      'x': position.dx,
      'y': position.dy,
    });
  }

  int _windowHandle(WindowController controller) {
    if (Platform.isMacOS) {
      return (controller as BaseWindowControllerMacOS).windowHandle.address;
    }
    if (Platform.isWindows) {
      return (controller as BaseWindowControllerWin32).windowHandle.address;
    }
    throw UnsupportedError('Native window position is unsupported.');
  }
}

/// 子窗口沿用主窗口的主题与自定义配色；子窗口不显示应用背景图。
class DetachedWindowTheme {
  const DetachedWindowTheme({
    required this.theme,
    this.customBaseTheme,
    this.lightOverrides = const {},
    this.darkOverrides = const {},
    required this.themeMode,
  });

  factory DetachedWindowTheme.fromSettings(AppSettings? settings) {
    return DetachedWindowTheme(
      theme: settings?.theme ?? AppTheme.classic,
      customBaseTheme: settings?.customTheme?.baseTheme,
      lightOverrides: settings?.customTheme?.lightOverrides ?? const {},
      darkOverrides: settings?.customTheme?.darkOverrides ?? const {},
      themeMode: settings?.themeMode ?? AppThemeMode.light,
    );
  }

  final AppTheme theme;
  final String? customBaseTheme;
  final Map<String, String> lightOverrides;
  final Map<String, String> darkOverrides;
  final AppThemeMode themeMode;

  RevericThemeData themeDataForBrightness(Brightness brightness) {
    final useDark =
        themeMode == AppThemeMode.dark ||
        (themeMode == AppThemeMode.system && brightness == Brightness.dark);
    return resolveThemePalette(
      baseTheme: customBaseTheme ?? theme.name,
      brightness: useDark ? Brightness.dark : Brightness.light,
      overrides: useDark ? darkOverrides : lightOverrides,
    );
  }
}

class DetachedWindowPresentation {
  const DetachedWindowPresentation({
    required this.controller,
    required this.theme,
  });

  final WindowController controller;
  final DetachedWindowTheme theme;
}

/// 单个独立子窗口的生命周期。同一 session 同时最多一个原生窗口，
/// 再次 [open] 时复用并激活已有窗口。
class DetachedWindowSession {
  DetachedWindowSession({
    required this.placementKey,
    required this.defaultSize,
    required this.constraints,
    required String logModule,
  }) : _log = AppLogger.forModule(logModule);

  /// SharedPreferences 中保存窗口尺寸与位置的 key。
  final String placementKey;
  final Size defaultSize;
  final BoxConstraints constraints;

  // 实验性多窗口是 Windows 原生崩溃高发路径，窗口生命周期各节点写 checkpoint
  // 日志（立即落盘），崩溃后可据此定位死在哪个窗口操作之后。
  final ModuleLogger _log;
  final ValueNotifier<DetachedWindowPresentation?> _presentation =
      ValueNotifier(null);
  final ValueNotifier<bool> _alwaysOnTop = ValueNotifier(false);
  final _nativeWindow = const _NativeWindowChannel();

  bool _disposed = false;
  String _title = '';
  Future<void>? _opening;
  Timer? _placementSaveTimer;
  WindowController? _windowController;
  SharedPreferences? _preferences;
  Future<void> _placementSaveTail = Future<void>.value();
  Offset? _lastKnownWindowPosition;
  bool _closingWindow = false;
  Completer<void>? _windowCloseCompleter;

  ValueListenable<DetachedWindowPresentation?> get presentation =>
      _presentation;

  /// 窗口是否置顶于其他窗口之上；跨次打开保持用户的选择。
  ValueListenable<bool> get alwaysOnTop => _alwaysOnTop;

  bool get supportsAlwaysOnTop => _nativeWindow.isSupported;

  String get _alwaysOnTopKey => '$placementKey.always_on_top';

  Future<void> setAlwaysOnTop(bool value) async {
    if (_disposed || _alwaysOnTop.value == value) {
      return;
    }
    _alwaysOnTop.value = value;
    await _preferences?.setBool(_alwaysOnTopKey, value);
    final controller = _windowController;
    if (controller != null && !controller.isDestroyed) {
      await _applyAlwaysOnTop(controller);
    }
  }

  Future<void> _applyAlwaysOnTop(WindowController controller) async {
    if (!_nativeWindow.isSupported) {
      return;
    }
    try {
      await _nativeWindow.setAlwaysOnTop(controller, _alwaysOnTop.value);
    } catch (error, stackTrace) {
      debugPrint(
        '[WindowPosition] set always-on-top $placementKey failed: $error\n'
        '$stackTrace',
      );
    }
  }

  bool get isWindowOpen {
    final controller = _windowController;
    return controller != null && !controller.isDestroyed && !_closingWindow;
  }

  void setTitle(String title) {
    _title = title;
    final controller = _windowController;
    if (_disposed || controller == null || controller.isDestroyed) {
      return;
    }
    controller.setTitle(title);
  }

  /// 打开窗口；已打开时更新标题与主题并激活。
  Future<void> open({
    required String title,
    required DetachedWindowTheme theme,
  }) {
    if (_disposed) {
      return Future<void>.value();
    }
    _title = title;
    final opening = _opening;
    if (opening != null) {
      return opening;
    }
    final task = _open(theme);
    final trackedTask = task.whenComplete(() {
      _opening = null;
    });
    _opening = trackedTask;
    return trackedTask;
  }

  Future<void> _open(DetachedWindowTheme theme) async {
    final pendingClose = _windowCloseCompleter?.future;
    if (pendingClose != null) {
      await pendingClose;
      if (_disposed) {
        return;
      }
    }

    final existingController = _windowController;
    if (existingController != null &&
        !existingController.isDestroyed &&
        !_closingWindow) {
      existingController.setTitle(_title);
      _presentation.value = DetachedWindowPresentation(
        controller: existingController,
        theme: theme,
      );
      existingController.activate();
      return;
    }

    final preferences = _preferences ??= await SharedPreferences.getInstance();
    if (_disposed) {
      return;
    }
    final placement = decodeDetachedWindowPlacement(
      preferences.getString(placementKey),
      minimumSize: constraints.smallest,
    );
    _lastKnownWindowPosition = placement?.position;
    _alwaysOnTop.value = preferences.getBool(_alwaysOnTopKey) ?? false;

    _log.checkpoint(
      'creating window '
      '(size=${placement?.size ?? defaultSize}, '
      'hasSavedPosition=${placement?.position != null})',
    );
    late final WindowController controller;
    controller = WindowController(
      size: placement?.size ?? defaultSize,
      constraints: constraints,
      title: _title,
      delegate: _DetachedWindowDelegate(
        onCloseRequested: () => _handleWindowCloseRequested(controller),
        onDestroyed: () => _handleWindowDestroyed(controller),
      ),
    );
    controller.addListener(_scheduleWindowPlacementSave);
    _windowController = controller;
    _log.checkpoint('window created');
    final savedPosition = placement?.position;
    if (savedPosition != null && _nativeWindow.isSupported) {
      try {
        await _nativeWindow.set(controller, savedPosition);
      } catch (error, stackTrace) {
        debugPrint(
          '[WindowPosition] restore $placementKey failed: $error\n'
          '$stackTrace',
        );
      }
    }
    if (_alwaysOnTop.value && !controller.isDestroyed) {
      await _applyAlwaysOnTop(controller);
    }
    if (_disposed || controller.isDestroyed) {
      if (controller.isDestroyed) {
        return;
      }
      controller.removeListener(_scheduleWindowPlacementSave);
      if (identical(_windowController, controller)) {
        _windowController = null;
      }
      controller.destroy();
      controller.dispose();
      return;
    }
    _presentation.value = DetachedWindowPresentation(
      controller: controller,
      theme: theme,
    );
    controller.activate();
  }

  /// 关闭窗口，与系统关窗走同一条 destroy 路径。
  Future<void> close() async {
    if (_disposed) {
      return;
    }
    final pendingClose = _windowCloseCompleter?.future;
    if (pendingClose != null) {
      await pendingClose;
      return;
    }
    final controller = _windowController;
    if (controller == null || controller.isDestroyed) {
      _presentation.value = null;
      return;
    }
    _handleWindowCloseRequested(controller);
    final closing = _windowCloseCompleter?.future;
    if (closing != null) {
      await closing;
    }
  }

  void _scheduleWindowPlacementSave() {
    final controller = _windowController;
    if (_disposed ||
        controller == null ||
        controller.isDestroyed ||
        controller.isMaximized ||
        _preferences == null) {
      return;
    }
    _placementSaveTimer?.cancel();
    _placementSaveTimer = Timer(const Duration(milliseconds: 300), () {
      if (!controller.isDestroyed && !controller.isMaximized) {
        unawaited(_saveWindowPlacement(controller));
      }
    });
  }

  Future<void> _saveWindowPlacement(WindowController controller) {
    final task = _placementSaveTail.then((_) async {
      if (controller.isDestroyed || controller.isMaximized) {
        return;
      }
      final preferences = _preferences;
      if (preferences == null) {
        return;
      }
      try {
        if (_nativeWindow.isSupported) {
          _lastKnownWindowPosition = await _nativeWindow.get(controller);
        }
        await preferences.setString(
          placementKey,
          encodeDetachedWindowPlacement(
            size: controller.contentSize,
            position: _lastKnownWindowPosition,
          ),
        );
      } catch (error, stackTrace) {
        debugPrint(
          '[WindowPosition] save $placementKey failed: $error\n'
          '$stackTrace',
        );
      }
    });
    _placementSaveTail = task;
    return task;
  }

  void _handleWindowCloseRequested(WindowController controller) {
    if (_closingWindow || controller.isDestroyed) {
      return;
    }
    _log.checkpoint('window close requested');
    _closingWindow = true;
    _windowCloseCompleter ??= Completer<void>();
    _placementSaveTimer?.cancel();
    unawaited(() async {
      await _saveWindowPlacement(controller);
      if (!controller.isDestroyed) {
        controller.destroy();
      } else {
        _completeClose();
      }
    }());
  }

  void _completeClose() {
    _closingWindow = false;
    final completer = _windowCloseCompleter;
    _windowCloseCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _handleWindowDestroyed(WindowController controller) {
    if (!identical(_windowController, controller)) {
      return;
    }
    _log.checkpoint('window destroyed');
    _placementSaveTimer?.cancel();
    controller.removeListener(_scheduleWindowPlacementSave);
    _windowController = null;
    if (!_disposed) {
      _presentation.value = null;
    }
    _completeClose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _placementSaveTimer?.cancel();
    _disposed = true;

    final controller = _windowController;
    _windowController = null;
    if (controller != null) {
      controller.removeListener(_scheduleWindowPlacementSave);
      if (!controller.isDestroyed) {
        await _saveWindowPlacement(controller);
      }
      _presentation.value = null;
      if (!controller.isDestroyed) {
        _log.checkpoint('destroying window on session dispose');
        controller.destroy();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
    } else {
      _presentation.value = null;
    }

    _presentation.dispose();
    _alwaysOnTop.dispose();
    _completeClose();
  }
}

class _DetachedWindowDelegate with WindowControllerDelegate {
  _DetachedWindowDelegate({
    required this.onCloseRequested,
    required this.onDestroyed,
  });

  final VoidCallback onCloseRequested;
  final VoidCallback onDestroyed;

  @override
  void onWindowCloseRequested(WindowController controller) {
    onCloseRequested();
  }

  @override
  void onWindowDestroyed() {
    onDestroyed();
    super.onWindowDestroyed();
  }
}

/// 把子窗口挂到主窗口 widget 树上，子窗口因此共享同一个 ProviderContainer。
/// 必须挂在不随 Main 区切换卸载的位置，否则子窗口只剩最后一帧、无法交互。
class DetachedWindowAnchor extends StatelessWidget {
  const DetachedWindowAnchor({
    super.key,
    required this.session,
    required this.builder,
    required this.child,
  });

  final DetachedWindowSession session;

  /// 子窗口的首页，构建在子窗口自己的 MaterialApp 下。
  final WidgetBuilder builder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DetachedWindowPresentation?>(
      valueListenable: session.presentation,
      child: child,
      builder: (context, presentation, child) {
        return ViewAnchor(
          view: presentation == null
              ? null
              : ProviderScope(
                  overrides: [
                    appBackgroundImagePathProvider.overrideWithValue(''),
                    appBackgroundFitProvider.overrideWithValue(
                      AppBackgroundFit.cover,
                    ),
                    appBackgroundThemeProvider.overrideWithValue(null),
                  ],
                  child: Window(
                    controller: presentation.controller,
                    child: _DetachedWindowApp(
                      theme: presentation.theme,
                      builder: builder,
                    ),
                  ),
                ),
          child: child!,
        );
      },
    );
  }
}

class _DetachedWindowApp extends StatelessWidget {
  const _DetachedWindowApp({required this.theme, required this.builder});

  final DetachedWindowTheme theme;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final light = theme.themeDataForBrightness(Brightness.light);
    final dark = theme.themeDataForBrightness(Brightness.dark);
    final themeMode = switch (theme.themeMode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };

    return MaterialApp(
      title: 'Reveric',
      debugShowCheckedModeBanner: false,
      theme: light.toThemeData(),
      darkTheme: dark.toThemeData(),
      themeMode: themeMode,
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      builder: (context, child) {
        final activeData = Theme.of(context).brightness == Brightness.dark
            ? dark
            : light;
        return RevericTheme(data: activeData, child: child!);
      },
      home: Builder(builder: builder),
    );
  }
}
