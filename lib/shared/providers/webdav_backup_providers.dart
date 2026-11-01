// 职责: 提供 WebDAV 远程备份服务依赖。
// 关联文件:
//   lib/shared/services/webdav_backup_service.dart
//   lib/shared/providers/settings_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/service-naming.md

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/webdav_backup_service.dart';
import '../services/webdav_transport.dart';

final webDavTransportProvider = Provider<WebDavTransport>((ref) {
  return const WebDavTransport();
});

final webDavBackupServiceProvider = Provider<WebDavBackupService>((ref) {
  return WebDavBackupService(transport: ref.watch(webDavTransportProvider));
});
