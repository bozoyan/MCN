// 职责: 验证只读 Provider 获取的 MCP 服务保活、命令保存及移动工具连接生命周期。
// 关联文件:
//   lib/shared/providers/mcp_providers.dart
//   lib/shared/services/mcp/settings_service.dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/providers/mcp_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/services/mcp/settings_service.dart';
import '../services/mcp/runtime_test.dart' show FakeConnection;

void main() {
  test(
    'read-only command keeps one application service and publishes committed settings',
    () async {
      final database = AppDatabase.forTest(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appSettingsDatabaseProvider.overrideWithValue(database)],
      );
      final service = container.read(mcpSettingsServiceProvider);
      try {
        await service.initialized;
        await pumpEventQueue();
        expect(container.read(mcpSettingsServiceProvider), same(service));
        await service.save(
          McpServerConfig(
            name: 'notes',
            connection: McpHttpConfig(url: 'https://example.test'),
          ),
          create: true,
        );
        final subscription = container.listen(mcpSettingsProvider, (_, _) {});
        addTearDown(subscription.close);
        final settings = await container.read(mcpSettingsProvider.future);
        expect(settings.servers.single.name, 'notes');
        expect(settings.servers.single.enabled, false);
      } finally {
        container.dispose();
        await service.close();
        await database.close();
      }
    },
  );
  test('foreground restore reconnects tools without replaying calls', () async {
    final database = AppDatabase.forTest(NativeDatabase.memory());
    final connections = <FakeConnection>[];
    final service = McpSettingsService(
      database,
      supportsStdio: false,
      connector: (_) async {
        final connection = FakeConnection();
        connections.add(connection);
        return connection;
      },
    );
    try {
      await service.initialized;
      await service.save(
        McpServerConfig(
          name: 'notes',
          enabled: true,
          connection: McpHttpConfig(url: 'https://example.test'),
        ),
        create: true,
      );
      await service.activate();
      await service.runtime.ensureReady('notes');
      expect(connections, hasLength(1));
      await service.setForeground(false);
      expect(connections.first.closed, true);
      await service.setForeground(true);
      expect(connections, hasLength(2));
      expect(connections.last.closed, false);
      await service.setForeground(true);
      expect(connections, hasLength(2));
    } finally {
      await service.close();
      await database.close();
    }
  });
}
