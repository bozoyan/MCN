// 职责: 验证正文缩进 formatter 的边界输入不再抛 RangeError，且缩进继承语义不变
// 关联文件:
//   lib/shared/utils/text_input_formatters.dart
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/mobile/pages/chapter_editor_page.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/text_input_formatters.dart';

void main() {
  const formatter = ChapterParagraphIndentFormatter();

  TextEditingValue apply(TextEditingValue old, TextEditingValue next) {
    return formatter.formatEditUpdate(old, next);
  }

  group('ChapterParagraphIndentFormatter 换行插入点在行首', () {
    // 线上 1.2.1/1.2.2 崩溃：
    // RangeError: Invalid value: Not in inclusive range 0..N: -1
    //（空文本按 Enter → _leadingIndent lineEnd=0 → lastIndexOf('\n', -1)）
    test('空文本按 Enter 不抛 RangeError', () {
      final result = apply(
        const TextEditingValue(text: ''),
        const TextEditingValue(
          text: '\n',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      expect(result.text, '\n');
    });

    test('行首按 Enter 不抛 RangeError', () {
      final result = apply(
        const TextEditingValue(text: '第一段'),
        const TextEditingValue(
          text: '\n第一段',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      expect(result.text, '\n第一段');
    });
  });

  test('段尾按 Enter 继承上一行行首缩进', () {
    final result = apply(
      const TextEditingValue(text: '\u3000\u3000第一段'),
      const TextEditingValue(
        text: '\u3000\u3000第一段\n',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    expect(result.text, '\u3000\u3000第一段\n\u3000\u3000');
    expect(result.selection.baseOffset, 8);
  });
}
