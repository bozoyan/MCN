// 职责: 实体关系图环色测试 — 验证人物按角色使用不同主题色。
// 关联文件:
//   lib/shared/entity_graph/colors.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/entity_graph/colors.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  test('character roles use distinct ring colors', () {
    final colors = RevericThemeData.reveric.colors;

    final protagonist = entityGraphRingColor(
      'character',
      colors,
      typeKey: 'protagonist',
    );
    final antagonist = entityGraphRingColor(
      'character',
      colors,
      typeKey: 'antagonist',
    );
    final supporting = entityGraphRingColor(
      'character',
      colors,
      typeKey: 'supporting',
    );
    final minor = entityGraphRingColor('character', colors, typeKey: 'minor');

    expect(protagonist, colors.accent);
    expect(antagonist, colors.error);
    expect(supporting, colors.textMuted);
    expect(minor, colors.textSubtle);
    expect({protagonist, antagonist, supporting, minor}.length, 4);
  });

  test('non-character types keep their own ring colors', () {
    final colors = RevericThemeData.reveric.colors;
    expect(entityGraphRingColor('faction', colors), isNot(colors.accent));
    expect(entityGraphRingColor('character', colors), colors.accent);
  });
}
