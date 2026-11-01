// 职责: 验证供应商搜索、跨平台详情导航、渠道链接和配置编辑布局。
// 关联文件:
//   lib/shared/widgets/settings/ai_providers_section.dart
//   lib/shared/widgets/settings/provider_config_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reveric/shared/components/reveric_search_field.dart';
import 'package:reveric/shared/components/reveric_text_field.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/provider_brand.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/settings/ai_providers_section.dart';
import 'package:reveric/shared/widgets/settings/provider_config_panel.dart';
import 'package:reveric/shared/widgets/settings/provider_logo.dart';

final _metaso = aiProviderBuiltinById('metaso')!;
final _configs = [_metaso, aiProviderBuiltinById('deepseek')!];

class _Settings extends AppSettingsNotifier {
  final saved = <AiProvider>[];
  @override
  Future<AppSettings> build() async => AppSettings(
    theme: AppTheme.reveric,
    themeMode: AppThemeMode.light,
    language: 'en',
    aiSettings: AiSettings(providers: _configs),
  );
  @override
  Future<void> setAiProviderConfig(AiProvider config) async {
    saved.add(config);
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());
  testWidgets(
    'all bundled provider logos and an unknown channel render offline',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          Wrap(
            children: [
              for (final type in [
                ...providerLogoAssets.keys,
                'codex',
                'custom',
              ])
                ProviderLogo(type: type),
            ],
          ),
          false,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('C'), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.android,
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        '$platform dark=$dark searches, opens details and saves the key',
        (tester) async {
          final mobile = platform == TargetPlatform.android;
          await tester.binding.setSurfaceSize(Size(mobile ? 360 : 900, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final settings = _Settings();
          final launched = <String>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'),
            (call) async {
              if (call.method == 'launch') {
                launched.add((call.arguments as Map)['url'] as String);
              }
              return true;
            },
          );
          addTearDown(
            () =>
                tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                  const MethodChannel('plugins.flutter.io/url_launcher'),
                  null,
                ),
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appSettingsProvider.overrideWith(() => settings),
                aiSettingsProvider.overrideWithValue(
                  AiSettings(providers: _configs),
                ),
              ],
              child: _wrap(const AiProvidersSection(), dark),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final search = find.descendant(
            of: find.byType(RevericSearchField),
            matching: find.byType(EditableText),
          );
          await tester.enterText(search, 'seedance');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('DeepSeek'), findsNothing);
          await tester.enterText(search, 'no-such-provider');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('No matches'), findsOneWidget);
          await tester.enterText(search, '');
          await tester.pump();
          expect(find.text('DeepSeek'), findsOneWidget);
          if (mobile) {
            await tester.tap(find.text('METASO'));
            await tester.pumpAndSettle();
          }
          expect(find.byType(ProviderConfigPanel), findsOneWidget);
          expect(find.byType(ProviderLogo), findsWidgets);
          expect(
            find.descendant(
              of: find.byType(ProviderConfigPanel),
              matching: find.text('Chat models'),
            ),
            findsNothing,
          );
          expect(find.text('seedance-2.0'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Go to METASO · Get API key'));
          await tester.tap(find.text('Go to METASO · Get API key'));
          await tester.pumpAndSettle();
          expect(launched, ['https://metaso.cn/minimax-h3/?s=Reveric']);
          final keyField = find.descendant(
            of: find.widgetWithText(RevericTextField, 'API Key'),
            matching: find.byType(EditableText),
          );
          await tester.ensureVisible(keyField);
          await tester.enterText(keyField, 'test-key');
          await tester.pumpAndSettle();
          expect(settings.saved.last.apiKey, 'test-key');
          expect(settings.saved.last.videoModels, _metaso.videoModels);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
        variant: TargetPlatformVariant.only(platform),
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  }
}

Widget _wrap(Widget child, bool dark) {
  final theme = dark ? RevericThemeData.revericDark : RevericThemeData.reveric;
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    startLocale: const Locale('en'),
    fallbackLocale: const Locale('en'),
    child: Builder(
      builder: (context) => MaterialApp(
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: theme.toThemeData(),
        builder: (_, child) => RevericTheme(data: theme, child: child!),
        home: Scaffold(body: child),
      ),
    ),
  );
}
