// 职责: 验证自定义主题实时展示、选择、明暗预览及软删除后的列表更新。
// 关联文件:
//   lib/shared/widgets/settings/custom_themes_section.dart
//   lib/shared/providers/custom_themes_provider.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart' show AppDatabase;
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/providers/custom_themes_provider.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/services/themes_orchestrator.dart';
import 'package:reveric/shared/widgets/settings/custom_themes_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends AppSettingsNotifier {
  final commands = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> runThemeCommand(
    Map<String, dynamic> command,
  ) async {
    commands.add(command);
    final theme = ref
        .read(customThemesProvider)
        .requireValue
        .firstWhere((theme) => theme.id == command['id']);
    state = AsyncData(state.requireValue.copyWith(customTheme: theme));
    return {'ok': true};
  }

  @override
  Future<void> setThemeMode(AppThemeMode mode) async {
    state = AsyncData(state.requireValue.copyWith(themeMode: mode));
  }

  @override
  Future<AppSettings> build() async => AppSettings(
    theme: AppTheme.reveric,
    themeMode: AppThemeMode.light,
    language: 'en',
    aiSettings: AiSettings(providers: []),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());

  testWidgets(
    'live theme list supports selection, dark preview and soft deletion at mobile width',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = AppDatabase.forTest(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          appSettingsDatabaseProvider.overrideWithValue(db),
          appSettingsProvider.overrideWith(_Settings.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await tester.runAsync(() => container.read(appSettingsProvider.future));
      final notifier =
          container.read(appSettingsProvider.notifier) as _Settings;
      final orchestrator = ThemesOrchestrator();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: EasyLocalization(
            supportedLocales: const [Locale('en')],
            startLocale: const Locale('en'),
            path: 'assets/translations',
            assetLoader: const MergingAssetLoader(),
            child: Builder(
              builder: (context) => MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: Consumer(
                  builder: (context, ref, _) {
                    final data = ref
                        .watch(appSettingsProvider)
                        .requireValue
                        .themeData;
                    return RevericTheme(
                      data: data,
                      child: Scaffold(
                        body: const SingleChildScrollView(
                          child: CustomThemesSection(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() => container.read(customThemesProvider.future));
      await tester.pumpAndSettle();
      expect(find.text('Custom themes'), findsNothing);
      expect(tester.getSize(find.byType(CustomThemesSection)).height, 0);

      late String id;
      await tester.runAsync(() async {
        final result = await orchestrator.run(db, {
          'action': 'create',
          'name': 'Forest',
          'baseTheme': 'reveric',
          'lightOverrides': {'accent': '#245C42', 'onAccent': '#FFFFFF'},
          'darkOverrides': {'accent': '#A4CBA6', 'onAccent': '#172118'},
        });
        expect(result['ok'], isTrue, reason: '$result');
        id = result['id'] as String;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Forest'), findsOneWidget);
      expect(find.text('Custom themes'), findsOneWidget);
      final card = find.byKey(ValueKey('custom-theme-$id'));
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(
        container.read(appSettingsProvider).requireValue.customTheme?.id,
        id,
      );
      expect(notifier.commands, [
        {'action': 'apply', 'id': id},
      ]);
      expect(tester.widget<InkWell>(card).onTap, isNull);
      await notifier.setThemeMode(AppThemeMode.dark);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container && widget.color == const Color(0xFFA4CBA6),
        ),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await orchestrator.run(db, {
          'action': 'update',
          'id': id,
          'revision': 1,
          'name': 'Forest renamed',
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Forest renamed'), findsOneWidget);
      await tester.runAsync(() async {
        await orchestrator.run(db, {
          'action': 'delete',
          'id': id,
          'revision': 2,
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Forest renamed'), findsNothing);
      expect(find.text('Custom themes'), findsNothing);
      expect(tester.getSize(find.byType(CustomThemesSection)).height, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
