// 职责: 验证插件清单可本地化文案的解析与按语言取值的回退顺序。
// 关联文件:
//   lib/shared/models/plugin/text.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/plugin/text.dart';

const _zh = Locale('zh', 'CN');
const _en = Locale('en');
const _ja = Locale('ja');

void main() {
  test('a plain string is shared by every language', () {
    final text = parsePluginText('Verify', 'title');
    expect(
      [
        for (final l in [_zh, _en, _ja]) text.resolve(l),
      ],
      ['Verify', 'Verify', 'Verify'],
    );
  });

  test('a localized map prefers the current language', () {
    final text = parsePluginText({'en': 'Verify', 'zh-CN': '验证'}, 'title');
    expect(text.resolve(_zh), '验证');
    expect(text.resolve(_en), 'Verify');
  });

  test('a missing language falls back to zh-CN, en, then the first entry', () {
    expect(
      parsePluginText({'en': 'Verify', 'zh-CN': '验证'}, 'title').resolve(_ja),
      '验证',
    );
    expect(parsePluginText({'en': 'Verify'}, 'title').resolve(_zh), 'Verify');
    expect(parsePluginText({'zh-CN': '验证'}, 'title').resolve(_en), '验证');
    expect(
      parsePluginText({'ja': '検証', 'fr': 'Vérifier'}, 'title').resolve(_en),
      '検証',
    );
  });

  test('empty or non-string text is rejected', () {
    for (final json in [
      null,
      ' ',
      1,
      <String, String>{},
      {'en': ' '},
      {'en': 1},
      {'': 'x'},
    ]) {
      expect(
        () => parsePluginText(json, 'title'),
        throwsFormatException,
        reason: '$json',
      );
    }
  });
}
