// 职责: sanitizeSurrogates 单元测试
// 关联文件:
//   lib/shared/agent/client/_sanitize.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:reveric/shared/agent/client/_sanitize.dart';

void main() {
  group('sanitizeSurrogates', () {
    test('keeps empty string unchanged', () {
      expect(sanitizeSurrogates(''), '');
    });

    test('keeps plain ASCII unchanged', () {
      expect(sanitizeSurrogates('hello world'), 'hello world');
    });

    test('keeps valid surrogate pair (emoji) unchanged', () {
      const emoji = '\u{1F600}'; // grinning face
      expect(sanitizeSurrogates(emoji), emoji);
      expect(sanitizeSurrogates('hi $emoji there'), 'hi $emoji there');
    });

    test('replaces lone high surrogate with U+FFFD', () {
      final lone = String.fromCharCode(0xD800);
      final out = sanitizeSurrogates('a${lone}b');
      expect(out, 'a\uFFFDb');
    });

    test('replaces lone low surrogate with U+FFFD', () {
      final lone = String.fromCharCode(0xDC00);
      final out = sanitizeSurrogates('a${lone}b');
      expect(out, 'a\uFFFDb');
    });

    test('keeps multibyte BMP characters unchanged', () {
      const s = '中文测试 — café';
      expect(sanitizeSurrogates(s), s);
    });

    test('handles consecutive valid surrogate pairs', () {
      const s = '\u{1F600}\u{1F601}\u{1F602}';
      expect(sanitizeSurrogates(s), s);
    });

    test('handles high surrogate at end of string', () {
      final s = 'tail${String.fromCharCode(0xD801)}';
      expect(sanitizeSurrogates(s), 'tail\uFFFD');
    });
  });
}
