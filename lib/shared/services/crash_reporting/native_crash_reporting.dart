// 职责: 桥接 Windows 崩溃诊断，整理最近转储并扫描、上报原生摘要。
// 关联文件:
//   lib/main.dart
//   lib/shared/logger/startup_failure_reporter.dart
//   lib/shared/services/crash_reporting/crash_sentinel.dart
//   lib/shared/services/diagnostics_export_orchestrator.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../logger/app_logger.dart';
import '../../logger/startup_failure_reporter.dart';
import 'crash_sentinel.dart';

final _log = AppLogger.forModule('NativeCrashReporting');

/// 一次原生崩溃的摘要，由 Windows runner 写入的 `crash_*.txt` 解析而来。
class NativeCrashSummary {
  const NativeCrashSummary({
    required this.txtPath,
    required this.kind,
    required this.occurredAt,
    required this.pid,
    required this.exceptionCode,
    required this.exceptionAddress,
    required this.module,
    required this.dumpPath,
    this.dumpError = 'unknown',
  });

  /// 摘要 txt 文件路径（上报成功后会被改名标记）。
  final String txtPath;

  /// 崩溃类别：unhandled_exception / abort。
  final String kind;

  /// 崩溃发生时间（原生侧本地时间字符串，原样保留）。
  final String occurredAt;

  final String pid;
  final String exceptionCode;
  final String exceptionAddress;

  /// 崩溃地址所在模块（通常是 flutter_windows.dll 或某个驱动 DLL），可为空。
  final String module;

  /// minidump 文件路径；dump 写入失败时为空字符串。
  final String dumpPath;
  final String dumpError;

  @override
  String toString() =>
      'NativeCrashSummary(kind=$kind, code=$exceptionCode, '
      'module=$module, at=$occurredAt)';
}

/// 原生崩溃诊断异常，仅用作上报载荷。
class NativeCrashReport implements Exception {
  const NativeCrashReport(this.summary);

  final NativeCrashSummary summary;

  @override
  String toString() =>
      'NativeCrashReport: classification=confirmed_crash kind=${summary.kind} dump_error=${summary.dumpError} '
      'code=${summary.exceptionCode} addr=${summary.exceptionAddress} '
      'module=${p.windows.basename(summary.module)} pid=${summary.pid} at=${summary.occurredAt} '
      'dump_written=${summary.dumpPath.isNotEmpty}';
}

/// Windows 原生崩溃转储的 Dart 侧桥接。
///
/// 原生侧（windows/runner/crash_handler.cpp）在进程崩溃时把 minidump 与摘要
/// 写入 `%APPDATA%\<ProductName>\crashes`；这里在下次启动时扫描该目录，
/// 上报未处理过的摘要并把 txt 改名为 `.reported.txt` 防止重复上报。
/// minidump 文件保留在本地，最近一份另存为 latest.dump，供用户主动上传诊断日志。
class NativeCrashReporting {
  NativeCrashReporting({CrashReportSink? reportSink})
    : _reportSink = reportSink ?? _defaultReportSink;

  final CrashReportSink _reportSink;

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

  static const MethodChannel _channel = MethodChannel(
    'reveric/crash_reporting',
  );

  /// 单次启动最多上报的崩溃数量；更早的标记为已上报但不发送，避免积压刷屏。
  static const int maxReportsPerLaunch = 5;

  static final RegExp _summaryFileName = RegExp(r'^crash_.*\.txt$');

