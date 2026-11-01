// 职责: 地点类型的可选项、显示名，以及地点类型 → 地图类型的映射
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/desktop/features/map/map_create_dialogs.dart
//   lib/desktop/features/map/map_cartographer_panel.dart
//   lib/desktop/features/map/map_studio_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
// 遵循的 Rules:
//   .agents/rules/i18n.md
import 'package:flutter/widgets.dart';

import '../../database/novel_content_database.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';

/// 新建地点可选类型。与地点树/检查器的类型图标保持同一子集。
const mapLocationTypeOptions = <String>[
  locationTypeWorld,
  locationTypeContinent,
  locationTypeCountry,
  locationTypeRegion,
  locationTypeMountain,
  locationTypePlain,
  locationTypeForest,
  locationTypeRiver,
  locationTypeLake,
  locationTypeSea,
  locationTypeIsland,
  locationTypeCity,
  locationTypeVillage,
  locationTypeBuilding,
  locationTypeLandmark,
];

String mapLocationTypeLabel(String type, BuildContext context) {
  return switch (type) {
    locationTypeWorld => context.t(LocaleKeys.mapEditorTypeWorld),
    locationTypeContinent => context.t(LocaleKeys.mapEditorTypeContinent),
    locationTypeCountry => context.t(LocaleKeys.mapEditorTypeCountry),
    locationTypeRegion => context.t(LocaleKeys.mapEditorTypeRegion),
    locationTypeMountain => context.t(LocaleKeys.mapEditorTypeMountain),
    locationTypePlain => context.t(LocaleKeys.mapEditorTypePlain),
    locationTypeForest => context.t(LocaleKeys.mapEditorTypeForest),
    locationTypeRiver => context.t(LocaleKeys.mapEditorTypeRiver),
    locationTypeLake => context.t(LocaleKeys.mapEditorTypeLake),
    locationTypeSea => context.t(LocaleKeys.mapEditorTypeSea),
    locationTypeIsland => context.t(LocaleKeys.mapEditorTypeIsland),
    locationTypeCity => context.t(LocaleKeys.mapEditorTypeCity),
    locationTypeVillage => context.t(LocaleKeys.mapEditorTypeVillage),
    locationTypeBuilding => context.t(LocaleKeys.mapEditorTypeBuilding),
    locationTypeLandmark => context.t(LocaleKeys.mapEditorTypeLandmark),
    _ => context.t(LocaleKeys.mapEditorTypeGeneric),
  };
}

/// 地点类型 → 建议的地图类型。
String suggestMapType(String? locationType) => switch (locationType) {
  locationTypeWorld || locationTypeContinent => mapTypeWorld,
  locationTypeCountry ||
  locationTypeRegion ||
  locationTypeMountain ||
  locationTypePlain ||
  locationTypeForest ||
  locationTypeRiver ||
  locationTypeLake ||
  locationTypeSea ||
  locationTypeIsland => mapTypeRegion,
  _ => mapTypeCity,
};

/// 地点自己的地图类型：顶层地点是世界图，子地点按地点类型推导。
String mapTypeForOwner(Location owner) =>
    owner.parentId == null ? mapTypeWorld : suggestMapType(owner.type);
