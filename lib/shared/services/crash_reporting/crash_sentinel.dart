// 职责: 会话崩溃哨兵 — 启动写 marker、正常退出清除，下次启动据此识别上次异常终止并上报
// 关联文件:
//   lib/main.dart
//   lib/shared/logger/log_manager.dart
//   lib/shared/logger/startup_failure_reporter.dart
//   lib/shared/services/system_tray_service.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../app_config.dart';
import '../../logger/app_logger.dart';
import '../../logger/log_manager.dart';
import '../../logger/startup_failure_reporter.dart';

final _log = AppLogger.forModule('CrashSentinel');

enum PreviousSessionCrashOrigin {
  currentMarker('current_marker'),
  pendingReplay('pending_replay');

  const PreviousSessionCrashOrigin(this.traceName);

  final String traceName;
}

/// 上次会话未正常退出（原生崩溃 / 强杀）的诊断异常，仅用作上报载荷。
class PreviousSessionCrash implements Exception {
  const PreviousSessionCrash({
    required this.markerContent,
    required this.origin,
  });

  /// 上次会话 marker 的原始内容（含 pid、启动时间、版本）。
  final String markerContent;
  final PreviousSessionCrashOrigin origin;

  Map<String, dynamic> get diagnostic {
    try {
      return Map<String, dynamic>.from(jsonDecode(markerContent) as Map);
    } on Object {
      return const {};
    }
  }

  String get classification {
    final data = diagnostic;
    if (data['native_crash'] == true) {
      return 'confirmed_crash';
    }
    if (data['exit_source'] != null ||
        (data['exit_phase'] != null && data['exit_phase'] != 'running') ||
        (data['native_exit_phase'] != null &&
            data['native_exit_phase'] != 'running') ||
        (data['native_exit_source'] != null &&
            data['native_exit_source'] != 'none')) {
      return 'exit_incomplete';
    }
    return 'unknown_termination';
  }

  @override
  String toString() {
    final data = diagnostic;
    final nativePhase = data['native_exit_phase'];
    final phase = nativePhase != null && nativePhase != 'running'
        ? nativePhase
        : data['exit_phase'];
    final summary = {
      'pid': data['pid'],
      'exit_source': data['exit_source'] ?? data['native_exit_source'],
      'exit_phase': phase,
      if (data['native_crash'] == true) 'native_crash': true,
      for (final key in [
        'exception_code',
        'dump_status',
        'dump_error',
        'summary_error',
        'marker_error',
        'native_handler_configured',
        'started_at',
        'app_version',
        'preserved_from',
      ])
        if (data.containsKey(key)) key: data[key],
    };
    return 'PreviousSessionCrash(classification=$classification, origin=${origin.traceName}): '
        '${data.isEmpty ? markerContent : jsonEncode(summary)}';
  }
}

typedef CrashReportSink =
    Future<StartupFailureReportOutcome> Function({
      required String phase,
      required Object error,
      required StackTrace stackTrace,
    });

/// 会话崩溃哨兵。
///
/// 原生崩溃会绕过 FlutterError / PlatformDispatcher 等所有 Dart 层错误处理，
/// 进程直接消失、日志也来不及落盘。哨兵方案不试图捕获崩溃本身，而是：
///   - 启动时写入 `session_running.marker`（pid / 启动时间 / 版本 / handler 状态）；
///   - 覆盖 active marker 前先把旧内容复制到 `pending_crashes/`；
///   - 当前 marker 与原生 handler 就绪后，在后台补报 pending，避免阻塞启动；
///   - 正常退出时删除（托盘/更新退出走 Dart，Windows runner 在消息循环结束后
///     兜底删除）；
///   - 下次启动发现 marker 残留，即上次会话异常终止，记录日志并上报。
class CrashSentinel {
  CrashSentinel({
    required this.logDirectory,
    CrashReportSink? reportSink,
    DateTime Function()? now,
    int Function()? currentPid,
  }) : _reportSink = reportSink ?? _defaultReportSink,
       _now = now ?? DateTime.now,
       _currentPid = currentPid ?? (() => pid);

