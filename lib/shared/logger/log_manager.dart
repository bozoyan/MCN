// 职责: 日志管理器 — 文件输出与控制台回显，管理日志级别与文件轮转，统一由 AppLogger 调度
// 关联文件:
//   lib/main.dart
//   lib/shared/logger/app_logger.dart
//   lib/shared/logger/compact_printer.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/database/app_database.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'compact_printer.dart';

class LogManager {
  static const int _maxLogFileSizeKB = 16 * 1024;
  static const int _maxLogFileSizeBytes = _maxLogFileSizeKB * 1024;

  static final LogManager _instance = LogManager._internal();
  factory LogManager() => _instance;
  LogManager._internal();

  static LogManager get instance => _instance;

  Logger? _logger;
  AdvancedFileOutput? _fileOutput;
  bool _isInitialized = false;
  String? _logDirectory;
  Level _currentLevel = _defaultLevel();

  static Level _defaultLevel() {
    final debugEnv = Platform.environment['REVERIC_DEBUG'];
    if (debugEnv == '1' || debugEnv == 'true') {
      return Level.trace;
    }
    return kReleaseMode ? Level.info : Level.debug;
  }

  bool isEnabled(Level level) =>
      level >= Level.trace && level <= Level.fatal && level >= _currentLevel;

  bool get isInitialized => _isInitialized;
  Level get currentLevel => _currentLevel;
  String? get logFilePath =>
      _logDirectory != null ? p.join(_logDirectory!, 'latest.log') : null;
  String? get logDirectory => _logDirectory;

  Future<void> initialize({Level? level}) async {
    if (_isInitialized) {
      if (level != null) {
        setLogLevel(level);
      }
      return;
    }

    try {
      final appDir = await getApplicationSupportDirectory();
      _logDirectory = p.join(appDir.path, 'logs');
      await prepareLatestLogFile(_logDirectory!);

      debugPrint('[LogManager] Log directory: $_logDirectory');

      _fileOutput = AdvancedFileOutput(
        path: _logDirectory!,
        fileHeader:
            '=== Reveric Startup Log ===\nStart Time: ${DateTime.now().toIso8601String()}\nPlatform: ${Platform.operatingSystem}\n',
        maxFileSizeKB: _maxLogFileSizeKB,
        latestFileName: 'latest.log',
        fileNameFormatter: _startupLogFileName,
        maxDelay: const Duration(milliseconds: 100),
        maxBufferSize: 100,
        writeImmediately: [Level.error, Level.fatal, Level.warning],
      );

      final debugEnv = Platform.environment['REVERIC_DEBUG'];
      final isDebugMode = debugEnv == '1' || debugEnv == 'true';

      final outputs = <LogOutput>[_fileOutput!];
      if (!kReleaseMode) {
        outputs.add(ConsoleOutput());
      }

      _currentLevel = level ?? _defaultLevel();
      _logger = Logger(
        filter: _AlwaysOnLogFilter(isEnabled),
        printer: CompactLogPrinter(),
        output: MultiOutput(outputs),
      );
      await _logger!.init;

      _isInitialized = true;
      info(
        'LogManager initialized',
        extra: {
          'logDirectory': _logDirectory,
          'level': _currentLevel.toString(),
          'debugMode': isDebugMode,
          'buildMode': kReleaseMode
              ? 'release'
              : (kProfileMode ? 'profile' : 'debug'),
        },
      );
    } catch (e, stack) {
      debugPrint('[LogManager] Failed to initialize: $e');
      debugPrint(stack.toString());
    }
  }

  void setLogLevel(Level level) {
    if (level == _currentLevel || !_isInitialized) {
      return;
    }
    _currentLevel = level;
    info('Log level changed to $level');
  }

  @visibleForTesting
  static Future<void> ensureLatestLogFileExists(String logDirectory) async {
    await prepareLatestLogFile(logDirectory);
  }

  @visibleForTesting
  static Future<void> prepareLatestLogFile(
    String logDirectory, {
    int maxLatestLogSizeBytes = _maxLogFileSizeBytes,
  }) async {
    final dir = Directory(logDirectory);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final latestLogFile = File(p.join(logDirectory, 'latest.log'));
    if (latestLogFile.existsSync()) {
      try {
        if (await latestLogFile.length() > maxLatestLogSizeBytes) {
          await latestLogFile.rename(_nextStartupLogPath(logDirectory));
        }
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode != 2 && !e.message.contains('Cannot rename')) {
          rethrow;
        }
      }
    }

