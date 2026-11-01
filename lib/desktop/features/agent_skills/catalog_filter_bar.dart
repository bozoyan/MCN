// 职责: 技能过滤栏 —— 技能库 / official / market tab 复用的分类筛选 + 搜索栏,
//   分类 chip 横向可滚动(不换行),搜索框复用 RevericSearchField(pill + 清除按钮 + debounce)。
// 关联文件:
//   lib/desktop/features/agent_skills/setup_panel.dart
//   lib/desktop/features/agent_skills/official_catalog_tab.dart
//   lib/desktop/features/agent_skills/marketplace_catalog_tab.dart
//   lib/shared/components/reveric_search_field.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md
//   .agents/rules/search-debounce.md
//   .agents/rules/code-style.md
import 'package:flutter/material.dart';

import '../../../shared/components/reveric_search_field.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

/// 技能库 / official / market tab 复用的过滤栏。
///
/// [categories] 由调用方从当前列表数据去重传入（不合并本地全量档）。
/// 分类选中值 null 代表「全部」。分类 chip 横向可滚动,避免过多时换行。
/// 搜索框复用 [RevericSearchField],由调用方持有 [searchController](通常配合
/// useDebouncedSearch)。
class CatalogFilterBar extends StatelessWidget {
  const CatalogFilterBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategory,
    required this.searchController,
    this.trailing,
  });

  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onCategory;
  final TextEditingController searchController;

  /// 搜索框右侧的附加操作(如广场刷新);null 时不占位。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: RevericSpacing.x5l,
        vertical: RevericSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CatalogFilterChip(
                    label: context.t(LocaleKeys.agentSkillCategoryAll),
                    selected: selectedCategory == null,
                    onTap: () => onCategory(null),
                  ),
                  for (final c in categories) ...[
                    const SizedBox(width: RevericSpacing.xs),
                    _CatalogFilterChip(
                      label: c,
                      selected: selectedCategory == c,
                      onTap: () => onCategory(c),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: RevericSpacing.x2l),
          SizedBox(
            width: 240,
            child: RevericSearchField(
              controller: searchController,
              hint: context.t(LocaleKeys.agentSkillSearchPlaceholder),
              height: RevericSizes.buttonHeightSm,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: RevericSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _CatalogFilterChip extends StatelessWidget {
  const _CatalogFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      color: selected
          ? colors.accent.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(RevericRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RevericRadius.pill),
            border: Border.all(
              color: selected ? colors.accent : colors.borderInput,
            ),
          ),
          child: Text(
            label,
            style: typo.uiSmall.copyWith(
              color: selected ? colors.accent : colors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
