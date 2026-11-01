// 职责: 验证 Markdown 虚拟编辑器的单一渲染、全文选择（含触屏长按/双击/手柄/浮动菜单）、输入、键盘、滚动与远端查找契约
// 关联文件:
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/widgets/md/block/markdown_block_list_view.dart
//   lib/shared/widgets/md/block/markdown_readonly_block.dart
//   lib/shared/widgets/md/block/markdown_text_input_client.dart
//   lib/shared/widgets/text_find_replace_scope.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/text-input-ime.md

import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind, TextBox;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  // 避免资源缓存的 Future 跨用例复用前一个 testWidgets 的 FakeAsync 队列。
  setUp(() => rootBundle.clear());

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      'caret geometry waits for ancestor transforms to finish layout ($platform)',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final controller = TextEditingController(text: 'A paragraph');
          final focusNode = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(focusNode.dispose);
          Object? geometryError;
          Rect? earlyCaret;
          Rect? earlyParagraph;
          var probed = false;
          await tester.pumpWidget(
            _wrap(
              _AncestorLayoutProbe(
                onChildLaidOut: () {
                  if (probed) {
                    return;
                  }
                  probed = true;
                  final block = tester.state<MarkdownReadonlyBlockState>(
                    find
                        .byType(MarkdownReadonlyBlock, skipOffstage: false)
                        .first,
                  );
                  try {
                    earlyCaret = block.globalCaretRect(1);
                    earlyParagraph = block.paragraphGlobalRect;
                    block.globalTextPositionForPosition(Offset.zero);
                  } catch (error) {
                    geometryError = error;
                  }
                },
                child: _editor(controller: controller, focusNode: focusNode),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(probed, isTrue);
          expect(geometryError, isNull);
          expect(earlyCaret, isNull);
          expect(earlyParagraph, isNull);
          final block = tester.state<MarkdownReadonlyBlockState>(
            find.byType(MarkdownReadonlyBlock).first,
          );
          expect(block.globalCaretRect(1), isNotNull);
          expect(block.paragraphGlobalRect, isNotNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets('bulk paste is unlimited by default and can be opted into', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        RevericMarkdownEditor(
          controller: controller,
          focusNode: focusNode,
          fontFamily: 'Roboto',
          fontSize: 14,
          letterSpacing: 0,
          lineHeight: 1.5,
        ),
      ),
    );
    await tester.pumpAndSettle();

    var blockList = tester.widget<MarkdownBlockListView>(
      find.byType(MarkdownBlockListView),
    );
    expect(blockList.inputFormatters, isEmpty);

    await tester.pumpWidget(
      _wrap(
        RevericMarkdownEditor(
          controller: controller,
          focusNode: focusNode,
          fontFamily: 'Roboto',
          fontSize: 14,
          letterSpacing: 0,
          lineHeight: 1.5,
          limitPasteSize: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    blockList = tester.widget<MarkdownBlockListView>(
      find.byType(MarkdownBlockListView),
    );
    expect(blockList.inputFormatters, hasLength(1));
  });

  testWidgets('段落分隔只占一个空行，聚焦不切换文本 renderer', (tester) async {
    final controller = TextEditingController(text: '第一段\n\n第二段');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final blocks = find.byType(MarkdownReadonlyBlock);
    expect(blocks, findsNWidgets(2));
    final secondHeight = tester.getSize(blocks.last).height;
    final firstHeight = tester.getSize(blocks.first).height;
    expect(firstHeight, closeTo(secondHeight * 2, 0.5));

    await tester.tap(blocks.first);
    await tester.pumpAndSettle();

    expect(focusNode.hasFocus, isTrue);
    expect(find.byType(MarkdownReadonlyBlock), findsNWidgets(2));
    expect(find.byType(EditableText), findsNothing);
    expect(tester.getSize(blocks.first).height, closeTo(firstHeight, 0.5));
  });

  testWidgets('点击完整可见块不会改变滚动位置', (tester) async {
    final controller = TextEditingController(
      text: List<String>.generate(100, (index) => '第 $index 段').join('\n\n'),
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode), height: 300),
    );
    await tester.pumpAndSettle();

    final scrollable = _editorScrollable(tester);
    scrollable.position.jumpTo(400);
    await tester.pumpAndSettle();
    final beforeTap = scrollable.position.pixels;
    final viewport = tester.getRect(find.byType(MarkdownBlockListView));
    Finder? target;
    var targetCenterY = double.negativeInfinity;
    for (final element in find.byType(MarkdownReadonlyBlock).evaluate()) {
      final finder = find.byElementPredicate(
        (current) => identical(current, element),
      );
      final rect = tester.getRect(finder);
      if (rect.top >= viewport.top + 4 &&
          rect.bottom <= viewport.bottom - 4 &&
          rect.center.dy > targetCenterY) {
        target = finder;
        targetCenterY = rect.center.dy;
      }
    }
    expect(target, isNotNull);

    await tester.tapAt(tester.getRect(target!).center);
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, closeTo(beforeTap, 0.5));
  });

  testWidgets('拖动桌面滚动条只滚动视口，不改变文本选区', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = TextEditingController(
      text: List<String>.generate(300, _blockText).join('\n\n'),
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode), height: 400),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scrollbar), findsOneWidget);
    final scrollable = _editorScrollable(tester);
    final position = scrollable.position;
    position.jumpTo(position.maxScrollExtent / 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    final thumbCenter = _scrollbarThumbCenter(tester);
    final beforeDrag = position.pixels;

    final gesture = await tester.startGesture(
      thumbCenter,
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = null;
    expect(position.pixels, greaterThan(beforeDrag));
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
  });

  testWidgets('聚焦前后保持同一个段落实例与视觉断行', (tester) async {
    final text = '正文' * 30;
    final controller = TextEditingController(text: text);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode), width: 260),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    final before = _paragraphIn(tester, block);
    final beforeElement = find
        .descendant(of: block, matching: find.byType(RichText))
        .evaluate()
        .single;
    final lineStartsBefore = _visualLineStarts(
      text.length,
      before.getBoxesForSelection,
    );

    await tester.tap(block);
    await tester.pumpAndSettle();

    final after = _paragraphIn(tester, block);
    final afterElement = find
        .descendant(of: block, matching: find.byType(RichText))
        .evaluate()
        .single;
    final lineStartsAfter = _visualLineStarts(
      text.length,
      after.getBoxesForSelection,
    );

    expect(afterElement, same(beforeElement));
    expect(lineStartsAfter, lineStartsBefore);
  });

  testWidgets('Enter 后全文 selection 与可见光标一起进入新行', (tester) async {
    final controller = TextEditingController(text: '甲\n\n乙');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MarkdownReadonlyBlock).first);
    await tester.pumpAndSettle();
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.text, '甲\n\n\n乙');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    final blockState = tester.state<MarkdownReadonlyBlockState>(
      find.byType(MarkdownReadonlyBlock).first,
    );
    expect(
      blockState.localCaretRect(2)!.top,
      greaterThan(blockState.localCaretRect(1)!.top),
    );
  });

  testWidgets('同块鼠标选区由 Backspace 一次删除', (tester) async {
    const source = '可删除的选中文本\n\n第三行';
    final controller = TextEditingController(text: source);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    final start = _globalTextPosition(tester, block, 1);
    final end = _globalTextPosition(tester, block, 7);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.selection.isCollapsed, isFalse);
    final selected = controller.selection.textInside(source);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(controller.text, source.replaceRange(1, 7, ''));
    expect(selected, source.substring(1, 7));
    expect(controller.selection, const TextSelection.collapsed(offset: 1));
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('桌面双击选中命中的单词', (tester) async {
    const source = '前缀 alpha 后缀\n\n第二段';
    final controller = TextEditingController(text: source);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    final position = _globalTextPosition(
      tester,
      block,
      source.indexOf('alpha') + 2,
    );
    await tester.tapAt(position, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(position, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(source), 'alpha');
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('桌面三击选中命中的当前段落', (tester) async {
    const source = '第一段 alpha\n\n第二段';
    final controller = TextEditingController(text: source);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    final position = _globalTextPosition(
      tester,
      block,
      source.indexOf('alpha') + 2,
    );
    for (var tap = 0; tap < 3; tap++) {
      await tester.tapAt(position, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(
      controller.selection,
      TextSelection(baseOffset: 0, extentOffset: source.indexOf('\n') + 1),
    );
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('跨块鼠标选区复制与删除共用全文 selection', (tester) async {
    const source = '第一段文字\n\n第二段文字\n\n第三段';
    final controller = TextEditingController(text: source);
    final focusNode = FocusNode();
    String? clipboardText;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    _mockClipboard((text) => clipboardText = text);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final first = find.byType(MarkdownReadonlyBlock).at(0);
    final second = find.byType(MarkdownReadonlyBlock).at(1);
    final gesture = await tester.startGesture(
      _globalTextPosition(tester, first, 1),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await gesture.moveTo(_globalTextPosition(tester, second, 4));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final selectedRange = controller.selection;
    expect(selectedRange.start, 1);
    expect(selectedRange.end, greaterThan(source.indexOf('第二段')));

    await _sendControlShortcut(tester, LogicalKeyboardKey.keyC);
    expect(clipboardText, selectedRange.textInside(source));

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(
      controller.text,
      source.replaceRange(selectedRange.start, selectedRange.end, ''),
    );
    expect(
      controller.selection,
      TextSelection.collapsed(offset: selectedRange.start),
    );
  });

  testWidgets('全选、单击与删除不会留下第二套渲染选区', (tester) async {
    _overrideTargetPlatform(TargetPlatform.macOS);
    const source = '第一段\n\n第二段\n\n末段';
    final controller = TextEditingController(text: source);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MarkdownReadonlyBlock).last);
    await tester.pumpAndSettle();

    await _sendMacShortcut(tester, LogicalKeyboardKey.keyA);

    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: source.length),
    );
    expect(focusNode.hasFocus, isTrue);

    await tester.tapAt(
      _globalTextPosition(tester, find.byType(MarkdownReadonlyBlock).at(1), 2),
    );
    await tester.pumpAndSettle();

    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.extentOffset, source.indexOf('第二段') + 2);

    await _sendMacShortcut(tester, LogicalKeyboardKey.keyA);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '替换',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.text, '替换');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));

    await _sendMacShortcut(tester, LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(controller.text, isEmpty);
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('上下方向键按同一段落几何在视觉行间移动', (tester) async {
    final text = '正文内容' * 30;
    final controller = TextEditingController(text: text);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode), width: 260),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MarkdownReadonlyBlock).first);
    await tester.pumpAndSettle();
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final secondLineOffset = controller.selection.extentOffset;
    expect(secondLineOffset, greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(controller.selection.extentOffset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('上下方向键可跨过段落空行进入相邻块', (tester) async {
    final controller = TextEditingController(text: '甲\n\n乙');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MarkdownReadonlyBlock).first);
    await tester.pumpAndSettle();
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(controller.selection.extentOffset, greaterThanOrEqualTo(3));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(controller.selection.extentOffset, lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS Command 方向键按原生行与全文边界移动或扩选', (tester) async {
    _overrideTargetPlatform(TargetPlatform.macOS);
    const source = '第一行\n第二行\n\n末段';
    final controller = TextEditingController(text: source);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MarkdownReadonlyBlock).first);
    await tester.pumpAndSettle();

    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();
    await _sendMacShortcut(tester, LogicalKeyboardKey.arrowLeft);
    expect(controller.selection, const TextSelection.collapsed(offset: 4));

    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    await _sendMacShortcut(tester, LogicalKeyboardKey.arrowRight);
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: 7, affinity: TextAffinity.upstream),
    );

    await _sendMacShortcut(tester, LogicalKeyboardKey.arrowDown);
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: source.length),
    );

    await _sendMacShortcut(tester, LogicalKeyboardKey.arrowUp);
    expect(controller.selection, const TextSelection.collapsed(offset: 0));

    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();
    await _sendMacShortcut(tester, LogicalKeyboardKey.arrowLeft, shift: true);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 6, extentOffset: 4),
    );

    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    await _sendMacShortcut(tester, LogicalKeyboardKey.arrowRight, shift: true);
    expect(
      controller.selection,
      const TextSelection(
        baseOffset: 5,
        extentOffset: 7,
        affinity: TextAffinity.upstream,
      ),
    );

    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    await _sendMacShortcut(tester, LogicalKeyboardKey.arrowDown, shift: true);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 4, extentOffset: source.length),
    );

    await _sendMacShortcut(tester, LogicalKeyboardKey.arrowUp, shift: true);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: source.length),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('macOS Option 按单词移动、扩选和删除', (tester) async {
    _overrideTargetPlatform(TargetPlatform.macOS);
    const source = 'alpha beta gamma';
    final controller = TextEditingController(text: source);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MarkdownReadonlyBlock).first);
    await tester.pumpAndSettle();

    controller.selection = const TextSelection.collapsed(offset: 10);
    await tester.pump();
    await _sendMacShortcut(tester, LogicalKeyboardKey.arrowLeft, alt: true);
    expect(controller.selection, const TextSelection.collapsed(offset: 6));

    await _sendMacShortcut(
      tester,
      LogicalKeyboardKey.arrowRight,
      alt: true,
      shift: true,
    );
    expect(
      controller.selection,
      const TextSelection(baseOffset: 6, extentOffset: 10),
    );

    controller.selection = const TextSelection.collapsed(offset: 10);
    await tester.pump();
    await _sendMacShortcut(tester, LogicalKeyboardKey.backspace, alt: true);
    expect(controller.text, 'alpha  gamma');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('macOS Command 行边界和删除遵循当前视觉断行', (tester) async {
    _overrideTargetPlatform(TargetPlatform.macOS);
    final source = 'alpha beta ${'正文内容' * 24}';
    final controller = TextEditingController(text: source);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode), width: 260),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MarkdownReadonlyBlock).first);
    await tester.pumpAndSettle();

    final paragraph = _paragraphIn(
      tester,
      find.byType(MarkdownReadonlyBlock).first,
    );
    final lineStarts = _visualLineStarts(
      source.length,
      paragraph.getBoxesForSelection,
    );
    expect(lineStarts.length, greaterThan(2));

    controller.selection = TextSelection.collapsed(offset: lineStarts[1] + 2);
    await tester.pump();
    await _sendMacShortcut(tester, LogicalKeyboardKey.arrowLeft);
    expect(controller.selection.extentOffset, lineStarts[1]);

    controller.selection = TextSelection.collapsed(offset: lineStarts[1] + 2);
    await tester.pump();
    await _sendMacShortcut(tester, LogicalKeyboardKey.arrowRight);
    expect(controller.selection.extentOffset, lineStarts[2]);
    expect(controller.selection.affinity, TextAffinity.upstream);

    final blockState = tester.state<MarkdownReadonlyBlockState>(
      find.byType(MarkdownReadonlyBlock).first,
    );
    final caret = blockState.localCaretRect(controller.selection.extentOffset);
    final nextLineBox = paragraph
        .getBoxesForSelection(
          TextSelection(
            baseOffset: lineStarts[2],
            extentOffset: lineStarts[2] + 1,
          ),
        )
        .first;
    expect(caret, isNotNull);
    expect(caret!.center.dy, lessThan(nextLineBox.top));

    controller.selection = const TextSelection.collapsed(offset: 10);
    await tester.pump();
    await _sendMacShortcut(tester, LogicalKeyboardKey.backspace);
    expect(controller.text, source.substring(10));
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows 常见边界快捷键移动、扩选与删除', (tester) async {
    _overrideTargetPlatform(TargetPlatform.windows);
    const source = 'alpha beta\n第二行\n\n末段';
    final controller = TextEditingController(text: source);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MarkdownReadonlyBlock).first);
    await tester.pumpAndSettle();

    controller.selection = const TextSelection.collapsed(offset: 10);
    await tester.pump();
    await _sendWindowsShortcut(tester, LogicalKeyboardKey.arrowLeft);
    expect(controller.selection, const TextSelection.collapsed(offset: 6));

    await _sendWindowsShortcut(
      tester,
      LogicalKeyboardKey.arrowRight,
      shift: true,
    );
    expect(
      controller.selection,
      const TextSelection(baseOffset: 6, extentOffset: 10),
    );

    controller.selection = const TextSelection.collapsed(offset: 8);
    await tester.pump();
    await _sendWindowsShortcut(tester, LogicalKeyboardKey.arrowDown);
    expect(controller.selection, const TextSelection.collapsed(offset: 11));

    await _sendWindowsShortcut(tester, LogicalKeyboardKey.arrowUp);
    expect(controller.selection, const TextSelection.collapsed(offset: 0));

    controller.selection = const TextSelection.collapsed(offset: 8);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home, platform: 'windows');
    expect(controller.selection, const TextSelection.collapsed(offset: 0));

    controller.selection = const TextSelection.collapsed(offset: 8);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.end, platform: 'windows');
    expect(
      controller.selection,
      const TextSelection.collapsed(
        offset: 10,
        affinity: TextAffinity.upstream,
      ),
    );

    await _sendWindowsShortcut(tester, LogicalKeyboardKey.end);
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: source.length),
    );

    await _sendWindowsShortcut(tester, LogicalKeyboardKey.home, shift: true);
    expect(
      controller.selection,
      const TextSelection(baseOffset: source.length, extentOffset: 0),
    );

    controller.selection = const TextSelection.collapsed(offset: 10);
    await tester.pump();
    await _sendWindowsShortcut(tester, LogicalKeyboardKey.backspace);
    expect(controller.text, 'alpha \n第二行\n\n末段');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));

    await _sendWindowsShortcut(tester, LogicalKeyboardKey.keyZ);
    expect(controller.text, source);
    await _sendWindowsShortcut(tester, LogicalKeyboardKey.keyY);
    expect(controller.text, 'alpha \n第二行\n\n末段');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows CUA 剪切、复制和粘贴快捷键共用全文 selection', (tester) async {
    _overrideTargetPlatform(TargetPlatform.windows);
    final controller = TextEditingController(text: 'alpha beta');
    final focusNode = FocusNode();
    String? clipboardText;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    _mockClipboard(
      (text) => clipboardText = text,
      readText: () => clipboardText,
    );

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MarkdownReadonlyBlock).first);
    await tester.pumpAndSettle();

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();
    await _sendWindowsShortcut(tester, LogicalKeyboardKey.insert);
    expect(clipboardText, 'alpha');
    expect(controller.text, 'alpha beta');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete, platform: 'windows');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(clipboardText, 'alpha');
    expect(controller.text, ' beta');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.insert, platform: 'windows');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(controller.text, 'alpha beta');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('平台 IME delta 直接更新全文 value，不挂载隐藏 EditableText', (tester) async {
    final controller = TextEditingController(text: '甲\n\n乙');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MarkdownReadonlyBlock).first);
    await tester.pumpAndSettle();
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '甲拼\n',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 2),
      ),
    );
    await tester.pump();

    expect(controller.text, '甲拼\n\n乙');
    expect(controller.value.composing, const TextRange(start: 1, end: 2));
    expect(focusNode.hasFocus, isTrue);
    expect(find.byType(EditableText), findsNothing);

    final composingBackspaceHandled = await tester.sendKeyEvent(
      LogicalKeyboardKey.backspace,
      platform: 'macos',
    );
    await tester.pump();

    expect(composingBackspaceHandled, isFalse);
    expect(controller.text, '甲拼\n\n乙');
    expect(controller.value.composing, const TextRange(start: 1, end: 2));

    final composingArrowHandled = await tester.sendKeyEvent(
      LogicalKeyboardKey.arrowLeft,
      platform: 'macos',
    );
    await tester.pump();

    expect(composingArrowHandled, isFalse);
    expect(controller.text, '甲拼\n\n乙');
    expect(controller.value.composing, const TextRange(start: 1, end: 2));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '甲拼\n',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.value.composing, TextRange.empty);
    expect(focusNode.hasFocus, isTrue);

    final committedBackspaceHandled = await tester.sendKeyEvent(
      LogicalKeyboardKey.backspace,
      platform: 'macos',
    );
    await tester.pumpAndSettle();

    expect(committedBackspaceHandled, isTrue);
    expect(controller.text, '甲\n\n乙');
  });

  testWidgets('Windows IME 组合态退格和方向键交还系统处理', (tester) async {
    _overrideTargetPlatform(TargetPlatform.windows);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = TextEditingController(text: '甲\n\n乙');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MarkdownReadonlyBlock).first);
    await tester.pumpAndSettle();
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '甲拼\n',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 2),
      ),
    );
    await tester.pump();

    final backspaceHandled = await tester.sendKeyEvent(
      LogicalKeyboardKey.backspace,
      platform: 'windows',
    );
    final arrowHandled = await tester.sendKeyEvent(
      LogicalKeyboardKey.arrowLeft,
      platform: 'windows',
    );
    await tester.pump();

    expect(backspaceHandled, isFalse);
    expect(arrowHandled, isFalse);
    expect(controller.text, '甲拼\n\n乙');
    expect(controller.value.composing, const TextRange(start: 1, end: 2));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('长文只挂载视口块，拖选自动滚动且远端查找可定位', (tester) async {
    final longText = List<String>.generate(
      3600,
      (index) => index == 3599 ? '末尾 target' : _blockText(index),
    ).join('\n\n');
    final controller = TextEditingController(text: longText);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        RevericMarkdownEditor(
          controller: controller,
          focusNode: focusNode,
          fontFamily: 'Roboto',
          fontSize: 14,
          letterSpacing: 0,
          lineHeight: 1.5,
          limitPasteSize: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mountedBefore = find.byType(MarkdownReadonlyBlock).evaluate().length;
    expect(mountedBefore, lessThan(20));
    expect(longText.length, greaterThan(480000));
    expect(mountedBefore, lessThan(3600));

    final first = find.byType(MarkdownReadonlyBlock).first;
    final gesture = await tester.startGesture(
      _globalTextPosition(tester, first, 1),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(
      (tester.testTextInput.editingState!['text'] as String).length,
      lessThan(1000),
    );
    final editorBottom =
        tester.getBottomLeft(find.byType(MarkdownBlockListView)) +
        const Offset(100, 20);
    await gesture.moveTo(editorBottom);
    await tester.pump(const Duration(seconds: 1));

    expect(_editorScrollable(tester).position.pixels, greaterThan(0));
    expect(controller.selection.isCollapsed, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();

    await _sendControlShortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    final queryField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == 'Find',
    );
    expect(queryField, findsOneWidget);
    await tester.enterText(queryField, '末尾 target');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(controller.text), '末尾 target');
    expect(find.byType(MarkdownReadonlyBlock).evaluate().length, lessThan(20));
  });

  testWidgets('autoHeight grows with content inside an outer scroll view', (
    tester,
  ) async {
    final shortController = TextEditingController(text: '一行');
    final longController = TextEditingController(
      text: List<String>.generate(12, (index) => '段落 $index').join('\n\n'),
    );
    final shortFocusNode = FocusNode();
    final longFocusNode = FocusNode();
    addTearDown(shortController.dispose);
    addTearDown(longController.dispose);
    addTearDown(shortFocusNode.dispose);
    addTearDown(longFocusNode.dispose);

    Future<double> measure(
      TextEditingController controller,
      FocusNode focusNode,
    ) async {
      await tester.pumpWidget(
        _wrap(
          // 高度不设限，交给外层滚动容器承载，模拟人物档案页的平铺分组。
          SingleChildScrollView(
            child: RevericMarkdownEditor(
              controller: controller,
              focusNode: focusNode,
              autoHeight: true,
              showToolbar: false,
              fontFamily: 'Roboto',
              fontSize: 14,
              letterSpacing: 0,
              lineHeight: 1.5,
            ),
          ),
          height: 200,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return tester.getSize(find.byType(MarkdownBlockListView)).height;
    }

    final shortHeight = await measure(shortController, shortFocusNode);
    final longHeight = await measure(longController, longFocusNode);

    // 自增高：内容越多越高，且长内容会超出 200 的视口交给外层滚动。
    expect(longHeight, greaterThan(shortHeight));
    expect(longHeight, greaterThan(200));

    final blockList = tester.widget<MarkdownBlockListView>(
      find.byType(MarkdownBlockListView),
    );
    expect(blockList.autoHeight, isTrue);
    // 自增高时内部不再自己滚动。
    expect(_editorScrollable(tester).position.maxScrollExtent, 0);
  });

  testWidgets('触屏长按选中单词并显示手柄与浮动菜单，单击收起', (tester) async {
    final controller = TextEditingController(text: 'hello world foo');
    final focusNode = FocusNode();
    _addTouchTestTearDowns(tester, controller, focusNode);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    await _touchLongPressSelect(tester, block, 2);

    expect(controller.selection.textInside(controller.text), 'hello');
    expect(find.byKey(_touchHandleStartKey), findsOneWidget);
    expect(find.byKey(_touchHandleEndKey), findsOneWidget);
    expect(find.byKey(_touchMenuKey), findsOneWidget);

    // 单击正文收起选区并隐藏触屏覆盖层。
    await tester.tapAt(
      _globalTextPosition(tester, block, 13),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(controller.selection.isCollapsed, isTrue);
    expect(find.byKey(_touchMenuKey), findsNothing);
    expect(find.byKey(_touchHandleStartKey), findsNothing);
    expect(find.byKey(_touchHandleEndKey), findsNothing);
  });

  testWidgets('触屏长按后拖动扩展选区，松手后显示菜单', (tester) async {
    final controller = TextEditingController(text: 'hello world foo');
    final focusNode = FocusNode();
    _addTouchTestTearDowns(tester, controller, focusNode);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    final gesture = await tester.startGesture(
      _globalTextPosition(tester, block, 2),
      kind: PointerDeviceKind.touch,
    );
    addTearDown(gesture.removePointer);
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.selection.textInside(controller.text), 'hello');
    // 长按拖动期间菜单隐藏，避免跟着选区跳动。
    expect(find.byKey(_touchMenuKey), findsNothing);

    await gesture.moveTo(_globalTextPosition(tester, block, 8));
    await tester.pump();
    expect(controller.selection.start, 0);
    expect(controller.selection.end, greaterThanOrEqualTo(7));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(_touchMenuKey), findsOneWidget);
  });

  testWidgets('触屏双击选中单词并显示浮动菜单', (tester) async {
    final controller = TextEditingController(text: 'hello world foo');
    final focusNode = FocusNode();
    _addTouchTestTearDowns(tester, controller, focusNode);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    final position = _globalTextPosition(tester, block, 8);
    await tester.tapAt(position, kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tapAt(position, kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(controller.text), 'world');
    expect(find.byKey(_touchMenuKey), findsOneWidget);
  });

  testWidgets('触屏选区菜单复制写入剪贴板并为当前选区隐藏菜单', (tester) async {
    String? clipboardText;
    _mockClipboard((text) => clipboardText = text);
    final controller = TextEditingController(text: 'hello world foo');
    final focusNode = FocusNode();
    _addTouchTestTearDowns(tester, controller, focusNode);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    await _touchLongPressSelect(tester, block, 2);

    await tester.tap(find.byKey(_touchMenuCopyKey));
    await tester.pumpAndSettle();

    expect(clipboardText, 'hello');
    // 复制不改变选区，但菜单为当前选区隐藏。
    expect(controller.selection.textInside(controller.text), 'hello');
    expect(find.byKey(_touchMenuKey), findsNothing);
  });

  testWidgets('触屏选区菜单剪切移除选中文本', (tester) async {
    String? clipboardText;
    _mockClipboard((text) => clipboardText = text);
    final controller = TextEditingController(text: 'hello world foo');
    final focusNode = FocusNode();
    _addTouchTestTearDowns(tester, controller, focusNode);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    await _touchLongPressSelect(tester, block, 2);
    expect(controller.selection.textInside(controller.text), 'hello');
    expect(find.byKey(_touchMenuKey), findsOneWidget);

    await tester.tap(find.byKey(_touchMenuCutKey));
    await tester.pumpAndSettle();

    expect(clipboardText, 'hello');
    expect(controller.text, ' world foo');
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
    expect(find.byKey(_touchMenuKey), findsNothing);

    await _touchLongPressSelect(tester, block, 2);
    expect(controller.selection.textInside(controller.text), 'world');
    expect(find.byKey(_touchMenuKey), findsOneWidget);
  });

  testWidgets('触屏选区菜单全选', (tester) async {
    final controller = TextEditingController(text: 'hello world foo');
    final focusNode = FocusNode();
    _addTouchTestTearDowns(tester, controller, focusNode);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    await _touchLongPressSelect(tester, block, 2);

    await tester.tap(find.byKey(_touchMenuSelectAllKey));
    await tester.pumpAndSettle();

    expect(controller.selection.textInside(controller.text), 'hello world foo');
    expect(find.byKey(_touchMenuKey), findsOneWidget);
  });

  testWidgets('拖动触屏手柄调整选区范围', (tester) async {
    final controller = TextEditingController(text: 'hello world foo');
    final focusNode = FocusNode();
    _addTouchTestTearDowns(tester, controller, focusNode);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    await _touchLongPressSelect(tester, block, 2);
    final endHandle = find.byKey(_touchHandleEndKey);
    expect(endHandle, findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(endHandle),
      kind: PointerDeviceKind.touch,
    );
    addTearDown(gesture.removePointer);
    // 越过 touch slop 后手柄拖动开始，菜单隐藏。
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    expect(find.byKey(_touchMenuKey), findsNothing);

    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(controller.selection.start, 0);
    expect(controller.selection.end, greaterThan(5));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(_touchMenuKey), findsOneWidget);
  });

  testWidgets('鼠标拖选不显示触屏手柄与菜单', (tester) async {
    final controller = TextEditingController(text: 'hello world foo');
    final focusNode = FocusNode();
    _addTouchTestTearDowns(tester, controller, focusNode);

    await tester.pumpWidget(
      _wrap(_editor(controller: controller, focusNode: focusNode)),
    );
    await tester.pumpAndSettle();

    final block = find.byType(MarkdownReadonlyBlock).first;
    final gesture = await tester.startGesture(
      _globalTextPosition(tester, block, 1),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await gesture.moveTo(_globalTextPosition(tester, block, 8));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.selection.isCollapsed, isFalse);
    expect(find.byKey(_touchMenuKey), findsNothing);
    expect(find.byKey(_touchHandleStartKey), findsNothing);
    expect(find.byKey(_touchHandleEndKey), findsNothing);
  });
}

const _touchMenuKey = ValueKey<String>('markdownTouchSelectionMenu');
const _touchMenuCopyKey = ValueKey<String>('markdownTouchMenuCopy');
const _touchMenuCutKey = ValueKey<String>('markdownTouchMenuCut');
const _touchMenuSelectAllKey = ValueKey<String>('markdownTouchMenuSelectAll');
const _touchHandleStartKey = ValueKey<String>('markdownTouchHandleStart');
const _touchHandleEndKey = ValueKey<String>('markdownTouchHandleEnd');

/// 触屏长按 [block] 内 [localOffset] 处并松手，等待长按超时触发选词。
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
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

Future<void> _sendControlShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _sendMacShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool alt = false,
}) async {
  if (!alt) {
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
  } else {
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.altLeft,
      platform: 'macos',
    );
  }
  if (shift) {
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
  }
  await tester.sendKeyEvent(key, platform: 'macos');
  if (shift) {
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
  }
  await tester.sendKeyUpEvent(
    alt ? LogicalKeyboardKey.altLeft : LogicalKeyboardKey.metaLeft,
    platform: 'macos',
  );
  await tester.pump();
}

