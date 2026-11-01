// 职责: 验证阅读设置可切换字体，且设置页只展示宿主平台的翻页设置。
// 关联文件:
//   lib/shared/widgets/reading/reading_settings_controls.dart
//   lib/shared/widgets/reading/reading_font_family_picker.dart
//   lib/shared/widgets/settings/reading_settings_section.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/components/reveric_select.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/providers/system_font_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/reading/reading_settings_controls.dart';
import 'package:reveric/shared/widgets/settings/reading_settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(rootBundle.clear);

  testWidgets('reading settings dialog switches the reading font', (
    tester,
  ) async {
    final appDb = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(appDb.close);
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      appDb,
      const SingleChildScrollView(
        child: ReadingSettingsControls(
          compact: false,
          platform: ReadingSettingsPlatform.desktop,
        ),
      ),
    );

    final select = find.byType(RevericSelect<String>);
    expect(select, findsOneWidget);
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Songti SC').last);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(select));
    expect(container.read(readingFontFamilyProvider), 'Songti SC');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('settings page shows only the host platform page turning', (
    tester,
  ) async {
    final appDb = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(appDb.close);
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final platform in ReadingSettingsPlatform.values) {
      await _pump(tester, appDb, ReadingSettingsSection(platform: platform));

      final desktop = platform == ReadingSettingsPlatform.desktop;
      expect(find.text(tr(LocaleKeys.settingsReadingPageTurn)), findsOneWidget);
      // 说明只挂在首个 section，后续 section 不重复。
      expect(
        find.text(tr(LocaleKeys.settingsReadingDescription)),
        findsOneWidget,
      );
      expect(
        find.text(tr(LocaleKeys.settingsDesktopReadingContinuousScroll)),
        desktop ? findsOneWidget : findsNothing,
      );
      expect(
        find.text(tr(LocaleKeys.settingsMobileReadingHorizontal)),
        desktop ? findsNothing : findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Future<void> _pump(WidgetTester tester, AppDatabase appDb, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(appDb),
        appSettingsDatabaseProvider.overrideWithValue(appDb),
        systemFontFamiliesProvider.overrideWith(
          (ref) async => const ['Songti SC'],
        ),
      ],
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
            builder: (context, child) =>
                RevericTheme(data: RevericThemeData.reveric, child: child!),
            home: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
