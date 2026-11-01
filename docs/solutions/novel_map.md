# 小说地图设计方案

## 概述

为小说创作系统设计地图功能，支持创建多个地图，每个地图包含多个地点（Location），并提供地点间的空间关系管理和可视化编辑。设计重点在于数据模型支持 AI 直接生成完整地图结构。

## 一、需求分析

### 1.1 核心需求

| 需求 | 说明 |
|------|------|
| 多地图支持 | 一部小说可以有多个地图（如：世界地图、城市地图、建筑内部地图） |
| 地点管理 | 每个地图包含多个地点，地点有名称、描述、类型、层级关系 |
| 空间关系 | 地点间的位置关系（相邻、可达路径） |
| 实体关联 | 地点与角色、势力、章节等实体的关联（通过 EntityRelations） |
| 可视化编辑 | 地图的可视化展示与交互式编辑 |
| AI 生成 | AI 能直接输出完整地图结构（地点 + 位置 + 连接），原子导入 |

### 1.2 使用场景

- **世界观构建**：创建小说世界的地理结构
- **剧情规划**：在地图上标注章节发生地点
- **角色轨迹**：追踪角色的活动范围和移动路径
- **势力分布**：展示势力的控制区域和影响范围

---

## 二、数据模型设计

### 2.1 新增表：Locations

独立的地点实体表，不包含画布坐标（坐标属于 MapLocations）。层级关系通过 `parentId` 自引用实现。

```dart
class Locations extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get description => text().withDefault(const Constant(''))();

  TextColumn get type =>
      text().withDefault(const Constant(locationTypeGeneric))();

  TextColumn get parentId => text().nullable()();

  TextColumn get tags => text().withDefault(const Constant(''))();

  TextColumn get status =>
      text().withDefault(const Constant(locationStatusActive))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

设计说明：
- **无经纬度**：虚构小说不需要地理坐标系，位置完全由画布坐标 `(x, y)` 在 MapLocations 中定义
- **`parentId` 处理层级**：大陆 → 国家 → 城市 → 街区，单亲树结构对小说世界观足够
- **`tags` 逗号分隔**：用于筛选和分类（如 "capital", "ruins", "sacred"）
- **`parentId` 仅引用 `Locations.id`**：层级关系是地点实体内的结构，不依赖具体地图实例

### 2.2 新增表：NovelMaps

地图主表，存储地图的基本信息和画布尺寸。

```dart
class NovelMaps extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get description => text().withDefault(const Constant(''))();

  TextColumn get type =>
      text().withDefault(const Constant(mapTypeWorld))();

  RealColumn get width => real().withDefault(const Constant(1000.0))();

  RealColumn get height => real().withDefault(const Constant(800.0))();

  TextColumn get settingsJson => text().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

命名说明：
- 使用 `NovelMaps` 而不是 `Maps`，避免 Drift 生成的数据类 `Map` 与 Dart 核心 `Map<K, V>` 冲突
- 背景图收敛到 `settingsJson.background.image`，主表不再保留 `backgroundImage` 字段，避免双写源

### 2.3 新增表：MapLocations

地图-地点关联表，存储地点在特定地图上的画布坐标和视觉样式。一个地点可以出现在多张地图上（如"王都"同时出现在世界地图和区域地图）。

```dart
class MapLocations extends Table {
  TextColumn get id => text()();

  TextColumn get mapId => text()();

  TextColumn get locationId => text()();

  RealColumn get x => real().withDefault(const Constant(0.0))();

  RealColumn get y => real().withDefault(const Constant(0.0))();

  RealColumn get width => real().nullable()();

  RealColumn get height => real().nullable()();

  TextColumn get styleJson => text().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {mapId, locationId},
      ];
}
```

约束说明：
- `mapId` → `NovelMaps.id`
- `locationId` → `Locations.id`
- `(mapId, locationId)` 作为唯一键，确保同一地点在同一张地图上只出现一次

### 2.4 新增表：LocationConnections

地点间连接表，存储同一张地图上地点之间的空间关系（相邻、可达路径）。连接端点引用地图内实例 `MapLocations.id`，而不是直接引用 `Locations.id`，这样数据库层才能保证连线端点真实存在于该地图中。

```dart
class LocationConnections extends Table {
  TextColumn get id => text()();

  TextColumn get mapId => text()();

  TextColumn get sourceMapLocationId => text()();

  TextColumn get targetMapLocationId => text()();

  TextColumn get type => text()();

  TextColumn get label => text().nullable()();

  RealColumn get distance => real().nullable()();

  TextColumn get conditions => text().nullable()();

  TextColumn get difficulty => text().nullable()();

  IntColumn get travelTimeDays => integer().nullable()();

  TextColumn get extraProperties => text().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {mapId, sourceMapLocationId, targetMapLocationId, type},
      ];
}
```

约束说明：
- `mapId` → `NovelMaps.id`
- `sourceMapLocationId` / `targetMapLocationId` → `MapLocations.id`
- service 层额外校验 `sourceMapLocationId` 和 `targetMapLocationId` 必须属于同一个 `mapId`
- 禁止自连接（`sourceMapLocationId != targetMapLocationId`）

**列说明：**

