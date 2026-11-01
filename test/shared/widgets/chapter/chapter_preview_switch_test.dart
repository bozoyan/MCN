// 职责: 验证桌面与移动端章节预览的设备选择会更新预览舞台，且窄屏布局不溢出。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_preview_dialog.dart
//   lib/mobile/pages/chapter_preview_page.dart
//   lib/shared/widgets/chapter/chapter_preview_stage.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/widgets/workspace/chapter_preview_dialog.dart';
import 'package:reveric/mobile/pages/chapter_preview_page.dart';
import 'package:reveric/shared/localization/app_localization.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/chapter/chapter_preview_stage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());

  for (final mobile in [false, true]) {
    testWidgets('device selection updates preview (mobile=$mobile)', (
      tester,
    ) async {
      tester.view.physicalSize = mobile
          ? const Size(375, 812)
          : const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(mobile: mobile));
      await tester.pumpAndSettle();
      final stage = find.byType(ChapterPreviewStage);
      expect(
        tester.widget<ChapterPreviewStage>(stage).device,
        ChapterPreviewDevice.phone390,
      );
      for (final device in ChapterPreviewDevice.values) {
        final label = tester.element(stage).t(device.labelKey);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.widget<ChapterPreviewStage>(stage).device, device);
        expect(tester.takeException(), isNull);
      }
    });
  }
}

Widget _wrap({required bool mobile}) {
  return ProviderScope(
    overrides: [
      editorFontFamilyProvider.overrideWithValue('Georgia'),
      editorFontSizeProvider.overrideWithValue(16),
      editorLetterSpacingProvider.overrideWithValue(0),
      editorLineHeightProvider.overrideWithValue(1.8),
    ],
    child: EasyLocalization(
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
          theme: RevericThemeData.reveric.toThemeData().copyWith(
            platform: mobile ? TargetPlatform.android : TargetPlatform.macOS,
          ),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: mobile
                ? const MobileChapterPreviewPage(
                    chapterTitle: 'Chapter 1',
                    chapterContent: 'A quiet morning.',
                  )
                : const Scaffold(
                    body: ChapterPreviewDialog(
                      chapterTitle: 'Chapter 1',
                      chapterContent: 'A quiet morning.',
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
}
