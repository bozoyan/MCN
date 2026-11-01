// 职责: 验证 UTF-16 代理对安全截断在边界与 emoji 场景下不产生落单代理。
// 关联文件:
//   lib/shared/utils/utf16_safe_text.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:reveric/shared/utils/utf16_safe_text.dart';

/// 高代理必须紧跟低代理、低代理必须有前置高代理，否则存在落单代理。
bool hasUnpairedSurrogate(String s) {
  var i = 0;
  while (i < s.length) {
    final u = s.codeUnitAt(i);
    final isHigh = u >= 0xD800 && u <= 0xDBFF;
    final isLow = u >= 0xDC00 && u <= 0xDFFF;
    if (isHigh) {
      if (i + 1 >= s.length) {
        return true;
      }
      final next = s.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) {
        return true;
      }
      i += 2;
    } else {
      if (isLow) {
        return true;
      }
      i += 1;
    }
  }
  return false;
}

void main() {
  group('splitsSurrogatePair', () {
    test('boundary indices never split', () {
      const text = 'a😀b';
      expect(splitsSurrogatePair(text, 0), isFalse);
      expect(splitsSurrogatePair(text, text.length), isFalse);
      expect(splitsSurrogatePair('', 0), isFalse);
    });

    test('detects index inside an emoji surrogate pair', () {
      // 'a' + U+1F600 (high D83D, low DE00) + 'b'
      const text = 'a😀b';
      expect(splitsSurrogatePair(text, 2), isTrue); // between D83D and DE00
      expect(splitsSurrogatePair(text, 1), isFalse); // before the pair
      expect(splitsSurrogatePair(text, 3), isFalse); // after the pair
    });

    test('lone code units never report a split', () {
      const text = 'abc';
      for (var i = 0; i <= text.length; i++) {
        expect(splitsSurrogatePair(text, i), isFalse);
      }
    });
  });

  group('truncateUtf16Safe', () {
    test('short text returns as-is', () {
      expect(truncateUtf16Safe('abc', 10), 'abc');
      expect(truncateUtf16Safe('abc', 3), 'abc');
    });

    test('plain truncation appends ellipsis', () {
      expect(truncateUtf16Safe('abcdef', 3), 'abc...');
    });

    test('boundary inside surrogate pair steps back one code unit', () {
      // '😀' is 2 code units; cutting at 1 would split it.
      const text = '😀😀';
      final result = truncateUtf16Safe(text, 3);
      // Cut at 2 (first emoji intact), not 3 (second emoji split).
      expect(result, '😀...');
      // Result must be well-formed UTF-16: no unpaired surrogates.
      expect(hasUnpairedSurrogate(result), isFalse);
    });

    test('custom ellipsis is honored', () {
      expect(truncateUtf16Safe('abcdef', 3, ellipsis: '…'), 'abc…');
    });

    test('emoji at the cut boundary is kept intact', () {
      const text = '文字😀文字';
      final result = truncateUtf16Safe(text, 3);
      // '文字' (2 units) + would-be emoji start (unit 3) → step back to 2.
      expect(result, '文字...');
      expect(result.contains('😀'), isFalse);
    });

    test('result of every prefix length is valid UTF-16', () {
      const text = 'a😀b😀c';
      for (var len = 0; len <= text.length; len++) {
        if (len == text.length) continue; // no truncation happens
        final result = truncateUtf16Safe(text, len);
        expect(
          hasUnpairedSurrogate(result),
          isFalse,
          reason: 'len=$len produced an unpaired surrogate',
        );
      }
    });
  });
}
