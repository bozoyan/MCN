// 职责: 测试共享文本单元统计口径，覆盖中英混排、标点、数字、空格、缩进与段落分项。
// 关联文件:
//   lib/shared/utils/text_unit_count.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/text_unit_count.dart';

void main() {
  group('countTextUnitStats', () {
    test(
      'counts saved word units from cjk, latin, punctuation, and digits',
      () {
        const content = '　　老猫A1，go-2!\n第二段  test.';

        final stats = countTextUnitStats(content);

        expect(stats.wordUnits, 14);
        expect(stats.cjkCharacters, 5);
        expect(stats.latinWords, 3);
        expect(stats.punctuation, 4);
        expect(stats.wordUnitsWithPunctuation, stats.wordUnits);
        expect(
          stats.wordUnitsWithoutPunctuation,
          stats.wordUnits - stats.punctuation,
        );
        expect(stats.arabicDigits, 2);
        expect(stats.characters, 23);
        expect(stats.whitespace, 2);
        expect(stats.indents, 2);
        expect(stats.paragraphs, 2);
      },
    );

    test('blank text returns zero for every stat', () {
      final stats = countTextUnitStats(' \n　\t');

      expect(stats.wordUnits, 0);
      expect(stats.cjkCharacters, 0);
      expect(stats.latinWords, 0);
      expect(stats.punctuation, 0);
      expect(stats.arabicDigits, 0);
      expect(stats.characters, 0);
      expect(stats.whitespace, 0);
      expect(stats.indents, 0);
      expect(stats.paragraphs, 0);
    });
  });
}
