// 职责: 展示统一的只读状态徽标，保留完整文案并适应受限宽度。
// 关联文件:
//   lib/shared/theme/theme.dart
//   lib/mobile/widgets/overview_panel.dart
//   lib/shared/widgets/settings/ai_providers_section.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// 调用方将业务状态映射为文案和主题语义色，徽标不认识业务状态。
class RevericBadge extends StatelessWidget {
  const RevericBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.sm,
          vertical: RevericSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(RevericRadius.small),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: typo.uiTinySemibold.copyWith(color: color),
        ),
      ),
    );
  }
}
