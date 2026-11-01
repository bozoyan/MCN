# Entity Graph 设计方案

## 概述

为小说创作系统设计实体关系图（Entity Graph），用于连接和管理小说中的各类实体（角色、势力、技能、物品、地点等）及其关系。

## 一、数据表重构

### 1.1 现有结构

```
ItemEntries 表（统一存储）
├── type = 'worldbuilding'  → 世界观
├── type = 'outline'        → 大纲
├── type = 'material'       → 素材
├── type = 'skill'          → 技能
├── type = 'item'           → 物品
└── type = 'faction'        → 势力
```

### 1.2 重构后结构

```
Documents 表（文档类）
├── type = 'worldbuilding'  → 世界观
├── type = 'outline'        → 大纲
└── type = 'material'       → 素材

ItemEntries 表（实体类）
├── type = 'skill'          → 技能
├── type = 'item'           → 物品
└── type = 'faction'        → 势力

Locations 表（独立实体）
└── 地点实体，详见 novel_map.md

EntityRelations 表
└── 存储实体间的关系
```

### 1.3 设计理由

| 类型 | 归属 | 理由 |
|------|------|------|
| 世界观 | Documents | 文档性质，主要是文本内容 |
| 大纲 | Documents | 文档性质，不参与实体关系 |
| 素材 | Documents | 文档性质，灵感碎片，不参与实体关系 |
| 技能 | ItemEntries | 实体性质，参与 Graph 关系 |
| 物品 | ItemEntries | 实体性质，参与 Graph 关系 |
| 势力 | ItemEntries | 实体性质，参与 Graph 关系 |
| 地点 | Locations | 独立实体，有专门的地图功能，详见 novel_map.md |

---

## 二、新增表定义

### 2.1 Documents 表

```dart
class Documents extends Table {
  TextColumn get id => text()();

  TextColumn get type => text()();

  TextColumn get title => text()();

  TextColumn get content => text().withDefault(const Constant(''))();

  TextColumn get status =>
      text().withDefault(const Constant(documentStatusActive))();

  TextColumn get tags => text().withDefault(const Constant(''))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

### 2.2 EntityRelations 表

```dart
class EntityRelations extends Table {
  TextColumn get id => text()();

  TextColumn get sourceType => text()();

  TextColumn get sourceId => text()();

  TextColumn get targetType => text()();

  TextColumn get targetId => text()();

  TextColumn get relationType => text()();

