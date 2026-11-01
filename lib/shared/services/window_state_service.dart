// 职责: 桌面端窗口状态管理服务 — 保存和恢复窗口大小、位置、最大化状态
// 关联文件:
//   lib/main.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../logger/app_logger.dart';

final _log = AppLogger.forModule('WindowState');

class WindowState {
  final double width;
  final double height;
  final double x;
  final double y;
  final bool isMaximized;
  final bool isFullScreen;

  const WindowState({
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    this.isMaximized = false,
    this.isFullScreen = false,
  });

  static const WindowState defaultState = WindowState(
    width: 1280,
    height: 720,
    x: 0,
    y: 0,
    isMaximized: false,
    isFullScreen: false,
  );

  factory WindowState.fromJson(Map<String, dynamic> json) {
    return WindowState(
      width: (json['width'] as num?)?.toDouble() ?? 1280,
      height: (json['height'] as num?)?.toDouble() ?? 720,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      isMaximized: json['isMaximized'] as bool? ?? false,
      isFullScreen: json['isFullScreen'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'width': width,
      'height': height,
      'x': x,
      'y': y,
      'isMaximized': isMaximized,
      'isFullScreen': isFullScreen,
    };
  }

  WindowState copyWith({
    double? width,
    double? height,
    double? x,
    double? y,
    bool? isMaximized,
    bool? isFullScreen,
  }) {
    return WindowState(
      width: width ?? this.width,
      height: height ?? this.height,
      x: x ?? this.x,
      y: y ?? this.y,
      isMaximized: isMaximized ?? this.isMaximized,
      isFullScreen: isFullScreen ?? this.isFullScreen,
    );
  }
}

class WindowStateService {
  static const _windowStateKey = 'window_state';
  static const _debounceDuration = Duration(milliseconds: 300);

  final SharedPreferences _prefs;
  Timer? _debounceTimer;
  WindowState? _lastSavedState;
  _WindowStateListener? _listener;

  WindowStateService(this._prefs);

  Future<WindowState> loadWindowState() async {
    try {
      final stateJson = _prefs.getString(_windowStateKey);
      if (stateJson != null && stateJson.isNotEmpty) {
        final json = jsonDecode(stateJson) as Map<String, dynamic>;
        return WindowState.fromJson(json);
      }
    } catch (e) {
      _log.warning('Failed to load window state: $e');
    }
    return WindowState.defaultState;
  }

  Future<void> saveWindowState(WindowState state) async {
    if (_lastSavedState != null && _isSameState(_lastSavedState!, state)) {
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () async {
      try {
        final json = jsonEncode(state.toJson());
        await _prefs.setString(_windowStateKey, json);
        _lastSavedState = state;
      } catch (e) {
        _log.warning('Failed to save window state: $e');
      }
    });
  }

  Future<WindowState> getCurrentWindowState() async {
    final bounds = await windowManager.getBounds();
    final isMaximized = await windowManager.isMaximized();
    final isFullScreen = await windowManager.isFullScreen();

    return WindowState(
      width: bounds.width,
      height: bounds.height,
      x: bounds.left,
      y: bounds.top,
      isMaximized: isMaximized,
      isFullScreen: isFullScreen,
    );
  }

  Future<void> applyWindowState(WindowState state) async {
    // checkpoint 立即落盘：window_manager 原生调用是启动期崩溃高发路径。
    _log.checkpoint(
      'applyWindowState ${state.width}x${state.height} '
      '@(${state.x},${state.y}) max=${state.isMaximized} '
      'fs=${state.isFullScreen}',
    );
    if (state.isMaximized) {
      await windowManager.maximize();
    } else if (state.isFullScreen) {
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setBounds(
        Rect.fromLTWH(state.x, state.y, state.width, state.height),
      );
    }
  }

  void startListening() {
    _listener = _WindowStateListener(this);
    windowManager.addListener(_listener!);
  }

  void dispose() {
    if (_listener != null) {
      windowManager.removeListener(_listener!);
      _listener = null;
    }
    _debounceTimer?.cancel();
  }

  bool _isSameState(WindowState a, WindowState b) {
    return a.width == b.width &&
        a.height == b.height &&
        a.x == b.x &&
        a.y == b.y &&
        a.isMaximized == b.isMaximized &&
        a.isFullScreen == b.isFullScreen;
  }
}

class _WindowStateListener extends WindowListener {
  final WindowStateService _service;

  _WindowStateListener(this._service);

  // 离散窗口事件打 checkpoint（立即落盘）：最小化/还原/最大化/全屏切换
  // 都会经过引擎与 window_manager 原生路径，崩溃后可据此定位最后动作。
  // onWindowResized/onWindowMoved 在拖拽期间连续触发，不打 checkpoint。

  @override
  void onWindowResized() {
    _saveCurrentState();
  }

  @override
  void onWindowMoved() {
    _saveCurrentState();
  }

  @override
  void onWindowMinimize() {
    _log.checkpoint('window minimized');
  }

  @override
  void onWindowRestore() {
    _log.checkpoint('window restored from minimize');
  }

  @override
  void onWindowMaximize() {
    _log.checkpoint('window maximized');
    _saveCurrentState();
  }

  @override
  void onWindowUnmaximize() {
    _log.checkpoint('window unmaximized');
    _saveCurrentState();
  }

  @override
  void onWindowEnterFullScreen() {
    _log.checkpoint('window enter fullscreen');
    _saveCurrentState();
  }

  @override
  void onWindowLeaveFullScreen() {
    _log.checkpoint('window leave fullscreen');
    _saveCurrentState();
  }

  void _saveCurrentState() {
    Future.microtask(() async {
      final state = await _service.getCurrentWindowState();
      await _service.saveWindowState(state);
    });
  }
}