| 列 | 类型 | 用途 | 适用类型 |
|---|---|---|---|
| `distance` | real? | 距离（km） | path_to |
| `conditions` | text? | 通行条件描述（如"冬季封路""需通行证"） | path_to |
| `difficulty` | text? | 通行难度（easy / normal / hard / impassable） | path_to |
| `travelTimeDays` | int? | 旅行天数 | path_to |
| `extraProperties` | text? | 预留扩展字段，用于加入上述列无法覆盖的自定义属性 | any |

`type` = `adjacent` 时除了 `label` 和 `extraProperties` 外不需要其他列。常见属性用固定列保持类型安全，未知扩展走 `extraProperties`。

**为什么不使用 EntityRelations？** 地点间的关系（相邻、路径）本质上是地图上的空间拓扑，不是 entity graph。它们属于地图子系统，有独立的语义（路径距离、通行条件等），不需要与角色/势力/章节的跨实体关系混在一起。EntityRelations 仍负责 character↔location、faction↔location、chapter↔location 的关联；地图连线只表达某张地图里的空间可视关系。

### 2.5 表结构汇总

| 表名 | 说明 | 关系 |
|------|------|------|
| Locations | 地点实体 | 独立实体，通过 EntityRelations 与其他实体关联；通过 parentId 自引用层级 |
| NovelMaps | 地图主表 | 一对多关联 MapLocations、LocationConnections |
| MapLocations | 地图-地点关联 | 多对一关联 NovelMaps，多对一关联 Locations；承载画布坐标和样式 |
| LocationConnections | 地点间连接 | 属于一张地图，引用两个 mapLocationId；处理 adjacent / path_to |

### 2.6 数据关系图

```
Locations (地点实体)
  │
  ├── parentId (层级关系，如：大陆 → 国家 → 城市)
  │
  ├── EntityRelations (跨实体关联)
  │     ├── 角色-地点（居住、出身、活动）
  │     ├── 势力-地点（占据、发源、影响）
  │     └── 章节-地点（发生、涉及）
  │
  └── MapLocations (在地图上的位置)
          │
          └── NovelMaps (所属地图)

NovelMaps (地图)
  │
  ├── 1:N ── MapLocations (地点 → 画布坐标 + 样式)
  │
  ├── 1:N ── LocationConnections (地点间连接)
  │     ├── adjacent (相邻)
  │     └── path_to (可达路径)
  │
  └── settingsJson (地图配置真源)
       ├── background (背景图)
       ├── grid (网格设置)
       └── viewport (视口状态)
```

---

### 2.7 设计原则：简单实现

**不是 GIS，不是游戏地图编辑器，只是画布 + 图钉 + 线。**

| 不做 | 原因 |
|------|------|
| 不规则多边形区域编辑 | 作者在外部工具（Procreate、Wonderdraft、手绘）画好包含国境线、森林、山脉的完整地图，导入为 `settingsJson.background.image` 即可，编辑器内不需要实现矢量绘图 |
| 图块/瓦片地图引擎 | Flutter 的 `InteractiveViewer` + 背景图对小说地图足够了，不需要 WebGL / Leaflet / 瓦片服务 |
| 3D / 多层自动切换 | 多层建筑用多张地图（"城堡一层""城堡二层"），不需要 3D 引擎 |
| 实时协作 / WebSocket | 单人写作场景不需要，后续可按需加 |

## 三、枚举与常量定义

### 3.1 地点类型

```dart
const String locationTypeGeneric = 'generic';
const String locationTypeContinent = 'continent';
const String locationTypeCountry = 'country';
const String locationTypeRegion = 'region';
const String locationTypeCity = 'city';
const String locationTypeDistrict = 'district';
const String locationTypeBuilding = 'building';
const String locationTypeRoom = 'room';
const String locationTypeNatural = 'natural';

const List<String> locationTypes = <String>[
  locationTypeGeneric,
  locationTypeContinent,
  locationTypeCountry,
  locationTypeRegion,
  locationTypeCity,
  locationTypeDistrict,
  locationTypeBuilding,
  locationTypeRoom,
  locationTypeNatural,
];
```

### 3.2 地点状态

```dart
const String locationStatusActive = 'active';
const String locationStatusArchived = 'archived';

const List<String> locationStatuses = <String>[
  locationStatusActive,
  locationStatusArchived,
];
```

### 3.3 地图类型

```dart
const String mapTypeWorld = 'world';
const String mapTypeRegion = 'region';
const String mapTypeCity = 'city';
const String mapTypeBuilding = 'building';
const String mapTypeDungeon = 'dungeon';

const List<String> mapTypes = <String>[
  mapTypeWorld,
  mapTypeRegion,
  mapTypeCity,
  mapTypeBuilding,
  mapTypeDungeon,
];
```

### 3.4 地图类型说明

| 类型 | 常量 | 说明 | 示例 |
|------|------|------|------|
| 世界地图 | `mapTypeWorld` | 整个世界的宏观地图 | 大陆、海洋分布 |
| 区域地图 | `mapTypeRegion` | 特定区域的地图 | 国家、省份 |
| 城市地图 | `mapTypeCity` | 城市或城镇的地图 | 街道、建筑分布 |
| 建筑地图 | `mapTypeBuilding` | 建筑内部的平面图 | 宫殿、学院 |
| 地下城地图 | `mapTypeDungeon` | 地下空间或迷宫 | 洞穴、遗迹 |