  TextColumn get propertiesJson => text().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

---

## 三、实体类型定义

### 3.1 实体类型枚举

```dart
enum EntityType {
  character,
  faction,
  skill,
  item,
  location,
  chapter,
  foreshadowing,
}

const String entityTypeCharacter = 'character';
const String entityTypeFaction = 'faction';
const String entityTypeSkill = 'skill';
const String entityTypeItem = 'item';
const String entityTypeLocation = 'location';
const String entityTypeChapter = 'chapter';
const String entityTypeForeshadowing = 'foreshadowing';

const List<String> entityTypes = [
  entityTypeCharacter,
  entityTypeFaction,
  entityTypeSkill,
  entityTypeItem,
  entityTypeLocation,
  entityTypeChapter,
  entityTypeForeshadowing,
];
```

### 3.2 文档类型枚举

```dart
enum DocumentType {
  worldbuilding,
  outline,
  material,
}

const String documentTypeWorldbuilding = 'worldbuilding';
const String documentTypeOutline = 'outline';
const String documentTypeMaterial = 'material';

const List<String> documentTypes = [
  documentTypeWorldbuilding,
  documentTypeOutline,
  documentTypeMaterial,
];

const String documentStatusActive = 'active';
const String documentStatusArchived = 'archived';

const List<String> documentStatuses = [
  documentStatusActive,
  documentStatusArchived,
];
```

---

## 四、关系类型定义

### 4.1 角色 ↔ 角色

| 关系类型 | 常量 | 说明 |
|----------|------|------|
| 家族/血缘 | `characterRelationFamily` | 家人、亲戚 |
| 友谊 | `characterRelationFriend` | 朋友 |
| 敌对 | `characterRelationEnemy` | 敌人 |
| 恋爱/婚姻 | `characterRelationLover` | 恋人、配偶 |
| 师徒 | `characterRelationMasterDisciple` | 师父/徒弟 |
| 同事/同门 | `characterRelationColleague` | 同事、同门师兄弟 |
| 上下级 | `characterRelationSubordinate` | 上级/下属 |

### 4.2 角色 ↔ 势力

| 关系类型 | 常量 | 说明 |
|----------|------|------|
| 成员 | `characterFactionMember` | 普通成员 |
| 领导者 | `characterFactionLeader` | 首领、掌门 |
| 创始人 | `characterFactionFounder` | 创始人 |
| 盟友 | `characterFactionAlly` | 盟友关系 |
| 敌对 | `characterFactionEnemy` | 敌对关系 |

### 4.3 角色 ↔ 技能

| 关系类型 | 常量 | 说明 |
|----------|------|------|
| 已学会 | `characterSkillLearned` | 已掌握基础 |
| 精通中 | `characterSkillMastering` | 正在精进 |
| 已精通 | `characterSkillMastered` | 完全精通 |
| 创造者 | `characterSkillCreator` | 技能创造者 |

### 4.4 角色 ↔ 物品

| 关系类型 | 常量 | 说明 |
|----------|------|------|
| 拥有者 | `characterItemOwner` | 当前拥有 |
| 使用者 | `characterItemUser` | 正在使用 |
| 制造者 | `characterItemCreator` | 制造者 |
| 前任拥有者 | `characterItemFormerOwner` | 曾经拥有 |

### 4.5 角色 ↔ 章节

| 关系类型 | 常量 | 说明 |
|----------|------|------|
| 出场 | `characterChapterAppears` | 在章节中出场 |
| 被提及 | `characterChapterMentioned` | 在章节中被提及 |
| 首次出场 | `characterChapterFirstAppearance` | 首次出场章节 |

### 4.6 伏笔 ↔ 章节

| 关系类型 | 常量 | 说明 |
|----------|------|------|
| 埋设于 | `foreshadowingChapterSetup` | 伏笔埋设的章节 |
| 回收于 | `foreshadowingChapterPayoff` | 伏笔回收的章节 |

### 4.7 势力 ↔ 势力

| 关系类型 | 常量 | 说明 |
|----------|------|------|
| 结盟 | `factionFactionAlly` | 结盟关系 |
| 敌对 | `factionFactionEnemy` | 敌对关系 |
| 从属 | `factionFactionSubordinate` | 从属关系（source 为上级） |

### 4.8 技能 ↔ 技能

| 关系类型 | 常量 | 说明 |
|----------|------|------|
| 前置技能 | `skillSkillPrerequisite` | 学习前置条件 |
| 进阶技能 | `skillSkillEvolvesTo` | 进阶方向 |
| 分支 | `skillSkillBranch` | 技能分支 |

### 4.9 物品 ↔ 物品

| 关系类型 | 常量 | 说明 |
|----------|------|------|
| 组成部分 | `itemItemPartOf` | 组成关系 |
| 进化为 | `itemItemEvolvesTo` | 进化/升级 |

### 4.10 章节 ↔ 地点

| 关系类型 | 常量 | 说明 |
|----------|------|------|
| 发生于 | `chapterLocationOccurs` | 章节发生的地点 |
| 涉及 | `chapterLocationInvolves` | 章节涉及的地点 |

### 4.11 关系类型常量定义

```dart
// character → character
const String characterRelationFamily = 'family'; // 泛亲属/血缘
const String characterRelationParent = 'parent'; // 父母（source 为父母）
const String characterRelationSibling = 'sibling'; // 兄弟姐妹
const String characterRelationGrandparent = 'grandparent'; // 祖辈（source 为祖辈）
const String characterRelationFriend = 'friend'; // 朋友
const String characterRelationEnemy = 'enemy'; // 敌人
const String characterRelationLover = 'lover'; // 恋人
const String characterRelationMasterDisciple = 'master_disciple'; // 师徒
const String characterRelationColleague = 'colleague'; // 同事
const String characterRelationSubordinate = 'subordinate'; // 下属（source 为上级）

// character → faction
const String characterFactionMember = 'member'; // 成员
const String characterFactionLeader = 'leader'; // 首领
const String characterFactionFounder = 'founder'; // 创始人
const String characterFactionAlly = 'ally'; // 盟友
const String characterFactionEnemy = 'enemy'; // 敌人

// character → skill
const String characterSkillLearned = 'learned'; // 已学会
const String characterSkillMastering = 'mastering'; // 学习中
const String characterSkillMastered = 'mastered'; // 已精通
const String characterSkillCreator = 'creator'; // 创造者

// character → item
const String characterItemOwner = 'owner'; // 持有者
const String characterItemUser = 'user'; // 使用者
const String characterItemCreator = 'creator'; // 创造者
const String characterItemFormerOwner = 'former_owner'; // 前持有者

// faction → faction
const String factionFactionAlly = 'ally'; // 盟友
const String factionFactionEnemy = 'enemy'; // 敌人
const String factionFactionSubordinate = 'subordinate'; // 下属组织（source 为上级）

// skill → skill
const String skillSkillPrerequisite = 'prerequisite'; // 前置技能
const String skillSkillEvolvesTo = 'evolves_to'; // 进化为
const String skillSkillBranch = 'branch'; // 分支

// item → item
const String itemItemPartOf = 'part_of'; // 组成部分
const String itemItemEvolvesTo = 'evolves_to'; // 进化为

// creature → creature
const String creatureCreatureEvolvesTo = 'evolves_to'; // 进化为
const String creatureCreaturePrey = 'prey'; // 猎物
const String creatureCreaturePredator = 'predator'; // 天敌
```

---

## 五、数据库 Schema 变更

### 5.1 新增表

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
  ],
)
class NovelContentDatabase extends _$NovelContentDatabase {
  // ...
}
```

### 5.2 Schema Version 升级

```dart
@override
int get schemaVersion => 17;

