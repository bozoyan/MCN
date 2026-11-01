// 职责: 验证自增高短字段全文选中时，触屏浮动菜单不被编辑器圆角裁掉
// 关联文件:
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/widgets/md/block/markdown_block_list_view.dart
//   lib/shared/widgets/md/block/markdown_readonly_block.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:ui' show PointerDeviceKind;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/md/block/markdown_readonly_block.dart';
import 'package:reveric/shared/widgets/md/reveric_markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  // 单独文件：同一进程第二个 EasyLocalization `_wrap` 会拿到空子树。
  testWidgets('autoHeight 短字段全文选中时浮动菜单可点按，不被编辑器裁剪', (tester) async {
    const markdown =
        '30 岁，连续创业者，此前做过两个失败的创业项目。擅长资本运作和人脉经营，但缺乏真正的技术理解。在创业大赛中窃取 Reveric 的创意。';
    String? clipboardText;
    _mockClipboard((text) => clipboardText = text);
    final controller = TextEditingController(text: markdown);
    final focusNode = FocusNode();
    addTearDown(() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.testTextInput.reset();
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: RevericMarkdownEditor(
            controller: controller,
            focusNode: focusNode,
            autoHeight: true,
            showToolbar: false,
            minHeight: 132,
            fontFamily: 'Roboto',
            fontSize: 14,
            letterSpacing: 0,
            lineHeight: 1.5,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    await _touchLongPressSelect(tester, block, 2);
    await tester.tap(find.byKey(_touchMenuSelectAllKey));
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(controller.text), markdown);
    expect(find.byKey(_touchMenuKey).hitTestable(), findsOneWidget);
    expect(find.byKey(_touchMenuCopyKey).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(_touchMenuCopyKey));
    await tester.pumpAndSettle();
    expect(clipboardText, markdown);
  });
}

const _touchMenuKey = ValueKey<String>('markdownTouchSelectionMenu');
const _touchMenuCopyKey = ValueKey<String>('markdownTouchMenuCopy');
const _touchMenuSelectAllKey = ValueKey<String>('markdownTouchMenuSelectAll');

Future<void> _touchLongPressSelect(
  WidgetTester tester,
  Finder block,
  int localOffset,
) async {
  final gesture = await tester.startGesture(
    _globalTextPosition(tester, block, localOffset),
    kind: PointerDeviceKind.touch,
  );
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.up();
  await tester.pumpAndSettle();
}

void _mockClipboard(ValueChanged<String?> onCopied) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments as Map<dynamic, dynamic>;
          onCopied(arguments['text']?.toString());
        }
        return null;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

RenderParagraph _paragraphIn(WidgetTester tester, Finder block) {
  return tester.renderObject<RenderParagraph>(
    find.descendant(of: block, matching: find.byType(RichText)).first,
  );
}

Offset _globalTextPosition(WidgetTester tester, Finder block, int localOffset) {
  final paragraph = _paragraphIn(tester, block);
  final textLength = paragraph.text.toPlainText().length;
  final safeOffset = localOffset.clamp(0, textLength);
  if (safeOffset == textLength) {
    final caret = paragraph.getOffsetForCaret(
      TextPosition(offset: safeOffset),
      const Rect.fromLTWH(0, 0, 2, 20),
    );
    return paragraph.localToGlobal(caret + const Offset(1, 8));
  }
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: safeOffset, extentOffset: safeOffset + 1),
  );
  expect(boxes, isNotEmpty);
  final rect = boxes.first.toRect();
  return paragraph.localToGlobal(Offset(rect.left + 1, rect.center.dy));
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
