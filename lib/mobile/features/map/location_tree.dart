// 职责: 移动端地点树 — 地点卡片逐层展开、左滑删除，行尾可挂额外动作；地点类型的图标与显示名。
// 关联文件:
//   lib/mobile/features/map/places_sheet.dart
//   lib/mobile/features/map/place_card.dart
//   lib/mobile/widgets/section_scaffold.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/location.json
//   assets/translations/zh-CN/location.json
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import '../../widgets/section_scaffold.dart';

class MobileLocationTreeItem extends StatelessWidget {
  const MobileLocationTreeItem({
    super.key,
    required this.location,
    required this.allLocations,
    required this.expandedIds,
    required this.depth,
    required this.onTap,
    required this.onDelete,
    this.trailingBuilder,
  });

  final Location location;
  final List<Location> allLocations;
  final ValueNotifier<Set<String>> expandedIds;
  final int depth;
  final ValueChanged<Location> onTap;
  final ValueChanged<Location> onDelete;

  /// 行尾额外动作（如「进入地图」），放在展开箭头之前；null 表示没有。
  final Widget? Function(Location location)? trailingBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final children =
        allLocations.where((l) => l.parentId == location.id).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final hasChildren = children.isNotEmpty;
    final isExpanded = expandedIds.value.contains(location.id);
    final trailing = trailingBuilder?.call(location);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            bottom: depth == 0 ? RevericSpacing.sm : RevericSpacing.sm,
          ),
          child: MobileSectionCard(
            cardKey: ValueKey('mobile_maps_tree_item_${location.id}'),
            onTap: () => onTap(location),
            onDelete: () => onDelete(location),
            deleteLabel: context.t(LocaleKeys.commonDelete),
            padding: EdgeInsets.only(
              left: RevericSpacing.lg + depth * RevericSpacing.x3l,
              right: RevericSpacing.lg,
              top: RevericSpacing.lg,
              bottom: RevericSpacing.lg,
            ),
            child: Row(
              children: [
                MobileSectionIconBox(
                  icon: mobileLocationTypeIcon(location.type),
                  size: 40,
                  iconSize: 18,
                  tint: colors.accent.withValues(alpha: 0.14),
                ),
                const SizedBox(width: RevericSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiSemibold.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hasChildren
                            ? '${mobileLocationTypeLabel(location.type, context)} · ${context.t(LocaleKeys.mobileEditorSubLocationCount, namedArgs: {'count': '${children.length}'})}'
                            : mobileLocationTypeLabel(location.type, context),
                        style: typo.uiTiny.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                ?trailing,
                if (hasChildren)
                  InkWell(
                    key: ValueKey('mobile_maps_tree_expand_${location.id}'),
                    onTap: () {
                      final next = Set<String>.from(expandedIds.value);
                      if (isExpanded) {
                        next.remove(location.id);
                      } else {
                        next.add(location.id);
                      }
                      expandedIds.value = next;
                    },
                    borderRadius: BorderRadius.circular(RevericRadius.small),
                    child: Padding(
                      padding: const EdgeInsets.all(RevericSpacing.xs),
                      child: RevericIcon(
                        isExpanded
                            ? RevericIcons.expand_more
                            : RevericIcons.chevron_right,
                        size: 18,
                        color: colors.textSubtle,
                      ),
                    ),
                  )
                else
                  const MobileSectionTrailingChevron(),
              ],
            ),
          ),
        ),
        if (hasChildren && isExpanded)
          for (final child in children)
            MobileLocationTreeItem(
              location: child,
              allLocations: allLocations,
              expandedIds: expandedIds,
              depth: depth + 1,
              onTap: onTap,
              onDelete: onDelete,
              trailingBuilder: trailingBuilder,
            ),
      ],
    );
  }
}

String mobileLocationTypeIcon(String type) {
  switch (type) {
    case locationTypeWorld:
    case locationTypeContinent:
    case locationTypeCountry:
      return RevericIcons.public;
    case locationTypeRegion:
    case locationTypeMountain:
    case locationTypePlain:
    case locationTypeForest:
    case locationTypeRiver:
    case locationTypeLake:
    case locationTypeSea:
    case locationTypeIsland:
      return RevericIcons.terrain;
    case locationTypeCity:
    case locationTypeDistrict:
    case locationTypeVillage:
      return RevericIcons.location_city;
    case locationTypeLandmark:
    case locationTypeBuilding:
    case locationTypeRoom:
      return RevericIcons.place;
    default:
      return RevericIcons.circle_outlined;
  }
}

String mobileLocationTypeLabel(String type, BuildContext context) {
  switch (type) {
    case locationTypeGeneric:
      return context.t(LocaleKeys.locationTypeGeneric);
    case locationTypeWorld:
      return context.t(LocaleKeys.locationTypeWorld);
    case locationTypeContinent:
      return context.t(LocaleKeys.locationTypeContinent);
    case locationTypeCountry:
      return context.t(LocaleKeys.locationTypeCountry);
    case locationTypeRegion:
      return context.t(LocaleKeys.locationTypeRegion);
    case locationTypeMountain:
      return context.t(LocaleKeys.locationTypeMountain);
    case locationTypePlain:
      return context.t(LocaleKeys.locationTypePlain);
    case locationTypeForest:
      return context.t(LocaleKeys.locationTypeForest);
    case locationTypeRiver:
      return context.t(LocaleKeys.locationTypeRiver);
    case locationTypeLake:
      return context.t(LocaleKeys.locationTypeLake);
    case locationTypeSea:
      return context.t(LocaleKeys.locationTypeSea);
    case locationTypeIsland:
      return context.t(LocaleKeys.locationTypeIsland);
    case locationTypeCity:
      return context.t(LocaleKeys.locationTypeCity);
    case locationTypeDistrict:
      return context.t(LocaleKeys.locationTypeDistrict);
    case locationTypeVillage:
      return context.t(LocaleKeys.locationTypeVillage);
    case locationTypeBuilding:
      return context.t(LocaleKeys.locationTypeBuilding);
    case locationTypeRoom:
      return context.t(LocaleKeys.locationTypeRoom);
    case locationTypeLandmark:
      return context.t(LocaleKeys.locationTypeLandmark);
    case locationTypeCustom:
      return context.t(LocaleKeys.locationTypeCustom);
    case locationTypeNatural:
      return context.t(LocaleKeys.locationTypeNatural);
    default:
      return type;
  }
}
