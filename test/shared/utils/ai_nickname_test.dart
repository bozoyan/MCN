// 职责: 验证首次启动随机称呼按界面语言生成且非空。
// 关联文件:
//   lib/shared/utils/ai_nickname.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/ai_nickname.dart';

void main() {
  test('zh locale yields a CJK pen name', () {
    final name = randomAiNickname(const Locale('zh', 'CN'), random: Random(1));
    expect(name, matches(RegExp(r'^[一-鿿]{3,4}$')));
  });

  test('other locales yield a two-word English name', () {
    final name = randomAiNickname(const Locale('en'), random: Random(1));
    expect(name, matches(RegExp(r'^[A-Z][a-z]+ [A-Z][a-z]+$')));
  });

  test('fits the 20-char onboarding limit', () {
    for (var seed = 0; seed < 200; seed++) {
      expect(
        randomAiNickname(const Locale('en'), random: Random(seed)).length,
        lessThanOrEqualTo(20),
      );
    }
  });
}
