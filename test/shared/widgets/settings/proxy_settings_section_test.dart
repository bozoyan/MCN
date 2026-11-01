// 职责: 验证代理设置在桌面与移动尺寸下的模式切换、地址校验和保存。
// 关联文件:
//   lib/shared/widgets/settings/proxy_settings_section.dart
//   lib/shared/models/network_proxy.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reveric/shared/components/reveric_select.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/network_proxy.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/settings/proxy_settings_section.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      '$platform validates custom proxy and saves the selected mode',
      (tester) async {
        tester.view.physicalSize = Size(
          platform == TargetPlatform.android ? 360 : 800,
          800,
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final saved = <NetworkProxy>[];
        await tester.pumpWidget(
          _wrap(
            ProxySettingsForm(
              config: const NetworkProxy(),
              onSave: (config) async => saved.add(config),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Environment variables'), findsOneWidget);
        expect(find.byType(EditableText), findsNothing);
        await tester.tap(find.byType(RevericSelect<NetworkProxyMode>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Custom proxy'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(EditableText).first, 'invalid');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(saved, isEmpty);
        expect(find.textContaining('Enter an http://'), findsOneWidget);
        await tester.enterText(
          find.byType(EditableText).first,
          'http://127.0.0.1:7890',
        );
        await tester.enterText(find.byType(EditableText).at(1), 'us:er');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(saved, isEmpty);
        expect(find.text('Enter both a username and a password.'), findsOne);
        expect(find.textContaining("can't contain : or ;"), findsOne);
        await tester.enterText(
          find.byType(EditableText).first,
          'socks5://127.0.0.1:1080',
        );
        await tester.enterText(find.byType(EditableText).at(2), 'secret');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(saved.single.mode, NetworkProxyMode.custom);
        expect(saved.single.url, 'socks5://127.0.0.1:1080');
        expect(
          (saved.single.username, saved.single.password),
          ('us:er', 'secret'),
        );
        await tester.tap(find.byType(RevericSelect<NetworkProxyMode>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('No proxy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(saved.last.mode, NetworkProxyMode.direct);
        expect(saved.last.url, saved.first.url);
        expect(saved.last.username, saved.first.username);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant({platform}),
    );
  }
}

Widget _wrap(Widget child) => EasyLocalization(
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
      home: RevericTheme(
        data: RevericThemeData.reveric,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    ),
  ),
);