@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (migrator) async {
    await migrator.createAll();
  },
  onUpgrade: (migrator, from, to) async {
    // ... 现有迁移逻辑 ...

    if (from < 17) {
      await migrator.createTable(documents);
      await migrator.createTable(entityRelations);
    }
  },
);
```

### 5.3 数据迁移

数据迁移（将 `worldbuilding`、`outline`、`material` 从 `ItemEntries` 迁移到 `Documents`）通过一次性 SQL 脚本处理，不在代码中实现。

---

## 六、服务层接口

### 6.1 DocumentsService

```dart
class DocumentsService {
  final NovelContentDatabase _database;

  DocumentsService(this._database);

  Stream<List<Document>> watchDocumentsByType(String type);
  Future<List<Document>> getDocumentsByType(String type);
  Future<Document?> getDocumentById(String id);

  Future<String> createDocument({required String type});
  Future<void> updateDocument({
    required String id,
    required String title,
    required String content,
    String? tags,
  });
  Future<void> updateDocumentStatus({
    required String id,
    required String status,
  });
  Future<void> deleteDocument(String id);
  Future<void> reorderDocuments(List<String> ids);
}
```

### 6.2 EntityRelationsService

```dart
class EntityRelationsService {
  final NovelContentDatabase _database;

  EntityRelationsService(this._database);

  Stream<List<EntityRelation>> watchRelationsForEntity({
    required String entityType,
    required String entityId,
    String? relationType,
  });
  Future<List<EntityRelation>> getRelationsForEntity({
    required String entityType,
    required String entityId,
    String? relationType,
  });

  Future<List<EntityRelation>> getRelationsBetween({
    required String sourceType,
    required String sourceId,
    required String targetType,
    required String targetId,
  });

  Future<String> createRelation({
    required String sourceType,
    required String sourceId,
    required String targetType,
    required String targetId,
    required String relationType,
    Map<String, dynamic>? properties,
  });

  Future<void> updateRelation({
    required String id,
    String? relationType,
    Map<String, dynamic>? properties,
  });

  Future<void> deleteRelation(String id);
  Future<void> deleteRelationsForEntity({
    required String entityType,
    required String entityId,
  });

