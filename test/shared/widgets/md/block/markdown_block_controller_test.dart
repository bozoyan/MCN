// 职责: 验证 Markdown 唯一全文编辑值、跨块选择、IME、Unicode 删除与撤销契约
// 关联文件:
//   lib/shared/widgets/md/block/markdown_block_controller.dart
//   lib/shared/widgets/md/block/markdown_block_document.dart
//   lib/shared/widgets/md/block/markdown_edit_patch_stack.dart
//   lib/shared/widgets/md/block/markdown_text_input_client.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/text-input-ime.md

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/md/block/markdown_block_controller.dart';
import 'package:reveric/shared/widgets/md/block/markdown_text_input_client.dart';

void main() {
  test('跨块范围保留为全文唯一 selection 并可一次删除', () {
    final external = TextEditingController(text: '甲\n\n乙');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);

    controller.activateRange(
      const TextRange(start: 0, end: 4),
      requestFocus: false,
    );

    expect(
      external.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );

    controller.deleteBackward();

    expect(external.text, isEmpty);
    expect(external.selection, const TextSelection.collapsed(offset: 0));
    expect(controller.document.source, external.text);
  });

  test('平台输入原子同步全文、全局光标与派生块文档', () {
    final external = TextEditingController(text: '甲\n\n乙');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);

    controller.applyUserValue(
      const TextEditingValue(
        text: '甲\n\n乙X',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );

    expect(external.text, '甲\n\n乙X');
    expect(external.selection.extentOffset, 5);
    expect(controller.document.source, external.text);
    expect(controller.document.isContiguous, isTrue);
  });

  test('滞后的平台 delta 不覆盖本地退格结果', () {
    final external = TextEditingController(text: 'abc');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);
    final inputClient = MarkdownTextInputClient(
      controller: controller,
      inputFormatters: const <TextInputFormatter>[],
      enabled: true,
    );
    addTearDown(inputClient.dispose);

    expect(inputClient.currentTextEditingValue.text, 'abc');

    controller.deleteBackward();

    inputClient.updateEditingValueWithDeltas([
      TextEditingDeltaDeletion(
        oldText: 'abc',
        deletedRange: const TextRange(start: 1, end: 2),
        selection: const TextSelection.collapsed(offset: 1),
        composing: TextRange.empty,
      ),
    ]);

    expect(external.text, 'ab');
    expect(external.selection, const TextSelection.collapsed(offset: 2));
  });

  test('输入空行会重切块但不重写 selection', () {
    final external = TextEditingController(text: '甲\n\n乙');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);

    controller.applyUserValue(
      const TextEditingValue(
        text: '甲\n\n新\n\n乙',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );

    expect(controller.document.length, 3);
    expect(controller.activeBlockIndex, 1);
    expect(external.selection.extentOffset, 4);
  });

  test('Enter 与后续输入在同一个全文坐标系连续前进', () {
    final external = TextEditingController(text: '甲\n\n乙');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);
    controller.setSelection(
      const TextSelection.collapsed(offset: 1),
      requestFocus: false,
    );

    controller.replaceSelection('\n');

    expect(external.text, '甲\n\n\n乙');
    expect(external.selection.extentOffset, 2);

    controller.replaceSelection('新', mergeable: true);

    expect(external.text, '甲\n新\n\n乙');
    expect(external.selection.extentOffset, 3);
  });

  test('IME 草稿实时派生块视图，提交后只生成一条可撤销编辑', () {
    final external = TextEditingController(text: '甲\n\n乙');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);

    controller.applyUserValue(
      const TextEditingValue(
        text: '甲拼\n\n乙',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 2),
      ),
    );

    expect(controller.document.source, '甲拼\n\n乙');
    expect(external.value.composing, const TextRange(start: 1, end: 2));
    expect(controller.canUndo, isFalse);

    controller.applyUserValue(
      const TextEditingValue(
        text: '甲拼\n\n乙',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );

    expect(external.value.composing, TextRange.empty);
    expect(controller.canUndo, isTrue);

    controller.undo();

    expect(external.text, '甲\n\n乙');
  });

  test('原生删除命令可以在 composing 状态下删除并结束 composing', () {
    final external = TextEditingController(text: 'abc');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);

    controller.applyUserValue(
      const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 2),
      ),
    );

    controller.deleteBackward(allowComposing: true);

    expect(external.text, 'ac');
    expect(external.selection, const TextSelection.collapsed(offset: 1));
    expect(external.value.composing, TextRange.empty);
  });

  test('原生方向命令可以在 composing 状态下移动并结束 composing', () {
    final external = TextEditingController(text: 'abc');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);

    controller.applyUserValue(
      const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 2),
      ),
    );

    controller.moveHorizontally(
      forward: false,
      extend: false,
      allowComposing: true,
    );

    expect(external.selection, const TextSelection.collapsed(offset: 1));
    expect(external.value.composing, TextRange.empty);
  });

  test('块首退格只删除一个换行序列并合并相邻块', () {
    final external = TextEditingController(text: '甲\n\n乙');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);
    controller.setSelection(
      const TextSelection.collapsed(offset: 3),
      requestFocus: false,
    );

    controller.deleteBackward();

    expect(external.text, '甲\n乙');
    expect(controller.document.length, 1);
    expect(external.selection.extentOffset, 2);
  });

  test('CRLF 前后删除把换行序列作为一个字符簇', () {
    final backwardExternal = TextEditingController(text: '甲\r\n\r\n乙');
    final backwardFocus = FocusNode();
    final backward = _controller(backwardExternal, backwardFocus);
    backward.setSelection(
      const TextSelection.collapsed(offset: 5),
      requestFocus: false,
    );

    backward.deleteBackward();

    expect(backwardExternal.text, '甲\r\n乙');

    final forwardExternal = TextEditingController(text: '甲\r\n\r\n乙');
    final forwardFocus = FocusNode();
    final forward = _controller(forwardExternal, forwardFocus);
    forward.setSelection(
      const TextSelection.collapsed(offset: 1),
      requestFocus: false,
    );

    forward.deleteForward();

    expect(forwardExternal.text, '甲\r\n乙');
  });

  test('退格不会拆开 emoji 字符簇', () {
    final external = TextEditingController(text: '甲👨‍👩‍👧‍👦乙');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);
    final beforeYi = external.text.indexOf('乙');
    controller.setSelection(
      TextSelection.collapsed(offset: beforeYi),
      requestFocus: false,
    );

    controller.deleteBackward();

    expect(external.text, '甲乙');
    expect(external.selection.extentOffset, 1);
  });

  test('全文 patch 可撤销和重做，外部 controller 始终同步', () {
    final external = TextEditingController(text: '甲\n\n乙');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);
    controller.setSelection(
      const TextSelection.collapsed(offset: 4),
      requestFocus: false,
    );
    controller.replaceSelection('X', mergeable: true);

    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(external.text, '甲\n\n乙');
    expect(controller.canRedo, isTrue);

    controller.redo();
    expect(external.text, '甲\n\n乙X');
  });

  test('外部整篇写入会重建块视图并保留同步 selection', () {
    final external = TextEditingController(text: '旧文');
    final focusNode = FocusNode();
    final controller = _controller(external, focusNode);

    external.value = const TextEditingValue(
      text: '新一\n\n新二\n\n新三',
      selection: TextSelection.collapsed(offset: 6),
    );

    expect(controller.document.source, external.text);
    expect(controller.document.length, 3);
    expect(external.selection.extentOffset, 6);
  });
}

MarkdownBlockController _controller(
  TextEditingController external,
  FocusNode focusNode,
) {
  final controller = MarkdownBlockController(
    externalController: external,
    focusNode: focusNode,
  );
  addTearDown(controller.dispose);
  addTearDown(external.dispose);
  addTearDown(focusNode.dispose);
  return controller;
}
