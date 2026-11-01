// 职责: Markdown 编辑器桌面右键菜单黄金图（加载真实字体），人工目检菜单定位与禁用态。
// 关联文件:
//   lib/shared/widgets/md/block/markdown_block_list_view.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/components/reveric_context_menu.dart

import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/md/block/markdown_readonly_block.dart';
import 'package:reveric/shared/widgets/md/reveric_markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
    await _loadFont('LXGWWenKai', 'assets/fonts/LXGWWenKai-Regular.ttf');
  });

  testWidgets('桌面右键在选区上弹出剪切/复制/粘贴/全选菜单', (tester) async {
    tester.view.physicalSize = const Size(760, 420);
    tester.view.devicePixelRatio = 1.0;

    // 有内容的剪贴板：粘贴项才是可用态，复制/粘贴也才能真的走通。
    var clipboard = '预置剪贴板';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.hasStrings':
              return <String, dynamic>{'value': clipboard.isNotEmpty};
            case 'Clipboard.setData':
              clipboard = (call.arguments as Map)['text'] as String;
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboard};
          }
          return null;
        });

    final controller = TextEditingController(
      text: '主角顾长戈：帝都顾家废少，天赋尽废，父亲失势被夺爵。',
    );
    final focusNode = FocusNode();
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.testTextInput.reset();
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh', 'CN')],
        path: 'assets/translations',
        assetLoader: const MergingAssetLoader(),
        fallbackLocale: const Locale('zh', 'CN'),
        startLocale: const Locale('zh', 'CN'),
        child: Builder(
          builder: (context) {
            return ProviderScope(
              // 字体颜色默认读设置库，测试里没有 path_provider，固定为跟随主题。
              overrides: [editorFontColorProvider.overrideWithValue(null)],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                // 显式给 UI 字体：默认走平台字体，测试环境里会渲染成方块。
                theme: RevericThemeData.reveric.toThemeData(
                  fontFamily: 'LXGWWenKai',
                ),
                builder: (context, child) {
                  return RevericTheme(
                    data: RevericThemeData.reveric,
                    child: child ?? const SizedBox.shrink(),
                  );
                },
                home: RevericTheme(
                  data: RevericThemeData.reveric,
                  child: Scaffold(
                    body: SizedBox(
                      width: 720,
                      height: 260,
                      child: RevericMarkdownEditor(
                        controller: controller,
                        focusNode: focusNode,
                        fontFamily: 'LXGWWenKai',
                        fontSize: 14,
                        letterSpacing: 0,
                        lineHeight: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 鼠标拖选出一段文字，右键落在选区内应保留选区。
    final block = find.byType(MarkdownReadonlyBlock).first;
    final drag = await tester.startGesture(
      _globalTextPosition(tester, block, 0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(drag.removePointer);
    await drag.moveTo(_globalTextPosition(tester, block, 9));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(controller.selection.isCollapsed, isFalse);

    final secondary = await tester.startGesture(
      _globalTextPosition(tester, block, 5),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    addTearDown(secondary.removePointer);
    await secondary.up();
    await tester.pumpAndSettle();

    // 右键不改动选区，四个菜单项都在。
    expect(controller.selection.isCollapsed, isFalse);
    expect(find.text('剪切'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('粘贴'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/markdown_context_menu.png'),
    );

    // 同一个 test 内继续验证行为：重包 EasyLocalization 的第二个
    // testWidgets 会拿到空子树。
    final selected = controller.selection.textInside(controller.text);
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNothing);
    expect(clipboard, selected);

    // 光标折叠后右键：剪切/复制置灰，粘贴仍可用并把剪贴板插到光标处。
    await tester.tapAt(
      _globalTextPosition(tester, block, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(controller.selection.isCollapsed, isTrue);

    final caretMenu = await tester.startGesture(
      _globalTextPosition(tester, block, 20),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    addTearDown(caretMenu.removePointer);
    await caretMenu.up();
    await tester.pumpAndSettle();
    expect(_menuItemOpacity(tester, '剪切'), 0.5);
    expect(_menuItemOpacity(tester, '复制'), 0.5);
    expect(_menuItemOpacity(tester, '粘贴'), 1.0);

    final before = controller.text;
    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();
    expect(controller.text.length, before.length + selected.length);
    expect(selected.allMatches(controller.text).length, 2);
  });
}

/// 菜单项禁用时整行降到 0.5 透明度，用它区分可点与置灰。
double _menuItemOpacity(WidgetTester tester, String label) {
  return tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Opacity))
            .first,
      )
      .opacity;
}

RenderParagraph _paragraphIn(WidgetTester tester, Finder block) {
  return tester.renderObject<RenderParagraph>(
    find.descendant(of: block, matching: find.byType(RichText)).first,
  );
}

Offset _globalTextPosition(WidgetTester tester, Finder block, int localOffset) {
  final paragraph = _paragraphIn(tester, block);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: localOffset, extentOffset: localOffset + 1),
  );
  expect(boxes, isNotEmpty);
  final rect = boxes.first.toRect();
  return paragraph.localToGlobal(Offset(rect.left + 1, rect.center.dy));
}
