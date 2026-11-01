// 职责: 绘制小说编辑页侧栏折叠时避开标题栏的竖向分隔线。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/widgets/desktop_window_frame.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';
import '../desktop_window_frame.dart';

class NovelEditorSidebarDivider extends StatelessWidget {
  const NovelEditorSidebarDivider({super.key, required this.skipTopInset});

  final bool skipTopInset;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return Container(
      width: RevericSizes.dividerThickness,
      color: Colors.transparent,
      child: Column(
        children: [
          SizedBox(
            height: skipTopInset ? DesktopWindowFrame.titleBarHeight : 0,
          ),
          Expanded(child: ColoredBox(color: colors.border)),
        ],
      ),
    );
  }
}
