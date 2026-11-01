// 职责: 有界清理更新进程，记录并上报退出失败，保证已确认的更新退出不会停在清理阶段。
// 关联文件:
//   lib/shared/services/update/update_service.dart
//   lib/shared/services/single_instance_service.dart
//   lib/shared/logger/startup_failure_reporter.dart
//   lib/shared/services/crash_reporting/crash_sentinel.dart

import 'dart:async';
import 'dart:io';

import '../../logger/app_logger.dart';
import '../../logger/startup_failure_reporter.dart';
import '../crash_reporting/crash_sentinel.dart';

final _log = AppLogger.forModule('UpdateExit');

Future<void> exitForUpdate({
  required Future<void> Function() releaseInstance,
  required void Function() markCleanExit,
  required void Function(int) terminate,
  StartupFailureReporter? failureReporter,
  Duration cleanupTimeout = const Duration(seconds: 3),
}) async {
  final watch = Stopwatch()..start();
  var stage = 'mark_clean_exit';
  _log.checkpoint('update exit started pid=$pid stage=$stage');
  CrashSentinel.markActiveExitProgressSync(source: 'update', phase: stage);
  try {
    // 必须在释放锁之前清理当前 marker，避免新实例把正在退出的进程误报为崩溃。
    markCleanExit();
    stage = 'release_instance';
    _log.checkpoint('update exit pid=$pid stage=$stage');
    await releaseInstance().timeout(cleanupTimeout);
  } catch (error, stack) {
    final reason =
        '${stage}_${error is TimeoutException ? 'timeout' : 'failed'}';
    _log.error(
      'Update exit failed stage=$stage',
      error: error,
      stackTrace: stack,
    );
    CrashSentinel.markActiveExitProgressSync(source: 'update', phase: reason);
    try {
      await (failureReporter ?? StartupFailureReporter())
          .reportLifecycleFailure(
            phase: 'update_exit',
            reason: reason,
            error: error,
            stackTrace: stack,
          )
          .timeout(const Duration(seconds: 5));
    } catch (reportError) {
      _log.warning('Update exit report did not finish: $reportError');
    }
  } finally {
    _log.checkpoint(
      'update exit terminating pid=$pid elapsed_ms=${watch.elapsedMilliseconds}',
    );
    // 只终止当前已确认要更新的进程，不结束其它实例；OS 负责释放残余句柄。
    terminate(0);
  }
}