### 3.5 地点连接类型

```dart
const String locationConnectionAdjacent = 'adjacent';
const String locationConnectionPathTo = 'path_to';

const List<String> locationConnectionTypes = <String>[
  locationConnectionAdjacent,
  locationConnectionPathTo,
];
```

设计说明：
- **`adjacent`**：两个地点相邻接壤，视觉上绘制为短直线或虚线
- **`path_to`**：两个地点之间有道路/路径可达，视觉上绘制为贝塞尔曲线，可携带距离和通行条件
- 包含关系（如城市包含街区）由 `Locations.parentId` 层级树处理，不在连接表中重复表达

---

## 四、跨实体关系（EntityRelations）

地点与角色、势力、章节之间的关系继续使用现有的 `EntityRelations` 表。地点↔地点的关系已移至 `LocationConnections`，不在 EntityRelations 中表达。

### 4.1 地点与其他实体关系

| 关系类型 | 常量 | 说明 |
|----------|------|------|
| 章节发生于 | `chapterLocationOccurs` | 章节发生的地点 |
| 章节涉及 | `chapterLocationInvolves` | 章节涉及的地点 |

这些关系复用已有的 `EntityRelationsService`，通过 `sourceType=entityTypeLocation` / `targetType=entityTypeLocation` 查询。

---

## 五、服务层接口

### 5.1 LocationsService

```dart
class LocationsService {
  final NovelContentDatabase _database;

  LocationsService(this._database);

  Stream<List<Location>> watchLocations();
  Future<List<Location>> getLocations();
  Future<Location?> getLocationById(String id);
  Future<List<Location>> getLocationsByType(String type);
  Future<List<Location>> getChildLocations(String parentId);

  Future<String> createLocation({
    required String name,
    String description = '',
    String type = locationTypeGeneric,
    String? parentId,
    List<String> tags = const [],
  });

  Future<void> updateLocation({
    required String id,
    String? name,
    String? description,
    String? type,
    String? parentId,
    String? tags,
    String? status,
  });

  Future<void> deleteLocation(String id);
  Future<void> reorderLocations(List<String> ids);
}
```

### 5.2 MapsService

```dart
class MapsService {
  final NovelContentDatabase _database;

  MapsService(this._database);

  Stream<List<NovelMap>> watchMaps();
  Future<List<NovelMap>> getMaps();
  Future<NovelMap?> getMapById(String id);

  Future<String> createMap({
    required String name,
    String type = mapTypeWorld,
    String? description,
    double width = 1000.0,
    double height = 800.0,
    Map<String, dynamic>? settings,
  });

  Future<void> updateMap({
    required String id,
    String? name,
    String? description,
    String? type,
    double? width,
    double? height,
    Map<String, dynamic>? settings,
  });

  Future<void> deleteMap(String id);
  Future<void> reorderMaps(List<String> ids);
}
```

### 5.3 MapLocationsService

```dart
class MapLocationsService {
  final NovelContentDatabase _database;

  MapLocationsService(this._database);

  Stream<List<MapLocation>> watchMapLocations(String mapId);
  Future<List<MapLocation>> getMapLocations(String mapId);
  Future<MapLocation?> getMapLocationById(String id);

  Future<String> addLocationToMap({
    required String mapId,
    required String locationId,
    double x = 0.0,
    double y = 0.0,
    double? width,
    double? height,
    Map<String, dynamic>? style,
  });

  Future<void> updateMapLocation({
    required String id,
    double? x,
    double? y,
    double? width,
    double? height,
    Map<String, dynamic>? style,
  });

  Future<void> removeLocationFromMap(String id);
  Future<void> reorderMapLocations(String mapId, List<String> ids);

  Future<List<MapLocation>> getMapsForLocation(String locationId);
}
```

### 5.4 LocationConnectionsService

```dart
class LocationConnectionsService {
  final NovelContentDatabase _database;

  LocationConnectionsService(this._database);

  Stream<List<LocationConnection>> watchConnections(String mapId);
  Future<List<LocationConnection>> getConnections(String mapId);
  Future<LocationConnection?> getConnectionById(String id);

  Future<String> createConnection({
    required String mapId,
    required String sourceMapLocationId,
    required String targetMapLocationId,
    required String type,
    String? label,
    double? distance,
    String? conditions,
    String? difficulty,
    int? travelTimeDays,
    Map<String, dynamic>? extra,
  });

  Future<void> updateConnection({
    required String id,
    String? type,
    String? label,
    double? distance,
    String? conditions,
    String? difficulty,
    int? travelTimeDays,
    Map<String, dynamic>? extra,
  });

  Future<void> deleteConnection(String id);
  Future<void> reorderConnections(String mapId, List<String> ids);

  /// 批量导入（AI 生成时在同一事务内写入）
  Future<void> batchCreateConnections(
    String mapId,
    List<LocationConnectionInput> inputs,
  );
}
```

---

## 六、数据库 Schema 变更

### 6.1 新增表

```dart
@DriftDatabase(
  tables: [
    CharacterProfiles,
    ItemEntries,
    Chapters,
    ForeshadowingEntries,
    AiChatMessages,
    AiEmbeddingDocuments,
    WorkingChanges,
    ChangeCommits,
    ChangeCommitItems,
    NovelStates,
    NovelSubAgents,
    AgentRules,
    Documents,
    EntityRelations,
    Locations,
    NovelMaps,
    MapLocations,
    LocationConnections,
  ],
)
class NovelContentDatabase extends _$NovelContentDatabase {
  // ...
}
```

