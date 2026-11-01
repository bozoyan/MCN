// 职责: 验证触屏在空白处短按/长按弹出粘贴与换行，并执行换行与粘贴
// 关联文件:
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/widgets/md/block/markdown_block_list_view.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:ui' show PointerDeviceKind;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/md/block/markdown_block_list_view.dart';
import 'package:reveric/shared/widgets/md/block/markdown_readonly_block.dart';
import 'package:reveric/shared/widgets/md/reveric_markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('空白处长按与短按显示粘贴/换行，再点空白收起', (tester) async {
    final longPressController = TextEditingController();
    final longPressFocus = FocusNode();
    addTearDown(() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.testTextInput.reset();
      longPressController.dispose();
      longPressFocus.dispose();
    });

    await tester.pumpWidget(
      _wrap(_emptyEditor(longPressController, longPressFocus)),
    );
    await tester.pumpAndSettle();

    final editorCenter = tester.getCenter(find.byType(MarkdownReadonlyBlock));
    final longPress = await tester.startGesture(
      editorCenter,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 600));
    await longPress.up();
    await tester.pumpAndSettle();

    _expectCaretMenu(tester);
    await tester.tap(find.byKey(_touchMenuNewlineKey));
    await tester.pumpAndSettle();
    expect(longPressController.text, '\n');
    expect(find.byKey(_touchMenuKey), findsNothing);

    final tapController = TextEditingController();
    final tapFocus = FocusNode();
    addTearDown(tapController.dispose);
    addTearDown(tapFocus.dispose);
    await tester.pumpWidget(_wrap(_emptyEditor(tapController, tapFocus)));
    await tester.pumpAndSettle();
    await tester.tapAt(editorCenter, kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    _expectCaretMenu(tester);

    String? clipboardText;
    _mockClipboard((text) => clipboardText = text, readText: () => '剪贴板');
    await tester.tap(find.byKey(_touchMenuPasteKey));
    await tester.pumpAndSettle();
    expect(tapController.text, '剪贴板');
    expect(clipboardText, isNull);
    expect(find.byKey(_touchMenuKey), findsNothing);

    final paddingController = TextEditingController(text: 'hi');
    final paddingFocus = FocusNode();
    addTearDown(paddingController.dispose);
    addTearDown(paddingFocus.dispose);
    await tester.pumpWidget(
      _wrap(_emptyEditor(paddingController, paddingFocus)),
    );
    await tester.pumpAndSettle();
    final listRect = tester.getRect(find.byType(MarkdownBlockListView));
    await tester.tapAt(
      Offset(listRect.center.dx, listRect.bottom - 12),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    _expectCaretMenu(tester);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(
      Offset(listRect.center.dx, listRect.bottom - 12),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_touchMenuKey), findsNothing);
  });
}

const _touchMenuKey = ValueKey<String>('markdownTouchSelectionMenu');
const _touchMenuPasteKey = ValueKey<String>('markdownTouchMenuPaste');
const _touchMenuNewlineKey = ValueKey<String>('markdownTouchMenuNewline');
const _touchMenuCutKey = ValueKey<String>('markdownTouchMenuCut');
const _touchHandleStartKey = ValueKey<String>('markdownTouchHandleStart');

void _expectCaretMenu(WidgetTester tester) {
  expect(find.byKey(_touchMenuKey), findsOneWidget);
  expect(find.byKey(_touchMenuPasteKey), findsOneWidget);
  expect(find.byKey(_touchMenuNewlineKey), findsOneWidget);
  expect(find.byKey(_touchMenuCutKey), findsNothing);
  expect(find.byKey(_touchHandleStartKey), findsNothing);
}

Widget _emptyEditor(TextEditingController controller, FocusNode focusNode) {
  return RevericMarkdownEditor(
    controller: controller,
    focusNode: focusNode,
    autoHeight: true,
    showToolbar: false,
    minHeight: 132,
    hintText: 'hint',
    fontFamily: 'Roboto',
    fontSize: 14,
    letterSpacing: 0,
    lineHeight: 1.5,
  );
}

void _mockClipboard(
  ValueChanged<String?> onCopied, {
  String? Function()? readText,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments as Map<dynamic, dynamic>;
          onCopied(arguments['text']?.toString());
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': readText?.call()};
        }
        return null;
      });
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const <Locale>[Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return ProviderScope(
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: SizedBox(width: 360, height: 400, child: child),
              ),
            ),
          ),
        );
      },
    ),
  );
}
