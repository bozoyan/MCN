// 职责: 地图工作台数据模型 — NovelMap.settings 的类型化读写与生成管线的疆域/地点候选
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/maps_service.dart
//   lib/shared/services/generate_map_orchestrator.dart
// 遵循的 Rules:
//   .agents/rules/json.md
import '../database/novel_content_database.dart';

/// NovelMap.settings 中地图工作台相关字段的类型化视图。
///
/// settings 是 JSON 存储列，仅承载地图成品元数据；解析时容忍缺字段，
/// 写回时保留未知键。
class MapStudioSettings {
  const MapStudioSettings({
    this.version = 0,
    this.image,
    this.canvasWidth,
    this.canvasHeight,
    this.style,
    this.model,
    this.generatedAt,
    this.unmatchedLocationIds = const [],
    this.extra = const {},
  });

  /// 成图版本，0 表示这张地图还没画。
  final int version;

  /// 地图文件在 app 容器内的相对路径，如 `images/maps/{mapId}/map-v3.webp`。
  final String? image;

  /// 地图像素尺寸（坐标归一化的换算基准）。
  final int? canvasWidth;
  final int? canvasHeight;

  final String? style;
  final String? model;
  final String? generatedAt;

  /// 最新一次识别中「本图不含」的地点 id（不硬删旧坐标，仅展示层忽略）。
  final List<String> unmatchedLocationIds;

  /// settings 里本功能不认识的键，写回时原样保留。
  final Map<String, dynamic> extra;

  bool get hasImage => image != null && image!.isNotEmpty;

  static MapStudioSettings fromMap(Map<String, dynamic>? map) {
    if (map == null) return const MapStudioSettings();
    final knownKeys = {
      'studioVersion',
      'image',
      'canvasWidth',
      'canvasHeight',
      'style',
      'model',
      'generatedAt',
      'unmatchedLocationIds',
    };
    final extra = <String, dynamic>{};
    map.forEach((key, value) {
      if (!knownKeys.contains(key)) extra[key] = value;
    });
    return MapStudioSettings(
      version: map['studioVersion'] is int ? map['studioVersion'] as int : 0,
      image: map['image'] is String ? map['image'] as String : null,
      canvasWidth: map['canvasWidth'] is int ? map['canvasWidth'] as int : null,
      canvasHeight: map['canvasHeight'] is int
          ? map['canvasHeight'] as int
          : null,
      style: map['style'] is String ? map['style'] as String : null,
      model: map['model'] is String ? map['model'] as String : null,
      generatedAt: map['generatedAt'] is String
          ? map['generatedAt'] as String
          : null,
      unmatchedLocationIds:
          (map['unmatchedLocationIds'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'studioVersion': version,
    if (image != null) 'image': image,
    if (canvasWidth != null) 'canvasWidth': canvasWidth,
    if (canvasHeight != null) 'canvasHeight': canvasHeight,
    if (style != null) 'style': style,
    if (model != null) 'model': model,
    if (generatedAt != null) 'generatedAt': generatedAt,
    'unmatchedLocationIds': unmatchedLocationIds,
  };
}

/// 疆域规格：本次生成把哪个地点当作疆域（来自地点树按级别推导，非 AI 决定）。
class MapRegionSpec {
  const MapRegionSpec({required this.locationId, required this.name});

  final String locationId;
  final String name;
}

/// 疆域地点类型：continent / country 级别的地点自动视为疆域。
const mapRegionLocationTypes = <String>{
  locationTypeContinent,
  locationTypeCountry,
};

/// 从地点树推导地图 prompt 的疆域清单与地名识别候选。
///
/// subtree 取 [rootId] 自身及其全部子孙；rootId 为空时退化为整棵地点树。
/// 疆域用于描述地图构图；识别候选包含疆域和普通地点，但不包含地图根地点。
(List<MapRegionSpec>, List<MapPlaceNameCandidate>) deriveMapRegionsAndPlaces({
  required List<Location> locations,
  required String? rootId,
}) {
  final byId = {for (final location in locations) location.id: location};
  final childrenByParent = <String, List<Location>>{};
  for (final location in locations) {
    final parent = location.parentId;
    if (parent == null) continue;
    childrenByParent.putIfAbsent(parent, () => []).add(location);
  }

  final subtree = <Location>[];
  void collect(String id) {
    final location = byId[id];
    if (location == null) return;
    subtree.add(location);
    for (final child in childrenByParent[id] ?? const <Location>[]) {
      collect(child.id);
    }
  }

  if (rootId != null) {
    collect(rootId);
  } else {
    subtree.addAll(locations);
  }

  final regions = [
    for (final location in subtree)
      if (mapRegionLocationTypes.contains(location.type))
        MapRegionSpec(locationId: location.id, name: location.name),
  ];
  final places = [
    for (final location in subtree)
      if (location.id != rootId)
        MapPlaceNameCandidate(locationId: location.id, name: location.name),
  ];
  return (regions, places);
}

/// 地名回读候选：一个待定位的地点。
class MapPlaceNameCandidate {
  const MapPlaceNameCandidate({required this.locationId, required this.name});

  final String locationId;
  final String name;
}

/// 地名回读的单个匹配结果。x/y 是文字框中心在成图上的归一化坐标。
class MapPlaceMatch {
  const MapPlaceMatch({
    required this.locationId,
    required this.requestedName,
    required this.matchedName,
    required this.x,
    required this.y,
  });

  final String locationId;
  final String requestedName;
  final String matchedName;
  final double x;
  final double y;
}

/// 一次地名回读的整体结果。
class MapPlaceReadResult {
  const MapPlaceReadResult({required this.matches, required this.unresolved});

  final List<MapPlaceMatch> matches;
  final List<String> unresolved;
}

/// 编辑两个地名字符串的莱文斯坦距离，用于地名匹配的错字兜底。
int mapNameEditDistance(String a, String b) {
  final s = a.replaceAll(RegExp(r'\s'), '');
  final t = b.replaceAll(RegExp(r'\s'), '');
  if (s == t) return 0;
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;
  var previous = List<int>.generate(t.length + 1, (i) => i);
  for (var i = 0; i < s.length; i++) {
    final current = [i + 1];
    for (var j = 0; j < t.length; j++) {
      final substitution = previous[j] + (s[i] == t[j] ? 0 : 1);
      current.add(
        [
          previous[j + 1] + 1,
          current[j] + 1,
          substitution,
        ].reduce((x, y) => x < y ? x : y),
      );
    }
    previous = current;
  }
  return previous[t.length];
}
