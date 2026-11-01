// 职责: 折叠 AI 面板布局回归测试 — 确保主体背景铺满整条窄轨。
// 关联文件:
//   lib/desktop/widgets/novel_editor/collapsed_ai_panel.dart
//   lib/shared/widgets/app_background.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/testing.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/widgets/novel_editor/collapsed_ai_panel.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/app_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('body background fills the collapsed rail width', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appBackgroundActiveProvider.overrideWithValue(false)],
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
              home: RevericTheme(
                data: RevericThemeData.reveric,
                child: const Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      height: 240,
                      child: NovelEditorCollapsedAiPanel(onExpand: _noop),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final panel = find.byType(NovelEditorCollapsedAiPanel);
    final backgrounds = find.descendant(
      of: panel,
      matching: find.byType(ColoredBox),
    );

    expect(backgrounds, findsNWidgets(2));
    expect(
      tester.getSize(backgrounds.at(1)).width,
      tester.getSize(backgrounds.first).width,
    );
    expect(tester.getSize(panel).width, NovelEditorCollapsedAiPanel.width);
  });
}

void _noop() {}
