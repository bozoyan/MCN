// 职责: 在 MCP 设置中展示需要用户处理的警示提示。
// 关联文件:
//   lib/shared/widgets/settings/mcp/section.dart
//   lib/shared/widgets/settings/mcp/server_editor.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';
import '../../../theme/theme.dart';

class McpNotice extends StatelessWidget {
  const McpNotice({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: RevericSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.warningBg,
        borderRadius: BorderRadius.circular(RevericRadius.large),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RevericIcon(
            RevericIcons.warning,
            size: RevericSizes.buttonIconSize,
            color: colors.warningText,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: typo.uiSmall.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
