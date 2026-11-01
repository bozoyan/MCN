// 职责: 地图工作台在一个 world 内的导航推导 — 当前画布属于哪个地点、面包屑、
//       已有地图的地点、上层参考图，以及选中地点时画布该切到哪张图。
// 关联文件:
//   lib/desktop/features/map/map_studio_page.dart
//   lib/mobile/features/map/studio_page.dart
//   lib/shared/services/ai/chat_turn_runner.dart
//   lib/shared/models/map_studio_models.dart
//   lib/shared/database/novel_content_database.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import '../database/novel_content_database.dart';
import 'map_studio_models.dart';

class MapStudioNav {
  const MapStudioNav({
    required this.world,
    required this.owner,
    required this.currentMap,
    required this.trail,
    required this.mappedLocationIds,
    required this.parentMap,
    required this.locationById,
  });

  /// 从 [requestedOwnerId] 推导导航状态；它不在 [world] 内（被删或移走）时回到 world。
  factory MapStudioNav.resolve({
    required Location world,
    required List<NovelMap> maps,
    required List<Location> locations,
    required String? requestedOwnerId,
  }) {
    final locationById = {
      for (final location in locations) location.id: location,
    };
    final mapByOwner = <String, NovelMap>{};
    for (final map in maps) {
      final owner = map.locationId;
      if (owner != null && locationById.containsKey(owner)) {
        mapByOwner.putIfAbsent(owner, () => map);
      }
    }

    List<Location> ancestorsOf(String id) =>
        mapLocationAncestors(id, locationById);

    final requested = locationById[requestedOwnerId];
    final ownerInWorld =
        requested != null &&
        (requested.id == world.id ||
            ancestorsOf(requested.id).any((item) => item.id == world.id));
    final owner = ownerInWorld ? requested : world;

    final worldIds = {
      world.id,
      for (final location in locations)
        if (ancestorsOf(location.id).any((item) => item.id == world.id))
          location.id,
    };
    final mappedLocationIds = {
      for (final id in mapByOwner.keys)
        if (worldIds.contains(id)) id,
    };

    final trail = [
      for (final item in ancestorsOf(owner.id).reversed)
        if (item.id == world.id || mappedLocationIds.contains(item.id)) item,
      owner,
    ];
    final parentMap = ancestorsOf(owner.id)
        .map((item) => mapByOwner[item.id])
        .where(
          (map) =>
              map != null && MapStudioSettings.fromMap(map.settings).hasImage,
        )
        .firstOrNull;

    return MapStudioNav(
      world: world,
      owner: owner,
      currentMap: mapByOwner[owner.id],
      trail: trail,
      mappedLocationIds: mappedLocationIds,
      parentMap: parentMap,
      locationById: locationById,
    );
  }

  final Location world;

  /// 当前画布这张图所属的地点；可能还没有 Map 记录（待生成）。
  final Location owner;

  /// [owner] 的 Map 记录；null 表示待生成。
  final NovelMap? currentMap;

  /// 面包屑：从 world 到当前地图所属地点，只含有图的层级。
  final List<Location> trail;

  /// 当前 world 内已经有 Map 记录的地点。
  final Set<String> mappedLocationIds;

  /// 最近一张已经画好的上层地图：子地图的默认画风与可选的画风参考图。
  final NovelMap? parentMap;
  final Map<String, Location> locationById;

  /// 选中 [locationId] 时画布该显示谁的图：最近一个有图的祖先。
  /// 当前这张图即使还在待生成，也算「有图」，免得点子地点把人弹回上层。
  String ownerForSelection(String locationId) {
    final visible = {...mappedLocationIds, owner.id};
    final nearest = mapLocationAncestors(
      locationId,
      locationById,
    ).where((item) => visible.contains(item.id)).firstOrNull;
    return nearest?.id ?? world.id;
  }

  /// [parentMap] 所属地点的名字；地点被删时退回地图自己的名字。
  String? get parentMapName {
    final map = parentMap;
    if (map == null) {
      return null;
    }
    return locationById[map.locationId]?.name ?? map.name;
  }
}

/// 从近到远的祖先链；遇到断链或环即停。
List<Location> mapLocationAncestors(
  String id,
  Map<String, Location> locationById,
) {
  final chain = <Location>[];
  final visited = <String>{id};
  var current = locationById[id]?.parentId;
  while (current != null && visited.add(current)) {
    final location = locationById[current];
    if (location == null) break;
    chain.add(location);
    current = location.parentId;
  }
  return chain;
}

/// [locationId] 所在树的顶层 world（它自己就是 world 时返回自己）；
/// 地点不存在、父链断开或树根不是 world 时返回 null。
Location? mapTopLevelWorldOf(
  String locationId,
  Map<String, Location> locationById,
) {
  final target = locationById[locationId];
  if (target == null) {
    return null;
  }
  final root = target.parentId == null
      ? target
      : mapLocationAncestors(locationId, locationById).lastOrNull;
  if (root == null || root.parentId != null || root.type != locationTypeWorld) {
    return null;
  }
  return root;
}

/// [selection] 所属的顶层 world；selection 可能是子地点（如 Agent 为子地图投递草稿）。
Location? resolveMapWorld(List<Location> locations, String? selection) {
  final worlds = mapWorldsOf(locations);
  final locationById = {
    for (final location in locations) location.id: location,
  };
  var requested = locationById[selection];
  final visited = <String>{};
  while (requested?.parentId != null && visited.add(requested!.id)) {
    requested = locationById[requested.parentId];
  }
  return worlds.where((world) => world.id == requested?.id).firstOrNull ??
      worlds.firstOrNull;
}

/// 顶层 world 列表，保持 [locations] 的原有顺序。
List<Location> mapWorldsOf(List<Location> locations) => [
  for (final location in locations)
    if (location.type == locationTypeWorld && location.parentId == null)
      location,
];
