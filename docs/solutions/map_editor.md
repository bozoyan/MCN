# 地图编辑器设计方案

## 概述

目标是把当前的“背景图 + 图钉 + 连线”能力，升级为适合小说创作的地图编辑器。编辑器既要支持手工编辑，也要支持 AI 通过 JSON 生成和修改地图结构。

核心设计原则：

- 地图编辑器不是 GIS，也不是游戏地形编辑器，而是“世界观结构 + 可视化摆放”的创作工具
- `Location` 是世界观实体，地图中的显示只是 `Location` 在某张地图上的一种表现
- 编辑器内优先支持简单可靠的几何能力：点、矩形区域；复杂多边形后续再加
- JSON 作为 AI 协议和导入导出格式，数据库仍保留结构化表，避免后续查询和增量更新失控

---

## 一、目标能力

### 1.1 用户目标

编辑器应支持以下能力：

1. 用户可以在地图上框出任意矩形区域，并直接创建一个新的 `Location`
2. 用户可以先创建 `Location`，再从左侧库拖拽到地图上放置
3. 地图数据能够完整导入导出为 JSON，并可由 AI 直接生成或增量修改
4. `Location` 具备层级和类型，例如山脉、平原、森林、国家、城市、建筑等
5. 点击 `Location` 后可查看详细信息，并支持聚焦、放大、缩小、进入子地图

### 1.2 非目标

第一阶段不做以下能力：

- 不做 GIS 坐标系、经纬度、投影
- 不做精细地形绘制、河流笔刷、自动边界生成
- 不做复杂碰撞检测和自动布局
- 不把数据库直接替换为单一大 JSON 文档

---

## 二、现状与问题

当前实现位于：

- `lib/desktop/widgets/map_editor_panel.dart`
- `lib/shared/widgets/maps/map_canvas.dart`
- `lib/shared/widgets/maps/map_editor_controller.dart`
- `lib/shared/services/maps_service.dart`

当前能力主要是：

- 背景图展示
- 地点图钉显示
- 点位拖动
- 简单连线
- 地图和地点的基础 CRUD

当前限制：

- `MapLocation` 只有 `x/y/width/height`，无法表达“区域”或未来的复杂几何
- 画布渲染是 marker-centered，而不是 feature-centered
- 交互模式过少，不支持框选、区域绘制、拖拽放置草图
- 信息面板太轻，只适合查看一个点位，不适合管理层级、类型、样式、子地图
- 没有统一的 JSON 文档协议，AI 难以稳定参与生成和增量编辑

### 2.1 当前实现与设计稿的偏差

当前代码已经从“点位编辑器”迈向“地图要素编辑器”，但离参考设计稿仍然有明显距离，必须明确区分：

- 已完成的是数据模型、交互骨架、迁移兼容层
- 未完成的是设计稿级工作台视觉、聊天式 AI 侧栏、项目导航式左栏、成品地图画布表现

目前实际状态更接近“开发中功能版”，而不是“接近设计稿的成品版”。主要偏差包括：

1. 左侧仍然是简化的 `Location Library`
   - 还不是设计稿中的“工作区树 + 类型分组 + 图层树 + 素材区”
2. 中央仍以开发态画布为主
   - 已支持 feature、框选、多选、拖拽、缩放，但视觉上仍是基础网格和临时工具条
3. 右侧仍是功能面板
   - 已能编辑地点元数据和几何，AI 聊天已移除（将接入 `AiChatPanel`）
4. 底部统计卡和版本信息还只是骨架
   - 没有设计稿中的完整图例、势力统计、重要地点、版本历史
5. 当前实现优先级偏向“数据闭环先行”
   - 这保证了后续界面重构不会返工数据库，但也导致当前视觉完成度明显落后于目标图

---

## 三、核心建模

### 3.1 两层模型

建议把“地点实体”和“地图显示”明确拆成两层：

#### A. `Location`

`Location` 是世界观实体，不绑定某一张地图。

建议字段：

- `id`
- `name`
- `description`
- `type`
- `parentId`
- `tags`
- `metaJson`
- `status`
- `sortOrder`
- `createdAt`
- `updatedAt`

用途：

- 表达世界观中的地理概念
- 维护父子层级关系
- 与角色、章节、势力等其他实体建立关系
- 允许被多张地图复用

#### B. `MapFeature`

`MapFeature` 是某个 `Location` 在某张地图上的视觉表现。

建议新增表：

```dart
class MapFeatures extends Table {
  TextColumn get id => text()();

  TextColumn get mapId => text()();

  TextColumn get locationId => text()();

  TextColumn get geometryType => text()();

  TextColumn get geometryJson => text()();

  TextColumn get styleJson => text().nullable()();

  TextColumn get labelJson => text().nullable()();

  IntColumn get zIndex => integer().withDefault(const Constant(0))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

用途：

- 表达一个地点在当前地图中的几何形状
- 表达标签位置、样式、显示层级
- 支持未来一个地点在不同地图中使用不同表现

### 3.2 为什么不继续只用 `MapLocations`

现有 `MapLocations` 更像“把一个点钉在地图上”。但你要的目标包含：

- 框出区域
- 区域类地点
- 层级地图钻取
- AI 输出统一几何结构

这些都要求地图层具备统一的“要素 feature”抽象。建议：

- 保留 `Locations`
- 保留 `NovelMaps`
- 保留 `LocationConnections`
- 用 `MapFeatures` 逐步替代 `MapLocations`

迁移策略见后文。

---

## 四、几何模型

### 4.1 第一阶段支持的几何类型

建议先支持三类中的前两类：

- `point`
- `rect`
- `polygon`（第二阶段再实现）

### 4.2 `point`

适合城市、据点、港口、建筑入口、遗迹等。

```json
{
  "type": "point",
  "x": 423.5,
  "y": 198.0
}
```

### 4.3 `rect`

适合区域框选新建地点，是第一阶段的核心几何。

```json
{
  "type": "rect",
  "x": 320,
  "y": 180,
  "width": 240,
  "height": 160
}
```

### 4.4 `polygon`

适合国家边界、湖泊、森林、山脉等不规则区域，作为后续升级能力。

```json
{
  "type": "polygon",
  "points": [[300, 180], [520, 160], [560, 280], [350, 320]]
}
```

### 4.5 几何选择原则

- 第一阶段把“区域编辑”定义为矩形区域，降低实现和交互复杂度
- 复杂边界优先通过背景图表达，编辑器只负责结构化标注
- 多边形只有在矩形区域已稳定后再加入

---

## 五、Location 类型与层级

### 5.1 类型

建议把当前 location type 扩展为更适合地图的集合：

```dart
const String locationTypeWorld = 'world';
const String locationTypeContinent = 'continent';
const String locationTypeCountry = 'country';
const String locationTypeRegion = 'region';
const String locationTypeMountain = 'mountain';
const String locationTypePlain = 'plain';
const String locationTypeForest = 'forest';
const String locationTypeRiver = 'river';
const String locationTypeLake = 'lake';
const String locationTypeSea = 'sea';
const String locationTypeIsland = 'island';
const String locationTypeCity = 'city';
const String locationTypeDistrict = 'district';
const String locationTypeVillage = 'village';
const String locationTypeBuilding = 'building';
const String locationTypeRoom = 'room';
const String locationTypeLandmark = 'landmark';
const String locationTypeCustom = 'custom';
```

### 5.2 层级

层级由 `parentId` 表达，示例：

```text
提瓦特
├── 蒙德
│   ├── 果酒湖
│   ├── 蒙德城
│   │   ├── 骑士团总部
│   │   └── 风神广场
│   └── 风起地
└── 璃月
    ├── 璃月港
    └── 绝云间