Future<void> _sendWindowsShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.controlLeft,
    platform: 'windows',
  );
  if (shift) {
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'windows',
    );
  }
  await tester.sendKeyEvent(key, platform: 'windows');
  if (shift) {
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'windows',
    );
  }
  await tester.sendKeyUpEvent(
    LogicalKeyboardKey.controlLeft,
    platform: 'windows',
  );
  await tester.pump();
}

void _overrideTargetPlatform(TargetPlatform platform) {
  debugDefaultTargetPlatformOverride = platform;
}

void _addTouchTestTearDowns(
  WidgetTester tester,
  TextEditingController controller,
  FocusNode focusNode,
) {
  addTearDown(() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    tester.testTextInput.reset();
    controller.dispose();
    focusNode.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}

ScrollableState _editorScrollable(WidgetTester tester) {
  return tester.state<ScrollableState>(
    find.descendant(
      of: find.byType(MarkdownBlockListView),
      matching: find.byType(Scrollable),
    ),
  );
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

String _blockText(int index) {
  return '第 $index 段 ${'正文内容' * 30} target';
}

Widget _wrap(Widget child, {double width = 800, double height = 400}) {
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
                body: SizedBox(width: width, height: height, child: child),
              ),
            ),
          ),
        );
      },
    ),
  );
}

