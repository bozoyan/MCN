// 职责: 将日志事件格式化为包含时间、级别和完整异常信息的紧凑文本
// 关联文件:
//   lib/shared/logger/log_manager.dart
//   lib/shared/logger/app_logger.dart
import 'package:logger/logger.dart';

class CompactLogPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    return [
      '${event.time.toIso8601String()} '
          '[${event.level.name.toUpperCase()}] ${event.message}',
      if (event.error != null) 'Error: ${event.error}',
      if (event.stackTrace != null) event.stackTrace.toString(),
    ];
  }
}
