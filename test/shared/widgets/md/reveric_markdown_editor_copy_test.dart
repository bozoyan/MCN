// 职责: 验证 Markdown 工具栏复制全文、空正文禁用及标题菜单保留光标位置。
// 关联文件:
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/i18n.md
//   .agents/rules/code-style.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/widgets/md/reveric_markdown_editor.dart';
import 'package:reveric/shared/widgets/md/block/markdown_block_list_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  for (final width in [390.0, 800.0]) {
    testWidgets('heading insertion at document start width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _wrap(_editor(controller, focusNode), width: width),
      );
      await tester.pumpAndSettle();

      for (final (text, offset) in [('', 0), ('正文', 0), ('正文', -1)]) {
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: offset),
        );
        await tester.pump();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is RevericIcon &&
                widget.assetPath == RevericIcons.format_heading,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('H2'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(controller.text, '## $text');
        expect(controller.selection.extentOffset, 3);
      }
    });
  }

  testWidgets('toolbar copy button writes the full markdown', (tester) async {
    const markdown = '## Core principle\n\nKeep the plot moving.';
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    String? clipboardText;
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>;
            clipboardText = args['text']?.toString();
          }
          return null;
        });

    await tester.pumpWidget(_wrap(_editor(controller, focusNode)));
    await tester.pumpAndSettle();

    expect(tester.widget<IconButton>(_copyButton()).onPressed, isNull);

    controller.text = markdown;
    await tester.pump();
    expect(
      tester
          .widget<MarkdownBlockListView>(find.byType(MarkdownBlockListView))
          .style
          .textStyle
          .color,
      const Color(0xFF175CD3),
    );

    await tester.tap(_copyButton());
    await tester.pump();
    expect(clipboardText, markdown);

    controller.value = const TextEditingValue(
      text: 'First\nSecond',
      selection: TextSelection.collapsed(offset: 8),
    );
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is RevericIcon &&
            widget.assetPath == RevericIcons.format_heading,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('H3'));
    await tester.pumpAndSettle();
    expect(controller.text, 'First\n### Second');

    controller.text = markdown;
    await tester.pumpWidget(_wrap(_editor(controller, focusNode), width: 390));
    await tester.pumpAndSettle();

    tester.widget<IconButton>(_copyButton()).onPressed!();
    await tester.pump();
    expect(clipboardText, markdown);
  });
}

const _copyButtonKey = RevericMarkdownEditor.copyButtonKey;

Finder _copyButton() => find.byKey(_copyButtonKey);

Widget _editor(TextEditingController controller, FocusNode focusNode) {
  return RevericMarkdownEditor(
    controller: controller,
    focusNode: focusNode,
    fontFamily: 'Roboto',
    fontSize: 14,
    letterSpacing: 0,
    lineHeight: 1.5,
  );
}

Widget _wrap(Widget child, {double width = 800}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: [
            editorFontColorProvider.overrideWithValue(const Color(0xFF175CD3)),
          ],
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            builder: (context, child) =>
                RevericTheme(data: RevericThemeData.reveric, child: child!),
            home: Scaffold(
              body: SizedBox(width: width, height: 400, child: child),
            ),
          ),
        );
      },
    ),
  );
}