  static Future<StartupFailureReportOutcome> _defaultReportSink({
    required String phase,
    required Object error,
    required StackTrace stackTrace,
  }) {
    return StartupFailureReporter().reportWithOutcome(
      phase: phase,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static const String markerFileName = 'session_running.marker';
  static const String pendingCrashDirectoryName = 'pending_crashes';
  static const int markerSchemaVersion = 3;
  static final RegExp _pendingCrashFileName = RegExp(r'^crash_.*\.marker$');

  final String logDirectory;
  final CrashReportSink _reportSink;
  final DateTime Function() _now;
  final int Function() _currentPid;

  String get markerPath => p.join(logDirectory, markerFileName);

  /// 待重试崩溃证据目录；正常退出只清除 [markerPath]，不会触碰这里。
  String get pendingCrashDirectoryPath =>
      p.join(logDirectory, pendingCrashDirectoryName);

  /// 上次会话是否异常终止；是则返回诊断异常，否则返回 null。
  Future<PreviousSessionCrash?> checkPreviousSession() async {
    return _readMarker(
      File(markerPath),
      origin: PreviousSessionCrashOrigin.currentMarker,
    );
  }

  Future<PreviousSessionCrash?> _readMarker(
    File marker, {
    required PreviousSessionCrashOrigin origin,
  }) async {
    if (!marker.existsSync()) {
      return null;
    }
    String content;
    try {
      content = await marker.readAsString();
    } catch (error, stackTrace) {
      _log.error(
        'Failed to read session marker',
        error: error,
        stackTrace: stackTrace,
      );
      content = '<unreadable: $error>';
    }
    if (origin == PreviousSessionCrashOrigin.currentMarker) {
      final native = File('$markerPath.native');
      try {
        if (native.existsSync()) {
          final payload = jsonDecode(content) as Map<String, dynamic>;
          final state =
              jsonDecode(await native.readAsString()) as Map<String, dynamic>;
          if (payload['session_token'] != null &&
              state['session_token'] == payload['session_token'] &&
              state['pid'] == payload['pid']) {
            content = jsonEncode({...payload, ...state});
          }
        }
      } catch (error, stackTrace) {
        _log.error(
          'Failed to read native exit state',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return PreviousSessionCrash(markerContent: content.trim(), origin: origin);
  }

  /// 在当前会话覆盖 active marker 前，将上一会话证据复制到 pending。
  ///
  /// 返回 false 表示证据无法安全持久化；调用方不得继续覆盖 active marker。
  Future<bool> preservePreviousSessionCrash() async {
    final crash = await checkPreviousSession();
    if (crash == null) {
      return true;
    }
    return _persistPendingCrash(crash);
  }

  /// 后台补报已经持久化的历史异常退出，不读取 active marker。
  Future<bool> reportPendingSessionCrashes() async {
    var allReportsDelivered = true;
    for (final marker in _pendingCrashFiles()) {
      final crash = await _readMarker(
        marker,
        origin: PreviousSessionCrashOrigin.pendingReplay,
      );
      if (crash == null) {
        continue;
      }
      final delivered = await _tryReport(crash);
      if (delivered) {
        await _deletePendingCrash(marker);
      } else {
        allReportsDelivered = false;
      }
    }
    return allReportsDelivered;
  }

  /// 检测并上报待处理的异常终止。
  ///
  /// 上报失败的旧会话会被复制到 pending 目录，然后继续写入本次会话
  /// marker；这样正常退出只删除本次 marker，不会丢失待重试证据。
  Future<bool> reportPreviousSessionCrash() async {
    var allReportsDelivered = await reportPendingSessionCrashes();

    final currentSessionCrash = await checkPreviousSession();
    if (currentSessionCrash == null) {
      return allReportsDelivered;
    }
    final delivered = await _tryReport(currentSessionCrash);
    if (!delivered) {
      allReportsDelivered = false;
      await _persistPendingCrash(currentSessionCrash);
    }
    return allReportsDelivered;
  }

  Future<bool> _tryReport(PreviousSessionCrash crash) async {
    _log.warning(
      'Previous session did not exit cleanly: ${crash.markerContent}',
    );
    try {
      final outcome = await _reportSink(
        phase: 'previous_session_crashed',
        error: crash,
        stackTrace: StackTrace.current,
      );
      return outcome != StartupFailureReportOutcome.retryableFailure;
    } catch (error, stackTrace) {
      _log.error(
        'Failed to report previous session crash',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  List<File> _pendingCrashFiles() {
    final directory = Directory(pendingCrashDirectoryPath);
    if (!directory.existsSync()) {
      return const [];
    }
    try {
      final files = directory
          .listSync()
          .whereType<File>()
          .where(
            (file) => _pendingCrashFileName.hasMatch(p.basename(file.path)),
          )
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      return files;
    } catch (error, stackTrace) {
      _log.error(
        'Failed to scan pending crash markers',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  Future<bool> _persistPendingCrash(PreviousSessionCrash crash) async {
    try {
      final directory = Directory(pendingCrashDirectoryPath);
      directory.createSync(recursive: true);
      final pendingContent = _pendingMarkerContent(crash);

      // 启动流程在极短时间内重复时避免同一份 marker 无限复制。
      for (final existing in _pendingCrashFiles()) {
        if (existing.readAsStringSync() == pendingContent) {
          return true;
        }
      }

      final timestamp = _now().toUtc().microsecondsSinceEpoch;
      var index = 0;
      late final File pending;
      do {
        pending = File(
          p.join(
            pendingCrashDirectoryPath,
            'crash_${timestamp}_${_currentPid()}_$index.marker',
          ),
        );
        index += 1;
      } while (pending.existsSync());
      await pending.writeAsString(pendingContent, flush: true);
      return true;
    } catch (error, stackTrace) {
      _log.error(
        'Failed to persist pending crash marker',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  String _pendingMarkerContent(PreviousSessionCrash crash) {
    if (crash.origin != PreviousSessionCrashOrigin.currentMarker) {
      return crash.markerContent;
    }
    try {
      final decoded = jsonDecode(crash.markerContent);
      if (decoded is! Map) {
        return crash.markerContent;
      }
      return jsonEncode({
        ...Map<String, dynamic>.from(decoded),
        'preserved_from': crash.origin.traceName,
      });
    } on FormatException {
      return crash.markerContent;
    }
  }

  Future<void> _deletePendingCrash(File marker) async {
    try {
      if (marker.existsSync()) {
        await marker.delete();
      }
    } catch (error, stackTrace) {
      _log.error(
        'Failed to delete pending crash marker ${marker.path}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 写入本次会话 marker（覆盖上次残留）。
  Future<bool> markSessionStart() async {
    final payload = jsonEncode({
      'marker_schema_version': markerSchemaVersion,
      'pid': _currentPid(),
      'started_at': _now().toIso8601String(),
      'app_version': appVersion,
      'native_handler_configured': false,
      'session_token': '${_now().microsecondsSinceEpoch}-${_currentPid()}',
      'exit_phase': 'running',
    });
    try {
      await File(markerPath).writeAsString(payload, flush: true);
      return true;
    } catch (error, stackTrace) {
      _log.error(
        'Failed to write session marker',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// 原生崩溃处理器配置成功后回写 active marker。
  ///
  /// 下一次异常启动可以据此区分「handler 就绪后的异常终止」与「启动早期、
  /// handler 尚未就绪时终止」。旧 marker 没有该字段，分析侧按 unknown 处理。
  Future<bool> markNativeHandlerConfigured() async {
    final marker = File(markerPath);
    try {
      if (!marker.existsSync()) {
        _log.error('Cannot mark native crash handler: active marker missing');
        return false;
      }
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map) {
        _log.error('Cannot mark native crash handler: malformed marker');
        return false;
      }
      final payload = Map<String, dynamic>.from(decoded);
      if (payload['pid'] != _currentPid()) {
        _log.error('Cannot mark native crash handler: marker PID mismatch');
        return false;
      }
      payload['native_handler_configured'] = true;
      payload['native_handler_configured_at'] = _now()
          .toUtc()
          .toIso8601String();
      await marker.writeAsString(jsonEncode(payload), flush: true);
      return true;
    } catch (error, stackTrace) {
      _log.error(
        'Failed to mark native crash handler configured',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// 退出开始或推进时记录阶段；未启用哨兵的平台不创建新文件。
  void markExitProgressSync({required String source, required String phase}) {
    final marker = File(markerPath);
    if (!marker.existsSync()) {
      return;
    }
    try {
      final payload =
          jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;
      if (payload['pid'] != _currentPid()) {
        return;
      }
      payload['exit_source'] = source;
      payload['exit_phase'] = phase;
      marker.writeAsStringSync(jsonEncode(payload), flush: true);
    } catch (error, stackTrace) {
      _log.error(
        'Failed to record exit progress',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static void markActiveExitProgressSync({
    required String source,
    required String phase,
  }) {
    final directory = LogManager.instance.logDirectory;
    if (directory != null) {
      CrashSentinel(
        logDirectory: directory,
      ).markExitProgressSync(source: source, phase: phase);
    }
  }

  /// 正常退出时只删除当前会话 marker，保留待重试崩溃证据。
  Future<void> markCleanExit() async {
    markCleanExitSync();
  }

  /// 正常退出时同步删除 marker，供 [dart:io] 进程退出前的最后路径调用。
  void markCleanExitSync() {
    try {
      final marker = File(markerPath);
      if (marker.existsSync()) {
        final payload =
            jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;
        if (payload['pid'] != _currentPid()) {
          return;
        }
        payload['exit_phase'] = 'cleanup_completed';
        marker.writeAsStringSync(jsonEncode(payload), flush: true);
        marker.deleteSync();
      }
    } catch (error, stackTrace) {
      _log.error(
        'Failed to delete session marker',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 供退出路径（托盘退出、更新重启）调用：基于当前 LogManager
  /// 的日志目录删除 marker。日志服务未初始化时无 marker 可言，直接返回。
  static Future<void> markActiveSessionCleanExit() async {
    final directory = LogManager.instance.logDirectory;
    if (directory == null) {
      return;
    }
    CrashSentinel(logDirectory: directory).markCleanExitSync();
  }

  /// 同步清除活动会话 marker，避免进程退出前异步删除未完成。
  static void markActiveSessionCleanExitSync() {
    final directory = LogManager.instance.logDirectory;
    if (directory == null) {
      return;
    }
    CrashSentinel(logDirectory: directory).markCleanExitSync();
  }
}
