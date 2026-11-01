// 职责: 制图师地点层级导航 — 提供父级返回与直接 children 逐层钻取入口。
// 关联文件:
//   lib/desktop/features/map/map_cartographer_panel.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../../database/novel_content_database.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

class MapLocationParentLink extends StatelessWidget {
  const MapLocationParentLink({
    super.key,
    required this.parent,
    required this.onSelected,
  });

  final Location parent;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('map_location_parent_${parent.id}'),
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        onTap: () => onSelected(parent.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RevericSizes.buttonHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.sm,
              vertical: RevericSpacing.sm,
            ),
            child: Row(
              children: [
                RevericIcon(
                  RevericIcons.chevron_left,
                  size: 13,
                  color: colors.textMuted,
                ),
                const SizedBox(width: RevericSpacing.xs),
                Expanded(
                  child: Text(
                    parent.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSmall.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MapLocationChildren extends StatelessWidget {
  const MapLocationChildren({
    super.key,
    required this.parentId,
    required this.locations,
    required this.onSelected,
  });

  final String parentId;
  final List<Location> locations;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final location in locations)
        if (location.parentId == parentId) location,
    ]..sort(_compareLocations);
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    final childCounts = <String, int>{};
    for (final location in locations) {
      final parent = location.parentId;
      if (parent != null) {
        childCounts.update(parent, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      key: const ValueKey('map_location_children_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: RevericSpacing.x2l),
        Row(
          children: [
            Expanded(
              child: Text(
                context.t(LocaleKeys.mapEditorChildLocations),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ),
            Text(
              '${children.length}',
              style: typo.uiTiny.copyWith(color: colors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(color: colors.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                _ChildLocationRow(
                  location: children[index],
                  childCount: childCounts[children[index].id] ?? 0,
                  onTap: () => onSelected(children[index].id),
                ),
                if (index < children.length - 1)
                  Divider(
                    height: RevericSizes.dividerThickness,
                    color: colors.borderSubtle,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

int _compareLocations(Location left, Location right) {
  final order = left.sortOrder.compareTo(right.sortOrder);
  if (order != 0) {
    return order;
  }
  return left.name.compareTo(right.name);
}

class _ChildLocationRow extends StatelessWidget {
  const _ChildLocationRow({
    required this.location,
    required this.childCount,
    required this.onTap,
  });

  final Location location;
  final int childCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('map_location_child_${location.id}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RevericSizes.buttonHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.md,
              vertical: RevericSpacing.sm,
            ),
            child: Row(
              children: [
                RevericIcon(
                  _iconForType(location.type),
                  size: 15,
                  color: colors.textMuted,
                ),
                const SizedBox(width: RevericSpacing.sm),
                Expanded(
                  child: Text(
                    location.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSmall.copyWith(color: colors.textPrimary),
                  ),
                ),
                if (childCount > 0) ...[
                  Text(
                    '$childCount',
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(width: RevericSpacing.xs),
                ],
                RevericIcon(
                  RevericIcons.chevron_right,
                  size: 13,
                  color: colors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _iconForType(String type) {
  return switch (type) {
    locationTypeWorld || locationTypeContinent => RevericIcons.public_outlined,
    locationTypeCountry => RevericIcons.rule_outlined,
    locationTypeRegion ||
    locationTypeMountain ||
    locationTypePlain => RevericIcons.landscape,
    locationTypeForest => RevericIcons.eco_outlined,
    locationTypeRiver ||
    locationTypeLake ||
    locationTypeSea ||
    locationTypeIsland => RevericIcons.water,
    locationTypeCity || locationTypeDistrict => RevericIcons.location_city,
    locationTypeVillage => RevericIcons.home,
    locationTypeBuilding ||
    locationTypeRoom => RevericIcons.temple_buddhist_outlined,
    _ => RevericIcons.location_on,
  };
}
