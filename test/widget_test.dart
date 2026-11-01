// 职责: 应用启动 smoke test — 验证 root widget 与应用级生命周期处理。
// 关联文件:
//   lib/main.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:drift/native.dart';

import 'package:reveric/main.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/providers/anonymous_reporting_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/anonymous_outbox_service.dart';

void main() {
  testWidgets('MyApp is a ConsumerWidget', (WidgetTester tester) async {
    // 不渲染完整 widget 树（依赖 database / EasyLocalization），
    // 只验证 MyApp 是可实例化的 ConsumerWidget。
    const app = MyApp();
    expect(app, isA<ConsumerWidget>());
  });

  testWidgets('lifecycle changes leave HardwareKeyboard state to Flutter', (
    WidgetTester tester,
  ) async {
    final usageHttpClient = http.Client();
    final database = AppDatabase.forTest(NativeDatabase.memory());
    final outbox = AnonymousOutboxService(
      database: database,
      httpClient: usageHttpClient,
      getBaseUrl: () => null,
      getEnabled: () => false,
    );
    addTearDown(usageHttpClient.close);
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          anonymousOutboxServiceProvider.overrideWithValue(outbox),
        ],
        child: const AppLifecycleWatcher(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    expect(HardwareKeyboard.instance.isMetaPressed, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(HardwareKeyboard.instance.isMetaPressed, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    expect(HardwareKeyboard.instance.isMetaPressed, isFalse);
  });
}