### 6.2 Schema Version 升级

```dart
@override
int get schemaVersion => 18;

@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (migrator) async {
    await migrator.createAll();
  },
  onUpgrade: (migrator, from, to) async {
    // ... 现有迁移逻辑 ...

    if (from < 18) {
      await migrator.createTable(locations);
      await migrator.createTable(novelMaps);
      await migrator.createTable(mapLocations);
      await migrator.createTable(locationConnections);
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_map_locations_unique '
        'ON map_locations (map_id, location_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_location_connections_map '
        'ON location_connections (map_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_locations_parent '
        'ON locations (parent_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_map_locations_map '
        'ON map_locations (map_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_map_locations_location '
        'ON map_locations (location_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_location_connections_source_map_location '
        'ON location_connections (source_map_location_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_location_connections_target_map_location '
        'ON location_connections (target_map_location_id)',
      );
    }
  },
);
```

Locations 为纯新增表，不从 ItemEntries 迁移存量数据。

---

## 七、地图编辑器实现方案

### 7.1 技术选型

基于 Flutter 的地图编辑器采用以下核心技术栈：

| 技术 | 用途 | 说明 |
|------|------|------|
| `InteractiveViewer` | 平移与缩放 | Flutter 内置组件，支持手势缩放、平移、边界约束 |
| `CustomPainter` | 自定义绘制 | 绘制网格、连接线、地点节点等 |
| `GestureDetector` | 交互处理 | 处理点击、拖拽、长按等手势 |
| `Stack` + `Positioned` | 节点布局 | 实现地点节点的自由定位 |

### 7.2 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    MapEditorWidget                          │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                  InteractiveViewer                     │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │              Stack (Layered Canvas)              │  │  │
│  │  │  ┌───────────────────────────────────────────┐  │  │  │
│  │  │  │  GridLayer (CustomPaint)                  │  │  │  │
│  │  │  │  - 绘制网格背景                           │  │  │  │
│  │  │  └───────────────────────────────────────────┘  │  │  │
│  │  │  ┌───────────────────────────────────────────┐  │  │  │
│  │  │  │  ConnectionLayer (CustomPaint)            │  │  │  │
│  │  │  │  - 绘制地点间的连接线                     │  │  │  │
│  │  │  └───────────────────────────────────────────┘  │  │  │
│  │  │  ┌───────────────────────────────────────────┐  │  │  │
│  │  │  │  LocationNodesLayer                       │  │  │  │
│  │  │  │  - Positioned widgets for each location   │  │  │  │
│  │  │  │  - Draggable location cards               │  │  │  │
│  │  │  └───────────────────────────────────────────┘  │  │  │
│  │  │  ┌───────────────────────────────────────────┐  │  │  │
│  │  │  │  OverlayLayer (CustomPaint)               │  │  │  │
│  │  │  │  - 绘制选中框、拖拽预览等                 │  │  │  │
│  │  │  └───────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 7.3 核心组件实现

#### 7.3.1 地图编辑器 Widget

```dart
class MapEditorWidget extends HookConsumerWidget {
  final String mapId;

  const MapEditorWidget({
    super.key,
    required this.mapId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapLocations = ref.watch(mapLocationsProvider(mapId));
    final selectedLocationId = useState<String?>(null);
    final transformationController = useTransformationController();

    return InteractiveViewer(
      transformationController: transformationController,
      minScale: 0.1,
      maxScale: 4.0,
      constrained: false,
      child: Stack(
        children: [
          _GridLayer(mapId: mapId),
          _ConnectionLayer(mapId: mapId),
          _LocationNodesLayer(
            mapId: mapId,
            selectedLocationId: selectedLocationId,
            onLocationMoved: (id, x, y) {
              ref.read(mapLocationsServiceProvider).updateMapLocation(
                id: id,
                x: x,
                y: y,
              );
            },
          ),
          _OverlayLayer(
            mapId: mapId,
            selectedLocationId: selectedLocationId,
          ),
        ],
      ),
    );
  }
}
```

#### 7.3.2 网格层 (GridLayer)

```dart
class _GridLayer extends HookConsumerWidget {
  final String mapId;

  const _GridLayer({required this.mapId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = ref.watch(mapByIdProvider(mapId));
    final settings = map?.settings != null
        ? MapSettings.fromJson(map!.settings!)
        : const MapSettings();

    return CustomPaint(
      size: Size(map?.width ?? 1000, map?.height ?? 800),
      painter: GridPainter(
        gridSize: settings.gridSize,
        gridColor: settings.gridColor,
        showGrid: settings.showGrid,
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  final double gridSize;
  final Color gridColor;
  final bool showGrid;

  GridPainter({
    this.gridSize = 50,
    this.gridColor = const Color(0xFFE0E0E0),
    this.showGrid = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showGrid) return;

    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return gridSize != oldDelegate.gridSize ||
        gridColor != oldDelegate.gridColor ||
        showGrid != oldDelegate.showGrid;
  }
}
```

#### 7.3.3 连接线层 (ConnectionLayer)

