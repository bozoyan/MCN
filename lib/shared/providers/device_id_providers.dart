// 职责: 提供跨匿名上报和匿名上传复用的设备 ID 服务。
// 关联文件:
//   lib/shared/services/device_id_service.dart
//   lib/shared/providers/trace_providers.dart
//   lib/shared/providers/anonymous_reporting_providers.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/device_id_service.dart';

part 'device_id_providers.g.dart';

/// Device ID 服务 Provider。
@riverpod
DeviceIdService deviceIdService(Ref ref) {
  return DeviceIdService();
}