```

层级有两种作用：

- 世界观结构组织
- 左侧 Location Library 的树状展示

### 5.3 子地图

建议支持一个 `Location` 对应一张子地图。

可在 `Location.metaJson` 中增加：

```json
{
  "defaultChildMapId": "map_mondstadt_city"
}
```

用途：

- 世界地图点击“蒙德”后可进入“蒙德区域地图”
- 区域地图点击“蒙德城”后可进入“城市地图”

---

## 六、JSON 文档协议

### 6.1 设计原则

JSON 既是：

- AI 生成协议
- 导入导出协议
- 地图草稿快照格式
- 历史版本基础格式

但数据库仍然是持久化真源，JSON 不直接替代结构化表。

### 6.2 文档结构

```json
{
  "version": "1.0",
  "map": {
    "id": "map_teyvat_world",
    "name": "提瓦特互动地图",
    "type": "world",
    "width": 4096,
    "height": 3072,
    "background": {
      "imageAssetId": "asset_teyvat_world",
      "fit": "cover"
    }
  },
  "locations": [],
  "features": [],
  "connections": []
}
```

### 6.3 `locations[]`

```json
{
  "id": "loc_mondstadt",
  "name": "蒙德",
  "type": "country",
  "parentId": "loc_teyvat",
  "description": "风之国度",
  "tags": ["nation", "anemo"],
  "meta": {
    "climate": "temperate",
    "defaultChildMapId": "map_mondstadt_region"
  }
}
```

### 6.4 `features[]`

```json
{
  "id": "feat_mondstadt_region",
  "mapId": "map_teyvat_world",
  "locationId": "loc_mondstadt",
  "geometryType": "rect",
  "geometry": {
    "x": 180,
    "y": 60,
    "width": 620,
    "height": 720
  },
  "style": {
    "stroke": "#8ED1C2",
    "fill": "#8ED1C233",
    "label": "蒙德",
    "icon": "region",
    "showLabel": true,
    "minScale": 0.2,
    "maxScale": 4.0
  },
  "zIndex": 10
}
```

### 6.5 `connections[]`

```json
{
  "id": "conn_mondstadt_liyue",
  "mapId": "map_teyvat_world",
  "sourceFeatureId": "feat_mondstadt_region",
  "targetFeatureId": "feat_liyue_region",
  "type": "path_to",
  "label": "商路",
  "distance": 1200,
  "travelTimeDays": 12
}
```

---

## 七、AI 协议

### 7.1 全量生成

适合从零生成一张地图。

输入：

- 世界观设定
- 地图层级要求
- 地点类型范围
- 风格偏好

输出：

- `locations[]`
- `features[]`
- `connections[]`

### 7.2 增量修改

适合“在现有地图上改一点”。

建议定义 patch 协议：

```json
{
  "operations": [
    {
      "op": "create_location",
      "location": {}
    },
    {
      "op": "create_feature",
      "feature": {}
    },
    {
      "op": "update_feature",
      "id": "feat_xxx",
      "changes": {}
    }
  ]
}
```

### 7.3 安全策略

AI 不应直接写数据库，流程建议为：

1. AI 生成 JSON 文档或 patch
2. 前端展示预览或 diff
3. 用户确认
4. 由 service 层批量落库

这样可以避免错误覆盖用户已有地图结构。

---

## 八、编辑器交互设计

### 8.1 布局

桌面端建议改为三栏布局：

1. 左栏：`Location Library`
2. 中栏：`Map Canvas`
3. 右栏：`Inspector`

#### 左栏：Location Library

能力：

- 树状层级展示
- 搜索
- 类型筛选
- 拖拽到地图
- 显示“已放置 / 未放置”

#### 中栏：Map Canvas

能力：

- 背景图
- 缩放和平移
- 点位/区域渲染
- 框选区域创建新地点
- 拖放已有地点
- 显示连接线

#### 右栏：Inspector

能力：

- 选中要素详情
- 名称、类型、父级、标签编辑
- 几何参数编辑
- 样式编辑
- 跳转子地图
- AI 补全描述和属性

### 8.1.1 参考图设计稿

参考图体现的是“创作工作台”而不是“浮层工具箱”，这一点应该直接吸收到最终布局中。

建议采用如下结构：

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ 顶部标题栏 / 保存栏                                                        │
├───────────────┬─────────────────────────────────────────────┬──────────────┤
│ 左侧地点树     │ 中央地图画布 + 顶部工具条 + 底部统计面板      │ 右侧检查器    │
│               │                                             │              │
│ - 地图层级     │ - 世界 / 区域 / 城市 / 图层切换              │ - 地点详情     │
│ - 类型分组     │ - 选择 / 绘制区域 / 添加城市 / 连线 / 标注    │ - 几何编辑     │
│ - 搜索         │ - 主地图                                     │ - 地图统计     │
│ - 图层树       │ - 缩放工具                                   │ - 设置入口     │
│ - 素材区       │ - 图例 / 统计 / 版本卡片                     │              │
└───────────────┴─────────────────────────────────────────────┴──────────────┘
```

布局重点：

- 左栏不是单纯列表，而是“地点树 + 图层树 + 素材入口”的导航面板
- 中栏上方是模式工具条，中间是主画布，下方是地图说明和统计摘要
- 右栏不是传统 inspector，而是“Inspector + 地图设置”面板，AI 协作将单独接入 `AiChatPanel`

### 8.1.2 参考图视觉方向

参考图的视觉语言值得保留的点：

- 大面积留白和浅暖底色，让地图像纸面工作台
- 工具栏像桌面设计软件，按钮轻、线条细、层次平
- 地图主体使用高圆角卡片包裹，和信息卡片形成统一系统
- 底部摘要卡片不是弹窗，而是地图的一部分，增强“编纂感”

