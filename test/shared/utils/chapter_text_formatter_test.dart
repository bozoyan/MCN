import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/chapter_text_formatter.dart';

void main() {
  group('applyCjkLatinSpacing', () {
    test('inserts space between CJK and Latin', () {
      expect(applyCjkLatinSpacing('我用AI写小说'), '我用 AI 写小说');
    });

    test('inserts space between Latin and CJK', () {
      expect(applyCjkLatinSpacing('重生之AI时代'), '重生之 AI 时代');
    });

    test('does not duplicate existing spaces', () {
      expect(applyCjkLatinSpacing('我用 AI 写小说'), '我用 AI 写小说');
    });
  });

  group('formatText', () {
    test(
      'preserves adjacent CJK, Latin letters, and numbers while formatting',
      () {
        const input = '我用AI写第2版\n\n第二段';
        const expected = '\u3000\u3000我用AI写第2版\n\n\u3000\u3000第二段';
        expect(formatText(input), expected);
      },
    );

    test('preserves existing spaces when spaces are allowed', () {
      const input = '我用 AI 写第 2 版';
      const expected = '\u3000\u3000我用 AI 写第 2 版';
      expect(formatText(input), expected);
    });

    test('indentCount: 0 removes indentation', () {
      const input = '第一段\n\n第二段';
      const expected = '第一段\n\n第二段';
      expect(formatText(input, indentCount: 0), expected);
    });

    test('indentCount: 1 uses a single full-width space', () {
      const input = '第一段\n\n第二段';
      const expected = '\u3000第一段\n\n\u3000第二段';
      expect(formatText(input, indentCount: 1), expected);
    });

    test(
      'blankLineBetweenParagraphs: false joins paragraphs without blank line',
      () {
        const input = '第一段\n\n第二段';
        const expected = '\u3000\u3000第一段\n\u3000\u3000第二段';
        expect(formatText(input, blankLineBetweenParagraphs: false), expected);
      },
    );

    test('allowSpaces: false removes spaces around Chinese text', () {
      const input = '我用 AI 写小说\n\n第二段';
      const expected = '\u3000\u3000我用AI写小说\n\n\u3000\u3000第二段';
      expect(formatText(input, allowSpaces: false), expected);
    });

    for (final example in <String, String>{
      'hello world': 'hello world',
      'Hello,   world!  How are you?': 'Hello, world! How are you?',
      'hello\t\u3000\u00a0world': 'hello world',
      "don't   stop; well-known   author": "don't stop; well-known author",
      '10   kg, 12  34, version  2': '10 kg, 12 34, version 2',
      'café   noir': 'café noir',
      '他说 hello   world 然后离开': '他说hello world然后离开',
      '他说 ： hello   world ， 然后 离开 。': '他说：hello world，然后离开。',
      '第 2 版 使用 AI model 3': '第2版使用AI model 3',
    }.entries) {
      test('allowSpaces: false preserves word boundaries: ${example.key}', () {
        final formatted = formatText(example.key, allowSpaces: false);
        expect(formatted, '\u3000\u3000${example.value}');
        expect(formatText(formatted, allowSpaces: false), formatted);
        expect(isChapterBodyFormatted(formatted, allowSpaces: false), isTrue);
      });
    }

    test('allowSpaces: true keeps repeated inline whitespace unchanged', () {
      expect(
        formatText('中文  hello\t\u3000world  中文'),
        '\u3000\u3000中文  hello\t\u3000world  中文',
      );
    });

    test('empty input returns empty', () {
      expect(formatText(''), '');
    });

    test('single paragraph no trailing newline', () {
      const input = '  一段文字  ';
      const expected = '\u3000\u3000一段文字';
      expect(formatText(input), expected);
    });
  });

  group('isChapterBodyFormatted', () {
    test('returns true for already formatted text', () {
      const input = '\u3000\u3000一段文字\n\n\u3000\u3000第二段';
      expect(isChapterBodyFormatted(input), true);
    });

    test('returns false for unformatted text', () {
      const input = '一段文字\n\n第二段';
      expect(isChapterBodyFormatted(input), false);
    });

    test('respects custom parameters', () {
      const formatted = '\u3000一段文字\n\n\u3000第二段';
      expect(isChapterBodyFormatted(formatted, indentCount: 1), true);
      expect(isChapterBodyFormatted(formatted, indentCount: 2), false);
    });
  });
}
