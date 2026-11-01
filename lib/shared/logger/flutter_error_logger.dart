// 职责: Flutter 错误日志桥接 — 保留框架默认错误展示，并同步写入 AppLogger。
// 关联文件:
//   lib/main.dart
//   lib/shared/logger/app_logger.dart
//   lib/shared/logger/startup_failure_reporter.dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_logger.dart';

final _log = AppLogger.forModule('FlutterError');

typedef FlutterErrorLogSink =
    void Function(String message, {Object? error, StackTrace? stackTrace});
typedef FlutterErrorReportSink =
    Future<void> Function(Object error, StackTrace stackTrace);

void installFlutterErrorLogger({
  FlutterExceptionHandler? presentErrorOverride,
  FlutterErrorLogSink? logErrorOverride,
  FlutterErrorReportSink? reportErrorOverride,
}) {
  FlutterError.onError = (details) {
    (presentErrorOverride ?? FlutterError.presentError)(details);
    // RenderFlex 溢出等布局错误的定位信息(widget creator 链)在
    // informationCollector 里,不拼进消息就只剩一句溢出行,无法定位。
    final message = StringBuffer(details.exceptionAsString());
    if (details.informationCollector != null) {
      for (final line in details.informationCollector!()) {
        message.write('\n${line.toString()}');
      }
    }
    (logErrorOverride ?? _log.error)(
      message.toString(),
      error: details.exception,
      stackTrace: details.stack,
    );
    if (reportErrorOverride != null) {
      unawaited(
        reportErrorOverride(
          details.exception,
          details.stack ?? StackTrace.current,
        ),
      );
    }
  };
}