Reveric 内的落地建议：

- 主色沿用 `RevericColors.cartographer`
- 卡片底色使用 `surface` / `surfaceContainerHigh`
- 边框优先 `borderSubtle`
- 工具栏按钮尽量使用紧凑高度 `RevericSizes.buttonHeightSm`
- 地图卡片、信息卡片统一使用 `RevericRadius.x2l`

### 8.1.3 中央画布区域的推荐结构

中央区不建议只有一个 `MapCanvas`，而建议分成四层：

1. 顶部标题区
   - 地图名
   - 当前视图层级
   - 保存状态
2. 工具栏区
   - 层级切换 tab：世界 / 区域 / 城市 / 图层
   - 工具：选择 / 绘制区域 / 添加城市 / 路线 / 地标 / 文本 / 测量
3. 主画布区
   - 地图本体
   - 缩放按钮
   - 选中高亮
   - 绘制草图
4. 底部信息区
   - 图例
   - 势力统计
   - 重要地点
   - 地图版本

### 8.1.4 左侧栏推荐信息结构

左侧栏建议由三段组成：

1. `Location Library`
   - 世界地图
   - 大陆
   - 王国
   - 城市
   - 势力领地
   - 路线
   - 地标
2. `Layers`
   - 边界层
   - 路线层
   - 城市层
   - 地标层
   - 注释层
3. `Assets`
   - 背景图
   - 样式模板
   - 图标素材

这样更接近参考图的“项目导航”感，也更适合后续扩展。

### 8.1.5 右侧检查器结构

右侧面板当前承担：

- 选中地点详情编辑（名称、描述、类型、父级、标签、子地图）
- 几何参数编辑（point/rect）
- 地图统计摘要
- 地图设置入口

AI 协作功能已移除嵌入式实现，后续将接入 `lib/desktop/widgets/ai/chat_panel.dart`（`AiChatPanel`）作为独立的 AI 协作区，而非嵌入 Inspector 内部。

### 8.1.6 Phase 1 视觉取舍

第一阶段不必完整还原参考图中的全部历史版本卡、势力统计卡和复杂工具，但建议优先保留这些骨架：

- 三栏布局
- 中央地图卡片
- 顶部轻量工具条
- 底部 3 到 4 张摘要卡
- 右侧 Inspector + 地图设置入口（AI 协作独立接入 `AiChatPanel`）

这样即便交互尚未全部接通，视觉和结构也已经进入正确方向。

### 8.2 编辑模式

建议扩展 `MapEditorMode`：

```dart
enum MapEditorMode {
  select,
  pan,
  createPoint,
  drawRect,
  dragFromLibrary,
  addConnection,
}
```

### 8.3 区域框选新建

流程：

1. 用户切换到 `drawRect`
2. 鼠标按下记录起点
3. 拖拽时显示半透明框
4. 鼠标抬起后计算 `rect geometry`
5. 打开“新建 Location”表单
6. 保存后创建：
   - `Location`
   - `MapFeature(geometryType=rect)`

需要补充的控制器状态：

- `draftRectStart`
- `draftRectCurrent`
- `draftGeometry`
- `draggingLibraryLocationId`
- `selectionBounds`

### 8.4 先建 Location 再拖进地图

流程：

1. 用户在左栏创建或选择一个 `Location`
2. 拖拽到画布
3. 落点时根据类型生成默认 `MapFeature`
4. 打开轻量确认面板，允许修改类型和尺寸

默认策略：

- 城市、地标、建筑：生成 `point`
- 国家、地区、森林、山脉、平原：生成 `rect`

### 8.5 点击查看信息

选中 `MapFeature` 后右栏显示：

- 名称
- 类型
- 父级路径
- 描述
- 标签
- 坐标或区域尺寸
- 连接关系
- 子地图入口

支持操作：

- 聚焦到该地点
- 放大查看
- 打开子地图
- 删除该地图中的表现
- 仅删除 feature，不删除底层 location

### 8.6 扩大、缩小与聚焦

保留 `InteractiveViewer` 作为基础缩放能力，同时增加语义缩放：

- 远视图只显示大区域和主城市
- 中视图显示地区和城市
- 近视图显示街区、建筑、房间

建议由 `styleJson` 控制：

```json
{
  "showLabel": true,
  "minScale": 0.3,
  "maxScale": 4.0
}
```

---

## 九、渲染架构

当前 `MapCanvas` 需要从“marker 渲染器”升级为“feature 渲染器”。

建议拆分为：

- `MapCanvas`
- `MapBackgroundLayer`
- `MapGridLayer`
- `MapConnectionLayer`
- `MapFeatureLayer`
- `MapSelectionLayer`
- `MapOverlayLayer`

`MapFeatureLayer` 再按几何类型分发：

- `PointFeatureRenderer`
- `RectFeatureRenderer`
- `PolygonFeatureRenderer`

### 9.1 不同类型的视觉策略

第一阶段先做轻量样式：

- 城市：图标 + 标签
- 山脉：边框较硬、偏褐色
- 平原：浅绿色半透明
- 森林：绿色半透明
- 国家/地区：描边 + 大区域标签

第二阶段再考虑：

- 纹理填充
- 标签避让
- 更复杂的样式模板

---

## 十、数据库演进与迁移

### 10.1 迁移目标

将现有：

- `MapLocations`

逐步迁移为：

- `MapFeatures`

### 10.2 迁移策略

建议采用兼容期迁移：

1. 新增 `MapFeatures` 表
2. 编写 migration，把 `MapLocations` 转成 `MapFeatures`
3. 旧记录统一映射为：
   - `geometryType = point`
   - `geometryJson = {"x": ..., "y": ...}`
4. 新代码优先读取 `MapFeatures`
5. 验证完成后再逐步下线 `MapLocations`

### 10.3 `LocationConnections` 的处理

短期方案：

- `LocationConnections` 改为引用 `featureId`

或兼容方案：

- 允许连接引用旧 `mapLocationId`
- 在 feature 迁移完成后统一切换到 `sourceFeatureId/targetFeatureId`

建议最终统一到 feature 层，避免“区域地点”和“点位地点”分开处理。

---

## 十一、服务层设计

建议新增统一服务，而不是继续在 UI 中零散调用多个简单 CRUD。

### 11.1 建议服务

- `MapFeatureService`
- `MapDocumentService`
- `MapImportExportService`
- `MapAiGenerationService`

### 11.2 关键事务

#### `createLocationWithFeature`

同时创建：

- `Location`
- `MapFeature`

