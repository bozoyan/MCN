// 职责: 实体关系图关系分类图例 — 横向展示各分类色条与名称。
// 关联文件:
//   lib/shared/entity_graph/colors.dart
//   lib/shared/entity_graph/labels.dart
//   lib/shared/entity_graph/data.dart
//   lib/shared/entity_graph/constants.dart
//   lib/desktop/widgets/entity_graph_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';
import 'colors.dart';
import 'labels.dart';

/// 图例中实际展示的分类：排除 `other`、只保留出现过的，按出现次数倒序。
List<RelationCategory> entityGraphLegendCategories(
  Map<RelationCategory, int> counts,
) {
  return RelationCategory.values
      .where((c) => c != RelationCategory.other && (counts[c] ?? 0) > 0)
      .toList()
    ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
}

/// 关系分类图例条 — 画布底部展示所有出现的分类色条与名称。
class EntityGraphLegend extends StatelessWidget {
  const EntityGraphLegend({super.key, required this.counts});

  final Map<RelationCategory, int> counts;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final entries = entityGraphLegendCategories(counts);

    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x2l,
        vertical: RevericSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            context.t(LocaleKeys.entityGraphLegendTitle),
            style: typo.uiTinySemibold.copyWith(
              color: colors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: RevericSpacing.md),
          Expanded(
            child: Wrap(
              spacing: RevericSpacing.md,
              runSpacing: RevericSpacing.xs,
              children: [
                for (final category in entries)
                  _LegendItem(
                    label: localizeRelationCategoryLabel(context, category),
                    color: relationCategoryColor(category),
                    colors: colors,
                    typo: typo,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.label,
    required this.color,
    required this.colors,
    required this.typo,
  });

  final String label;
  final Color color;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: RevericSpacing.xxs),
        Text(label, style: typo.uiTiny.copyWith(color: colors.textSecondary)),
      ],
    );
  }
}