从 `LocationConnections` 读取连接数据，按 `sourceMapLocationId`/`targetMapLocationId` 直接定位 `MapLocations.id` 并绘制贝塞尔曲线。

```dart
class _ConnectionLayer extends HookConsumerWidget {
  final String mapId;

  const _ConnectionLayer({required this.mapId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapLocations = ref.watch(mapLocationsProvider(mapId));
    final connections = ref.watch(locationConnectionsProvider(mapId));

    return CustomPaint(
      size: const Size(double.infinity, double.infinity),
      painter: ConnectionPainter(
        connections: connections,
        mapLocations: mapLocations,
      ),
    );
  }
}

class ConnectionPainter extends CustomPainter {
  final List<LocationConnection> connections;
  final List<MapLocation> mapLocations;

  ConnectionPainter({
    required this.connections,
    required this.mapLocations,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final connection in connections) {
      final source = mapLocations.firstWhereOrNull(
        (l) => l.id == connection.sourceMapLocationId,
      );
      final target = mapLocations.firstWhereOrNull(
        (l) => l.id == connection.targetMapLocationId,
      );

      if (source == null || target == null) continue;

      final path = _buildBezierPath(
        Offset(source.x, source.y),
        Offset(target.x, target.y),
      );

      canvas.drawPath(path, paint);
    }
  }

  Path _buildBezierPath(Offset start, Offset end) {
    final controlPoint1 = Offset(
      start.dx + (end.dx - start.dx) * 0.5,
      start.dy,
    );
    final controlPoint2 = Offset(
      start.dx + (end.dx - start.dx) * 0.5,
      end.dy,
    );

    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        controlPoint1.dx, controlPoint1.dy,
        controlPoint2.dx, controlPoint2.dy,
        end.dx, end.dy,
      );
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return connections != oldDelegate.connections ||
        mapLocations != oldDelegate.mapLocations;
  }
}
```

#### 7.3.4 地点节点层 (LocationNodesLayer)

```dart
class _LocationNodesLayer extends HookConsumerWidget {
  final String mapId;
  final ValueNotifier<String?> selectedLocationId;
  final void Function(String id, double x, double y) onLocationMoved;

  const _LocationNodesLayer({
    required this.mapId,
    required this.selectedLocationId,
    required this.onLocationMoved,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapLocations = ref.watch(mapLocationsProvider(mapId));
    final locations = ref.watch(locationsByIdsProvider(
      mapLocations.map((ml) => ml.locationId).toList(),
    ));

    return Stack(
      children: mapLocations.map((mapLocation) {
        final location = locations.firstWhereOrNull(
          (l) => l.id == mapLocation.locationId,
        );
        if (location == null) return const SizedBox.shrink();

        return Positioned(
          left: mapLocation.x,
          top: mapLocation.y,
          child: _DraggableLocationNode(
            mapLocation: mapLocation,
            location: location,
            isSelected: selectedLocationId.value == mapLocation.id,
            onTap: () {
              selectedLocationId.value = mapLocation.id;
            },
            onMoved: (dx, dy) {
              onLocationMoved(
                mapLocation.id,
                mapLocation.x + dx,
                mapLocation.y + dy,
              );
            },
          ),
        );
      }).toList(),
    );
  }
}

class _DraggableLocationNode extends HookWidget {
  final MapLocation mapLocation;
  final Location location;
  final bool isSelected;
  final VoidCallback onTap;
  final void Function(double dx, double dy) onMoved;

  const _DraggableLocationNode({
    required this.mapLocation,
    required this.location,
    required this.isSelected,
    required this.onTap,
    required this.onMoved,
  });

  @override
  Widget build(BuildContext context) {
    final position = useState(Offset.zero);

    return GestureDetector(
      onPanStart: (_) {
        position.value = Offset.zero;
      },
      onPanUpdate: (details) {
        position.value += details.delta;
        onMoved(details.delta.dx, details.delta.dy);
      },
      onPanEnd: (_) {
        // 拖拽结束时提交最终位置，减少中间写入
        position.value = Offset.zero;
      },
      onTap: onTap,
      child: Transform.translate(
        offset: position.value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? RevericTheme.colorsOf(context).primary
                : RevericTheme.colorsOf(context).surface,
            borderRadius: RevericRadius.md,
            border: Border.all(
              color: isSelected
                  ? RevericTheme.colorsOf(context).primary
                  : RevericTheme.colorsOf(context).outline,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getLocationIcon(location.type),
                size: 16,
                color: isSelected
                    ? Colors.white
                    : RevericTheme.colorsOf(context).onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                location.name,
                style: RevericTheme.textOf(context).bodyMedium?.copyWith(
                  color: isSelected
                      ? Colors.white
                      : RevericTheme.colorsOf(context).onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getLocationIcon(String type) {
    switch (type) {
      case locationTypeContinent:
        return Icons.public;
      case locationTypeCountry:
        return Icons.flag;
      case locationTypeCity:
        return Icons.location_city;
      case locationTypeBuilding:
        return Icons.home;
      case locationTypeNatural:
        return Icons.terrain;
      default:
        return Icons.place;
    }
  }
}
```

### 7.4 状态管理

使用 `@riverpod` + `@freezed` 管理地图编辑器的全局编辑器状态：