适合“框区域后新建”。

#### `placeExistingLocationOnMap`

把已有 `Location` 放到当前地图中。

#### `importMapDocument`

解析 JSON、做校验、批量写库。

#### `applyMapPatch`

执行 AI 生成的 patch 操作，并支持预览。

---

## 十二、UI 组件拆分建议

建议替换当前“一个大面板承载全部逻辑”的方式，拆成：

- `MapEditorShell`
- `MapLocationLibraryPanel`
- `MapCanvasViewport`
- `MapInspectorPanel`
- `MapToolbar`
- `MapCreateLocationDialog`
- `MapFeatureInfoCard`

控制器建议拆分：

- `MapEditorController`
  - 当前模式
  - 当前选中要素
  - 当前缩放状态
  - 当前草图几何
- `MapSelectionController`
  - 多选
  - 框选
- `MapViewportController`
  - 平移、缩放、聚焦

---

## 十三、分阶段实施

### Phase 1：建立正确抽象

目标：做出能用的第一版。

范围：

- 新增 `MapFeatures`
- 支持 `point + rect`
- 左侧 `Location Library`
- 右侧 `Inspector`
- 工具栏支持 `drawRect`
- 支持“框区域创建 location”
- 支持“拖拽已有 location 到地图”
- 支持 JSON 导入导出
- AI 先支持“生成 JSON 草稿”

### Phase 2：提升编辑体验

范围：

- 多选和框选
- 对齐辅助线
- 缩放分级显示
- 更完整的连接关系编辑
- 子地图跳转
- AI patch 预览和增量修改

### Phase 3：提升表现力

范围：

- `polygon`
- 样式模板
- 区域纹理
- 智能标签避让
- 历史版本
- 撤销重做

---

## 十四、推荐的最小可行版本

如果以最快速度交付一个接近目标图体验的版本，建议先做：

1. 保留背景图
2. 新增 `MapFeatures`
3. 支持 `point` 和 `rect`
4. 左侧树状 `Location Library`
5. 工具栏增加“框区域”
6. 点击 feature 后右侧显示详情
7. 支持 JSON 导入导出
8. AI 生成地图 JSON 草稿

这样已经可以覆盖以下核心诉求：

- 随便框一个区域新建 location
- 先建 location 再拖进地图
- JSON 表示地图数据
- location 有层级和类型
- 点击 location 看信息并缩放聚焦

---

## 十五、结论

地图编辑器的关键不是继续增强“图钉”，而是引入统一的 `MapFeature` 抽象，让地图支持点位和区域两种表达。基于这个抽象，再补齐左侧地点库、右侧检查器、JSON/AI 协议和子地图机制，才能真正接近互动地图的编辑体验。

建议按 `Phase 1 -> Phase 2 -> Phase 3` 分阶段推进，先完成 `point + rect + JSON + Location Library + Inspector` 这一最小闭环。

---

## 十六、数据表变更草案

这一节给出和当前实现对接的最小变更方案，目标是尽量少打断现有功能。

### 16.1 `Locations` 扩展

当前 `Locations` 已有：

- `id`
- `name`
- `description`
- `type`
- `parentId`
- `tags`
- `status`
- `sortOrder`
- `createdAt`
- `updatedAt`

建议新增：

```dart
TextColumn get metaJson => text().nullable()();
```

用途：

- `defaultChildMapId`
- AI 生成的补充结构
- 自定义类型附加属性

### 16.2 新增 `MapFeatures`

建议新增：

