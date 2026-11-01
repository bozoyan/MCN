// 职责: 移动端技能目录 tab(官方 / 广场)共用的横向类别筛选条,首项为「全部」,
//   消除 official_tab 与 marketplace_tab 的重复实现。
// 关联文件:
//   lib/mobile/features/agent_skills/official_tab.dart
//   lib/mobile/features/agent_skills/marketplace_tab.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../../shared/components/reveric_filter_chip.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

/// 顶部类别筛选条:水平滚动 chip 行,首项为「全部」。
class SkillCategoryFilterBar extends StatelessWidget {
  const SkillCategoryFilterBar({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final allCategories = <String>{...categories}.toList(growable: false);
    return SizedBox(
      height: RevericSizes.touchTargetSize + RevericSpacing.x2l,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.x4l,
          vertical: RevericSpacing.sm,
        ),
        children: [
          RevericFilterChip(
            label: context.t(LocaleKeys.agentSkillCategoryAll),
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          const SizedBox(width: RevericSpacing.xs),
          for (final c in allCategories) ...[
            RevericFilterChip(
              label: c,
              selected: selected == c,
              onTap: () => onSelect(c),
            ),
            const SizedBox(width: RevericSpacing.xs),
          ],
        ],
      ),
    );
  }
}
