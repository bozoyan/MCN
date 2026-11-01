// 职责: 验证流式 delta 边界缓冲不下发半个代理对，且不丢失/损坏字符。
// 关联文件:
//   lib/shared/agent/surrogate_carry.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:reveric/shared/agent/surrogate_carry.dart';

/// 高代理必须紧跟低代理、低代理必须有前置高代理，否则存在落单代理。
bool hasUnpairedSurrogate(String s) {
  var i = 0;
  while (i < s.length) {
    final u = s.codeUnitAt(i);
    if (u >= 0xD800 && u <= 0xDBFF) {
      if (i + 1 >= s.length) return true;
      final next = s.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return true;
      i += 2;
    } else {
      if (u >= 0xDC00 && u <= 0xDFFF) return true;
      i += 1;
    }
  }
  return false;
}

void main() {
  group('SurrogateCarry', () {
    test('passes plain text straight through', () {
      final carry = SurrogateCarry();
      expect(carry.take('hello'), 'hello');
      expect(carry.hasPending, isFalse);
      expect(carry.flush(), '');
    });

    test('keeps an intact emoji in a single delta', () {
      final carry = SurrogateCarry();
      expect(carry.take('hi 😀'), 'hi 😀');
      expect(carry.hasPending, isFalse);
    });

    test('holds back a trailing high surrogate until the next delta', () {
      // provider 把 😀 (D83D DE00) 拆成两个 delta。
      final high = String.fromCharCode(0xD83D);
      final low = String.fromCharCode(0xDE00);
      final carry = SurrogateCarry();

      final first = carry.take('hi $high');
      expect(first, 'hi '); // 半个 emoji 没有下发
      expect(hasUnpairedSurrogate(first), isFalse);
      expect(carry.hasPending, isTrue);

      final second = carry.take('${low}there');
      expect(second, '😀there'); // 晚一拍完整出现
      expect(hasUnpairedSurrogate(second), isFalse);
      expect(carry.hasPending, isFalse);
    });

    test('accumulated stream never contains an unpaired surrogate', () {
      const source = 'a😀b👨‍👩‍👧c𠀋d';
      // 逐个 code unit 下发 —— 每个代理对都被切开，是最坏情况。
      for (var chunk = 1; chunk <= 3; chunk++) {
        final carry = SurrogateCarry();
        final buffer = StringBuffer();
        for (var i = 0; i < source.length; i += chunk) {
          final end = (i + chunk).clamp(0, source.length);
          final safe = carry.take(source.substring(i, end));
          buffer.write(safe);
          expect(
            hasUnpairedSurrogate(buffer.toString()),
            isFalse,
            reason: 'chunk=$chunk 在 i=$i 处出现落单代理',
          );
        }
        buffer.write(carry.flush());
        // 全部下发完毕后内容与原文完全一致，没有丢字也没有替换。
        expect(buffer.toString(), source, reason: 'chunk=$chunk 内容被改动');
      }
    });

    test('flushes a dangling high surrogate as U+FFFD', () {
      final carry = SurrogateCarry();
      expect(carry.take('x${String.fromCharCode(0xD83D)}'), 'x');
      expect(carry.hasPending, isTrue);
      // 上游截断在代理对中间：补替换符，不静默丢字符。
      expect(carry.flush(), '�');
      expect(carry.hasPending, isFalse);
      expect(carry.flush(), '');
    });

    test('empty deltas do not disturb a pending surrogate', () {
      final carry = SurrogateCarry();
      expect(carry.take(String.fromCharCode(0xD83D)), '');
      expect(carry.take(''), '');
      expect(carry.hasPending, isTrue);
      expect(carry.take(String.fromCharCode(0xDE00)), '😀');
    });
  });
}