Widget _editor({
  required TextEditingController controller,
  required FocusNode focusNode,
}) {
  return RevericMarkdownEditor(
    controller: controller,
    focusNode: focusNode,
    fontFamily: 'Roboto',
    fontSize: 14,
    letterSpacing: 0,
    lineHeight: 1.5,
    limitPasteSize: false,
  );
}

List<int> _visualLineStarts(
  int textLength,
  List<TextBox> Function(TextSelection selection) boxesForSelection,
) {
  final starts = <int>[0];
  double? previousTop;
  for (var offset = 0; offset < textLength; offset++) {
    final boxes = boxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
    );
    expect(boxes, isNotEmpty);
    final top = boxes.first.top;
    if (previousTop != null && (top - previousTop).abs() > 0.5) {
      starts.add(offset);
    }
    previousTop = top;
  }
  return starts;
}

Offset _scrollbarThumbCenter(WidgetTester tester) {
  final scrollbar = find.byWidgetPredicate((widget) => widget is RawScrollbar);
  expect(scrollbar, findsOneWidget);
  final scrollbarRect = tester.getRect(scrollbar);
  final dynamic state = tester.state(scrollbar);
  final hits = <Offset>[];
  for (var y = scrollbarRect.top; y <= scrollbarRect.bottom; y += 1) {
    for (var x = scrollbarRect.right - 32; x <= scrollbarRect.right; x += 1) {
      final point = Offset(x, y);
      if (state.isPointerOverThumb(point, PointerDeviceKind.mouse) as bool) {
        hits.add(point);
      }
    }
  }
  expect(hits, isNotEmpty);
  final left = hits.map((point) => point.dx).reduce(math.min);
  final right = hits.map((point) => point.dx).reduce(math.max);
  final top = hits.map((point) => point.dy).reduce(math.min);
  final bottom = hits.map((point) => point.dy).reduce(math.max);
  return Offset((left + right) / 2, (top + bottom) / 2);
}

// Reproduce a laid-out paragraph below a transform whose size is not assigned yet.
class _AncestorLayoutProbe extends SingleChildRenderObjectWidget {
  const _AncestorLayoutProbe({
    required this.onChildLaidOut,
    required super.child,
  });
  final VoidCallback onChildLaidOut;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ProbeTransform(onChildLaidOut);
}

class _ProbeTransform extends RenderTransform {
  _ProbeTransform(this.onChildLaidOut)
    : super(transform: Matrix4.identity(), alignment: Alignment.center);
  final VoidCallback onChildLaidOut;

  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    onChildLaidOut();
    size = child!.size;
  }
}
