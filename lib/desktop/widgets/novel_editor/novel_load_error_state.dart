// 职责: 展示小说编辑页加载失败的错误信息。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';

class NovelEditorLoadErrorState extends StatelessWidget {
  const NovelEditorLoadErrorState({
    super.key,
    required this.message,
    required this.detail,
  });

  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x6l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.error_outline,
              color: colors.warningText,
              size: 28,
            ),
            const SizedBox(height: RevericSpacing.lg),
            Text(
              message,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.xs),
            Text(
              detail,
              style: typo.uiSmall.copyWith(color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
