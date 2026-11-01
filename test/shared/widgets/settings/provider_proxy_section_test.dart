// 职责: 验证 AI 供应商代理设置在桌面与移动尺寸下的格式校验，以及不合法时不写回配置。
// 关联文件:
//   lib/shared/widgets/settings/provider_config_panel.dart
//   lib/shared/widgets/settings/proxy_settings_section.dart
//   lib/shared/models/network_proxy.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/components/reveric_text_field.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/settings/provider_config_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _openai = aiProviderBuiltinById('openai')!;

class _Settings extends AppSettingsNotifier {
  final saved = <AiProvider>[];

  @override
  Future<AppSettings> build() async => AppSettings(
    theme: AppTheme.reveric,
    themeMode: AppThemeMode.light,
    language: 'en',
    aiSettings: AiSettings(providers: [_openai]),
  );

  @override
  Future<void> setAiProviderConfig(AiProvider config) async =>
      saved.add(config);
}

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
      '$platform validates the provider proxy before saving it',
      (tester) async {
        await tester.binding.setSurfaceSize(
          Size(platform == TargetPlatform.android ? 375 : 900, 1600),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final settings = _Settings();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appSettingsProvider.overrideWith(() => settings),
              aiSettingsProvider.overrideWithValue(
                AiSettings(providers: [_openai]),
              ),
            ],
            child: _wrap(ProviderConfigPanel(providerId: _openai.id)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Proxy'));
        await tester.tap(find.text('Proxy'));
        await tester.pumpAndSettle();

        Finder field(String label) => find.descendant(
          of: find.widgetWithText(RevericTextField, label),
          matching: find.byType(EditableText),
        );
        Future<void> enter(String label, String text) async {
          await tester.ensureVisible(field(label));
          await tester.enterText(field(label), text);
          await tester.pumpAndSettle();
        }

        await enter('URL', '127.0.0.1:7890');
        expect(find.textContaining('Enter an http://'), findsOne);
        expect(settings.saved, isEmpty);

        // 代理不合法时编辑其他字段，不能把未通过校验的代理一起写回。
        await enter('API Key', 'sk-test');
        expect(settings.saved.single.apiKey, 'sk-test');
        expect(settings.saved.single.proxyUrl, '');

        await enter('URL', 'socks5://127.0.0.1:1080');
        expect(find.textContaining('Enter an http://'), findsNothing);
        expect(settings.saved.last.proxyUrl, 'socks5://127.0.0.1:1080');

        final count = settings.saved.length;
        await enter('Username', 'us:er');
        expect(find.text('Enter both a username and a password.'), findsOne);
        expect(settings.saved, hasLength(count));

        await enter('Password', 'pa;ss');
        expect(
          find.text('Enter both a username and a password.'),
          findsNothing,
        );
        expect(
          (
            settings.saved.last.proxyUsername,
            settings.saved.last.proxyPassword,
          ),
          ('us:er', 'pa;ss'),
        );

        // HTTP 代理凭据不能含 `:` / `;`，切换后应提示且不保存。
        await enter('URL', 'http://127.0.0.1:7890');
        expect(find.textContaining("can't contain : or ;"), findsOne);
        expect(find.textContaining("can't contain ;."), findsOne);
        expect(settings.saved.last.proxyUrl, 'socks5://127.0.0.1:1080');
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }
}

Widget _wrap(Widget child) => EasyLocalization(
  supportedLocales: const [Locale('en')],
  startLocale: const Locale('en'),
  fallbackLocale: const Locale('en'),
  path: 'assets/translations',
  assetLoader: const MergingAssetLoader(),
  child: Builder(
    builder: (context) => MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: RevericThemeData.reveric.toThemeData(),
      home: RevericTheme(
        data: RevericThemeData.reveric,
        child: Scaffold(body: child),
      ),
    ),
  ),
);
