// 职责: 上次写到句子提取测试 — 覆盖 markdown 清洗、末句回溯与空内容处理
// 关联文件:
//   lib/shared/utils/chapter_last_sentence.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/chapter_last_sentence.dart';

void main() {
  group('extractLastWrittenSentence', () {
    test('returns null for empty content', () {
      expect(extractLastWrittenSentence(null), isNull);
      expect(extractLastWrittenSentence('   \n  '), isNull);
    });

    test('cleans markdown and returns the last meaningful sentence', () {
      const content = '''
# 第一章

她推开门。

**这里藏着真正重要的东西。**
''';

      expect(extractLastWrittenSentence(content), '“这里藏着真正重要的东西。”');
    });

    test('strips wrapping quotes and truncates long sentence', () {
      final longText = '“${'很'.padRight(90, '长')}。”';

      expect(
        extractLastWrittenSentence(longText),
        '“${'很'.padRight(80, '长')}…”',
      );
    });
  });
}
