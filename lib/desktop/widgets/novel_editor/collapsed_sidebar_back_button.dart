// 职责: 提供小说编辑页侧栏折叠时返回书库的浮动入口。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';

class NovelEditorCollapsedSidebarBackButton extends StatelessWidget {
  const NovelEditorCollapsedSidebarBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return Center(
      child: Tooltip(
        message: MaterialLocalizations.of(context).backButtonTooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RevericRadius.small),
          hoverColor: colors.hover,
          child: Padding(
            padding: const EdgeInsets.all(RevericSpacing.xs),
            child: RevericIcon(
              RevericIcons.chevron_left,
              size: 20,
              color: colors.accent,
            ),
          ),
        ),
      ),
    );
  }
}
