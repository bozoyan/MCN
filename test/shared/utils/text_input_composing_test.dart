import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/text_input_composing.dart';

void main() {
  test('isTextInputComposing detects active composing range', () {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    controller.value = const TextEditingValue(
      text: 'ni',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );

    expect(isTextInputComposing(controller), isTrue);
  });

  test('isTextInputComposing is false after committed text', () {
    final controller = TextEditingController(text: '你');
    addTearDown(controller.dispose);

    expect(isTextInputComposing(controller), isFalse);
  });

  group('writeControllerTextAfterComposing', () {
    test('writes immediately when not composing', () {
      final controller = TextEditingController(text: 'old');
      addTearDown(controller.dispose);

      writeControllerTextAfterComposing(controller, (_) => 'new');

      expect(controller.text, 'new');
      expect(controller.selection, const TextSelection.collapsed(offset: 3));
    });

    test('does not clobber composing range while user is composing', () {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );

      writeControllerTextAfterComposing(controller, (_) => 'draft');

      // 组词未结束：文本与 composing 都必须原样保留，否则 embedder 会
      // discardMarkedText 丢掉用户正在输入的拼音。
      expect(controller.text, 'ni');
      expect(controller.value.composing, const TextRange(start: 0, end: 2));
      expect(isTextInputComposing(controller), isTrue);
    });

    test('applies the deferred write once composing ends', () {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );

      writeControllerTextAfterComposing(controller, (_) => 'draft');
      expect(controller.text, 'ni');

      // 用户上屏「你」，composing 清空 → 延后的写入此时套用。
      controller.value = const TextEditingValue(
        text: '你',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(controller.text, 'draft');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
    });

    test(
      'deferred append sees the committed text, not the pre-compose text',
      () {
        final controller = TextEditingController(text: 'hi');
        addTearDown(controller.dispose);
        controller.value = const TextEditingValue(
          text: 'hini',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange(start: 2, end: 4),
        );

        writeControllerTextAfterComposing(
          controller,
          (currentText) => '$currentText!',
        );

        controller.value = const TextEditingValue(
          text: 'hi你',
          selection: TextSelection.collapsed(offset: 3),
        );

        expect(controller.text, 'hi你!');
      },
    );

    test('queued deferred writes apply in order', () {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );

      writeControllerTextAfterComposing(controller, (current) => '${current}A');
      writeControllerTextAfterComposing(controller, (current) => '${current}B');

      controller.value = const TextEditingValue(
        text: '你',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(controller.text, '你AB');
    });
  });
}
