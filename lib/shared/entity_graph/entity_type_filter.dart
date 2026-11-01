// 职责: 实体关系图实体类型多选筛选 — 工具栏下拉多选控件。
// 关联文件:
//   lib/shared/entity_graph/data.dart
//   lib/shared/entity_graph/labels.dart
//   lib/desktop/widgets/entity_graph_panel.dart
//   lib/mobile/widgets/entity_graph_panel.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
//   assets/translations/en/entity.json
//   assets/translations/zh-CN/entity.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';

import '../components/reveric_checkbox.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';
import 'data.dart';
import 'labels.dart';

/// 关系图实体类型筛选按钮的摘要文案。
String formatEntityGraphEntityTypeFilterLabel(
  BuildContext context,
  Set<String> selectedTypes,
) {
  final selected = kEntityGraphFilterableEntityTypes
      .where(selectedTypes.contains)
      .toList();
  if (selected.isEmpty) {
    return context.t(LocaleKeys.entityGraphFilterAll);
  }
  if (selected.length == kEntityGraphFilterableEntityTypes.length) {
    return context.t(LocaleKeys.entityGraphFilterAll);
  }
  return selected
      .map((type) => localizeEntityNodeTypeName(context, type))
      .join('、');
}

/// 关系图工具栏实体类型多选筛选。
class EntityGraphEntityTypeFilter extends StatelessWidget {
  const EntityGraphEntityTypeFilter({
    super.key,
    required this.selectedTypes,
    required this.onChanged,
    this.usePillStyle = false,
  });

  final Set<String> selectedTypes;
  final ValueChanged<Set<String>> onChanged;
  final bool usePillStyle;

  void _toggleType(String entityType) {
    final next = Set<String>.from(selectedTypes);
    if (next.contains(entityType)) {
      if (next.length <= 1) {
        return;
      }
      next.remove(entityType);
    } else {
      next.add(entityType);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final summary = formatEntityGraphEntityTypeFilterLabel(
      context,
      selectedTypes,
    );
    final tooltip = context.t(LocaleKeys.entityGraphFilterEntityTypes);

    return Tooltip(
      message: tooltip,
      child: MenuAnchor(
        style: MenuStyle(
          visualDensity: VisualDensity.compact,
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(vertical: RevericSpacing.xxs),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(RevericRadius.medium),
              side: BorderSide(color: colors.borderSubtle),
            ),
          ),
        ),
        menuChildren: [
          for (final entityType in kEntityGraphFilterableEntityTypes)
            _EntityTypeFilterMenuRow(
              label: localizeEntityNodeTypeName(context, entityType),
              selected: selectedTypes.contains(entityType),
              colors: colors,
              typo: typo,
              onTap: () => _toggleType(entityType),
            ),
        ],
        builder: (context, controller, child) {
          final borderRadius = usePillStyle
              ? BorderRadius.circular(RevericRadius.pill)
              : BorderRadius.circular(RevericRadius.medium);
          return InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            borderRadius: borderRadius,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: usePillStyle
                    ? RevericSpacing.md
                    : RevericSpacing.sm,
                vertical: usePillStyle
                    ? RevericSpacing.xs
                    : RevericSpacing.xxs,
              ),
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    summary,
                    style: typo.uiSmall.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(width: RevericSpacing.xxs),
                  RevericIcon(
                    RevericIcons.expand_more,
                    size: 12,
                    color: colors.textSubtle,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EntityTypeFilterMenuRow extends StatelessWidget {
  const _EntityTypeFilterMenuRow({
    required this.label,
    required this.selected,
    required this.colors,
    required this.typo,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final RevericColors colors;
  final RevericTypography typo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.md,
          vertical: RevericSpacing.xxs,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: RevericCheckbox(
                value: selected,
                onChanged: (_) => onTap(),
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: typo.uiSmall.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
