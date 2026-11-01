// 职责: 测试标点替换纯函数 — 引号交替、全角标点、空规则幂等。
// 关联文件:
//   lib/shared/utils/punctuation_replace.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/punctuation_replace.dart';

void main() {
  group('applyPunctuationReplace', () {
    test('alternates the default paired quote rule', () {
      const rules = [PunctuationReplaceRule(from: '"', to: '“”')];
      expect(applyPunctuationReplace('他说"你好"然后离开。', rules), '他说“你好”然后离开。');
    });

    test('replaces a custom single-character rule with two characters', () {
      const rules = [PunctuationReplaceRule(from: 'a', to: 'BC')];
      expect(applyPunctuationReplace('a a a', rules), 'BC BC BC');
    });

    test('converts half-width punctuation with default rules', () {
      expect(
        applyPunctuationReplace('Ready?: go!', defaultPunctuationReplaceRules),
        'Ready？： go！',
      );
    });

    test('empty text or empty rules returns input unchanged', () {
      expect(applyPunctuationReplace('', defaultPunctuationReplaceRules), '');
      expect(applyPunctuationReplace('hello', const []), 'hello');
    });

    test('skips rules with empty from', () {
      const rules = [
        PunctuationReplaceRule(from: '', to: '！'),
        PunctuationReplaceRule(from: '!', to: '！'),
      ];
      expect(applyPunctuationReplace('Hi!', rules), 'Hi！');
    });
  });
}
