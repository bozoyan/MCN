// 职责: 验证更新轻提示的关闭、查看操作、自动消失与后台延迟展示。
// 关联文件:
//   lib/shared/widgets/update/reminder.dart
//   lib/shared/providers/update_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
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

}
