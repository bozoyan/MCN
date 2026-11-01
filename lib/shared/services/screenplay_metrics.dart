// 职责: 以固定算法计算剧本正文的页数、台词数与字数。
// 关联文件:
//   lib/shared/models/screenplay_element.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/utils/text_unit_count.dart

import 'dart:math' as math;

import '../models/screenplay_element.dart';
import '../utils/text_unit_count.dart';

class ScreenplayMetrics {
  const ScreenplayMetrics({
    required this.pageEighths,
    required this.dialogueLineCount,
    required this.wordCount,
  });

  static const int linesPerPage = 36;
  static const int actionUnitsPerLine = 28;
  static const int dialogueUnitsPerLine = 16;
  static const int parentheticalUnitsPerLine = 12;

  final int pageEighths;
  final int dialogueLineCount;
  final int wordCount;

  factory ScreenplayMetrics.calculate(Iterable<ScreenplayElement> elements) {
    var lines = 0;
    var dialogueLines = 0;
    var words = 0;
    for (final element in elements.map((value) => value.normalized())) {
      if (element.type == ScreenplayElementType.note) {
        continue;
      }
      if (element.type != ScreenplayElementType.character) {
        words += countTextUnits(element.text);
      }
      switch (element.type) {
        case ScreenplayElementType.action:
        case ScreenplayElementType.subtitle:
          lines += _textLines(element.text, actionUnitsPerLine);
        case ScreenplayElementType.dialogue:
          dialogueLines += 1;
          lines += _textLines(element.text, dialogueUnitsPerLine);
        case ScreenplayElementType.parenthetical:
          lines += _textLines(element.text, parentheticalUnitsPerLine);
        case ScreenplayElementType.character:
        case ScreenplayElementType.transition:
          lines += 1;
        case ScreenplayElementType.scene_heading:
        case ScreenplayElementType.note:
          break;
      }
    }
    final pageEighths = lines == 0 ? 0 : (lines * 8 / linesPerPage).ceil();
    return ScreenplayMetrics(
      pageEighths: pageEighths,
      dialogueLineCount: dialogueLines,
      wordCount: words,
    );
  }

  static int _textLines(String text, int unitsPerLine) {
    return text.split('\n').fold<int>(0, (total, paragraph) {
      final units = countTextUnits(paragraph);
      return total + math.max(1, (units / unitsPerLine).ceil());
    });
  }
}
