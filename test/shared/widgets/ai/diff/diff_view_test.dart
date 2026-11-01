// 职责: 验证统一 diff 视图在窄容器中仍能约束折叠区提示，不产生横向溢出。
// 关联文件:
//   lib/shared/widgets/ai/diff/diff_view.dart
//   lib/shared/utils/line_diff.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/diff.json
//   assets/translations/zh-CN/diff.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/diff/diff_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('collapsed hunk fits the narrow inline diff width', (
    tester,
  ) async {
    final contextLines = List.generate(12, (index) => 'unchanged $index');
    final oldText = ['before', ...contextLines].join('\n');
    final newText = ['after', ...contextLines].join('\n');

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 158.3,
          child: AiDiffView(oldText: oldText, newText: newText),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('9 unchanged'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return RevericTheme(
          data: RevericThemeData.reveric,
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: Scaffold(body: Center(child: child)),
          ),
        );
      },
    ),
  );
}
