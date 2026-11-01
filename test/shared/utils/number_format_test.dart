import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/number_format.dart';

void main() {
  group('formatHomeNovelWordCount', () {
    test('uses 万 unit for Chinese locales', () {
      expect(formatHomeNovelWordCount(31450, languageCode: 'zh-CN'), '3.1');
      expect(formatHomeNovelWordCount(4406163, languageCode: 'zh'), '440.6');
    });

    test('keeps compact k/m suffix for English', () {
      expect(formatHomeNovelWordCount(32000, languageCode: 'en'), '32k');
    });
  });
}