```dart
@freezed
class MapEditorState with _$MapEditorState {
  const factory MapEditorState({
    String? selectedLocationId,
    String? selectedConnectionId,
    @Default(false) bool isCreatingConnection,
    String? connectionSourceId,
    @Default(1.0) double viewportZoom,
    @Default(Offset.zero) Offset viewportOffset,
  }) = _MapEditorState;

  factory MapEditorState.fromJson(Map<String, dynamic> json) =>
      _$MapEditorStateFromJson(json);
}

@riverpod
class MapEditorNotifier extends _$MapEditorNotifier {
  @override
  MapEditorState build(String mapId) {
    return const MapEditorState();
  }

  void selectLocation(String? locationId) {
    state = state.copyWith(selectedLocationId: locationId);
  }

  void startConnection(String sourceMapLocationId) {
    state = state.copyWith(
      isCreatingConnection: true,
      connectionSourceId: sourceMapLocationId,
    );
  }

  void finishConnection() {
    state = state.copyWith(
      isCreatingConnection: false,
      connectionSourceId: null,
    );
  }

  void updateViewport({double? zoom, Offset? offset}) {
    state = state.copyWith(
      viewportZoom: zoom ?? state.viewportZoom,
      viewportOffset: offset ?? state.viewportOffset,
    );
  }
}
```

### 7.5 性能优化策略

| 策略 | 说明 |
|------|------|
| RepaintBoundary | 为每个地点节点添加 RepaintBoundary，隔离重绘范围 |
| shouldRepaint 优化 | 在 CustomPainter 中精确判断是否需要重绘 |
| 虚拟化渲染 | 大量节点时只渲染视口范围内的节点 |
| 路径缓存 | 缓存连接线路径计算结果，避免重复计算 |
| 状态分离 | 将选中状态、拖拽状态与渲染状态分离，减少不必要的重建 |
| 批量加载 | 使用 `getLocationsInBulk(mapId)` 一次查询，避免 `locationsByIdsProvider` 逐个加载 |

### 7.6 可选第三方库

如果需要更复杂的功能，可以考虑以下 Flutter 包：

| 包名 | 特点 | 适用场景 |
|------|------|----------|
| **GraphFlow** | 节点编辑器，支持网格、连接线、平移缩放 | 类似流程图的地图编辑 |
| **vyuh_node_flow** | 类似 React Flow，功能丰富，支持 MiniMap | 复杂的节点图编辑 |
| **fl_nodes** | 轻量级，高度可定制 | 简单的节点编辑需求 |

**推荐方案**：对于小说地图编辑器，建议使用 **CustomPainter + InteractiveViewer** 自定义实现，原因：
1. 更灵活的样式控制
2. 更好的性能优化空间
3. 与现有设计系统（RevericTheme）无缝集成
4. 不依赖第三方包，便于维护

---

## 八、AI 生成地图

### 8.1 MapBlueprint：AI 可输出的完整地图结构

AI 输出单个 `MapBlueprint` JSON，包含地图元信息、所有地点（含画布坐标和样式）、地点间连接。App 反序列化后在单个事务中原子写入 DB；任何一步失败都整体回滚。

```json
{
  "name": "艾尔大陆",
  "description": "故事的主要舞台，三块大陆被无尽之海环绕",
  "type": "world",
  "width": 2400,
  "height": 1800,
  "locations": [
    {
      "id": "loc_kingdom_01",
      "name": "光明王国",
      "description": "大陆中部最强大的王国",
      "type": "country",
      "x": 1000,
      "y": 800,
      "width": 200,
      "height": 160,
      "tags": ["powerful", "central"],
      "style": { "color": "#C62828", "icon": "flag" }
    },
    {
      "id": "loc_capital_01",
      "name": "王都·光辉城",
      "description": "以白色大理石建筑闻名的繁华都城",
      "type": "city",
      "parent": "loc_kingdom_01",
      "x": 1050,
      "y": 850,
      "width": 80,
      "height": 50,
      "tags": ["capital"],
      "style": { "color": "#FFD700", "icon": "location_city" }
    },
    {
      "id": "loc_district_01",
      "name": "商业区",
      "description": "王都最繁华的商业街",
      "type": "district",
      "parent": "loc_capital_01",
      "x": 1070,
      "y": 860,
      "width": 50,
      "height": 30,
      "style": { "color": "#4CAF50", "icon": "store" }
    }
  ],
  "connections": [
    {
      "source": "loc_capital_01",
      "target": "loc_kingdom_border_fort",
      "type": "path_to",
      "label": "国王大道",
      "distance": 200,
      "travelTimeDays": 2,
      "conditions": "主要道路，四季可通行",
      "difficulty": "easy"
    },
    {
      "source": "loc_district_01",
      "target": "loc_capital_academy",
      "type": "adjacent",
      "label": "相邻街区"
    }
  ]
}
```

### 8.2 Dart 类型定义