```dart
class MapFeatures extends Table {
  TextColumn get id => text()();

  TextColumn get mapId => text()();

  TextColumn get locationId => text()();

  TextColumn get geometryType => text()();

  TextColumn get geometryJson => text()();

  TextColumn get styleJson => text().nullable()();

  TextColumn get labelJson => text().nullable()();

  IntColumn get zIndex => integer().withDefault(const Constant(0))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

### 16.3 `LocationConnections` 升级方向

当前表字段：

- `sourceMapLocationId`
- `targetMapLocationId`

建议最终升级为：

- `sourceFeatureId`
- `targetFeatureId`

但第一阶段不建议一次性硬切，推荐两步走：

1. 先保留旧结构，新增 feature 层后内部做映射
2. Phase 2 再把连接端点迁移到 feature

### 16.4 `NovelMaps.settingsJson` 建议结构

当前已有 `settingsJson`，建议正式定义结构：

```json
{
  "background": {
    "imageAssetId": "asset_xxx",
    "imagePath": "/path/to/image.png",
    "fit": "cover",
    "opacity": 0.92
  },
  "grid": {
    "enabled": true,
    "size": 50
  },
  "viewport": {
    "initialScale": 0.8,
    "initialX": 0,
    "initialY": 0
  }
}
```

### 16.5 迁移脚本思路

旧 `MapLocations` 向新 `MapFeatures` 的迁移规则：

```text
MapLocation.id         -> MapFeature.id
MapLocation.mapId      -> MapFeature.mapId
MapLocation.locationId -> MapFeature.locationId
x/y                    -> geometryJson(point)
styleJson              -> styleJson
sortOrder              -> sortOrder
```

默认转换：

```json
{
  "geometryType": "point",
  "geometry": {
    "x": 420,
    "y": 128
  }
}
```

---

## 十七、代码落点建议

这一节给出和当前工程结构对应的文件拆分建议，方便直接开工。

### 17.1 数据库层

已有文件：

- `lib/shared/database/novel_content_database.dart`

需要修改：

- 新增 `MapFeatures` 表
- 给 `Locations` 增加 `metaJson`
- 更新 `@DriftDatabase(tables: [...])`
- 重新生成 `novel_content_database.g.dart`

### 17.2 Service 层

已有文件：

- `lib/shared/services/maps_service.dart`

建议拆分为：

- `lib/shared/services/maps/locations_service.dart`
- `lib/shared/services/maps/maps_service.dart`
- `lib/shared/services/maps/map_features_service.dart`
- `lib/shared/services/maps/location_connections_service.dart`
- `lib/shared/services/maps/map_document_service.dart`
- `lib/shared/services/maps/map_import_export_service.dart`

如果第一阶段不想拆太散，也可以先保留一个文件，但类边界要先分清：

- `LocationsService`
- `MapsService`
- `MapFeaturesService`
- `LocationConnectionsService`
- `MapDocumentService`

### 17.3 Provider 层

已有文件：

- `lib/shared/providers/maps_providers.dart`

建议新增：

- `mapFeaturesServiceProvider`
- `mapFeaturesProvider`
- `mapFeatureByIdProvider`
- `mapDocumentProvider`
- `locationTreeProvider`

推荐 provider 设计：

```text
locationsProvider
mapsProvider
mapFeaturesProvider(mapId)
locationConnectionsProvider(mapId)
locationTreeProvider(databasePath)
mapDocumentProvider(mapId)
```

其中：

- `locationTreeProvider` 用于左侧树状库
- `mapDocumentProvider` 用于导出、AI 生成预览、调试

### 17.4 Widget 层

当前文件：

- `lib/desktop/widgets/map_editor_panel.dart`
- `lib/shared/widgets/maps/map_canvas.dart`
- `lib/shared/widgets/maps/map_editor_controller.dart`
- `lib/shared/widgets/maps/map_editor_toolbar.dart`
- `lib/shared/widgets/maps/map_location_marker.dart`

建议重构为：

#### Desktop 入口

- `lib/desktop/widgets/map_editor_panel.dart`
  - 只负责整体布局和 provider 装配

#### Shared widgets

- `lib/shared/widgets/maps/map_editor_shell.dart`
- `lib/shared/widgets/maps/map_location_library_panel.dart`
- `lib/shared/widgets/maps/map_inspector_panel.dart`
- `lib/shared/widgets/maps/map_canvas.dart`
- `lib/shared/widgets/maps/map_feature_layer.dart`
- `lib/shared/widgets/maps/map_selection_overlay.dart`
- `lib/shared/widgets/maps/map_editor_toolbar.dart`
- `lib/shared/widgets/maps/map_create_location_dialog.dart`

#### Feature renderer

- `lib/shared/widgets/maps/renderers/point_feature_renderer.dart`
- `lib/shared/widgets/maps/renderers/rect_feature_renderer.dart`
- `lib/shared/widgets/maps/renderers/polygon_feature_renderer.dart`

### 17.5 Controller / state 层

当前：

- `MapEditorController` 只覆盖基础选中和缩放

建议扩展或拆分：

- `MapEditorController`
  - mode
  - selectedFeatureId
  - hoveredFeatureId
  - draftRect
  - draggingLibraryLocationId
- `MapViewportController`
  - 视图变换
  - 聚焦指定 feature
- `MapSelectionController`
  - 框选范围
  - 多选集合

如果第一阶段要控制复杂度，建议先保留单控制器，但增加字段：

- `selectedFeatureId`
- `hoveredFeatureId`
- `draftRectStart`
- `draftRectCurrent`
- `isDrawingRect`
- `draggingLocationId`

### 17.6 Localization

当前地图编辑器已接入一部分 i18n。第一阶段新增文案时，记得同步更新：

- `lib/shared/localization/locale_keys.dart`
- `assets/translations/en.json`
- `assets/translations/zh-CN.json`

需要新增的文案类别：

- 区域绘制
- 拖拽放置
- 地点库
- 子地图
- 导入导出 JSON
- AI 生成地图

---

## 十八、Phase 1 开发任务拆解

下面按推荐顺序拆成可以直接执行的开发任务。

### 18.1 Task 1：数据库扩展

目标：

- 新增 `MapFeatures`
- `Locations` 增加 `metaJson`

修改文件：

- `lib/shared/database/novel_content_database.dart`
- `lib/shared/database/novel_content_database.g.dart`

验收标准：

- 新表可生成
- 旧数据不丢失
- 数据库可正常打开

### 18.2 Task 2：新增 `MapFeaturesService`

目标：

- 支持 feature 的 CRUD
- 支持 `point` / `rect` 创建
- 支持按 `mapId` watch

建议接口：

```dart
Future<String> createPointFeature({...})
Future<String> createRectFeature({...})
Future<void> updateFeatureGeometry({...})
Future<void> updateFeatureStyle({...})
Future<void> deleteFeature(String id)
Stream<List<MapFeature>> watchMapFeatures(String mapId)
```

验收标准：

- 可单独读写 feature
- geometryJson 编解码稳定

### 18.3 Task 3：Provider 接入

目标：

- 在现有 Riverpod 层接入 `mapFeaturesProvider`

修改文件：

- `lib/shared/providers/maps_providers.dart`

验收标准：

- UI 可直接 watch 当前地图的 features
- provider 命名与现有 maps provider 风格保持一致

### 18.4 Task 4：画布升级为 feature 渲染

目标：

- `MapCanvas` 不再直接面向 `MapLocationMarker`
- 改为面向 `MapFeature`

优先保留：

- 背景图
- 缩放
- 网格

新增：

- point feature 渲染
- rect feature 渲染
- 选中高亮

验收标准：

- 点位和区域都能画出来
- 缩放后显示正常
- 选中状态正确

### 18.5 Task 5：框区域创建 Location

目标：

- 新增 `drawRect` 模式
- 鼠标拖出矩形后弹出创建表单

实现步骤：

1. controller 记录拖拽起点和当前点
2. overlay 绘制草图矩形
3. 抬起后得到 rect geometry
4. 调用 `createLocationWithFeature`

验收标准：

- 能用鼠标拖出区域
- 能创建 `Location + MapFeature`
- 新创建区域立即出现在地图上

### 18.6 Task 6：左侧 `Location Library`

目标：

- 展示所有 location
- 支持树状层级
- 支持拖拽到画布

第一阶段可先不做复杂筛选，只做：

- 搜索框
- 展开/收起
- 拖拽放置

验收标准：

- 现有 location 可拖到地图
- 城市类默认生成 point
- 区域类默认生成 rect

### 18.7 Task 7：右侧 `Inspector`

目标：

- 选中 feature 时显示地点信息和几何信息

---

## 十九、当前开发进度

### 已完成

- [x] `MapFeatures` 表 + `Locations.metaJson` — 数据模型落地，旧 `MapLocations` 已迁移为 `point feature`
- [x] `LocationConnections.sourceFeatureId` / `targetFeatureId` — 连接端点向 feature 迁移，自连接校验
- [x] `point` / `rect` / `polygon` 三种几何 — 创建、渲染、拖拽移动；rect 支持 resize 手柄
- [x] 框区域创建 Location、左侧拖拽落图 — 交互链路打通
- [x] Inspector 编辑地点元数据 — 名称、描述、类型、父级、标签、子地图
- [x] Inspector 编辑几何 — point/rect 可编辑坐标宽高，polygon 显示顶点数+边界
- [x] 多选与框选 — 选择模式框选（含 polygon）、批量高亮、批量删除并清理连接
- [x] 子地图跳转 — `metaJson.defaultChildMapId`，Inspector 可直接打开
- [x] 图层系统 — `MapLayers` 表 + service（含默认图层初始化），`layerId` 关联 feature
- [x] 图层显隐 — 画布按 `isVisible` 过滤渲染
- [x] 图层锁定 — 锁定图层上 feature 禁止拖拽和 resize
- [x] 图层导入导出 — `MapDocumentLayerNode`，导入导出含完整图层数据
- [x] JSON 导入导出 — `MapDocumentService` 完整 round-trip（map + locations + features + connections + layers）
- [x] Location 层级防护 — 循环引用校验、父节点存在校验、`deleteLocation` 级联（子节点脱父+清理 feature/connection）
- [x] 层级辅助查询 — `getAncestorIds`、`getDescendantIds`、`getFullPath`
- [x] 撤销/重做 — `MapUndoService` 快照双栈（50 步），`Cmd+Z` / `Cmd+Shift+Z` 快捷键，关键操作前自动 `takeSnapshot`
- [x] 撤销/重做 provider 刷新 — 撤销/重做后自动 `invalidate` 所有地图 Provider
- [x] i18n — 硬编码中文修复，polygon/图层 相关 key 已补充 EN/ZH 翻译
- [x] 工具栏 icon-over-label — 工具按钮改为图标在上、文字在下的竖排布局，与设计稿对齐
- [x] 工具栏禁用占位 — "文本"和"测量"工具以 disabled 态显示，Tooltip 提示"即将推出"
- [x] 区域颜色体系 — `_resolveLocationFill` 改为按 location 级别着色：国家/区域使用 golden-ratio 哈希分配色相，山脉/森林/水域/平原使用固定特征色
- [x] 区域渲染升级 — rect/polygon 使用 `RadialGradient` 填充 + 双层边框 + `BoxShadow` 内发光
- [x] 地图标签系统 — `_cartographicLabelStyle` 按 location type 分三档字号（heading2/body/uiSemibold），自动缩放适配区域大小，带文字阴影增强可读性
- [x] 地图标签居中 — polygon/rect 标签从左上角改为几何中心居中
- [x] 点位标签增强 — 城市/地标使用 `uiSmallSemibold`，背景半透明底板 + 文字阴影
- [x] 地形纹理基础版 — `TerrainPatternPainter` 按 location type 在 feature 几何内绘制：山脉正弦脊线、森林圆点、水域波纹、平原草丛
- [x] "世界"视图全量显示 — "世界" tab 不再过滤类型，显示所有 feature
- [x] 移除全局地形色块 — 删除 `_paintTerrainBands`，只保留纸张纹理底图
- [x] 演示数据 — `demo_map_data.dart` 提供完整设计稿级别 JSON（4 国 + 3 海 + 山脉/森林/平原/河流 + 8 城市/地标 + 7 连线），可通过 Inspector 魔术棒按钮一键加载

### 已实现但仍是过渡态

- [ ] `MapLocations` 兼容层 — 旧表仍存在于渲染/删除路径，待彻底下线
- [ ] Inspector 布局 — 已是功能卡片形态，AI 聊天已移除（将接入 `AiChatPanel`）
- [ ] 左侧地点库 — 搜索框未接通，Layers/Assets 区域为静态占位，未接入实际图层数据
- [ ] polygon Inspector — 仅只读显示，不支持顶点拖拽编辑
- [ ] 图层 UI 管理面板 — 底层能力就绪，但缺少图层列表、显隐/锁定切换控件
- [ ] 地形纹理 — 当前 `TerrainPatternPainter` 使用简单几何图案（正弦线、圆点、短线），视觉效果偏技术图而非手绘风。需要升级为仿手绘程序化地形（见 Phase H 方案）

### 尚未完成

- [ ] 地图 AI 协作 — 已移除嵌入式 `MapAiMessage` 占位，待接入 `AiChatPanel`（`lib/desktop/widgets/ai/chat_panel.dart`）
- [ ] AI patch 应用链路 — 结构化 diff / 预览 / 确认 / 落库事务
- [ ] 图层 UI 管理面板 — 图层列表、显隐/锁定切换开关、拖拽排序
- [ ] 路线几何表示 — 连接目前仅"起点-终点"，缺少折线/曲线路径
- [ ] 设计稿级 UI 还原 — 左侧工作区树、中央顶部工具条+底部信息区、成品地图卡片视觉（AI 协作区单独接入 `AiChatPanel`）

### 当前阶段判断

数据层 + 交互层已超额完成。画布视觉已从"技术原型"推进到"带颜色的编辑器"，但距设计稿的手绘地图风格仍有明显差距。后续重心按优先级排序：

1. **地形纹理仿手绘升级**（Phase H）— 当前最大视觉短板
2. 按设计稿重构工作台 UI（AI 协作区接入 `AiChatPanel`）
3. AI patch 应用链路

---

## 二十、Phase 1 验收清单

- [x] 1. 打开一张地图，看到背景图和已有 feature（point/rect/polygon）
- [x] 2. 在左侧看到地点库（按类型分组，可拖拽）
- [x] 3. 将一个已有城市拖到地图中，生成点位
- [x] 4. 将一个区域类地点拖到地图中，生成矩形区域
- [x] 5. 使用“框区域”工具直接新建一个 location
- [x] 6. 点击任意 feature，在右侧查看/编辑详情
- [x] 7. 放大、缩小、聚焦到某个地点
- [x] 8. 导出整张地图 JSON（含 layers）
- [x] 9. 通过 JSON 重新导入并恢复地图（完整 round-trip）
- [ ] 10. 使用 AI 生成一张地图草稿并手动确认导入（嵌入式 AI 聊天已移除，将接入 `AiChatPanel`）

9/10 项已完成。

---

## 二十一、Phase 2 — 设计稿对齐：核心地图能力升级

> 触发：用户参考新版设计稿提出"地图核心部分"优化诉求，重点是不规则区域、颜色/地形支持、势力统计、版本卡、底部 5 项指标条。本节记录 **Phase A（不规则区域）** 已落地的范围，后续阶段在文末补充。

### 21.1 现状盘点（2026-05-04 更新）

| 能力 | 数据层 | 渲染层 | 交互层 | 备注 |
| ---- | ---- | ---- | ---- | ---- |
| Point feature | ✅ | ✅ 带背景底板+文字阴影 | ✅ | "添加城市" / "地标" 工具 |
| Rect feature | ✅ | ✅ RadialGradient + 双边框 + 内发光 | ✅ "绘制区域" | |
| Polygon feature | ✅ | ✅ RadialGradient shader + 内发光 + 双描边 | ✅ 绘制 / 顶点编辑 | Phase A 补齐 |
| 颜色按 location | ✅ | ✅ 国家用 golden-ratio 色相分配，地形用固定特征色 | ✅ | 不再是统一 accent |
| 颜色用户自定义 | 字段已有 `MapFeature.styleJson` | ❌ 未读取 | ❌ | Phase B 待做 |
| 地形纹理 | — | ⚠️ `TerrainPatternPainter` 简单几何图案 | — | Phase H 待升级为仿手绘 |
| 连线类型样式区分 | `LocationConnection.type` ✅ | ❌ 都画成虚线 | ❌ | Phase D 待做 |
| 工具栏 | — | ✅ icon-over-label + 禁用占位 | ✅ | Phase F 已完成 |
| 地图标签 | — | ✅ 类型分档字号 + 居中 + 自动缩放 + 阴影 | — | `_cartographicLabelStyle` |
| 演示数据 | ✅ `demo_map_data.dart` | — | ✅ Inspector 魔术棒按钮 | 4国+3海+城市+连线 |

### 21.2 用户决策（与本阶段相关）

1. 多边形绘制交互：**单击加点 + 双击/Enter 闭合 + Esc 取消**（桌面 GIS 标准）
2. **要做** Rect → Polygon 一键转换按钮，降低首次创建成本
3. 势力卡数据源：复用 `item_entries` 中 `entityTypeFaction`（Phase G）
4. 版本卡：方案 A — 只显示当前版本 + 最后修改时间（Phase G）
5. 不做"保存"按钮，保留自动持久化
6. 工具栏只是壳，**重点在地图本体能力**
7. 地标先做（Phase C 占位 wire 完成）
8. 文本 / 测量 后续再做

### 21.3 Phase A 实现清单 — 不规则区域全链路

#### 控制器（[`map_editor_controller.dart`](../../lib/shared/widgets/maps/map_editor_controller.dart)）

- 枚举 `MapEditorMode` 增加 `drawPolygon`、`addLandmark`
- 字段：`_draftPolygonPoints: List<Offset>`、`_draftPolygonCursor: Offset?`
- 方法：
  - `addPolygonPoint(Offset)` — 点击加点
  - `updatePolygonCursor(Offset?)` — 鼠标移动实时预览
  - `finishPolygon()` — 返回点列表，少于 3 个返回 null
  - `cancelDraftPolygon()` — Esc 取消
  - `removeLastPolygonPoint()` — 备用退一步
- `setMode` / `clearSelection` 切换或清理时同步清空 polygon 草稿状态

#### 画布（[`map_canvas.dart`](../../lib/shared/widgets/maps/map_canvas.dart)）

**绘制态交互**

- `InteractiveViewer.panEnabled / scaleEnabled` 在 `drawPolygon` 模式禁用平移缩放，避免误触
- 外层包 `MouseRegion`：`onHover` → `controller.updatePolygonCursor`，`onExit` 清空
- `GestureDetector.onTapUp` → 加点；`onDoubleTap` → `finishPolygon` + 回调 `onPolygonDrawn(points)`

**绘制态预览** — 新增 `_PolygonDraftPainter`：

- 已加点之间画实线
- 3 点以上预览半透明填充
- 最后点到鼠标画虚线，并预览鼠标 → 首点的闭合虚线
- 首点用空心圈（白心 + 彩边）便于识别"回到起点"
- 其余顶点用实心彩点

**已落地 polygon 顶点编辑** — 选中 polygon feature 时在 `_buildPolygonFeature` 内叠加：

- `_buildPolygonVertexHandles`：每个顶点一个白底彩边圆点（14px），可拖拽更新坐标，右键删除（保留 ≥ 3 顶点）
- `_buildPolygonInsertHandles`：每条边中点显示带 `+` 号的小圆，单击插入新顶点
- 抽出 `_polygonGeometry(points)` 工具方法统一计算 `bounds`，避免内联多处重复

**信号路径**：所有顶点修改通过现有 `onFeatureGeometryChanged` 回调写回，复用 panel 已有的 `MapFeaturesService.updateFeature` 流程。

#### Shell / 工具栏（[`map_editor_shell.dart`](../../lib/shared/widgets/maps/map_editor_shell.dart)）

- `MapEditorTool` 增加 `drawPolygon`（`Icons.polyline_outlined`）+ `addLandmark`（`Icons.star_outline`）
- `_toolToMode` 映射对应新模式

#### Panel（[`map_editor_panel.dart`](../../lib/desktop/widgets/map_editor_panel.dart)）

- `_PlaceLocationOnMap` typedef 新增可选 `initialPolygon: List<Offset>?`
- `_placeLocationOnMap` 优先按 polygon → rect → point 决定 feature 类型，调用 `mapFeaturesService.createPolygonFeature`
- `_showCreateLocationDialog` 与 `_CreateLocationDialog` 透传 `initialPolygon` 给 placement
- `MapCanvas` 新增 `onPolygonDrawn` 回调：takeSnapshot → 弹 create dialog → 选中 + 切回 select 模式
- 工具栏 `onToolPressed` 增加 `drawPolygon` / `addLandmark` 分支
- `_handleCanvasTap` 让 `addLandmark` 走与 `addLocation` 相同的添加流程
- **快捷键**（Shortcuts/Actions）：
  - `Esc` → `_CancelDrawingIntent`：在 drawPolygon / drawRect 模式下取消草稿并切回 select
  - `Enter` / `NumpadEnter` → `_FinishPolygonIntent`：drawPolygon 模式下闭合多边形并触发 create dialog
- Inspector 注入 `onConvertRectToPolygon`：选中 rect 时显示"转为多边形"按钮，用 4 个角点把 rect feature 升级为 polygon，自动 `invalidateProviders`

#### Inspector（[`map_inspector_panel.dart`](../../lib/shared/widgets/maps/map_inspector_panel.dart)）

- 新增 `onConvertRectToPolygon: VoidCallback?` 参数
- 几何区按钮组从 `Row` 改为 `Wrap`，`isRect` 时追加"转为多边形"`OutlinedButton.icon`

#### i18n

- `lib/shared/localization/locale_keys.dart` 增加：`mapEditorDrawPolygon` / `mapEditorPolygonDrawHint` / `mapEditorPolygonNeedMorePoints` / `mapEditorConvertToPolygon` / `mapEditorRemoveVertex` / `mapEditorInsertVertex` / `mapEditorFinishPolygon` / `mapEditorCancelDrawing`
- `assets/translations/zh-CN.json` 已补对应翻译；**`assets/translations/en.json` 待补**（用户指示先聚焦功能，i18n 完善留待最后）

### 21.4 验收用例（Phase A）

- [x] 工具栏出现"不规则区域"和"地标" chip
- [x] 选中"不规则区域"，画布平移/缩放禁用，鼠标 hover 看到虚线预览
- [x] 单击 3 次以上，看到实线边和半透明填充
- [x] 双击或 Enter 完成绘制 → 弹出 create dialog → 选定类型保存为 polygon feature
- [x] Esc 取消绘制，回到 select 模式
- [x] 选中 polygon feature，所有顶点显示白底圆点
- [x] 拖拽顶点更新形状（带 undo 支持）
- [x] 单击边中点 `+` 插入新顶点
- [x] 顶点右键删除（≥ 3 才允许）
- [x] 选中 rect feature，inspector 出现"转为多边形"按钮，点击后 rect → 4 顶点 polygon，可继续拖角变形
- [x] `dart analyze` 通过（仅旧有 unused / build_context_synchronously 警告）

### 21.5 后续阶段（Roadmap，待逐步实现）

- **Phase B 颜色/样式自定义**：`_resolveFeatureFill` 优先读 `styleJson.fillColor / strokeColor / strokeWidth / opacity`；inspector 增"外观"分组（势力色 preset + 自定义）
- **Phase C 地标差异化**：`addLandmark` 模式触发的对话框默认 type=landmark，与"添加城市"区分
- **Phase D 连线样式**：按 `LocationConnection.type`（adjacent → 实线、path_to → 虚线）+ `extraProperties` 自定义；后续做端点重连 / 中段插点
- **Phase E 选中视觉强化**：feature 选中边框 + 外发光 + bbox 四角 L 记号
- ~~**Phase F 工具栏样式**~~：✅ 已完成（icon-over-label + 文本/测量 disabled 占位）
- **Phase G 底部信息区**：势力统计（基于 `entityTypeFaction` + `faction_location_occupies` 计面积/城市数）；地图版本（方案 A）；底部 5 项指标 strip（势力 / 城市 / 地标 / 主路线 / 地图面积）
- **Phase H 仿手绘程序化地形** — 当前最高优先级视觉升级，详见 §21.6

### 21.6 Phase H 方案 — 仿手绘程序化地形渲染

> 目标：用纯 `CustomPainter` 在 feature 几何内绘制接近手绘奇幻地图风格的地形纹理，不依赖外部图片资源。

#### 设计原则

- 每个"笔触"由 2-3 个 Path 组合出明暗和层次感（亮面 + 暗面 + 轮廓）
- 使用确定性随机（基于 feature bounds hashCode 做种子），保证每次重绘结果一致
- 每个 feature 内控制在数百次绘制操作以内，避免性能问题
- 所有颜色基于 feature 的 `fill` 色派生，不引入硬编码色值

#### 按地形类型的绘制方案

##### 山脉 (`mountain`)

多排三角形山峰，前排大后排小产生纵深：

1. **山体**：等腰三角形 Path，左侧面用 `fill` 较亮色填充，右侧面用 `fill` 较暗色填充（模拟光照），用两个三角形半边拼成一座山
2. **山脊线**：山峰顶部连线，用 `fill` 深色细描边（1px）勾勒轮廓
3. **雪顶**：最高的几座山峰顶部叠一个白色小三角（`Colors.white.withAlpha(0.6)`），面积约为山体的 1/5
4. **层叠**：3-4 排山峰，后排 y 偏移更高、尺寸更小、颜色更淡，前排覆盖后排底部
5. **参数**：山峰宽度 `featureSize.width / 8`，高度 `featureSize.height * 0.25`，排间距 `featureSize.height / 5`

##### 森林 (`forest`)

密集的棒棒糖形树木 + 三角针叶树穿插：

1. **落叶树**：细矩形树干（2×6px，深棕色） + 圆形树冠（半径 5-8px，`fill` 色）。树冠上半部分用稍亮色，下半部分用稍暗色（`canvas.drawArc` 分上下半圆）
2. **针叶树**：每隔 4-5 棵穿插一棵三角形（底宽 8px，高 14px），同样有明暗分半
3. **地面阴影**：每棵树底部画一个扁椭圆阴影（`fill` 极低 alpha，4×2px）
4. **密度**：间距约 14-16px 的网格 + 随机偏移 ±4px，产生自然疏密

##### 水域 / 海洋 (`sea`, `lake`, `river`)

海岸深度渐变 + 波纹标记：

1. **深度渐变**：在已有的 RadialGradient 基础上，沿 polygon 边缘向内画 3-4 圈半透明描边（alpha 从 0.35 递减到 0.05，宽度从 8px 递减到 2px），模拟岸边浅水到深水的过渡
2. **波纹**：水平方向的短弧线段（40-60px 长），每段是一条 quadraticBezier 微弧。颜色为白色极低 alpha（0.12）。6-8 排，间距 `featureSize.height / 9`
3. **海岸线加粗**：polygon 外轮廓描边加粗到 2.5px，颜色比水域填充色更深（`fill` darkened 0.3），模拟海岸线

##### 平原 (`plain`)

成簇草丛 + 水平纹理线：

1. **草丛**：3-4 根弧线从同一基点向不同方向散开（`canvas.drawPath` 使用 quadraticBezier），每丛高 6-10px，基点间距约 24px
2. **小灌木**：每隔 5-6 个草丛穿插一个小圆（半径 3px，`fill` 稍深色）
3. **水平纹理**：间距 30-40px 的极细水平线（0.3px，alpha 0.08），贯穿整个区域，营造开阔平坦感

##### 河流 (`river`)

当 polygon 为窄长形时自动识别流向：

1. **流向线**：沿 polygon 长轴方向画 2-3 条贝塞尔曲线，略有弯曲，白色低 alpha（0.15）
2. **河岸阴影**：polygon 两条长边内侧各画一条 3px 宽的深色渐变带
3. **水面高光**：中轴线位置画一条 1px 白色线，alpha 0.1

##### 岛屿 (`island`)

复用森林的树木 + 海岸线渐变：

1. 岛屿内部按森林密度的 60% 散布树木
2. polygon 边缘向内画 2 圈浅蓝渐变带，模拟环岛浅滩

#### 实现文件

- `lib/shared/widgets/maps/map_terrain_painters.dart` — 重写现有 `TerrainPatternPainter`，按上述方案分 6 个私有方法
- 不需要新增文件或修改其他文件，`_buildRectFeature` / `_buildPolygonFeature` 已接入 `TerrainPatternPainter`

#### 验收标准

- [ ] 山脉区域显示多排三角山峰，有明暗面和雪顶
- [ ] 森林区域显示密集树木（落叶树 + 针叶树混合）
- [ ] 水域有海岸深度渐变和波纹标记
- [ ] 平原有草丛和水平纹理
- [ ] 缩放后地形纹理跟随缩放，不模糊不抖动
- [ ] 性能：50 个 feature 的地图在 M1 Mac 上渲染无卡顿

