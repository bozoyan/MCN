// 职责: 验证查找栏在跳到屏外匹配时仍固定可见，并滚动正文到匹配处。
// 关联文件:
//   lib/shared/widgets/text_find_replace_scope.dart
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/text_find_replace_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'next match outside viewport scrolls content and keeps find bar visible',
    (tester) async {
      final controller = TextEditingController(
        text: 'alpha\n${'line\n' * 80}omega alpha',
      );
      final focusNode = FocusNode();
      final scrollController = ScrollController();

      await tester.pumpWidget(
        _wrap(
          TextFindReplaceScope(
            controller: controller,
            editorFocusNode: focusNode,
            child: SizedBox(
              height: 240,
              child: SingleChildScrollView(
                controller: scrollController,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLines: null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      // 查找框 hint 为「查找」；用 hint 定位，避免点到正文 TextField。
      final queryField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.hintText == '查找',
      );
      expect(queryField, findsOneWidget);
      await tester.enterText(queryField, 'alpha');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('1/2'), findsOneWidget);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
        reason: '输入停止后应自动选中首个匹配，无需按 Enter',
      );

      // 固定到首个匹配并滚回顶部，再点「下一个」验证屏外跳转。
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      scrollController.jumpTo(0);
      await tester.pumpAndSettle();
      expect(scrollController.offset, 0);

      final nextButton = find.byTooltip('查找下一个');
      expect(nextButton, findsOneWidget);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(find.byTooltip('查找下一个'), findsOneWidget);
      expect(scrollController.offset, greaterThan(0));
      expect(controller.selection.start, greaterThan(5));
      expect(
        controller.text.substring(
          controller.selection.start,
          controller.selection.end,
        ),
        'alpha',
      );

      controller.dispose();
      focusNode.dispose();
      scrollController.dispose();
    },
  );
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) {
        return MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          theme: RevericThemeData.reveric.toThemeData(),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(
              body: Center(child: SizedBox(width: 480, child: child)),
            ),
          ),
        );
      },
    ),
  );
}
