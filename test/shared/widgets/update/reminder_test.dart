// 职责: 验证更新轻提示的关闭、查看操作、自动消失与后台延迟展示。
// 关联文件:
//   lib/shared/widgets/update/reminder.dart
//   lib/shared/providers/update_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/app_config.dart' show appVersion;
import 'package:reveric/shared/providers/update_providers.dart';
import 'package:reveric/shared/services/update.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/update/reminder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Source implements UpdateSource {
  _Source([this.pending]);
  final Future<UpdateCheckResult>? pending;
  @override
  Future<UpdateCheckResult> checkForUpdate(String currentVersion) async =>
      pending ??
      const UpdateAvailable(
        UpdateInfo(
          version: '9.0.0',
          downloadUrl: 'https://example.com/update.zip',
        ),
      );
}

Widget _wrap({
  required VoidCallback onView,
  bool mobile = false,
  _Source? source,
}) {
  return ProviderScope(
    overrides: [updateSourceProvider.overrideWithValue(source ?? _Source())],
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
          theme: RevericThemeData.reveric.toThemeData(),
          builder: (context, child) => RevericTheme(
            data: RevericThemeData.reveric,
            child: Stack(
              children: [
                child!,
                UpdateReminder(onViewUpdate: onView, mobile: mobile),
              ],
            ),
          ),
          home: const Scaffold(body: Text('Editor')),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() {
    // AssetBundle 缓存的 Future 不跨 testWidgets 的 FakeAsync zone 复用。
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'preview works without a new release, repeats and does not mark history',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          onView: () {},
          source: _Source(Future.value(const UpdateUpToDate())),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(UpdateReminder)),
      );
      expect(find.text('View update'), findsNothing);
      for (var i = 0; i < 2; i++) {
        container.read(updateReminderPreviewProvider.notifier).show();
        await tester.pumpAndSettle();
        expect(find.text('Version v$appVersion is available'), findsOneWidget);
        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();
        expect(find.text('View update'), findsNothing);
      }
      expect(
        container.read(latestReleaseProvider).value,
        isA<UpdateUpToDate>(),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(LatestRelease.notifiedVersionsKey), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('view action opens target and dismisses reminder', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(_wrap(onView: () => opened++));
    await tester.pumpAndSettle();
    expect(find.text('Version v9.0.0 is available'), findsOneWidget);
    await tester.tap(find.text('View update'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('Version v9.0.0 is available'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'close preserves editor and reminder stays dismissed after resume',
    (tester) async {
      await tester.pumpWidget(_wrap(onView: () {}));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.text('Editor'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('View update'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'mobile reminder waits for foreground then expires without moving content',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<UpdateCheckResult>();
      await tester.pumpWidget(
        _wrap(onView: () {}, mobile: true, source: _Source(pending.future)),
      );
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('Editor'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(
        const UpdateAvailable(
          UpdateInfo(
            version: '9.0.0',
            downloadUrl: 'https://example.com/update.zip',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('View update'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('View update'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Editor')), before);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.text('View update'), findsNothing);
      expect(tester.getTopLeft(find.text('Editor')), before);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
