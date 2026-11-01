// 职责: 全局日志入口 — 静态便捷方法与模块作用域日志，统一路由到 LogManager 文件输出
// 关联文件:
//   lib/shared/logger/log_manager.dart
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'log_manager.dart';

/// 全局日志入口。
///
/// - 业务日志：在文件顶部声明 `final _log = AppLogger.forModule('ModuleName');`，
///   后续用 `_log.info/debug/warning/error`，自动添加 `[ModuleName]` 前缀。
/// - debug / trace 动态消息先用 `isDebugEnabled/isTraceEnabled` 判断再构造。
/// - 静态输出方法供模块日志器内部转发；级别配置通过 AppLogger 管理。
///
/// 所有日志在 LogManager 初始化后写入文件；初始化前 fallback 到 debugPrint。
class AppLogger {
  // ---------------------------------------------------------------------------
  // 静态输出 API（无 tag，供模块日志器转发）
  // ---------------------------------------------------------------------------

  static void trace(String message) {
    if (!isEnabled(Level.trace)) {
      return;
    }
    if (LogManager.instance.isInitialized) {
      LogManager.instance.trace(message);
    } else {
      debugPrint('[TRACE] $message');
    }
  }

  static void debug(String message) {
    if (!isEnabled(Level.debug)) {
      return;
    }
    if (LogManager.instance.isInitialized) {
      LogManager.instance.debug(message);
    } else {
      debugPrint('[DEBUG] $message');
    }
  }

  /// 是否允许输出该级别；初始化前使用当前构建和环境变量的默认级别。
  static bool isEnabled(Level level) => LogManager.instance.isEnabled(level);

  static bool get isDebugEnabled => isEnabled(Level.debug);
  static bool get isTraceEnabled => isEnabled(Level.trace);

  static void info(String message, {Map<String, dynamic>? extra}) {
    if (LogManager.instance.isInitialized) {
      LogManager.instance.info(message, extra: extra);
    } else {
      debugPrint('[INFO] $message');
    }
  }

  static void warning(String message) {
    if (LogManager.instance.isInitialized) {
      LogManager.instance.warning(message);
    } else {
      debugPrint('[WARN] $message');
    }
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    if (LogManager.instance.isInitialized) {
      LogManager.instance.error(message, error: error, stackTrace: stackTrace);
    } else {
      debugPrint('[ERROR] $message${error != null ? ' | $error' : ''}');
      if (stackTrace != null) {
        debugPrint(stackTrace.toString());
      }
    }
  }

  /// 崩溃诊断检查点 — 立即落盘（内部以 warning 级别写入）。
  /// 仅用于原生崩溃高发路径（窗口生命周期、退出流程），禁止高频调用。
  static void checkpoint(String message) {
    if (LogManager.instance.isInitialized) {
      LogManager.instance.checkpoint(message);
    } else {
      debugPrint('[CHECKPOINT] $message');
    }
  }

  /// 当前日志级别（仅初始化后有效）。
  static Level? get currentLevel => LogManager.instance.isInitialized
      ? LogManager.instance.currentLevel
      : null;

  /// 设置日志级别，即时生效。
  static void setLogLevel(Level level) {
    LogManager.instance.setLogLevel(level);
  }

  // ---------------------------------------------------------------------------
  // 模块作用域日志
  // ---------------------------------------------------------------------------

  /// 创建一个带 `[module]` 前缀的模块日志器。
  /// 建议在文件顶部声明为 `final _log = AppLogger.forModule('Xxx');`。
  static ModuleLogger forModule(String module) => ModuleLogger(module);

  AppLogger._();
}

/// 模块作用域日志器，自动为每条日志添加 `[module]` 前缀。
class ModuleLogger {
  final String _tag;
  const ModuleLogger(this._tag);

  bool isEnabled(Level level) => AppLogger.isEnabled(level);
  bool get isDebugEnabled => AppLogger.isDebugEnabled;
  bool get isTraceEnabled => AppLogger.isTraceEnabled;

  void trace(String message) {
    if (isEnabled(Level.trace)) {
      AppLogger.trace('[$_tag] $message');
    }
  }

  void debug(String message) {
    if (isEnabled(Level.debug)) {
      AppLogger.debug('[$_tag] $message');
    }
  }

  void info(String message, {Map<String, dynamic>? extra}) =>
      AppLogger.info('[$_tag] $message', extra: extra);
  void warning(String message) => AppLogger.warning('[$_tag] $message');
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      AppLogger.error('[$_tag] $message', error: error, stackTrace: stackTrace);
  void checkpoint(String message) => AppLogger.checkpoint('[$_tag] $message');
}
