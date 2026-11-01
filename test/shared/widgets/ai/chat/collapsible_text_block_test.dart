// 职责: 验证 AI 聊天文本块按 Markdown 渲染、不覆盖平台字体 fallback，且全角数字归一化为半角。
// 关联文件:
//   lib/shared/widgets/ai/chat/chat_message_parts.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/chat/chat_message_parts.dart';

void main() {
  testWidgets(
    'AI text block renders markdown without overriding font fallback',
    (tester) async {
      const theme = RevericThemeData.reveric;

      await tester.pumpWidget(
        MaterialApp(
          theme: theme.toThemeData(),
          home: RevericTheme(
            data: theme,
            child: const Scaffold(
              body: CollapsibleTextBlock(
                content: '1. ✅ **TensorFlow 时间线** — 改为说明',
                textStyle: TextStyle(),
              ),
            ),
          ),
        ),
      );

      final markdown = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
      expect(markdown.data, contains('**TensorFlow 时间线**'));
      expect(markdown.data.runes, contains(0x2705));
      expect(markdown.style?.fontFamily, isNull);
      expect(markdown.style?.fontFamilyFallback, isNull);
    },
  );

  testWidgets(
    // 模型写中文时常输出全角数字（U+FF10–FF19），它们占满 CJK 字宽，渲染出来又宽又散。
    // 这里验证全角数字被归一化为半角，而中文全角标点（「」，。）保持原样，不被误改。
    'AI text block normalizes fullwidth digits but keeps CJK punctuation',
    (tester) async {
      const theme = RevericThemeData.reveric;

      await tester.pumpWidget(
        MaterialApp(
          theme: theme.toThemeData(),
          home: RevericTheme(
            data: theme,
            child: const Scaffold(
              body: CollapsibleTextBlock(
                content: '第１２章「２.０版本开发」，用户数破５００，约４５００字。',
                textStyle: TextStyle(),
              ),
            ),
          ),
        ),
      );

      final markdown = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
      // 全角数字已转半角。
      expect(markdown.data, contains('第12章'));
      expect(markdown.data, contains('2.0版本开发'));
      expect(markdown.data, contains('用户数破500'));
      expect(markdown.data, contains('约4500字'));
      // 不残留任何全角数字。
      expect(
        RegExp(r'[０-９]').hasMatch(markdown.data),
        isFalse,
        reason: '全角数字应已全部归一化为半角',
      );
      // 中文全角标点保持原样。
      expect(markdown.data, contains('「'));
      expect(markdown.data, contains('」'));
      expect(markdown.data, contains('，'));
      expect(markdown.data, contains('。'));
    },
  );
}
