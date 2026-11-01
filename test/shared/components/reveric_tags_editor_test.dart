// 职责: 验证通用标签编辑器的 IME 组合输入与最终长度限制。
// 关联文件:
//   lib/shared/components/reveric_tags_editor.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/text-input-ime.md
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_tags_editor.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  testWidgets('Windows IME keeps long pinyin until Chinese text is committed', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      List<String>? updatedTags;
      await tester.pumpWidget(
        MaterialApp(
          theme: RevericThemeData.reveric.toThemeData(),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(
              body: RevericTagsEditor(
                tags: const [],
                onChanged: (tags) => updatedTags = tags,
                addLabel: 'Add tag',
                hintText: 'Tag',
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Add tag'));
      await tester.pump();

      const composingPinyin = TextEditingValue(
        text: 'xuanhuan',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 0, end: 8),
      );
      tester.testTextInput.updateEditingValue(composingPinyin);
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.value, composingPinyin);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '玄幻',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(updatedTags, ['玄幻']);

      await tester.tap(find.text('Add tag'));
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '玄幻爽文流',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();

      final limitedField = tester.widget<TextField>(find.byType(TextField));
      expect(limitedField.controller!.text, '玄幻爽文');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