  /// 保留历史转储，并以固定文件名提供最近一份非空转储。
  /// 同时覆盖升级前已经上报过摘要的 .dmp 文件。
  static Future<File?> prepareLatestDump(String crashDumpDir) async {
    final directory = Directory(crashDumpDir);
    if (!await directory.exists()) {
      return null;
    }
    final latest = File(p.join(crashDumpDir, 'latest.dump'));
    File? newest;
    DateTime? modified;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = p.basename(entity.path);
      if (name != 'latest.dump' && !RegExp(r'^crash_.*\.dmp$').hasMatch(name)) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.size > 0 &&
          (modified == null ||
              stat.modified.isAfter(modified) ||
              (stat.modified == modified && name == 'latest.dump'))) {
        newest = entity;
        modified = stat.modified;
      }
    }
    if (newest == null || newest.path == latest.path) {
      return newest;
    }

    // 同目录临时副本 + rename，防止中途失败留下不完整的 latest.dump。
    final staging = File(
      p.join(crashDumpDir, '.latest-${const Uuid().v4()}.tmp'),
    );
    try {
      await newest.copy(staging.path);
      await staging.setLastModified(modified!);
      await staging.rename(latest.path);
      return latest;
    } finally {
      if (await staging.exists()) {
        await staging.delete();
      }
    }
  }

  /// 把会话 marker 路径交给原生侧（正常退出时删除），返回崩溃转储目录。
  ///
  /// 仅 Windows 可用。失败时记录错误并返回 null —— 崩溃诊断能力降级，
  /// 但不阻断启动（降级行为：日志可见、可测试）。
  Future<String?> configure({required String sessionMarkerPath}) async {
    try {
      final result = await _channel
          .invokeMethod<Map<Object?, Object?>>('configure', {
            'sessionMarkerPath': sessionMarkerPath,
            'sessionToken':
                (jsonDecode(await File(sessionMarkerPath).readAsString())
                    as Map)['session_token'],
          });
      final dir = result?['crashDumpDir'];
      if (dir is String && dir.isNotEmpty) {
        return dir;
      }
      _log.error('Native configure returned unexpected payload: $result');
      return null;
    } catch (error, stackTrace) {
      _log.error(
        'Failed to configure native crash reporting',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// 扫描崩溃目录，返回尚未上报的崩溃摘要（按文件名时间升序）。
  List<NativeCrashSummary> scanPending(
    String crashDumpDir, {
    void Function(File, String)? onFailure,
  }) {
    final dir = Directory(crashDumpDir);
    if (!dir.existsSync()) {
      return const [];
    }
    final summaries = <NativeCrashSummary>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) {
        continue;
      }
      final name = p.basename(entity.path);
      if (!_summaryFileName.hasMatch(name) || name.contains('.reported.')) {
        continue;
      }
      final summary = tryParseSummary(
        entity,
        onFailure: (code) => onFailure?.call(entity, code),
      );
      if (summary != null) {
        summaries.add(summary);
      }
    }
    summaries.sort((a, b) => a.txtPath.compareTo(b.txtPath));
    return summaries;
  }

  /// 解析单个摘要 txt；内容不可读或缺字段时记录错误并返回 null。
  static NativeCrashSummary? tryParseSummary(
    File txtFile, {
    void Function(String)? onFailure,
  }) {
    final String content;
    try {
      content = txtFile.readAsStringSync().replaceFirst(RegExp(r'^\uFEFF'), '');
    } catch (error, stackTrace) {
      _log.error(
        'Failed to read crash summary ${txtFile.path}',
        error: error,
        stackTrace: stackTrace,
      );
      onFailure?.call('read_failed');
      return null;
    }
    final fields = <String, String>{};
    for (final line in content.split('\n')) {
      final separator = line.indexOf(': ');
      if (separator <= 0) {
        continue;
      }
      fields[line.substring(0, separator)] = line
          .substring(separator + 2)
          .trim();
    }
    if (!const {'unhandled_exception', 'abort'}.contains(fields['kind']) ||
        !RegExp(r'^0x[0-9a-fA-F]+$').hasMatch(fields['exception_code'] ?? '')) {
      _log.error('Malformed crash summary ${p.basename(txtFile.path)}');
      onFailure?.call('parse_failed');
      return null;
    }
    return NativeCrashSummary(
      txtPath: txtFile.path,
      kind: fields['kind'] ?? '',
      occurredAt: fields['timestamp'] ?? '',
      pid: fields['pid'] ?? '',
      exceptionCode: fields['exception_code'] ?? '',
      exceptionAddress: fields['exception_address'] ?? '',
      module: fields['module'] ?? '',
      dumpPath: fields['dump_file'] ?? '',
      dumpError: fields['dump_error'] ?? 'unknown',
    );
  }

  /// 上报未处理的崩溃摘要；成功后把 txt 改名为 `.reported.txt`。
  Future<void> reportPendingCrashes(String crashDumpDir) async {
    try {
      await prepareLatestDump(crashDumpDir);
    } catch (error, stackTrace) {
      // 整理附件失败不阻断摘要上报；手动上传时会重试并显示失败。
      _log.error(
        'Failed to prepare latest native dump',
        error: error,
        stackTrace: stackTrace,
      );
    }
    final failures = <(File, String)>[];
    final pending = scanPending(
      crashDumpDir,
      onFailure: (file, code) => failures.add((file, code)),
    );
    for (final (file, code) in failures.take(maxReportsPerLaunch)) {
      try {
        final outcome = await _reportSink(
          phase: 'native_crash_summary_$code',
          error: StateError('summary_$code file=${p.basename(file.path)}'),
          stackTrace: StackTrace.current,
        );
        if (code == 'parse_failed' &&
            outcome != StartupFailureReportOutcome.retryableFailure) {
          await file.rename(
            '${file.path.substring(0, file.path.length - 4)}.reported.txt',
          );
        }
      } catch (error, stackTrace) {
        _log.error(
          'Failed to report crash summary diagnostic',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (pending.isEmpty) {
      return;
    }
    _log.warning(
      'Found ${pending.length} unreported native crash(es) in $crashDumpDir',
    );

    final staleCount = pending.length > maxReportsPerLaunch
        ? pending.length - maxReportsPerLaunch
        : 0;
    for (final summary in pending.sublist(0, staleCount)) {
      _log.info('Skipping stale native crash report: ${summary.txtPath}');
      await markReported(summary);
    }
    for (final summary in pending.sublist(staleCount)) {
      try {
        final outcome = await _reportSink(
          phase: 'native_crash',
          error: NativeCrashReport(summary),
          stackTrace: StackTrace.current,
        );
        if (outcome != StartupFailureReportOutcome.retryableFailure) {
          await markReported(summary);
        } else {
          _log.warning(
            'Native crash report retained for retry: ${summary.txtPath}',
          );
        }
      } catch (error, stackTrace) {
        _log.error(
          'Failed to report native crash ${summary.txtPath}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// 把摘要 txt 改名为 `.reported.txt`，防止下次启动重复上报。
  Future<void> markReported(NativeCrashSummary summary) async {
    final txtFile = File(summary.txtPath);
    if (!txtFile.existsSync()) {
      return;
    }
    final reportedPath = p.join(
      p.dirname(summary.txtPath),
      '${p.basenameWithoutExtension(summary.txtPath)}.reported.txt',
    );
    try {
      await txtFile.rename(reportedPath);
    } catch (error, stackTrace) {
      _log.error(
        'Failed to mark crash summary as reported: ${summary.txtPath}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
