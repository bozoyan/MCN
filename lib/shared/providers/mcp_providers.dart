// 职责: 在应用容器内共享 MCP 配置、连接与独立 OAuth 事务。
// 关联文件:
//   lib/shared/services/mcp/settings_service.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/models/mcp/config.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/mcp/config.dart';
import '../services/mcp/settings_service.dart';
import '../services/mcp/runtime.dart';
import 'settings_providers.dart';

// 单一应用容器拥有连接；页面切换和单次聊天取消不得销毁共享 transport。
final mcpSettingsServiceProvider = Provider<McpSettingsService>((ref) {
  final service = McpSettingsService(
    ref.watch(appSettingsDatabaseProvider),
    supportsStdio: !Platform.isAndroid,
  );
  ref.onDispose(() => unawaited(service.close()));
  return service;
});
final mcpSettingsProvider = StreamProvider<McpSettings>(
  (ref) => ref
      .watch(appSettingsDatabaseProvider)
      .appSettingsDao
      .watch(McpSettings.key)
      .map(McpSettings.decode),
);
final mcpConnectionStatesProvider =
    StreamProvider<Map<String, McpConnectionState>>((ref) async* {
      final service = ref.watch(mcpSettingsServiceProvider);
      await service.initialized;
      yield service.runtime.states;
      yield* service.runtime.changes;
    });
