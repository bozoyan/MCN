// 职责: 匿名 trace 上报相关 Riverpod Provider
// 关联文件:
//   lib/shared/services/device_id_service.dart
//   lib/shared/services/ai/trace_reporter_service.dart
//   lib/shared/providers/anonymous_reporting_providers.dart
//   lib/shared/providers/device_id_providers.dart
//

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/ai/trace_reporter_service.dart';
import 'anonymous_reporting_providers.dart';
import 'device_id_providers.dart';

part 'trace_providers.g.dart';

/// Trace 上报服务 Provider（全局单例，keepAlive）
///
@Riverpod(keepAlive: true)
TraceReporterService traceReporterService(Ref ref) {
  final deviceIdService = ref.watch(deviceIdServiceProvider);
  final service = TraceReporterService(
    deviceIdService: deviceIdService,
    outbox: ref.watch(anonymousOutboxServiceProvider),
  );
  ref.onDispose(() {
    service.dispose();
  });
  return service;
}
