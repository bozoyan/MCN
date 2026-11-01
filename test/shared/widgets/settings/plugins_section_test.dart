// 职责: 验证插件设置在桌面与移动宽度显示详情并切换实际可用工具。
// 关联文件:
//   lib/shared/widgets/settings/plugins/section.dart
//   lib/shared/providers/plugin_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reveric/shared/database/app_database.dart' hide PluginRegistry;
import 'package:reveric/shared/providers/plugin_providers.dart';
import 'package:reveric/shared/services/plugins/host.dart';
import 'package:reveric/shared/models/plugin/manifest.dart';
import 'package:reveric/shared/services/plugins/registry.dart';
import 'package:reveric/shared/widgets/settings/plugins/section.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import '../../services/plugins/host_test.dart' show FakeExecutor, package;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      'user can inspect and disable plugin tools on narrow and wide screens (${platform.name})',
      (tester) async {
        final db = AppDatabase.forTest(NativeDatabase.memory());
        final host = PluginHostService(
          dao: db.pluginDao,
          registry: PluginRegistry(hostToolNames: {}),
          packages: () async => [package()],
          executorFactory: (call, stop) => FakeExecutor(),
          platform: 'macos',
        );
        await tester.runAsync(host.start);
        addTearDown(() async {
          await host.dispose();
          await db.close();
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(wrapPluginSettings(host, platform: platform));
        await tester.pumpAndSettle();
        expect(find.text('Test'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('plugin-details-test.web')));
        await tester.pumpAndSettle();
        expect(find.textContaining('WebSearch'), findsOneWidget);
        expect(tester.takeException(), null);
        await tester.tap(find.byKey(const ValueKey('plugin-toggle-test.web')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
        expect(host.registry.effectiveTools, isEmpty);
        expect(find.text('Disabled'), findsOneWidget);
        tester.view.physicalSize = const Size(1000, 800);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('plugin-toggle-test.web')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pumpAndSettle();
        expect(host.registry.effectiveTools, hasLength(2));
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'activation failure shows a useful reason without raw diagnostics',
    (tester) async {
      final db = AppDatabase.forTest(NativeDatabase.memory());
      final host = PluginHostService(
        dao: db.pluginDao,
        registry: PluginRegistry(hostToolNames: {}),
        packages: () async => [package()],
        executorFactory: (call, stop) => _InvalidPluginExecutor(),
        platform: 'macos',
      );
      await tester.runAsync(host.start);
      addTearDown(() async {
        await host.dispose();
        await db.close();
      });
      await tester.pumpWidget(wrapPluginSettings(host));
      await tester.pumpAndSettle();
      expect(find.text('Failed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plugin-details-test.web')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The plugin package is invalid. Check its manifest and entry file.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('private-token'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

Widget wrapPluginSettings(
  PluginHostService host, {
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderScope(
  overrides: [pluginHostServiceProvider.overrideWithValue(host)],
  child: EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) => MaterialApp(
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: RevericThemeData.reveric.toThemeData().copyWith(
          platform: platform,
        ),
        home: RevericTheme(
          data: RevericThemeData.reveric,
          child: const Scaffold(body: PluginsSettingsSection()),
        ),
      ),
    ),
  ),
);

class _InvalidPluginExecutor extends FakeExecutor {
  @override
  Future<List<Map<String, dynamic>>> activate(
    PluginManifest manifest,
    String code,
  ) async {
    throw const FormatException('Invalid schema private-token');
  }
}
