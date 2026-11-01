// 职责: 提供卡片层级的投影与描边 — 浅色无描边靠柔和投影浮起，深色投影不可见改用极淡描边。
// 关联文件:
//   lib/shared/theme/reveric_colors.dart
//   lib/shared/components/reveric_surfaces.dart
//   lib/shared/components/reveric_dialog.dart
//   designs/SYSTEM.md
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import 'reveric_colors.dart';

/// 卡片描边：浅色透明（靠投影分层），深色用 [RevericColors.borderSubtle]。
Color revericCardBorder(RevericColors colors) {
  return colors.isDark ? colors.borderSubtle : Colors.transparent;
}

/// 卡片投影：浅色为一层贴边细影 + 一层大而淡的扩散影；深色只留贴边细影。
List<BoxShadow> revericCardShadows(RevericColors colors) {
  if (colors.isDark) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.24),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
  }
  return [
    BoxShadow(
      color: colors.textPrimary.withValues(alpha: 0.04),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: colors.textPrimary.withValues(alpha: 0.06),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}
