// 职责: 验证 A2UI 调试预览可切换全部样例与插件配置表单，且在桌面与移动端布局下无异常。
// 关联文件:
//   lib/shared/widgets/a2ui/preview/preview_panel.dart
//   lib/shared/widgets/a2ui/preview/config_preview.dart
//   lib/shared/widgets/a2ui/preview/samples.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/a2ui/preview/preview_panel.dart';
import 'package:reveric/shared/widgets/a2ui/preview/samples.dart';
import 'package:reveric/shared/widgets/app_background.dart';
import 'package:reveric/shared/widgets/settings/plugins/config_form.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, Size size) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: [appBackgroundActiveProvider.overrideWithValue(false)],
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: SizedBox.fromSize(size: size, child: child),
              ),
            ),
          ),
        );
      },
    ),
  );
}

void main() {
  setUp(() => rootBundle.clear());

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final (platform, size) in [
    (TargetPlatform.macOS, const Size(1040, 720)),
    (TargetPlatform.android, const Size(400, 800)),
  ]) {
    testWidgets('switches every sample and the config form ($platform)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_wrap(const A2uiPreviewPanel(), size));
        await tester.pumpAndSettle();

        for (final sample in a2uiSamples.skip(1)) {
          await tester.tap(find.text(a2uiSamples.first.title).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text(sample.title).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: sample.id);
          // 回到第一个样例，下一轮从同一个触发器打开菜单。
          await tester.tap(find.text(sample.title).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text(a2uiSamples.first.title).last);
          await tester.pumpAndSettle();
        }

        await tester.tap(find.text('Plugin settings form'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(PluginConfigForm), findsOneWidget);
        expect(find.text('Nothing saved yet'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }
}