```dart
/// AI 生成地图的完整蓝图，一个 JSON 包含整张地图
@freezed
class MapBlueprint with _$MapBlueprint {
  const factory MapBlueprint({
    required String name,
    String description = '',
    @Default(mapTypeWorld) String type,
    @Default(2400.0) double width,
    @Default(1800.0) double height,
    MapSettings? settings,
    required List<BlueprintLocation> locations,
    @Default([]) List<BlueprintConnection> connections,
  }) = _MapBlueprint;

  factory MapBlueprint.fromJson(Map<String, dynamic> json) =>
      _$MapBlueprintFromJson(json);
}

@freezed
class BlueprintLocation with _$BlueprintLocation {
  const factory BlueprintLocation({
    required String id,
    required String name,
    String description = '',
    @Default(locationTypeGeneric) String type,
    required double x,
    required double y,
    double? width,
    double? height,
    String? parent,
    @Default([]) List<String> tags,
    LocationStyle? style,
  }) = _BlueprintLocation;

  factory BlueprintLocation.fromJson(Map<String, dynamic> json) =>
      _$BlueprintLocationFromJson(json);
}

@freezed
class BlueprintConnection with _$BlueprintConnection {
  const factory BlueprintConnection({
    required String source,
    required String target,
    @Default(locationConnectionPathTo) String type,
    String? label,
    double? distance,
    String? conditions,
    String? difficulty,
    int? travelTimeDays,
    @Default({}) Map<String, dynamic> extra,
  }) = _BlueprintConnection;

  factory BlueprintConnection.fromJson(Map<String, dynamic> json) =>
      _$BlueprintConnectionFromJson(json);
}
```

### 8.3 导入流程

```
AI → MapBlueprint JSON → MapImportService.import(blueprint)
                              │
                              ▼
                     事务内原子写入:
                     1. NovelMaps.create(map)
                     2. 遍历 locations: Locations.create(location)
                     3. parent ID 解析: 按 blueprint.id → DB location.id 映射
                     4. 遍历 locations: MapLocations.create(mapLocation)
                     5. 建立 blueprint.id → mapLocation.id 映射
                     6. 遍历 connections: LocationConnections.create(connection)
                     7. source/target 解析为 sourceMapLocationId/targetMapLocationId
                              │
                              ▼
                     提交事务 → Provider invalidate → UI 刷新
```

导入规则：
- `parent`、`source`、`target` 在蓝图中使用 `blueprint.id`（AI 生成的临时 ID）引用
- 导入时分别建立 `blueprint.id → location.id` 与 `blueprint.id → mapLocation.id` 两套映射
- 默认采用 `insert-only` 语义：若蓝图中的 `id` 已映射到现有记录，不覆盖旧记录，直接报错并回滚
- 如后续需要“覆盖导入”，单独设计 `replaceMapFromBlueprint()`，不要和默认导入混用

### 8.4 AI Prompt 示例

```
为我的小说《xxx》创建一个世界地图，包含以下地点：
- 光明王国（国家）
- 王都·光辉城（城市，属于光明王国）
- 商业区（街区，属于光辉城）
- 边境要塞（城市，属于光明王国）
...

请按照 MapBlueprint JSON 格式输出，包含 locations 和 connections，
locations 使用唯一 id 供 connections 引用。
```

---

## 九、UI 设计建议

### 9.1 地图列表页面

- 显示所有地图的卡片视图
- 支持创建、编辑、删除地图
- 支持拖拽排序
- 显示地图类型图标、地点数量
- "AI 生成地图"入口按钮，弹出对话框输入描述

### 9.2 地图编辑器布局

```
┌─────────────────────────────────────────────────────────────────┐
│ [返回] 地图名称                                    [保存] [设置] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                                                           │  │
│  │      ┌──────────┐                    ┌──────────┐         │  │
│  │      │ 王都     │ ═════════════════  │ 商业区   │         │  │
│  │      └──────────┘                    └──────────┘         │  │
│  │           │                                                 │  │
│  │           │ (连接线: path_to)                                │  │
│  │      ┌──────────┐                                          │  │
│  │      │ 学院     │                                          │  │
│  │      └──────────┘                                          │  │
│  │                                                           │  │
│  │                                                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ [添加地点] [绘制连接] [设置背景] [缩放: 100%] [AI生成] [导出]   │
└─────────────────────────────────────────────────────────────────┘
```

### 9.3 地点编辑面板

- 地点基本信息（名称、描述、类型）
- 在地图上的位置（坐标、尺寸）
- 关联的实体（角色、势力、章节）— 通过 EntityRelations
- 地点间连接列表（相邻、可达路径）— 通过 LocationConnections

---

## 十、地图配置结构

### 10.1 settingsJson 结构

`settingsJson` 是地图配置的唯一真源，背景图路径、透明度、适配模式等都只存这里。

```json
{
  "background": {
    "image": "path/to/image.png",
    "opacity": 0.8,
    "fit": "cover"
  },
  "grid": {
    "enabled": true,
    "size": 50,
    "color": "#E0E0E0",
    "snapToGrid": true
  },
  "viewport": {
    "zoom": 1.0,
    "centerX": 500,
    "centerY": 400
  }
}
```

### 10.2 styleJson 结构（MapLocations）

```json
{
  "icon": "location_city",
  "color": "#FF5722",
  "shape": "rounded_rect",
  "size": "medium",
  "label": {
    "visible": true,
    "position": "bottom",
    "fontSize": 12
  },
  "border": {
    "width": 1,
    "color": "#333333"
  }
}
```

### 10.3 extraProperties 结构（LocationConnections）

当固定列不足以表达时，使用 `extraProperties` 存储自定义扩展信息：

