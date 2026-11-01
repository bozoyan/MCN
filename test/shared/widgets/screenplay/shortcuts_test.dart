// 职责: 用真实输入框验证整场键鼠选区、剪贴板、撤销和查找替换的协作。
// 关联文件:
//   lib/shared/widgets/screenplay/editing_scope.dart
//   lib/shared/widgets/screenplay/editing_row.dart
//   lib/shared/widgets/screenplay/editing_controller.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/hooks.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/models/screenplay_editing.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/screenplay/editing_controller.dart';
import 'package:reveric/shared/widgets/screenplay/editing_scope.dart';
import 'package:reveric/shared/widgets/screenplay/editing_row.dart';

late Map<String, dynamic> _translations;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    _translations = (await const MergingAssetLoader().load(
      'assets/translations',
      const Locale('en'),
    ))!;
  });
  testWidgets('输入框替换后滚动使用重新绑定的节点', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final editor = _editor();
    final generation = ValueNotifier(0);
    final input = TextEditingController(text: 'alpha');
    final focus = FocusNode();
    addTearDown(editor.dispose);
    addTearDown(generation.dispose);
    addTearDown(input.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _wrap(
        ValueListenableBuilder<int>(
          valueListenable: generation,
          builder: (context, version, _) => ScreenplayEditingScope(
            controller: editor,
            onFocusElement: (_, _) {},
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 1000),
                  ScreenplayEditingRow(
                    index: 0,
                    child: TextField(
                      key: ValueKey(version),
                      controller: input,
                      focusNode: focus,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = tester.state<ScreenplayEditingRowState>(
      find.byType(ScreenplayEditingRow),
    );
    final oldInput = row.editable!;
    final scroll = Scrollable.of(row.context).position;
    expect(scroll.pixels, 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      expect(oldInput.mounted, isFalse);
      expect(row.mounted, isTrue);
      row.reveal(3);
      row.focusAt(3);
    });
    generation.value++;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    expect(
      row.editable,
      same(tester.state<EditableTextState>(find.byType(EditableText))),
    );
    expect(row.editable, isNot(same(oldInput)));
    expect(scroll.pixels, greaterThan(0));
    expect(focus.hasFocus, isTrue);
    expect(input.text, 'alpha');
    row.reveal(3);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('帧后绑定前删除末行不会访问过期下标', (tester) async {
    final editor = _editor();
    addTearDown(editor.dispose);
    await _mount(tester, editor);
    final removedRow = tester.state<ScreenplayEditingRowState>(
      find.byType(ScreenplayEditingRow).last,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      editor.acceptExternal([editor.value.first]);
      expect(removedRow.mounted, isTrue);
      expect(removedRow.index, editor.value.length);
    });
    await tester.pumpWidget(_wrap(_Body(editor)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ScreenplayEditingRow), findsOneWidget);
    expect(editor.value.single.text, 'alpha');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('鼠标可双向跨元素拖选，回拖与松开后保持正确选区', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final editor = _editor();
    addTearDown(editor.dispose);
    await _mount(tester, editor);
    Offset point(int row, int offset) => _point(tester, row, offset);

    final mouse = await tester.startGesture(
      point(0, 2),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(point(1, 3));
    await tester.pump();
    expect(
      editor.selection,
      const TextSelection(baseOffset: 2, extentOffset: 9),
    );
    expect(editor.selectedText(), 'pha\nbet');
    await mouse.moveTo(point(0, 4));
    await tester.pump();
    expect(
      editor.selection,
      const TextSelection(baseOffset: 2, extentOffset: 4),
    );
    await mouse.moveTo(point(1, 2));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(
      editor.selection,
      const TextSelection(baseOffset: 2, extentOffset: 8),
    );

    final reverse = await tester.startGesture(
      point(1, 3),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await reverse.moveTo(point(0, 1));
    await reverse.up();
    await tester.pumpAndSettle();
    expect(
      editor.selection,
      const TextSelection(baseOffset: 9, extentOffset: 1),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(
      editor.selection,
      const TextSelection(baseOffset: 9, extentOffset: 2),
    );
    await tester.enterText(find.byType(TextField).first, 'X');
    await tester.pumpAndSettle();
    expect(editor.value.single.text, 'alXa');
    await _command(tester, LogicalKeyboardKey.keyZ, TargetPlatform.macOS);
    expect(editor.value.map((e) => e.text), ['alpha', 'beta']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('跨角色拖选包含角色名，单元素鼠标选词仍可用', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final editor =
        ScreenplayEditingController(const [
            ScreenplayElement(
              id: 'a',
              type: ScreenplayElementType.action,
              text: 'alpha',
            ),
            ScreenplayElement(
              id: 'c',
              type: ScreenplayElementType.character,
              characterId: 'actor',
            ),
            ScreenplayElement(
              id: 'b',
              type: ScreenplayElementType.dialogue,
              text: 'beta',
            ),
          ], ScreenplayElementKeys())
          ..characterNames = {'actor': 'Actor'}
          ..onEdited = (_) {};
    addTearDown(editor.dispose);
    await _mount(tester, editor);
    final mouse = await tester.startGesture(
      _point(tester, 0, 2),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(_point(tester, 1, 3));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(
      editor.selection,
      const TextSelection(baseOffset: 2, extentOffset: 11),
    );
    expect(editor.selectedText(), 'pha\nActor：\nbet');

    final roleRow = tester.state<ScreenplayEditingRowState>(
      find.byType(ScreenplayEditingRow).at(1),
    );
    final roleBox = roleRow.context.findRenderObject()! as RenderBox;
    final paragraph = tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byType(ScreenplayEditingRow).at(1),
            matching: find.byType(RichText),
          )
          .first,
    );
    final textBox = paragraph
        .getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: paragraph.text.toPlainText().length,
          ),
        )
        .single
        .toRect()
        .shift(paragraph.localToGlobal(Offset.zero, ancestor: roleBox));
    final painter = tester
        .widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(ScreenplayEditingRow).at(1),
                matching: find.byType(CustomPaint),
              )
              .first,
        )
        .foregroundPainter!;
    expect(
      (Canvas canvas) => painter.paint(canvas, roleBox.size),
      paints..rect(rect: textBox),
    );

    final point = _point(tester, 0, 2);
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(editor.selectedText(), 'alpha');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('跨段拖选停留在同一字符时，输入框高亮仍与整场选区一致', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final editor = _editor();
    addTearDown(editor.dispose);
    await _mount(tester, editor);
    final origin = tester.state<EditableTextState>(
      find.byType(EditableText).last,
    );
    final mouse = await tester.startGesture(
      _point(tester, 1, 3),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final target = _point(tester, 0, 1);
    await mouse.moveTo(target);
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await mouse.moveTo(target + Offset(0, i.isEven ? 1 : 2));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        editor.selection,
        const TextSelection(baseOffset: 9, extentOffset: 1),
      );
      expect(
        origin.widget.controller.selection,
        const TextSelection(baseOffset: 3, extentOffset: 0),
      );
      expect(
        origin.renderEditable.selection,
        origin.widget.controller.selection,
      );
    }
    await mouse.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('内外滚动容器均可边缘拖选，取消后停止，触摸仍可滚动', (tester) async {
    for (final outerScroll in [false, true]) {
      final editor = ScreenplayEditingController([
        for (var i = 0; i < 32; i++)
          ScreenplayElement(
            id: 'row_$i',
            type: ScreenplayElementType.action,
            text: 'Row $i',
          ),
      ], ScreenplayElementKeys())..onEdited = (_) {};
      addTearDown(editor.dispose);
      await tester.pumpWidget(_wrap(_Body(editor, outerScroll: outerScroll)));
      await tester.pumpAndSettle();
      final scope = tester.state<ScreenplayEditingScopeState>(
        find.byType(ScreenplayEditingScope),
      );
      final scroll = Scrollable.of(
        tester.element(find.byType(ScreenplayEditingRow).first),
      ).position;
      final mouse = await tester.startGesture(
        _point(tester, 0, 2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.moveTo(const Offset(60, 630));
      await tester.pump();
      final firstExtent = editor.selection.extentOffset;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(scroll.pixels, greaterThan(0));
      expect(editor.selection.baseOffset, 2);
      expect(editor.selection.extentOffset, greaterThan(firstExtent));
      await mouse.cancel();
      await tester.pumpAndSettle();
      expect(scope.selectingWithMouse, isFalse);
      final stoppedAt = scroll.pixels;
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.pixels, stoppedAt);

      FocusManager.instance.primaryFocus?.unfocus();
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(300, 400), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(scroll.pixels, greaterThan(0));
      expect(scope.selectingWithMouse, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
  testWidgets('macOS/Windows 整场剪贴板、跨元素输入、撤销与查找替换', (tester) async {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      String? clipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String;
            }
            if (call.method == 'Clipboard.getData') {
              return {'text': clipboard};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final editor = _editor();
      addTearDown(editor.dispose);
      await _mount(tester, editor);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!
          .selection = const TextSelection.collapsed(
        offset: 3,
      );
      await _command(
        tester,
        platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.arrowDown
            : LogicalKeyboardKey.end,
        platform,
      );
      expect(editor.selection.extentOffset, editor.source.length);
      await _command(
        tester,
        platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.arrowUp
            : LogicalKeyboardKey.home,
        platform,
      );
      expect(editor.selection.extentOffset, 0);
      if (platform == TargetPlatform.macOS) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
      } else {
        await _command(tester, LogicalKeyboardKey.arrowRight, platform);
      }
      expect(editor.selection.extentOffset, 5);
      await _command(tester, LogicalKeyboardKey.keyA, platform);
      expect(
        editor.selection,
        TextSelection(baseOffset: 0, extentOffset: editor.source.length),
      );
      await _command(tester, LogicalKeyboardKey.keyX, platform, shift: true);
      expect(editor.value.length, 2, reason: '未定义的组合键不能误剪切正文');
      await _command(tester, LogicalKeyboardKey.keyC, platform);
      expect(clipboard, 'alpha\nbeta');
      if (platform == TargetPlatform.windows) {
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText).last,
        );
        final toolbar =
            screenplayContextMenuBuilder(editable.context, editable)
                as AdaptiveTextSelectionToolbar;
        toolbar.buttonItems!
            .firstWhere((item) => item.type == ContextMenuButtonType.cut)
            .onPressed!();
        await tester.pumpAndSettle();
        expect(clipboard, 'alpha\nbeta');
      } else {
        await _command(tester, LogicalKeyboardKey.keyX, platform);
      }
      expect(editor.value, isEmpty);
      await _command(tester, LogicalKeyboardKey.keyV, platform);
      expect(editor.value.single.text, 'alpha\nbeta');
      await _command(tester, LogicalKeyboardKey.keyZ, platform);
      expect(editor.value, isEmpty);
      await _command(tester, LogicalKeyboardKey.keyZ, platform);
      expect(editor.value.map((e) => e.text), ['alpha', 'beta']);
      await _command(tester, LogicalKeyboardKey.keyZ, platform, shift: true);
      expect(editor.value, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    }
    {
      final editor = _editor();
      addTearDown(editor.dispose);
      await _mount(tester, editor);
      await tester.tap(find.byType(TextField).first);
      tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!
          .selection = const TextSelection.collapsed(
        offset: 2,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(editor.value.map((e) => e.text), ['al\npha', 'beta']);
      await _command(tester, LogicalKeyboardKey.keyZ, TargetPlatform.windows);
      expect(editor.value.map((e) => e.text), ['alpha', 'beta']);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(editor.value.map((e) => e.text), ['al', 'pha', 'beta']);
      await _command(tester, LogicalKeyboardKey.keyZ, TargetPlatform.windows);
      expect(editor.value.map((e) => e.text), ['alpha', 'beta']);
    }
    {
      final editor = _editor();
      addTearDown(editor.dispose);
      await _mount(tester, editor);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await _command(tester, LogicalKeyboardKey.keyA, TargetPlatform.windows);
      final selection = editor.selection;
      await tester.enterText(find.byType(TextField).last, 'replacement');
      await tester.pumpAndSettle();
      expect(editor.value.single.text, 'replacement');
      await _command(tester, LogicalKeyboardKey.keyZ, TargetPlatform.windows);
      expect(editor.value.map((e) => e.text), ['alpha', 'beta']);
      expect(editor.selection, selection);
    }
    {
      final editor = _editor();
      addTearDown(editor.dispose);
      await _mount(tester, editor);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await _command(tester, LogicalKeyboardKey.keyH, TargetPlatform.windows);
      expect(find.byType(TextField), findsNWidgets(4));
      await tester.enterText(find.byType(TextField).at(2), 'beta');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(
        editor.selection,
        const TextSelection(baseOffset: 6, extentOffset: 10),
      );
      await tester.enterText(find.byType(TextField).last, 'BETA');
      tester.widget<TextField>(find.byType(TextField).last).onSubmitted!(
        'BETA',
      );
      await tester.pumpAndSettle();
      expect(editor.value.map((e) => e.text), ['alpha', 'BETA']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      await _command(tester, LogicalKeyboardKey.keyZ, TargetPlatform.windows);
      expect(editor.value.map((e) => e.text), ['alpha', 'beta']);
    }
    {
      final editor = ScreenplayEditingController([
        for (var i = 0; i < 32; i++)
          ScreenplayElement(
            id: 'row_$i',
            type: ScreenplayElementType.action,
            text: 'Row $i',
          ),
      ], ScreenplayElementKeys())..onEdited = (_) {};
      addTearDown(editor.dispose);
      await tester.pumpWidget(_wrap(_Body(editor, outerScroll: true)));
      await tester.pumpAndSettle();
      final scroll = Scrollable.of(
        tester.element(find.byType(TextField).first),
      ).position;
      scroll.jumpTo(200);
      await tester.pumpAndSettle();
      tester
          .widget<TextField>(find.byType(TextField).at(8))
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      await _command(tester, LogicalKeyboardKey.keyF, TargetPlatform.windows);
      final barPosition = tester.getTopLeft(find.byType(TextField).last);
      scroll.jumpTo(400);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(TextField).last), barPosition);
      await tester.enterText(find.byType(TextField).last, 'Row 25');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(editor.positionAt(editor.selection.start).index, 25);
      expect(tester.getTopLeft(find.byType(TextField).last), barPosition);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _mount(
  WidgetTester tester,
  ScreenplayEditingController editor,
) async {
  await tester.pumpWidget(_wrap(_Body(editor)));
  await tester.pumpAndSettle();
}

Offset _point(WidgetTester tester, int field, int offset) {
  final render = tester
      .state<EditableTextState>(find.byType(EditableText).at(field))
      .renderEditable;
  return render.localToGlobal(
    render.getLocalRectForCaret(TextPosition(offset: offset)).centerLeft,
  );
}

ScreenplayEditingController _editor() => ScreenplayEditingController(const [
  ScreenplayElement(id: 'a', type: ScreenplayElementType.action, text: 'alpha'),
  ScreenplayElement(id: 'b', type: ScreenplayElementType.action, text: 'beta'),
], ScreenplayElementKeys())..onEdited = (_) {};

Future<void> _command(
  WidgetTester tester,
  LogicalKeyboardKey key,
  TargetPlatform platform, {
  bool shift = false,
}) async {
  final modifier = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyEvent(key);
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

class _Body extends HookWidget {
  const _Body(this.editor, {this.outerScroll = false});
  final ScreenplayEditingController editor;
  final bool outerScroll;
  @override
  Widget build(BuildContext context) {
    useListenable(editor);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < editor.value.length; i++)
          ScreenplayEditingRow(
            key: ValueKey(editor.keys.keyFor(editor.value[i])),
            index: i,
            child: _Input(editor, i),
          ),
      ],
    );
    final scope = ScreenplayEditingScope(
      controller: editor,
      onFocusElement: (_, _) {},
      child: outerScroll ? content : SingleChildScrollView(child: content),
    );
    return outerScroll ? SingleChildScrollView(child: scope) : scope;
  }
}

class _Input extends HookWidget {
  const _Input(this.editor, this.index);
  final ScreenplayEditingController editor;
  final int index;
  @override
  Widget build(BuildContext context) {
    final input = useTextEditingController(text: editor.value[index].text);
    final focus = useFocusNode();
    if (editor.value[index].type == ScreenplayElementType.character) {
      return Focus(
        focusNode: focus,
        child: const SizedBox(height: 40, child: Text('Actor')),
      );
    }
    return TextField(
      contextMenuBuilder: screenplayContextMenuBuilder,
      controller: input,
      focusNode: focus,
      maxLines: null,
      onChanged: (text) {
        final before = editor.value[index];
        editor.edit(
          [...editor.value]
            ..[index] = editor.keys.preserveKey(
              before,
              before.copyWith(text: text),
            ),
        );
      },
    );
  }
}

Widget _wrap(Widget child) => EasyLocalization(
  supportedLocales: const [Locale('en')],
  path: 'assets/translations',
  assetLoader: const _LoadedTranslations(),
  fallbackLocale: const Locale('en'),
  startLocale: const Locale('en'),
  child: Builder(
    builder: (context) => RevericTheme(
      data: RevericThemeData.reveric,
      child: MaterialApp(
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: RevericThemeData.reveric.toThemeData(),
        home: Scaffold(body: child),
      ),
    ),
  ),
);

// 在真实异步环境中只加载一次，避免每个 widget 测试等待翻译 JSON 的解码 isolate。
class _LoadedTranslations extends AssetLoader {
  const _LoadedTranslations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      _translations;
}
