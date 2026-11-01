// 职责: 验证剧本时间补全的初始候选、键盘选择、自由输入和输入法焦点。
// 关联文件:
//   lib/shared/widgets/screenplay/time_field.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/screenplay/time_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  testWidgets('time suggestions, IME and responsive layout', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController(text: 'Day');
    await tester.pumpWidget(_wrap(ScreenplayTimeField(controller: controller)));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(tester.getSize(field).height, RevericSizes.fieldHeight);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Night'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Night'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Night');
    await tester.enterText(field, 'Mo');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.widgetWithText(ListTile, 'Morning'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Night'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, 'Morning');
    await tester.tap(field);
    await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '傍晚',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(controller.value.composing, const TextRange(start: 0, end: 2));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '傍晚',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.text, '傍晚');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    // 新增时段可搜索并选择，值仍由输入框直接交回表单。
    for (final (query, expected) in [
      ('After', 'Afternoon'),
      ('Late n', 'Late night'),
    ]) {
      await tester.enterText(field, query);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, expected));
      await tester.pumpAndSettle();
      expect(controller.text, expected);
    }
    await tester.enterText(field, 'La');
    await tester.pump(const Duration(milliseconds: 20));
    await tester.enterText(field, '');
    await tester.pump();
    expect(find.widgetWithText(ListTile, 'Day'), findsOneWidget);
    tester.view.physicalSize = const Size(900, 844);
    await tester.pumpAndSettle();
    expect(tester.getSize(field).width, 852);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.enterText(field, 'Mor');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();
  });
}

Widget _wrap(Widget child) => EasyLocalization(
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
      theme: RevericThemeData.reveric.toThemeData(),
      home: RevericTheme(
        data: RevericThemeData.reveric,
        child: Scaffold(
          body: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    ),
  ),
);
