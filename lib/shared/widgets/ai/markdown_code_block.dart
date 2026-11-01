// 职责: GptMarkdown 代码块渲染 — 替换包内默认 CodeField，图标走 RevericIcon 而非 Material Icons。
// 关联文件:
//   lib/shared/widgets/ai/markdown_text.dart
//   lib/shared/widgets/ai/chat/chat_message_parts.dart
//   lib/shared/widgets/ai/agent_round_detail_dialog.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';

import 'package:reveric/shared/theme/theme.dart';
import 'chat/chat_message_parts.dart';

/// 作为 `GptMarkdown.codeBuilder` 传入。gpt_markdown 自带的代码块写死了
/// `Icons.*`，项目未打包 Material Icons 字体，会渲染成方块。
Widget buildMarkdownCodeBlock(
  BuildContext context,
  String name,
  String code,
  bool closed,
) {
  return MarkdownCodeBlock(name: name, code: code);
}

class MarkdownCodeBlock extends StatelessWidget {
  const MarkdownCodeBlock({super.key, required this.name, required this.code});

  /// 代码块语言标记（```dart 中的 dart），可为空。
  final String name;
  final String code;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final label = name.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: RevericSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.lg,
              RevericSpacing.xs,
              RevericSpacing.xs,
              0,
            ),
            child: Row(
              children: [
                RevericIcon(
                  RevericIcons.terminal_rounded,
                  size: 14,
                  color: colors.textMuted,
                ),
                const SizedBox(width: RevericSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ),
                CopyIconButton(text: code),
              ],
            ),
          ),
          // 源码保持 LTR 与横向滚动，不随 Markdown 段落折行。
          Directionality(
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.lg,
                RevericSpacing.xxs,
                RevericSpacing.lg,
                RevericSpacing.lg,
              ),
              child: Text(
                code,
                style: typo.mono.copyWith(color: colors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