  Future<void> batchCreateRelations(List<EntityRelationsCompanion> relations);
  Future<void> reorderRelations(List<String> ids);
}
```

---

## 七、Graph 查询场景

### 7.1 获取角色的完整关系网络

```dart
Future<Map<String, List<EntityRelation>>> getCharacterNetwork(
  String characterId,
) async {
  final relations = await getRelationsForEntity(
    entityType: entityTypeCharacter,
    entityId: characterId,
  );

  return {
    'characters': relations.where((r) => r.targetType == entityTypeCharacter).toList(),
    'factions': relations.where((r) => r.targetType == entityTypeFaction).toList(),
    'skills': relations.where((r) => r.targetType == entityTypeSkill).toList(),
    'items': relations.where((r) => r.targetType == entityTypeItem).toList(),
    'chapters': relations.where((r) => r.targetType == entityTypeChapter).toList(),
  };
}
```

### 7.2 获取势力的成员列表

```dart
Future<List<EntityRelation>> getFactionMembers(
  String factionId, {
  String? relationType,
}) async {
  return await (select(entityRelations)
    ..where((table) =>
        table.targetType.equals(entityTypeFaction) &
        table.targetId.equals(factionId) &
        table.sourceType.equals(entityTypeCharacter) &
        (relationType != null
            ? table.relationType.equals(relationType)
            : const Constant(true))))
      .get();
}
```

### 7.3 获取伏笔的埋设和回收章节

```dart
Future<Map<String, Chapter?>> getForeshadowingChapters(
  String foreshadowingId,
) async {
  final relations = await getRelationsForEntity(
    entityType: entityTypeForeshadowing,
    entityId: foreshadowingId,
  );

  final setupRelation = relations.firstWhereOrNull(
    (r) => r.relationType == foreshadowingChapterSetup,
  );
  final payoffRelation = relations.firstWhereOrNull(
    (r) => r.relationType == foreshadowingChapterPayoff,
  );

  return {
    'setup': setupRelation != null
        ? await getChapterById(setupRelation.targetId)
        : null,
    'payoff': payoffRelation != null
        ? await getChapterById(payoffRelation.targetId)
        : null,
  };
}
```

### 7.4 获取技能的学习者列表

```dart
Future<List<EntityRelation>> getSkillLearners(
  String skillId, {
  List<String>? relationTypes,
}) async {
  final allowedTypes = relationTypes ?? [
    characterSkillLearned,
    characterSkillMastering,
    characterSkillMastered,
  ];

  return await (select(entityRelations)
    ..where((table) =>
        table.targetType.equals(entityTypeSkill) &
        table.targetId.equals(skillId) &
        table.sourceType.equals(entityTypeCharacter) &
        table.relationType.isIn(allowedTypes)))
      .get();
}
```

### 7.5 获取章节的发生地点

```dart
Future<List<EntityRelation>> getChapterLocations(
  String chapterId, {
  String? relationType,
}) async {
  return await (select(entityRelations)
    ..where((table) =>
        table.sourceType.equals(entityTypeChapter) &
        table.sourceId.equals(chapterId) &
        table.targetType.equals(entityTypeLocation) &
        (relationType != null
            ? table.relationType.equals(relationType)
            : const Constant(true))))
      .get();
}
```

---

## 八、UI 集成建议

### 8.1 关系图可视化

- 使用自定义 Canvas 绘制关系网络
- 节点：角色、势力、技能、物品、地点、章节
- 边：各种关系类型，用不同颜色/线型区分
- 交互：点击节点查看详情，拖拽布局，筛选关系类型

### 8.2 关系编辑界面

- 在实体详情页添加「关系」标签页
- 支持添加/删除/修改关系
- 支持选择关系类型和设置属性

### 8.3 AI 上下文集成

- 将实体关系作为上下文提供给 AI
- AI 写作时自动关联相关角色、势力、技能、地点
- 支持基于关系的智能提示（如：提醒伏笔未回收）

---

## 九、Tasks

### Phase 1：数据库迁移

- [x] 新增 `Documents` 表
- [x] 新增 `EntityRelations` 表
- [x] 通过 SQL 脚本迁移现有 `worldbuilding`、`outline`、`material` 数据
- [x] 更新 `NovelContentDatabase` schema version

### Phase 2：服务层实现

- [x] 实现 `DocumentsService`
- [x] 实现 `EntityRelationsService`
- [x] 更新现有 `NovelContentService`

### Phase 3：Provider 层更新

- [x] 新增 `documentsProvider` 系列
- [x] 新增 `entityRelationsProvider` 系列
- [x] 更新现有 provider 以适配新结构

### Phase 4：UI 适配

- [x] 更新世界观/大纲/素材页面使用 `Documents`
- [ ] 添加关系编辑界面
- [ ] 实现关系图可视化

### Phase 5：AI 集成

- [ ] 将实体关系纳入 AI 上下文
- [ ] 实现基于关系的智能提示
- [ ] 优化 AI 写作时的实体引用

---

## 十、注意事项

1. **数据迁移**：通过 SQL 脚本一次性处理，迁移前需备份数据
2. **向后兼容**：保留 `ItemEntries` 表结构，仅过滤掉已迁移的类型
3. **性能优化**：为 `EntityRelations` 表的 `sourceId`、`targetId` 字段添加索引
4. **关系约束**：删除实体时，需级联删除相关关系
5. **循环检测**：技能前置、势力从属、地点包含等关系需检测循环依赖
