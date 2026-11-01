// 职责: 统一列表筛选项的可选计数、选中与禁用状态及平台触控区域。
// 关联文件:
//   lib/shared/entity_graph/entity_list_section.dart
//   lib/desktop/widgets/sidebar/sections.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// 列表筛选 chip，支持无计数标签；选中态沿用 accent 实色。
class RevericFilterChip extends StatelessWidget {
  const RevericFilterChip({
    super.key,
    required this.label,
    this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final mobile = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    return FilterChip(
      label: Text(count == null ? label : '$label $count'),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      showCheckmark: false,
      labelStyle: typo.uiTiny.copyWith(
        color: onTap == null
            ? colors.textSubtle
            : selected
            ? colors.onAccent
            : colors.textMuted,
      ),
      backgroundColor: colors.surface,
      selectedColor: colors.accent,
      disabledColor: colors.surfaceDim,
      side: BorderSide(
        color: selected && onTap != null ? colors.accent : colors.borderSubtle,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RevericRadius.pill),
      ),
      padding: const EdgeInsets.symmetric(vertical: RevericSpacing.xxs),
      labelPadding: const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
      materialTapTargetSize: mobile
          ? MaterialTapTargetSize.padded
          : MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
  }
}