    if (!latestLogFile.existsSync()) {
      await latestLogFile.create();
    }
  }

  static String _nextStartupLogPath(String logDirectory) {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    var path = p.join(logDirectory, 'startup_$timestamp.log');
    var index = 1;
    while (File(path).existsSync()) {
      path = p.join(logDirectory, 'startup_${timestamp}_$index.log');
      index += 1;
    }
    return path;
  }

  static String _startupLogFileName(DateTime timestamp) {
    return 'startup_${timestamp.toIso8601String().replaceAll(':', '-')}.log';
  }

  void trace(String message) {
    if (isEnabled(Level.trace)) {
      _logger?.t(message);
    }
  }

  void debug(String message) {
    if (isEnabled(Level.debug)) {
      _logger?.d(message);
    }
  }

  void info(String message, {Map<String, dynamic>? extra}) {
    if (extra != null && extra.isNotEmpty) {
      _logger?.i('$message | ${_jsonEncode(extra)}');
    } else {
      _logger?.i(message);
    }
  }

  void warning(String message) {
    _logger?.w(message);
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _logger?.e(message, error: error, stackTrace: stackTrace);
  }

  /// 崩溃诊断检查点 — 绕过异步 IOSink，同步追加并 flush 到日志文件。
  /// 仅用于原生崩溃高发路径（窗口生命周期、退出流程），禁止高频调用。
  void checkpoint(String message) {
    final path = logFilePath;
    if (path == null) {
      return;
    }
    try {
      appendCheckpointSync(path, message);
    } catch (error, stackTrace) {
      debugPrint('[LogManager] Failed to persist checkpoint: $error');
      debugPrint(stackTrace.toString());
      _logger?.w('[Checkpoint] $message');
    }
  }

  @visibleForTesting
  static void appendCheckpointSync(
    String logFilePath,
    String message, {
    DateTime? timestamp,
  }) {
    final file = File(logFilePath);
    final output = file.openSync(mode: FileMode.append);
    try {
      final lineEnding = Platform.isWindows ? '\r\n' : '\n';
      output.writeStringSync(
        '${(timestamp ?? DateTime.now()).toIso8601String()} '
        '[WARNING] [Checkpoint] $message$lineEnding',
      );
      output.flushSync();
    } finally {
      output.closeSync();
    }
  }

  void fatal(String message, {Object? error, StackTrace? stackTrace}) {
    _logger?.f(message, error: error, stackTrace: stackTrace);
  }

  String _jsonEncode(Map<String, dynamic> data) {
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  Future<List<File>> getLogFiles() async {
    if (_logDirectory == null) {
      return [];
    }
    final dir = Directory(_logDirectory!);
    if (!dir.existsSync()) {
      return [];
    }

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList();

    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> cleanupOldLogs({int keepCount = 10}) async {
    final files = await getLogFiles();
    if (files.length <= keepCount) {
      return;
    }

    final filesToDelete = files.sublist(keepCount);
    for (final file in filesToDelete) {
      try {
        await file.delete();
        if (isEnabled(Level.debug)) {
          debug('Deleted old log file: ${file.path}');
        }
      } catch (e) {
        warning('Failed to delete old log file: ${file.path} | Error: $e');
      }
    }
  }

  Future<void> dispose() async {
    await _logger?.close();
    _logger = null;
    _fileOutput = null;
    _isInitialized = false;
    _logDirectory = null;
    _currentLevel = _defaultLevel();
  }

  Future<bool> openApplicationDirectory() async {
    try {
      final dir = await getApplicationSupportDirectory();
      if (!dir.existsSync()) {
        return false;
      }

      if (Platform.isMacOS) {
        // bundle id 以 .app 结尾，Finder 会把目录当应用包去「启动」；
        // 改为 reveal 包内子项，让 Finder 直接进入目录内部。
        final logs = Directory(p.join(dir.path, 'logs'));
        final target = logs.existsSync()
            ? logs.path
            : dir.listSync().map((e) => e.path).firstOrNull;
        await Process.run(
          'open',
          target == null ? ['-R', dir.path] : ['-R', target],
        );
      } else if (Platform.isWindows) {
        await Process.run('explorer', [dir.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir.path]);
      } else {
        return false;
      }
      return true;
    } catch (e, stackTrace) {
      error(
        'Failed to open application directory',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}

class _AlwaysOnLogFilter extends LogFilter {
  _AlwaysOnLogFilter(this.isEnabled);

  final bool Function(Level) isEnabled;

  @override
  bool shouldLog(LogEvent event) {
    return isEnabled(event.level);
  }
}