```json
{
  "requiresPass": "王室通行证",
  "seasonalClosure": "冬季12月-2月关闭",
  "waypoints": ["迷雾森林", "断桥"]
}
```

---

## 十一、与现有功能的集成

### 11.1 与 Entity Graph 的集成

- Entity Graph 中的地点节点映射到 Location 实体
- EntityRelations 的角色-地点/势力-地点关系可在弹出面板中查看
- 点击地点节点时，如果该地点只出现在一张地图中，直接跳转
- 如果该地点出现在多张地图中，弹出地图选择器
- 如需默认跳转目标，后续可在 `Locations` 或关联表增加 `primaryMapId` / `isPrimary` 语义

### 11.2 与章节的集成

- 章节编辑器中通过 EntityRelations 选择发生地点（按 locationId 关联）
- 支持按地点筛选章节
- 在地图上标记章节分布（按章节数量显示热度）

### 11.3 与 AI 的集成

- AI 写作时可以获取地点上下文（locationId → location 详情）
- 支持基于地点的智能提示
- 支持生成 `MapBlueprint` 完整地图结构（第八节）
- 支持增量添加单条 location/connection

---

## 十二、Tasks

### Phase 1：数据库迁移

- [ ] 新增 `Locations` 表
- [ ] 新增 `NovelMaps` 表
- [ ] 新增 `MapLocations` 表
- [ ] 新增 `LocationConnections` 表
- [ ] 更新 `NovelContentDatabase` schema version
- [ ] 编写迁移测试

### Phase 2：服务层实现

- [ ] 实现 `LocationsService`
- [ ] 实现 `MapsService`
- [ ] 实现 `MapLocationsService`
- [ ] 实现 `LocationConnectionsService`

### Phase 3：Provider 层

- [ ] 新增 `locationsProvider` 系列
- [ ] 新增 `mapsProvider` 系列
- [ ] 新增 `mapLocationsProvider` 系列
- [ ] 新增 `locationConnectionsProvider` 系列
- [ ] 实现地图编辑器状态管理（`MapEditorNotifier` + `MapEditorState`）

### Phase 4：UI 实现

- [ ] 实现地点列表页面
- [ ] 实现地图列表页面
- [ ] 实现地图编辑器基础功能
- [ ] 实现地点拖拽和定位
- [ ] 实现连接线绘制（从 LocationConnections 读取）

### Phase 5：高级功能

- [ ] 实现背景图片支持
- [ ] 实现网格对齐
- [ ] 实现 `MapBlueprint` 导入（AI 生成 → 事务原子写入 + 失败回滚）
- [ ] 实现地图导出
- [ ] 实现地点搜索与筛选

### Phase 6：集成与优化

- [ ] 与 Entity Graph 集成（显示跨实体关联）
- [ ] 与章节编辑器集成
- [ ] AI 上下文集成
- [ ] 性能优化

---

## 十三、注意事项

1. **地点独立性**：Locations 是独立实体，一个地点可出现在多张地图上

2. **画布坐标**：
   - 虚构小说使用纯画布坐标 `(x, y)`，不需要真实经纬度
   - `x` 向右为正，`y` 向下为正（与 Flutter 坐标系一致）
   - 坐标原点 `(0, 0)` 为画布左上角

3. **层级关系**：
   - 通过 `parentId` 字段实现地点层级（单亲树结构）
   - 如：大陆 → 国家 → 城市 → 街区
   - 争议领土等双亲场景暂不支持，必要时可后续扩展为多对多

4. **连接 vs 层级**：
   - `parentId` = 树形包含关系（continent contains country）
   - `LocationConnections` = 图上可见的连线（adjacent / path_to）
   - 两者互补不重叠

5. **性能优化**：
   - 大量地点时使用虚拟化渲染
   - 地图缩放时动态加载/卸载地点详情
   - 为 `mapId`、`locationId`、`parentId`、`sourceMapLocationId`、`targetMapLocationId` 字段添加索引
   - 批量加载地点而非逐个查询

6. **数据一致性**：
   - 删除地点时，级联删除 `MapLocations` 中的关联记录
   - 删除 `MapLocations` 记录时，级联删除以该记录为端点的 `LocationConnections`
   - 删除地点时，更新子地点的 `parentId` 为 NULL 或重新指定
   - 删除地图时，级联删除所有 `MapLocations` 和 `LocationConnections` 记录
   - 创建连接时，必须校验两个端点都属于同一 `mapId`
   - `MapBlueprint` 导入必须在单个事务中完成，任一记录失败即整体回滚

7. **扩展性**：
   - `settingsJson`、`styleJson`、`extraProperties` 使用 JSON 格式，便于后续扩展
   - 预留自定义属性字段

---

## 十四、未来扩展

### 14.1 路径系统增强

- 路径自动寻路算法（基于 LocationConnections 图）
- 路径距离和旅行时间自动计算
- 角色路径规划（"从 A 到 B 需要经过 C"）

### 14.2 时间线

- 支持记录地点随时间的变化（季节、战争前后）
- 支持显示不同时间点的地图状态
- 支持角色移动轨迹回放

### 14.3 多层地图

- 支持建筑内部多层结构（通过地图类型 building / dungeon）
- 层间连接（楼梯、传送点）

### 14.4 势力领地

- 在 MapLocations 上添加 radius/region 字段用于势力范围可视化
