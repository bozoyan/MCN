// 职责: 统一文本单元统计与文本差异计数，供字数与变更数量复用同一口径。
// 关联文件:
//   lib/shared/services/working_change_summary.dart
//   lib/shared/services/ai/tools.dart
final RegExp _cjkCharacterPattern = RegExp(
  r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\u3040-\u30ff\uac00-\ud7af]',
);
final RegExp _latinWordPattern = RegExp(r"[A-Za-z]+(?:['_-][A-Za-z]+)*");
final RegExp _arabicDigitPattern = RegExp(r'[0-9]');
final RegExp _punctuationPattern = RegExp(
  r'[\u0021-\u002F\u003A-\u0040\u005B-\u0060\u007B-\u007E'
  r'\u2000-\u206F'
  r'\u3001-\u303F\uFF01-\uFF0F\uFF1A-\uFF20\uFF3B-\uFF40\uFF5B-\uFF65]',
);
final RegExp _spacePattern = RegExp(' ');
final RegExp _lineBreakPattern = RegExp(r'\r\n|\r|\n');

class TextUnitStats {
  const TextUnitStats({
    required this.wordUnits,
    required this.cjkCharacters,
    required this.latinWords,
    required this.punctuation,
    required this.arabicDigits,
    required this.characters,
    required this.whitespace,
    required this.indents,
    required this.paragraphs,
  });

  final int wordUnits;
  final int cjkCharacters;
  final int latinWords;
  final int punctuation;
  final int arabicDigits;
  final int characters;
  final int whitespace;
  final int indents;
  final int paragraphs;

  int get wordUnitsWithPunctuation => wordUnits;

  int get wordUnitsWithoutPunctuation => wordUnits - punctuation;
}

int countTextUnits(String content) {
  return countTextUnitStats(content).wordUnits;
}

TextUnitStats countTextUnitStats(String content) {
  if (content.trim().isEmpty) {
    return const TextUnitStats(
      wordUnits: 0,
      cjkCharacters: 0,
      latinWords: 0,
      punctuation: 0,
      arabicDigits: 0,
      characters: 0,
      whitespace: 0,
      indents: 0,
      paragraphs: 0,
    );
  }

  final cjkCount = _cjkCharacterPattern.allMatches(content).length;
  final latinWordCount = _latinWordPattern.allMatches(content).length;
  final punctuationCount = _punctuationPattern.allMatches(content).length;
  final arabicDigitCount = _arabicDigitPattern.allMatches(content).length;
  return TextUnitStats(
    wordUnits: cjkCount + latinWordCount + punctuationCount + arabicDigitCount,
    cjkCharacters: cjkCount,
    latinWords: latinWordCount,
    punctuation: punctuationCount,
    arabicDigits: arabicDigitCount,
    characters: content.runes.length,
    whitespace: _spacePattern.allMatches(content).length,
    indents: '　'.allMatches(content).length,
    paragraphs: content
        .split(_lineBreakPattern)
        .where((line) => line.trim().isNotEmpty)
        .length,
  );
}

({int added, int removed}) countTextUnitDelta(
  String? oldText,
  String? newText,
) {
  final before = countTextUnits(oldText ?? '');
  final after = countTextUnits(newText ?? '');
  if (after >= before) {
    return (added: after - before, removed: 0);
  }
  return (added: 0, removed: before - after);
}
