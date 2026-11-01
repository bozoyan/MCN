# 无限画布(Canvas)方案

> 术语定义见 [CONTEXT.md](../../CONTEXT.md) 的 `### Canvas` 节;原方向 [ADR-0013](../adr/0013-canvas-v1-agent-authored-user-read-only.md) 已不适用,本方案为 V1 定稿。落地后同步更新 CONTEXT.md 术语并补 ADR-0014。
>
> **落地状态**:PR-1~PR-4 主体已落地(schemaVersion 11 / `canvas_dao.dart` / `canvas_service.dart` / `canvas_providers.dart` / `lib/desktop/features/canvas/` / `tools_canvas.dart` / `AiToolManager.activeCanvasIdGetter/Setter`)。文中「改动清单」保留为实施记录,已与实际实现对齐;未落地项单独标注「待办」。

## 1. 背景 `[核心]`

### 现状

Reveric 的小说创作资源(角色、章节、大纲、地点、伏笔等)目前以列表 / 树形 / 独立编辑器的方式分散呈现:

- 角色在角色编辑器,章节在章节编辑器,地点在地图编辑器,实体关系在 `entity_graph`。
- `NovelEditor` 通过 `contentSelection`(`lib/desktop/pages/novel_editor.dart#L4050`)在 Main 区域切换不同视图,但每个视图只看一类资源。
- 没有一个地方能把「多个资源摆在一个二维平面上」,让作者自由构思结构、关联、节奏。

已有的几个「图 / 画布」类能力都不是这个定位:

- `map_editor`(`lib/shared/widgets/maps/map_canvas.dart`):地理地图,背景图 + 地点 feature,服务于世界观空间结构,不是通用故事板。
- `entity_graph`(`lib/shared/services/entity_relations_service.dart`):实体关系图,边有强类型语义(家族/敌对/师徒……),是正典业务关系网络(`EntityRelations` 表),由 `CreateRelation` 工具写入、`GraphSearch` 查询,不是自由排版。

### 问题

作者在构思阶段需要把章节片段、角色、情节线索、伏笔、灵感笔记自由摆在一个平面上,看清结构和节奏。现有工具要么只看一类资源,要么是强语义的正典关系图,都不够「自由」:

- 想「把主角和反派的关系画出来看看」——`entity_graph` 要求关系是正典的、有章节证据、有 proof,构思阶段还没定。
- 想「把伏笔埋设到兑现的脉络铺开」——`Foreshadowings` 表只存文本和 setup/payoff 章节锚点,没有可视化。
- 想「让 agent 帮我把角色关系画到画布上,我再手动调」——现有工具没有画布操作入口。

### 约束

- **AGENTS.md metadata 禁令**:不能用 schemaless metadata(JSON)承载画布节点、连线、便签内容这类业务数据;业务关系必须显式建表。节点位置、大小是字段,不入 metadata。
- **novel-scoped**:画布属于具体小说。`NovelContentDatabase` 本身是 per-novel 的,canvas 表不需要 `novelId` 列(与 `CharacterProfiles`/`Foreshadowings`/`NovelMaps` 一致)。
- **桌面先行**:V1 只做桌面端 UI,数据模型预留移动端兼容。
- **复用 Persisted Workspace Entry 体系**:画布是一种 workspace 资源类型,和角色 / 大纲 / 地点平级,通过 `NovelWorkspaceSection` 注册(`lib/shared/models/novel_workspace.dart#L112`);画布**列表**在 `NovelEditor` 侧边栏展示。
- **画布详情为独立页面**:进入某张画布后,跳出 `NovelEditor` 的 `contentSelection` 切换逻辑,使用独立路由页面,专注编辑单张画布;关闭后返回小说编辑器。agent 画布工具只在画布详情页打开时对该画布生效。
- **agent 走 Chat Orchestrator 工具**:画布操作入口是 novel-scoped `AiToolManager` 的工具,不走 Dreaming(V1)。
- **与 `entity_graph` 边界清晰**:canvas 边是视觉组织,不污染正典业务关系。
- **db-migration 规则**:新增表必须 `schemaVersion + onUpgrade + Dart 模型类`三同步(见 [db-migration.md](../../.agents/rules/db-migration.md))。

## 2. 目标 `[核心]`

### 目标

1. 在 `NovelEditor` 侧边栏新增 Canvas 列表;每个小说可有零或多张 Canvas,桌面端可新建 / 打开 / 删除 / 重命名。打开某张画布后进入独立的 `CanvasEditorPage`,专注编辑该画布。
2. **人机共创**:用户可直接在画布上拖拽节点、画连线、写便签、编辑便签;Chat Orchestrator 也可通过画布工具在当前 active Canvas 上做同样操作。两者写入同一套表,实时互见。
3. **强语义节点**:节点分两类——引用型节点(指向现有 Persisted Workspace Entry:角色/章节/伏笔/大纲/地点/物品/势力/技能/生物/文档)和便签节点(画布自有文本)。
4. **强语义边**:边有类型(`relationship` 人物关系 / `causal` 因果 / `timeline` 时间线 / `foreshadow_payoff` 伏笔兑现 / `association` 通用关联),用于表达剧情发展、人物关系、伏笔埋设→兑现。
5. 画布、节点、边各自独立建表(`canvases` / `canvas_nodes` / `canvas_edges`),节点位置/大小是列,不入 metadata。
6. agent 操作**实时同步**显示,用户看着节点出现 / 移动 / 连线生成;用户操作也实时反映给正在读画布的 agent。
7. 引用型节点指向的资源被删除时,画布节点标识为「已失效」而非悄悄消失。

### 非目标

1. **不做就地编辑资源内容**:画布上改角色本体 = 改源头,留待 V2;V1 画布是组织视图,资源内容在各自编辑器改,画布引用节点实时反映源头最新值。
2. **不做 canvas 边进入 entity_graph**:canvas 边只是视觉组织,不作为业务关系被 `GraphSearch` 查询。想正典化一条关系,用 `CreateRelation` 单独写入 `entity_graph`。
3. **不做移动端 UI**:V1 桌面 only;数据模型预留,移动端交互暂不设计。
4. **不做跨画布连线 / 章节锚点连线**:V1 连线只在画布内,连本画布节点。
5. **不做 agent 生成新内容到画布**:V1 agent 只组织现有资源 + 写便签,不在画布上生成章节片段 / 角色草稿等新内容。
6. **不做多人协作 / CRDT / OT**:桌面单用户,last-write-wins 即可(见「已知妥协」)。
7. **不做自动布局**:V1 节点位置由人或 agent 显式放置;自动布局(layout engine)留待 V2。

### 成功信号

| 信号 | 验证方式 |
|------|----------|
| NovelEditor 侧边栏出现 Canvas 列表,可新建 / 打开 / 删除 / 重命名多张画布;打开后进入独立 `CanvasEditorPage` | widget 测试 + 手动检查 |
| 用户能拖拽节点、画连线、写/改便签;agent 通过 chat 工具也能做同样事,两者实时互见 | 手动检查 + 集成测试 |
| 用户能画「人物关系」「因果」「伏笔兑现」等类型化边,边按类型有不同视觉 | widget 测试 |
| agent 被要求「把角色关系画到画布上」时,active Canvas 实时出现引用型节点 + 类型化连线 | 集成测试(agent 工具调用 → DB 写入 → UI stream 更新) |
| 引用的角色被删除后,画布上对应节点显示「已失效」 | widget 测试 |
| 画布数据查询不依赖 metadata JSON 解析(节点/边/便签都在独立表) | 单测(DAO 层) |
| canvas 边不出现在 `EntityRelations` 表中,`GraphSearch` 查不到 | 单测 |

## 3. User Stories `[按需]`

### 核心路径

1. 作为作者,我希望新建一张「角色关系」画布,把相关角色拖上去,手动画线表达关系,以便自由构思人物网络,而不必先给出正典证据。
2. 作为作者,我希望新建一张「情节时间线」画布,把章节和情节便签铺开,用因果/时间线边连起来,以便看清节奏和伏笔脉络。
3. 作为作者,我希望在画布上放伏笔节点,用「伏笔兑现」边连到兑现章节节点,以便一眼看清埋设→兑现的闭环。
4. 作为作者,我希望在侧边栏看到所有画布列表,点击打开后进入独立全屏编辑页,以便按不同视角(角色/情节/伏笔)组织,且编辑时不被侧边栏其他 section 打扰。
5. 作为作者,我希望在画布编辑页中实时看到 agent 操作的节点出现、连线生成、便签写入,以便跟着 agent 的思路走、及时纠偏。

### agent 路径

6. 作为 Chat Orchestrator,我希望当作者打开某张画布详情页时,通过画布工具在该画布上放引用型节点、画类型化连线、写便签,以便把我对小说结构的理解和推理可视化给作者。
7. 作为 Chat Orchestrator,我希望在作者未打开画布页时创建一张画布(或提示作者先打开),以便在无画布状态下也能完成任务。
8. 作为 Chat Orchestrator,我希望读取当前打开的画布内容(节点/边/便签),以便基于作者已有的画布组织继续工作,而不是从零开始。

### 错误 / 失败 / 回滚路径

9. 作为作者,我希望 agent 引用的资源被删除时,画布上的引用节点能明确标识为「已失效」而不是悄悄消失,以便我知道哪些引用悬空了。
10. 作为维护者,我希望 agent 画布工具调用失败时(如 DB 写入失败、无 active Canvas)向 agent 透出结构化错误,而不是静默兜底成「成功」(守 `.agents/rules/error-handling.md`)。
11. 作为作者,我希望误删的节点能撤销(soft-delete + 恢复),而不是永久丢失;边为硬删,删节点时级联删除的边不随节点恢复(V1 妥协,见已知妥协 4)。

### 兼容路径

12. 作为作者,我希望 Canvas 加入 NovelEditor 侧边栏后不影响章节 / 角色 / 大纲等其他 workspace section,以便现有编辑流程零回归。
13. 作为作者,我希望画布只引用现有资源而不复制内容,以便资源在各自编辑器改了之后,画布上看到的就是最新的。

### 维护路径

14. 作为维护者,我希望画布 / 节点 / 边独立建表并有清晰的 migration,以便后续查询、索引、扩展不依赖 JSON 解析。
15. 作为维护者,我希望 agent 画布工具的注册和权限遵循现有 `AiToolManager` 工具体系,以便复用既有 dispatcher 和权限模型,不另起一套。
16. 作为维护者,我希望 canvas 边和 `EntityRelations` 边界清晰,以便不会把构思阶段的随手连线污染成正典业务关系。

## 4. 解决方案 `[核心]`

### 方案对比

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|------|------|------|------|------|
| A. 基于 vyuh_node_flow 构建(本方案) | 使用项目已有的 `lib/third/flow/vyuh_node_flow` 作为画布引擎,通过 adapter 层在 DB 模型与 flow 模型间做双向转换;节点/边/交互/视口/选择/键盘/LOD/小地图全部复用 | pan/zoom/drag/connect/resize/grid/snap/minimap/LOD 开箱即用;CommentNode 自带便签内联编辑/resize/颜色/自动高度;MobX 已是项目依赖 | Connection 基于 port 连线,`CommentNode` 默认 `ports:const[]`,需创建后 `addPort()` 添加隐藏 anchor port;需要写 DB↔flow adapter 层;MobX Controller 与 Riverpod Service 间需双向同步 | **推荐** |
| B. 保持 ADR-0013(agent 创作、用户只读 + 无语义边) | agent 写、用户看;边无类型 | V1 最小;无并发问题 | 不满足「用户随意构思」;无法表达人物关系/伏笔兑现 | 放弃 |
| C. 复用 map_editor 画布层 | 在 `map_canvas` 上加节点/边能力 | 少写画布交互代码 | `map_canvas` 是地图专属(背景图 + 地点 feature + 地形 painter),强耦合地图数据模型,改造量大于基于 vyuh_node_flow 构建;且会污染地图编辑器 | 放弃 |
| D. 纯 Flutter 原生自建(InteractiveViewer+Stack+CustomPainter) | 从零写画布交互 | 完全可控,无依赖 | 需重写 pan/zoom/拖拽/连线/选择/键盘/小地图/LOD 等所有交互,工作量大且容易出交互 bug;vyuh_node_flow 已在项目内,无理由重复造轮子 | 放弃 |

### 决策

推荐方案:**A. 基于 vyuh_node_flow 构建画布交互层,人机共创 + 强语义节点/边,独立三表,DB↔flow adapter 双向同步**。

选择理由:

1. **vyuh_node_flow 已在项目内**:位于 `lib/third/flow/vyuh_node_flow/`,不是新引入的第三方依赖。
2. **交互能力开箱即用**:pan/zoom、节点拖拽、连线、多选/框选、键盘快捷键、网格、snap、自动平移、小地图(minimap)、LOD(远距缩略)、节点 resize、连接动画效果(粒子/流动虚线/脉冲)等,省去从零实现画布交互的大量工作和 bug。
3. **便签复用 CommentNode**:`CommentNode` 已自带内联文本编辑、resize、颜色、自动高度增长,画布便签节点直接复用;由于 `CommentNode` 构造函数 hardcode `ports:const[]`,创建后调用 `addPort()` 动态添加一个隐藏 anchor port 即可支持连线。引用型节点用基础 `flow.Node`+自定义 widgetBuilder,同样挂 anchor port。
4. **adapter 转换与同步分别验证**:转换层负责「领域模型 ↔ flow 模型」映射；画布还需要处理「DB stream 实时写入 → sync 回 flow controller」。用 `isSyncingFromProps` 防止组件内 props/事件回环，并对下行快照做内容比较，验证写入后的同步时机(见核心原则 5、风险表)。
5. **边界清晰**:canvas 边不进 `EntityRelations`,正典关系仍走 `CreateRelation`,构思与正典分离。
6. **复用现有体系**:DAO/Service/Provider/Tool 四层模式与 `entity_graph`/`foreshadowing` 一致;迁移走 `migrateToV8` 同款范式。

拒绝方案:

- **方案 B**:不满足需求。
- **方案 C**:`map_canvas` 与地图数据模型强耦合,改造量超过基于 vyuh_node_flow 构建。
- **方案 D**:vyuh_node_flow 已在项目内且功能完整,自建等于重造轮子(违反 Rule 2 简单优先)。

### 核心原则

1. **canvas 是构思层,不是正典层**:canvas 边只是视觉组织,绝不进入 `EntityRelations`;正典关系走 `CreateRelation`。
2. **引用不复制**:引用型节点只存 `(refType, refId)`,实时反映源头最新值;画布不缓存资源内容。
3. **位置是数据,不是样式**:节点 `x/y/width/height` 是表列,不入 metadata 样式字段。
4. **单一写入入口**:用户操作通过 flow 事件回调 → `CanvasService` 写入;agent 工具直接调 `CanvasService`;不绕过 DAO 直写 DB。
5. **DB 是唯一真相源,flow Controller 是 UI 状态**:用户拖拽等高频交互先在 flow Controller(MobX)中响应用户保证流畅,拖拽结束(onDragStop)才写回 DB;agent/外部写入走 DB → stream → 全量 `loadGraph` 同步到 flow Controller。防循环用 `isSyncingFromProps` 标志;但「stream 实时下行同步」本身是新实现,需对 stream 快照做签名比对(节点/边 id 集合一致则跳过 reload),避免自己写入触发的重发导致 flow controller 频繁 reset、节点跳回旧位置(实现见 `canvas_board.dart` 的 `_sameCanvasContentSignature`)。
6. **节点统一挂 anchor port**:vyuh_node_flow 的 Connection 基于 port 连线,每个 canvas 节点加一个 `PortType.both` 的隐藏 anchor port(不渲染 port 控件),所有连线通过该 port 连接,实现 node-to-node 的自由连线效果。
7. **实时即流式**:canvas 列表用 `StreamProvider` watch DAO;打开 `CanvasEditorPage` 后,该画布内容由 flow Controller 管理高频交互,DB stream 用于接收外部(agent)写入。用户关闭页面后不再实时同步,下次打开重新加载。
8. **错误不静默**:agent 工具失败(无 active canvas / DB 错误 / 引用失效)向 agent 透出结构化错误,不兜底成成功。

### 关键假设

| 假设 | 如果不成立 | 应对 |
|------|------------|------|
| 桌面端单用户,用户与 agent 不会真并发写同一节点 | agent 和用户同时移动同一节点,画面跳动 | last-write-wins;flow Controller 本地即时响应保证拖拽流畅;agent 写入通过 DB stream 同步回来时以本地拖拽状态为准(V1 接受偶尔跳变) |
| active canvas 由 `CanvasEditorPage` 打开时写入 `activeCanvasIdProvider`;`AiToolManager` 工具执行时读取当前 active canvas id | `AiToolManager` 拿不到当前打开的画布页,agent 无法定位目标 | `activeCanvasIdProvider`(keepAlive Notifier,riverpod 3 无 StateProvider)+ 向 `AiToolManager` 注入 `activeCanvasIdGetter`/`activeCanvasIdSetter` 回调;`CanvasEditorPage` 挂载后首个安全帧 `set(canvasId)`,卸载时 `clearIfActive(canvasId)`;不在画布详情页时 canvas 工具返回 `no_active_canvas` |
| `NovelContentDatabase` 是 per-novel,canvas 表无需 `novelId` | 若未来改成单库多小说,需加 `novelId` 列 | 表结构预留 `novelId` 列(默认空,per-novel 库不用),migration 时 backfill;**V1 不加**(与 `CharacterProfiles` 等保持一致,避免孤立) |
| 节点引用的资源类型集合 = `NovelWorkspaceSection` 的可引用资源 | 新增资源类型时 canvas 引用也要跟上 | `refType` 复用 `aiResourceType` 字符串;新增 section 时自动可用 |
| 伏笔已有 `Foreshadowings` 表(状态 pending/planted/payoff/abandoned) | 无需 canvas 重建伏笔模型 | canvas 引用型节点 `refType='foreshadowing'` 直接指向;`foreshadow_payoff` 边链接伏笔节点→章节节点 |
| vyuh_node_flow 的 anchor port 方案可行(每个节点挂一个隐藏 `PortType.both` port;`CommentNode` 创建后调用继承自 `Node` 的 `addPort`) | 已验证可行:所有 `Node` 都有 `addPort`/`removePort`,`CommentNode` 虽构造时 hardcode `ports:const[]`,但创建后仍可通过 `addPort` 动态添加。**注意**:`CommentNode.copyWith`/`fromJson` 会把 ports 重置为空,运行时挂的 anchor port 不随之保留,adapter 每次 `loadGraph` 构建节点后必须重挂 anchor port(见风险表) | V1 采用隐藏 port 实现 node-to-node 自由连线;连线端点默认在 port 所在边,视觉上为边到边,V1 可接受;V2 通过自定义 `ConnectionPainter`/`endpoint_position_calculator` 将端点延伸到节点中心或边缘最近点 |
| DB↔flow 模型转换正确，不代表 DB stream 实时同步也正确；二者需要分别验证 | 实时同步出现回环、节点跳变、选中态丢失等问题 | `isSyncingFromProps` 标志 + stream 快照内容比较(相同快照不重载);agent 连续写入导致的频繁全量 reload 由 stream 侧合并缓解(见风险表「外部写入频繁触发全量 reload」) |

## 5. 方案实施

### 5.1 模型设计 `[按需]`

```text
canvases
- id: text PK
- name: text
- description: text (default '')
- sort_order: integer (default 0)
- created_at: datetime
- updated_at: datetime
- deleted_at: datetime (NOT NULL DEFAULT 0, 软删)

canvas_nodes
- id: text PK
- canvas_id: text (所属画布)
- type: text ('reference' | 'sticky')
- ref_type: text nullable (引用型: 'character'/'chapter'/'foreshadowing'/'outline'/'location'/'item'/'faction'/'skill'/'creature'/'document')
- ref_id: text nullable (引用型: 指向资源 id)
- title: text (default '') — 引用型缓存资源标题用于显示,便签为标题
- content: text (default '') — 便签正文;引用型为空
- x: real (default 0.0)
- y: real (default 0.0)
- width: real nullable
- height: real nullable
- style: text nullable (JsonMapConverter — 颜色/形状等纯视觉,非业务数据)
- z_index: integer (default 0)
- sort_order: integer (default 0)
- created_at, updated_at, deleted_at (软删)

canvas_edges
- id: text PK
- canvas_id: text
- source_node_id: text
- target_node_id: text
- type: text ('relationship' | 'causal' | 'timeline' | 'foreshadow_payoff' | 'association')
- label: text nullable (边上的说明文字)
- created_at, updated_at
- (无 deleted_at — 与 EntityRelations 一致,边硬删;需撤销靠新增)
```

说明:

- **软删策略**:`canvases`/`canvas_nodes` 软删(与 `CharacterProfiles`/`Foreshadowings` 一致,支持恢复);`canvas_edges` 硬删(与 `EntityRelations` 一致,边轻量、重建容易)。这是有意的边界,不是疏漏。
- **`title` 冗余**:引用型节点缓存资源标题用于画布渲染(避免每次渲染都 join 资源表)。值得冗余,因为画布常驻渲染、join 成本高。V1 刷新策略:**统一**由打开画布时调用一次 `refreshReferenceTitlesForCanvas(canvasId)` 校准;不做「各资源 service 更新路径末尾调用 refreshReferenceTitle」的散弹式接入(侵入 N 个 service 且易漏)。画布打开期间源头改名的实时性放弃(见已知妥协 3)。
- **`style` 是 JSON**:只承载纯视觉(颜色/形状/图标),不承载业务判断(守 metadata 禁令,样式不属于业务数据)。
- **`ref_type`/`ref_id` 可空**:便签节点(`type='sticky'`)这两列为空;引用型节点必填。校验在 service 层。
- **唯一约束**:`canvas_edges` 加 `(canvas_id, source_node_id, target_node_id, type)` 唯一索引防重复同型边;`canvas_nodes` 加 `(canvas_id, ref_type, ref_id)` 索引(非唯一,同一资源可在同画布放多个,但鼓励一个)。注意该唯一索引是**有向**的:`relationship`/`association` 语义上常为无向,A→B 与 B→A 可同时存在,视觉上重复;V1 接受(见已知妥协 7),service 层可对无向类型做双向查重优化。

### 5.2 ERD `[按需]`

```text
NovelContentDatabase (per-novel)
  │
  ├── canvases (1) ──< canvas_nodes (N)
  │                       │
  │                       └── ref_type/ref_id ──> CharacterProfiles / Chapters /
  │                                              Foreshadowings / Outlines /
  │                                              Locations / Items / ... (引用,不复制)
  │
  └── canvases (1) ──< canvas_edges (N) ──> canvas_nodes (source / target)
                                            (只在同一 canvas_id 内连)

canvas_edges ──(不进入)──> EntityRelations  (边界:canvas 边是视觉组织,
                                              entity_graph 是正典业务关系,
                                              两者不互通)
```

删除 / 级联策略:

- 删 canvas(软删):其下 nodes 软删、edges 硬删(由 service 级联,DB 层不加外键,守 Drift 现有模式)。
- 删 node(软删):以其为端点的 edges 硬删(service 级联)。
- 删被引用资源(如角色):canvas_nodes 中的引用行**不删**,由 UI 层在渲染时检测源头是否存在,不存在则显示「已失效」(ref_type/ref_id 保留,便于资源恢复后自动恢复显示)。

### 5.3 关键业务流程 `[核心]`

#### 流程 A:用户拖拽节点(人写路径)

```text
User drags node ─> vyuh_node_flow NodeFlowController (MobX) updates position
 ─> onDragStop event fires (拖拽结束才触发,拖拽中不写 DB)
 ─> CanvasBoard 回调 → CanvasService.updateNodePosition(nodeId, x, y)
 ─> CanvasNodeDao.upsert(node with new x/y)
 ─> DB write
 ─> (高频拖拽直接在 flow Controller 响应,UI 丝滑;结束时写 DB 持久化;
     stream 因此重发,签名比对到 id 集合未变,跳过 reload,不打断 UI)
```

#### 流程 B:agent 放置节点(agent 写路径)

```text
LLM calls CanvasAddNode{type:'reference', ref_type:'character', ref_id:'char_xxx', x:100, y:200}
 ─> AiToolManager.executeTool('CanvasAddNode')
 ─> _runMutationTool(previewDiff, run: _handleCanvasAddNode)
 ─> resolve active canvas (via AiToolManager.activeCanvasIdGetter 回调,
    读 activeCanvasIdProvider,由 CanvasEditorPage 生命周期写入/清空)
    ├─ no active canvas ─> return {ok:false, error_code:'no_active_canvas'}
    └─ has active canvas ─> CanvasService.addNode(canvasId, ...)
                            ─> CanvasNodeDao.upsert
                            ─> DB write
                            ─> canvasContentStreamProvider stream emit
                            ─> CanvasBoard 签名比对(节点 id 集合变化) → loadGraph 同步到 flow
                            ─> NodeFlowEditor 实时出现节点
 ─> return {ok:true, node_id, path:'/canvas/{canvasId}/nodes/{nodeId}'}
```

#### 流程 C:实时互见(用户和 agent 同时操作)

```text
User drags node A ─> flow Controller 即时响应 UI(A 移动) ─> onDragStop → DB
Agent 同时 addEdge(A,B) ─> CanvasService.addEdge ─> DB ─> stream ─> 签名比对 → loadGraph
                                              (flow Controller 内 MobX 管理 UI 状态;
                                               DB 为持久化真相源;isSyncingFromProps 防循环;
                                               签名比对使拖拽中的位置类 stream 重发不触发 reload)
```

#### 流程 D:引用失效

```text
User deletes character char_xxx in CharacterEditor
 ─> CharacterProfileDao.softDelete(char_xxx)
 ─> canvas_nodes 中 ref_type='character' ref_id='char_xxx' 行保留
 ─> CanvasWidget 渲染时:
     refId 存在性检查(watch源头资源) ─不存在─> 节点渲染为「已失效」灰态 + 失效图标
                                            └─点击─> 提示「该角色已被删除」
```

#### 失败路径

- agent 工具无 active canvas → 返回 `{ok:false, error_code:'no_active_canvas', message:'请先打开一张画布或用 CanvasCreate 创建'}`,不静默创建。
- DB 写入失败 → try-catch + `[DB]` 日志 + 返回 `{ok:false, error_code:'db_write_failed', message:...}`(守 error-handling.md)。
- 引用资源不存在 → `CanvasAddNode` 校验 ref_id 存在性,不存在返回 `invalid_reference`。

### 5.4 改动清单 `[核心]`

#### `lib/shared/database/novel_content_database.dart`
- 新增表类 `Canvases` / `CanvasNodes` / `CanvasEdges`(参照 `NovelMaps`/`MapLocations`/`Foreshadowings` 的字段风格,软删表带 `deletedAt` 列)。
- 新增常量:`canvasNodeTypeReference='reference'` / `canvasNodeTypeSticky='sticky'`;`canvasEdgeTypeRelationship/causal/timeline/foreshadow_payoff/association` 及 `List<String> canvasEdgeTypes`;`canvasNodeRefTypes`(复用 `entityType*` + `document`/`outline`)。
- `@DriftDatabase(tables:[...])` 增加 `Canvases, CanvasNodes, CanvasEdges`(`lib/shared/database/novel_content_database.dart#L1376`)。
- `schemaVersion` 从 `10` 改为 `11`(现为 `lib/shared/database/novel_content_database.dart#L1597`,已落地)。
- `onUpgrade` 增加 `if (from < 11) { await migrations.migrateToV11(migrator); }`;`onCreate` 同步调用索引创建函数(与 migration 内一致,已落地)。

#### NEW: `lib/shared/database/novel_content_daos/canvas_dao.dart`
- `@DriftAccessor(tables: [Canvases, CanvasNodes, CanvasEdges])` + `part 'canvas_dao.drift.dart';`
- 参照 `lib/shared/database/novel_content_daos/foreshadowing_dao.dart` 模式:
  - `Stream<List<Canvas>> watchAll()` / `watchById(id)`
  - `Stream<List<CanvasNode>> watchNodesByCanvas(canvasId)` / `watchNodeById(id)`
  - `Stream<List<CanvasEdge>> watchEdgesByCanvas(canvasId)`
  - `Future<void> upsertCanvas/upsertNode/upsertEdge`
  - `Future<int> softDeleteCanvas(id)`(级联软删 nodes + 硬删 edges)/ `softDeleteNode(id)`(级联硬删 edges)
  - `Future<int> hardDeleteEdge(id)`

#### `lib/shared/database/novel_content_database_migrations.dart`
- 新增 `migrateToV11(Migrator m)`,参照 `migrateToV8`(L204)范式:
  - `_tableExists` 守卫 → `m.createTable(db.canvases)` / `m.createTable(db.canvasNodes)` / `m.createTable(db.canvasEdges)`
  - 建索引:`canvas_nodes_by_canvas_id`、`canvas_edges_by_canvas_id`、`canvas_edges_by_source`、`canvas_edges_unique`(canvas_id, source_node_id, target_node_id, type)。

#### NEW: `lib/shared/services/canvas_service.dart`
- 参照 `lib/shared/services/entity_relations_service.dart` 模式:
  - `class CanvasService { CanvasService(this._database); final NovelContentDatabase _database; ... }`
  - `Stream<List<Canvas>> watchCanvases()` / `Stream<({List<CanvasNode> nodes, List<CanvasEdge> edges})> watchCanvasContent(canvasId)`
  - `Future<String> createCanvas({name, description})` / `renameCanvas` / `softDeleteCanvas`
  - `Future<String> addNode({canvasId, type, refType?, refId?, content?, x, y, ...})`(校验 ref_id 存在性)
  - `Future<void> updateNodePosition(nodeId, x, y)` / `updateNodeContent(nodeId, content)`
  - `Future<void> softDeleteNode(nodeId)`(级联删 edges)
  - `Future<String> addEdge({canvasId, sourceNodeId, targetNodeId, type, label?})`
  - `Future<void> hardDeleteEdge(edgeId)`
  - `Future<void> refreshReferenceTitle({required String refType, required String refId})`/`refreshReferenceTitlesForCanvas(canvasId)`:引用资源标题变更后刷新画布节点缓存 title。**接入策略(待办)**:不做「每个资源 service 更新路径末尾调用」的散弹式接入(侵入面大且易漏);统一由 `CanvasEditorPage` 打开画布时调用一次 `refreshReferenceTitlesForCanvas(canvasId)` 校准。画布打开期间源头改名的实时性放弃(见已知妥协 3)。
  - 所有写操作 try-catch + `[DB]` 日志。

#### NEW: `lib/shared/providers/canvas_providers.dart`(已落地,实际为独立文件而非并入 novel_providers)
- `canvasServiceProvider`(codegen `@riverpod`,family by `databasePath`——与 `novelContentDatabaseProvider`/`entityRelationsServiceProvider` 同款键,**不是** novelId;注入 per-novel 的 `NovelContentDatabase`,不是 appDatabase)。
- `canvasesProvider` = `@riverpod Stream<List<CanvasEntry>>`(family by `databasePath`)。
- `canvasContentStreamProvider` = plain `StreamProvider.family`,键为 `(canvasId, databasePath)` record,转调 `watchCanvasContent`,供 `CanvasBoard` 同步 flow controller。
- `activeCanvasIdProvider`:riverpod 3 已无 `StateProvider`,实际为 `@Riverpod(keepAlive: true) class ActiveCanvasIdNotifier`(生成 provider 名 `activeCanvasIdProvider`),含 `set(String?)` 与 `clearIfActive(String)`;
  - `CanvasEditorPage` 挂载后首个安全帧 `set(canvasId)`,卸载时 `clearIfActive(canvasId)`(避免 A→B 快速切换时 A 的 dispose 清掉 B 刚写入的 id);
  - `AiToolManager` 通过构造注入的 `activeCanvasIdGetter` 回调读取、`activeCanvasIdSetter` 回调写入(`CanvasCreate` 创建后置为 active);不在画布详情页时 canvas 工具返回 `no_active_canvas`;
  - 该 provider 仅用于「当前是否有打开的画布页」,不是全局导航状态。

#### `lib/shared/models/novel_workspace.dart`
- `NovelWorkspaceSection` 枚举增加 `canvas`(`lib/shared/models/novel_workspace.dart#L112`)。
- `aiResourceType` 映射增加 `NovelWorkspaceSection.canvas => 'canvas'`(L19)。
- `novelWorkspaceSectionFromAiResourceType` 增加 `'canvas' => NovelWorkspaceSection.canvas`(L80)。
- `isReadOnly` 中 `canvas` 不加(可读写)。

#### `lib/desktop/pages/novel_editor.dart`
- **不**新增 `_EditorContentSelection` 子类;画布详情不再寄生在 `NovelEditor` 的 Main 区域。
- 保留 `selection` 对 `NovelWorkspaceSection.canvas` 的处理,但仅用于侧边栏显示画布列表,不驱动主内容区。

#### `lib/desktop/widgets/sidebar/rail.dart` & `sections.dart`
- rail 中 workspace section 列表增加 `NovelWorkspaceSection.canvas` 入口(参照 `NovelWorkspaceSection.maps` 的注册方式,L202)。
- `sections.dart` 处理 `case NovelWorkspaceSection.canvas:` 渲染画布**列表面板**:展示当前小说所有画布,支持新建 / 打开 / 重命名 / 删除。
  - 点击某张画布 → 调用 `Navigator.of(context).push(MaterialPageRoute(builder: (_) => CanvasEditorPage(canvasId: canvas.id)))`。
  - 不在 sidebar 内直接渲染画布工作区,保持 sidebar 轻量。

#### `lib/desktop/widgets/workspace/novel_workspace_panel.dart`
- **无需**为 canvas 增加 switch case;画布详情不通过 `contentSelection` 在 Main 区域切换。

#### NEW: `lib/desktop/features/canvas/` (feature 目录)
- `pages/canvas_editor_page.dart` — 画布详情独立页:
  - 接收 `canvasId` + `novelId`(或从 provider 读取当前小说);
  - 使用 `DesktopWindowFrame` 作为页面根 body(守 desktop-window-frame.md);
  - 挂载后首个安全帧向 `activeCanvasIdProvider` `set(canvasId)`,卸载时 `clearIfActive(canvasId)`;
  - 主体为 `CanvasBoard` + `CanvasToolbar` + 可选 `CanvasInspector`;
  - 提供「关闭/返回」按钮,返回 `NovelEditor`。
- `widgets/canvas_list_panel.dart` — 侧边栏画布列表面板(新建/打开/重命名/删除),由 `sections.dart` 引用。
- `widgets/canvas_board.dart` — 画布工作区核心:创建 `NodeFlowController`(MobX),通过 `NodeFlowEditor` 渲染;监听 `canvasContentStreamProvider`,快照签名比对(节点/边 id 集合)变化时 `loadGraph` 同步到 flow Controller(`isSyncingFromProps` 置位防回环);flow 事件(`onDragStop`/connection `onCreated`/`onDeleted` 等)通过 CanvasService 写回 DB(拖拽中不写,结束才写,无需 debounce);主题适配 RevericTheme。
- `widgets/canvas_flow_adapter.dart` — DB 模型 ↔ flow 模型双向转换:
  - `canvasNodeToFlowNode()` → flow 节点:
    - 便签型:`flow.CommentNode(text: content, color: stickyYellow)` + 创建后 `addPort(hiddenAnchorPort)`
    - 引用型:`flow.Node<CanvasNodeData>` + 自定义 `widgetBuilder`(引用图标+缓存 title) + 构造时传入 `ports: [hiddenAnchorPort]`
  - 隐藏 anchor port:`Port(id:'anchor', name:'', type: PortType.both, multiConnections: true, widgetBuilder: (_,__,___) => const SizedBox.shrink())`(port 控件不渲染;端口位置在节点边缘,V1 连线为边到边)
  - `canvasEdgeToFlowConnection()` → `flow.Connection<CanvasEdgeData>`(边类型存在 data 字段,按 type 设置 color/style/endPoint 箭头)
  - `flowNodeToCanvasNode()` / `flowConnectionToCanvasEdge()`:反向转换用于写回 DB
- `widgets/canvas_node_widget.dart` — 引用型节点的自定义 widgetBuilder 内容(按 refType 显示对应图标 + 缓存 title;失效态灰显)。
- `widgets/canvas_toolbar.dart` — 顶部工具栏(缩放复位 + fitToView + 关闭返回,复用 flow controller 的 viewport API;**不**再负责新建/切换画布,这些操作在侧边栏列表完成)。
- `widgets/canvas_inspector.dart` — 右侧检查器(选中引用型节点时显示 ref 信息/可跳转;选中便签时无需额外编辑器(CommentNode 自带内联编辑);选中边时可编辑边类型/label/颜色;属性变更通过 CanvasService 写 DB,sync 回 flow)。

#### NEW: `lib/shared/services/ai/tools_canvas.dart`
- `part of 'tools.dart';`,参照 `lib/shared/services/ai/tools_graph.dart` 模式。
- `mixin _AiToolManagerCanvasMixin on _AiToolManagerBase` 实现 7 个 handler:
  - `_handleCanvasCreate` / `_handleCanvasGetContent` / `_handleCanvasAddNode` / `_handleCanvasUpdateNode` / `_handleCanvasRemoveNode` / `_handleCanvasAddEdge` / `_handleCanvasRemoveEdge`
- 每个 handler:校验入参 → 解析 active canvas → 调 `CanvasService` → 返回结构化结果;失败走 `AiToolManager._structuredWriteError`。
- 定义每个工具的 `_*Description` 常量 + `_*InputSchema`(SchemanticType.from + jsonSchema)。

#### `lib/shared/services/ai/tools.dart`
- `AiToolDefinition` 列表增加 7 个 canvas 工具(`lib/shared/services/ai/tools.dart#L652` 附近):`CanvasCreate/CanvasGetContent/CanvasAddNode/CanvasUpdateNode/CanvasRemoveNode/CanvasAddEdge/CanvasRemoveEdge`,group = `AiToolGroup.canvas`(新增 group)。
- `registerAllTools` 中为每个 canvas 工具 `_registerDispatch(name, group, (input, callId) => _runMutationTool(...))`(参照 L1017 `CreateRelation` 注册;读类工具 `CanvasGetContent` 走 `_runToolObserved`)。
- `buildToolDefs()` 增加 7 个 `ToolDef`(`lib/shared/services/ai/tools.dart#L1291` 附近)。
- `_AiToolManagerBase` with `_AiToolManagerCanvasMixin`。
- `AiToolManager` 构造函数新增 `String? Function()? activeCanvasIdGetter` 与 `void Function(String?)? activeCanvasIdSetter` 参数(可选,nullable):getter 供 canvas 工具读取当前 active canvas id;setter 供 `CanvasCreate` 在创建后把新画布置为 active。`chat.dart` 的 `AiToolManager` 实例化处注入(由 `ai_providers.dart` 读写 `activeCanvasIdProvider`)。

#### `lib/shared/services/ai/builtin_agent_tools.dart`
- 把 canvas 工具加入相关 agent 的工具集(`lib/shared/services/ai/builtin_agent_tools.dart`):
  - `builtinDefaultSubAgentToolNames` 加 `CanvasGetContent`(只读)
  - `builtinChroniclerSubAgentToolNames` 加 `CanvasCreate/CanvasGetContent/CanvasAddNode/CanvasUpdateNode/CanvasRemoveNode/CanvasAddEdge/CanvasRemoveEdge`(chronicler 负责梳理结构,最需要画布)
  - `builtinWriterSubAgentToolNames` 加 `CanvasGetContent`(writer 只读画布)
  - orchestrator 默认工具集加全部 7 个(orchestrator 是画布主要 agent 操作者)

#### i18n 三件套(新增画布文案)
- `lib/shared/localization/locale_keys.dart` — 新增 `canvas.*` keys(canvasTitle/newCanvas/renameCanvas/deleteCanvas/nodeTypeReference/nodeTypeSticky/edgeTypeRelationship/edgeTypeCausal/edgeTypeTimeline/edgeTypeForeshadowPayoff/edgeTypeAssociation/invalidReference/noActiveCanvas/stickyPlaceholder 等)。
- `assets/translations/en/canvas.json` + `assets/translations/zh-CN/canvas.json` — 新建 namespace 文件。
- 涉及用户可见文案的文件在 `// 关联文件:` 中列出上述 locale 文件(守 AGENTS.md 文件头规则)。

#### 图标(守 `.agents/rules/icons.md`)
- `RevericIcons` 中检查/新增:canvas 画布图标、sticky 便签图标、各类边类型图标。缺的去 `PHOSPHOR_ICONS_DIR` 指定的目录 找,复制到 `assets/icons/phosphor/` 并注册。节点 refType 图标复用现有 `RevericIcons`(角色/章节/伏笔等已有)。

### 5.5 Task Graph `[按需]`

```text
PR-1 数据模型 + migration
  ├─ canvases/canvas_nodes/canvas_edges 表 + schemaVersion 11 + migrateToV11
  ├─ CanvasDao + build_runner 生成
  └─ 单测:DAO watch/upsert/软删/级联
       │
       └─ PR-2 CanvasService + providers
            ├─ CanvasService(校验/级联/refreshReferenceTitles)
            ├─ canvasServiceProvider/canvasesProvider
            └─ 单测:service 校验逻辑 + 引用失效检测
                 │
                 ├─ PR-3 Canvas UI + workspace 集成
                 │    ├─ canvas_flow_adapter.dart(DB↔flow 双向转换)
                 │    ├─ CanvasBoard(NodeFlowController + NodeFlowEditor + DB↔flow sync)
                 │    ├─ CanvasEditorPage/CanvasListPanel/CanvasToolbar/CanvasInspector/node widgets
                 │    ├─ 侧边栏 rail/sections 接入(只展示列表,不渲染工作区)
                 │    ├─ `CanvasEditorPage` 打开/关闭时写入/清空 `activeCanvasIdProvider`
                 │    ├─ RevericTheme 适配 flow NodeFlowTheme(颜色/字体/圆角)
                 │    ├─ anchor port(CommentNode 创建后 addPort,引用型 Node 构造时传入)
                 │    ├─ 用户拖拽/画线/便签编辑/快捷键处理(人写路径)
                 │    └─ widget 测试:拖拽、画线、失效态、独立页打开/关闭
                 │
                 └─ PR-4 Agent canvas 工具
                      ├─ tools_canvas.dart(7 工具 handler + schema + description)
                      ├─ tools.dart 注册(AiToolDefinition + _registerDispatch + ToolDef)
                      ├─ builtin_agent_tools.dart 权限集
                      ├─ active canvas 解析(从 `AiToolManager.activeCanvasIdGetter/Setter` 回调)
                      └─ 集成测试:agent 工具 → DB → stream → flow sync → UI 更新

PR-5 收尾:评测 + i18n + 图标 + 回归
```

| 任务 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| PR-1 | 三表 + migration + DAO | 无 | `flutter pub run build_runner build`;DAO 单测 |
| PR-2 | CanvasService + providers | PR-1 | service 单测 |
| PR-3 | Canvas UI + 独立页集成(人写路径) | PR-2 | widget 测试;手动检查拖拽/画线/独立页导航 |
| PR-4 | Agent 工具(agent 写路径) | PR-2 | 集成测试:工具 → DB → stream |
| PR-5 | 评测 + i18n + 图标 + 回归 | PR-3, PR-4 | 评测脚本;回归测试 |

### 5.6 Migration `[按需]`

```text
from version 10 to 11:
1. createTable canvases
2. createTable canvas_nodes
3. createTable canvas_edges
4. create index canvas_nodes_by_canvas_id on canvas_nodes (canvas_id)
5. create index canvas_edges_by_canvas_id on canvas_edges (canvas_id)
6. create unique index canvas_edges_unique on canvas_edges (canvas_id, source_node_id, target_node_id, type)
```

- **索引 API**:遵循现有先例用 `database.customStatement('CREATE [UNIQUE] INDEX IF NOT EXISTS ...')`,不用 `m.createIndex`;索引创建函数同时在 `onCreate` 调用,保证新库与升级库一致(已落地,见 `createCanvasIndexes`)。
- **schemaVersion**:10 → 11(已落地;若与其他分支冲突,rebase 时按 `.agents/skills/git/SKILL.md` 的 DB migration 版本冲突流程解决)。
- **旧数据**:无,新功能空表。
- **默认值**:所有 `deletedAt` 列 `NOT NULL DEFAULT 0`(与现有表一致);`sort_order` 默认 0;`type`/`status` 类列有默认常量。
- **回滚**:`migrateToV11` 只建表不删表,回滚 = 降版本号 + 手动 drop 三表(开发期可接受;线上不回滚)。
- **迁移失败**:`_tableExists` 守卫保证幂等,失败重试安全。
- **无需补数据脚本**:新功能无历史数据。
- **build_runner**:改完 DB 必须跑 `flutter pub run build_runner build --delete-conflicting-outputs`(守 AGENTS.md Flutter 代码生成命令规则),生成 `canvas_dao.drift.dart` 和 `novel_content_database.drift.dart`。

### 5.7 上线后验证 `[按需]`

| 指标 / 日志 / 数据 | 目的 | 异常信号 | 观察周期 |
|-------------------|------|----------|----------|
| canvas 工具调用成功率 | agent 画布操作是否健康 | 成功率 < 95% / `no_active_canvas` 占比高 | 上线 1 周 |
| `no_active_canvas` 错误占比 | agent 是否常在无画布时被调用 | 占比 > 30% 说明 prompt 引导不够 | 2 周 |
| 单画布节点数分布 | 是否有超大画布影响性能 | 中位数 > 200 / max > 500 需考虑虚拟化 | 1 个月 |
| 引用失效节点数 | 资源删除后画布悬空引用规模 | 持续增长不清理 | 1 个月 |
| 用户/agent 写入冲突导致的节点位置跳变 | last-write-wins 是否够用 | 用户反馈「节点乱跳」 | 上线 2 周 |

## 6. 验收标准 `[核心]`

| 类别 | 标准 | 验证方式 |
|------|------|----------|
| 功能 | NovelEditor 侧边栏出现 Canvas 列表,可新建/打开/删除/重命名画布;打开后进入独立 `CanvasEditorPage` | `flutter test test/desktop/features/canvas/` + 手动 |
| 功能 | 用户可拖拽节点、画 5 种类型边、写/改便签 | widget 测试 |
| 功能 | agent 7 个画布工具可调用,操作实时反映到 UI | 集成测试 `test/.../canvas_tools_test.dart` |
| 功能 | 引用资源删除后,画布节点显示「已失效」 | widget 测试 |
| 功能 | 未打开 `CanvasEditorPage` 时 canvas 工具返回 `no_active_canvas` 错误 | 单测 |
| 兼容 | Canvas 列表不影响其他 workspace section;`NovelWorkspaceSection` 新增 `canvas` 不破坏现有 switch | 回归测试 `test/desktop/widgets/sidebar/`、`test/desktop/pages/novel_editor_test.dart` |
| 兼容 | 现有 `entity_graph`/`map_editor` 无变化 | 回归测试 |
| 错误处理 | DB 写入失败 try-catch + `[DB]` 日志 + 结构化错误返回 | 单测(mock DAO 抛错) |
| 错误处理 | 工具不静默兜底成功 | 单测 |
| 性能 | 100 节点 + 100 边画布拖拽/缩放 < 16ms/帧 | `flutter test` performance + 手动 DevTools |
| 可维护性 | 画布数据查询不经 metadata JSON 解析 | DAO 单测 |
| 可维护性 | canvas 边不进入 `EntityRelations`,`GraphSearch` 查不到 | 单测 |
| migration | schemaVersion 11 建表 + 幂等 + 旧库升级不丢数据 | migration 单测 |

测试命令(守 AGENTS.md Rule 14,串行不并行):

```bash
flutter test test/shared/database/canvas_dao_test.dart
flutter test test/shared/services/canvas_service_test.dart
flutter test test/desktop/features/canvas/
flutter test test/shared/services/ai/tools_canvas_test.dart
```

## 7. 评测 `[按需]`

### 评测对象

- 被测能力:agent 在「把角色关系画到画布上」「把伏笔脉络铺开」等指令下,正确选择 canvas 工具、正确引用现有资源、正确选边类型、在 active canvas 上操作。
- 不测内容:画布渲染性能(属验收)、用户拖拽交互(属验收)。
- 输入来源:固定场景剧本(5-10 个,覆盖人物关系/因果/时间线/伏笔兑现/混合)。
- 输出判定:工具调用序列是否合理、引用 id 是否真实存在、边类型是否匹配指令语义、是否处理无 active canvas 情况。

### 评测场景

| 场景 | 输入 | 期望 | 判定方式 |
|------|------|------|----------|
| 人物关系 | 「把主角团的关系画到画布上」 | `CanvasCreate`(若无 active canvas) → 多个 `CanvasAddNode`(ref_type=character) → `CanvasAddEdge`(type=relationship) | deterministic(工具序列) + manual(合理性) |
| 伏笔兑现 | 「把第一卷的伏笔兑现脉络铺开」 | `CanvasAddNode`(foreshadowing) + `CanvasAddNode`(chapter) + `CanvasAddEdge`(type=foreshadow_payoff) | deterministic + manual |
| 无画布 | 在未打开画布时指令 | `CanvasCreate` 或返回 `no_active_canvas` 并提示用户 | deterministic |
| 引用失效 | 指令引用已删除资源 | `CanvasAddNode` 返回 `invalid_reference` | deterministic |
| 读后继写 | 「看看我画布上有什么,接着帮我补全」 | 先 `CanvasGetContent` 读取,再基于已有节点继续 | judge(是否基于现有内容) |

### 自动化与人工评测边界

- 自动化:deterministic 场景的工具调用序列校验(prompt regression evaluation 框架)。
- 人工:边类型语义合理性、节点布局可读性。
- 只观察不阻断:节点位置(x/y)的合理性(agent 乱放位置不阻断,作为 prompt 优化信号)。

## 8. Token 成本 `[按需]`

| 维度 | 估计 | 说明 |
|------|------|------|
| 单次调用 token | 输入 ~500 / 输出 ~200 | `CanvasGetContent` 返回节点/边轻量摘要,可控 |
| 调用次数 | 每次画布任务 5-15 次工具调用 | 放置 N 节点 + M 边,每节点/边一次调用;读内容 1 次 |
| 上下文增长 | 随 `CanvasGetContent` 调用线性,但受 max_nodes/max_edges 上限控制 | 默认 50 节点 + 100 边,不含资源正文 |
| 模型档位 | sonnet | 画布操作是结构化工具调用,不需 opus;chronicler/orchestrator 默认 sonnet |

- 相比现状:增量(新增工具 + 新增 prompt 引导),量级中等。
- 随规模放大:`CanvasGetContent` 返回受 `max_nodes`/`max_edges` 上限控制,默认上界固定;超大画布通过多次调用或分段操作消化。
- 失败降级:`no_active_canvas` 时直接返回,不消耗额外 token。

## 9. 风险 `[核心]`

| 风险 | 触发条件 | 影响 | 对策 |
|------|----------|------|------|
| 用户与 agent 并发写同一节点 | 用户拖拽节点时 agent 同时 `CanvasUpdateNode` 移动同节点 | 节点位置跳变,用户体验差 | last-write-wins(V1 接受);V2 加操作锁(用户拖拽中时 agent 工具对该节点排队) |
| canvas 边被误用为正典关系 | 作者把画布上的关系当成已生效业务关系 | 数据不一致(画布有边但 `EntityRelations` 没有) | UI 明示「画布边仅用于构思,正典化请用 CreateRelation」;canvas 边不可被 `GraphSearch` 查询 |
| 引用悬空堆积 | 大量资源被删,画布遗留失效节点 | 画布杂乱 | UI 提供「清理失效节点」按钮;失效节点视觉灰显 |
| 大画布性能 | 单画布节点/边 > 500 | 拖拽/缩放卡顿 | vyuh_node_flow 内置空间索引(`GraphSpatialIndex`)+ LOD 插件(`LodPlugin` 缩远时缩略渲染)+ minimap,性能基础好;超 500 节点提示拆分画布 |
| active canvas 解析不准 | `CanvasEditorPage` 打开/关闭时未正确写入/清空 `activeCanvasIdProvider`,或 Navigator 路由堆栈异常导致 provider 残留 | agent 操作到错误画布,或在未打开画布页时工具仍认为有 active canvas | 单一来源:`activeCanvasIdProvider` 由 `CanvasEditorPage` 生命周期驱动;页面 `dispose` 必须清 null;增加断言单测验证打开/关闭状态 |
| 页面导航后工具状态残留 | 用户打开画布页 → 关闭 → agent 在旧上下文仍持有 canvas 工具 | 工具调用返回 `no_active_canvas`,体验正常,但 prompt 需要引导「先打开画布页」 | 工具错误码明确提示;评测场景包含「无画布页」case |
| DB↔flow 双向同步循环 | DB stream 触发 syncToFlow,又触发 flow 事件写 DB | 无限循环/重复写入 | `isSyncingFromProps` 标志:外部 sync 到 flow 时置标志位,忽略此期间的 flow 事件回调 |
| 外部写入频繁触发全量 reload | agent 连续放 N 个节点,每次 DB 写入触发一次 stream 重发 → 签名比对到 id 集合变化 → 全量 `loadGraph` | flow controller 频繁 reset,选中态/视口交互被打断,N 个节点重置 N 次 | V1 签名比对已滤掉位置类重发;进一步缓解:stream 侧 debounce 合并连发,或提供批量工具(`CanvasAddNodes`/`CanvasAddEdges`,见待办)一次写入只触发一次 reload;V2 增量 patch 替代全量 reload |
| CommentNode 运行时 port 丢失 | `CommentNode.copyWith`/`fromJson` 把 ports 重置为空,undo/复制/序列化路径丢失运行时挂的 anchor port | 便签连线断裂 | adapter 每次 `loadGraph` 构建节点后统一重挂 anchor port;不依赖 flow 内部保留 port |
| anchor port 连线视觉不自然 | 隐藏 port 只能挂在节点边缘,连线端点从边缘出发,视觉上为边到边 | 连线贴边而非中心出发,可能不够美观 | V1 可接受;V2 自定义 `ConnectionPainter`/`endpoint_position_calculator` 将端点延伸到节点中心或边缘最近点 |
| vyuh_node_flow 默认键盘快捷键冲突 | Delete/Ctrl+A/Escape 等快捷键与编辑器全局快捷键冲突 | 误删节点/行为异常 | 初始化 controller 后按需 `shortcuts.removeShortcut()` 移除冲突键位 |
| migration 版本冲突 | 多分支同时 bump schemaVersion | rebase 冲突 | 按 `.agents/skills/git/SKILL.md` DB migration 版本冲突流程解决 |
| build_runner 失败 | 改 DB 后未生成 `.drift.dart` | 编译错 | CI 强制 `flutter pub run build_runner build --delete-conflicting-outputs`;AGENTS.md 已有规则 |
| agent 乱放节点位置 | agent 给出离谱 x/y | 画布混乱 | 工具不阻断(只观察);prompt 引导「按合理布局放置,避免重叠」;V2 加自动布局 |

## 10. 已知妥协 `[按需]`

```text
1. 妥协:用户与 agent 并发写采用 last-write-wins,无操作锁/OT
   - 原因:桌面单用户,真并发概率低;OT/CRDT 复杂度远超 V1 价值。
   - 影响:用户拖拽节点时 agent 移动同节点会跳变;agent 放节点时用户删画布会写到已删画布(service 校验 canvas 存在性兜底)。
   - 升级触发:用户反馈「节点乱跳」频繁,或引入移动端/多设备同步。
   - 后续方向:操作锁(节点级乐观锁,drag 期间 agent 对该节点排队);或引入 CRDT(如 Yjs)做真协作。

2. 妥协:canvas 边不可被 agent 查询为业务关系
   - 原因:与 `entity_graph` 边界清晰,避免构思阶段随手连线污染正典。
   - 影响:作者在画布上画了 100 条人物关系,想让 agent 「按画布关系写章节」时,agent 不能直接 `GraphSearch` 到这些边,需先 `CanvasGetContent` 读取再自行理解。
   - 升级触发:用户明确要求「把画布关系正典化」。
   - 后续方向:提供「画布边 → EntityRelations」一键转换工具(人确认后批量写入 entity_graph)。

3. 妥协:引用型节点缓存 title,资源改名后需刷新
   - 原因:画布常驻渲染,每次 join 资源表取标题成本高。
   - 影响:资源改名后画布显示旧标题;V1 只在打开画布时校准一次(`refreshReferenceTitlesForCanvas`),画布打开期间源头改名不实时反映。
   - 升级触发:用户反馈画布标题与资源不一致。
   - 后续方向:资源更新事件驱动刷新,或渲染时实时 join(若性能允许)。

4. 妥协:canvas 边硬删,无撤销;删节点时级联硬删的边不随节点恢复
   - 原因:与 `EntityRelations` 一致,边轻量易重建。
   - 影响:误删边需重画;软删节点恢复后其关联边已丢失,需重连(user story 11 的「撤销」仅覆盖节点本体)。
   - 升级触发:用户频繁误删边,或节点恢复后抱怨边丢失。
   - 后续方向:边也改软删 + 撤销栈;级联删除场景改为边软删陪葬,随节点一同恢复。

5. 妥协:V1 无自动布局
   - 原因:自动布局(layout engine)复杂度高,V1 优先让人/agent 显式放置。
   - 影响:agent 放节点可能重叠,需人手调。
   - 升级触发:agent 放置的节点经常重叠不可读。
   - 后续方向:接入 dagre/force-directed 布局,提供「自动整理」按钮。

6. 妥协:双状态管理 — UI 状态在 MobX(flow Controller),持久化状态在 Riverpod(CanvasService)
   - 原因:vyuh_node_flow 基于 MobX 构建,拖拽/连线等高频交互需要 MobX 的细粒度响应式;项目数据层统一走 Riverpod + Drift。
   - 影响:需要 adapter 层做双向同步,代码量比纯 Riverpod 多;需用 isSyncingFromProps 防循环。
   - 升级触发:如果双写导致难以排查的 bug,考虑封装统一的 CanvasController 隐藏同步细节。
   - 后续方向:将 sync 逻辑封装为通用的 `FlowControllerSyncMixin`,供 canvas 和未来其他 flow 场景复用。

7. 妥协:边唯一索引是有向的,无向语义边(relationship/association)可重复
   - 原因:`(canvas_id, source, target, type)` 唯一索引只防同向重复;A→B 与 B→A 可并存。
   - 影响:用户/agent 可能画出视觉重复的双向「人物关系」边。
   - 升级触发:重复双向边频繁出现、影响可读性。
   - 后续方向:service 层对无向类型做双向查重(addEdge 时按 (min,max) 归一化检查)。

8. 妥协:agent 工具单节点/单边一次调用,无批量变体
   - 原因:V1 保持工具面窄;单个调用粒度与 pending changes/diff 预览机制天然对齐。
   - 影响:「把主角团关系画出来」类任务需 5-15+ 次 LLM 工具往返,token 与延迟成本偏高;每次写入触发一次 stream 重发与全量 reload(见风险表)。
   - 升级触发:评测/上线指标显示画布任务调用次数或耗时明显偏高。
   - 后续方向:新增 `CanvasAddNodes`/`CanvasAddEdges` 批量工具(数组输入,单事务写入,一次 stream 重发)。
```

## 附录:Agent 画布工具设计(完整)

> 7 个工具,均在 novel-scoped `AiToolManager` 注册,操作「当前 active canvas」(经 `AiToolManager.activeCanvasIdGetter` 回调读取 `activeCanvasIdProvider`,由 `CanvasEditorPage` 生命周期写入/清空;`CanvasCreate` 经 `activeCanvasIdSetter` 把新画布置为 active)。

### 1. `CanvasCreate`

```json
{
  "name": "CanvasCreate",
  "description": "创建一张新画布。当用户要求在画布上构思,但当前没有 active canvas 时使用。创建后该画布成为 active canvas。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "name": { "type": "string", "description": "画布名称,如「角色关系」「情节时间线」「伏笔脉络」" },
      "description": { "type": "string", "description": "画布说明(可选)" }
    },
    "required": ["name"],
    "additionalProperties": false
  }
}
```

返回:`{ok:true, canvas_id, path:'/canvas/{id}'}`;失败:`{ok:false, error_code, message}`。

### 2. `CanvasGetContent`

```json
{
  "name": "CanvasGetContent",
  "description": "读取当前 active canvas 的节点/边轻量摘要,用于 agent 在操作前了解画布现状(如查找已有节点 id 用于连线)。不返回资源正文。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "max_nodes": { "type": "integer", "description": "最多返回节点数,默认 50,上限 100" },
      "max_edges": { "type": "integer", "description": "最多返回边数,默认 100,上限 200" }
    },
    "additionalProperties": false
  }
}
```

返回:`{ok:true, canvas_id, nodes:[{id,type,ref_type,ref_id,title,x,y,width,height}], edges:[{id,source_node_id,target_node_id,type,label}], truncated:{nodes,edges}}`。
- 若用户未打开任何画布页,返回 `no_active_canvas`。
- 超过上限时 `truncated` 标记实际返回数与总数,agent 应缩小范围或基于已知 id 直接操作。

### 3. `CanvasAddNode`

```json
{
  "name": "CanvasAddNode",
  "description": "在 active canvas 上放置一个节点。两类:type='reference' 引用现有资源(需 ref_type+ref_id);type='sticky' 写便签(需 content)。位置 (x,y) 为画布坐标。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "type": { "type": "string", "enum": ["reference", "sticky"], "description": "节点类型" },
      "ref_type": { "type": "string", "description": "reference 必填:character/chapter/foreshadowing/outline/location/item/faction/skill/creature/document" },
      "ref_id": { "type": "string", "description": "reference 必填:指向的资源 id" },
      "title": { "type": "string", "description": "sticky 可选:便签标题" },
      "content": { "type": "string", "description": "sticky 必填:便签正文" },
      "x": { "type": "number", "description": "画布坐标 x" },
      "y": { "type": "number", "description": "画布坐标 y" },
      "width": { "type": "number", "description": "可选" },
      "height": { "type": "number", "description": "可选" }
    },
    "required": ["type", "x", "y"],
    "additionalProperties": false
  }
}
```

校验:reference 必须有 ref_type+ref_id 且 ref_id 真实存在;sticky 必须有 content。失败:`invalid_reference` / `missing_required_fields` / `no_active_canvas`。

### 4. `CanvasUpdateNode`

```json
{
  "name": "CanvasUpdateNode",
  "description": "更新节点位置或便签内容。用于移动节点、改便签文字。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "node_id": { "type": "string" },
      "x": { "type": "number", "description": "可选,新 x" },
      "y": { "type": "number", "description": "可选,新 y" },
      "content": { "type": "string", "description": "可选,便签新正文(仅 sticky)" }
    },
    "required": ["node_id"],
    "additionalProperties": false
  }
}
```

### 5. `CanvasRemoveNode`

```json
{
  "name": "CanvasRemoveNode",
  "description": "从 active canvas 软删一个节点(同时硬删以其为端点的边)。",
  "inputSchema": {
    "type": "object",
    "properties": { "node_id": { "type": "string" } },
    "required": ["node_id"],
    "additionalProperties": false
  }
}
```

### 6. `CanvasAddEdge`

```json
{
  "name": "CanvasAddEdge",
  "description": "在 active canvas 上画一条类型化边。边类型:relationship(人物关系)、causal(因果)、timeline(时间线)、foreshadow_payoff(伏笔兑现:source=伏笔节点,target=章节节点)、association(通用关联)。注意:canvas 边只是视觉组织,不进入 entity_graph 业务关系;正典关系请用 CreateRelation。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "source_node_id": { "type": "string" },
      "target_node_id": { "type": "string" },
      "type": { "type": "string", "enum": ["relationship", "causal", "timeline", "foreshadow_payoff", "association"] },
      "label": { "type": "string", "description": "可选,边上的说明文字" }
    },
    "required": ["source_node_id", "target_node_id", "type"],
    "additionalProperties": false
  }
}
```

校验:两端点必须同属 active canvas;`foreshadow_payoff` 校验 source 是 foreshadowing 引用节点、target 是 chapter 引用节点(语义校验,失败返回 `invalid_edge_semantics`)。重复同型边返回 `duplicate_edge`。

### 7. `CanvasRemoveEdge`

```json
{
  "name": "CanvasRemoveEdge",
  "description": "从 active canvas 硬删一条边。",
  "inputSchema": {
    "type": "object",
    "properties": { "edge_id": { "type": "string" } },
    "required": ["edge_id"],
    "additionalProperties": false
  }
}
```

### 工具行为通则

- **active canvas 解析**:所有写工具与读工具(除 `CanvasCreate`)从 `AiToolManager.activeCanvasIdGetter` 回调读取当前打开的画布页 canvas id;该值由 `CanvasEditorPage` 在页面打开时写入、关闭时清空;`CanvasCreate` 创建成功后经 `activeCanvasIdSetter` 把新画布置为 active。不在画布详情页(或无打开画布)时,工具返回 `{ok:false, error_code:'no_active_canvas', message:'当前没有打开的画布,请先用 CanvasCreate 创建或请用户打开一张画布'}`。
- **错误处理**:统一走 `AiToolManager._structuredWriteError(path:'/canvas/...', errorCode, message, operation)`,不静默兜底(守 error-handling.md)。
- **mutation 工具**:`CanvasCreate/AddNode/UpdateNode/RemoveNode/AddEdge/RemoveEdge` 走 `_runMutationTool`(支持 pending changes/diff);`CanvasGetContent` 走 `_runToolObserved`(只读)。
- **权限**:orchestrator 默认有全部 7 个;chronicler 有全部 7 个;writer/explorer 只有 `CanvasGetContent`;其他 subagent 默认 `CanvasGetContent`(见改动清单 builtin_agent_tools.dart)。

## 附录:写作检查清单

- [x] 背景说明了真实问题(构思阶段没有自由排版平面)。
- [x] 开头说明了与 ADR-0013 的关系。
- [x] 目标和非目标都写了。
- [x] 至少比较了一个备选方案(A/B/C/D),推荐方案有明确理由。
- [x] 改动清单具体到文件 / 函数 / 行号。
- [x] 涉及用户可见文案时列了 i18n 三件套。
- [x] 验收标准可判断 pass / fail,并写了对应测试命令。
- [x] (完整档) 数据模型字段语义清楚;多实体有 ERD。
- [x] (完整档) 关键流程包含失败路径(无 active canvas / DB 错误 / 引用失效)。
- [x] (完整档) Task graph 能指导 PR 切分。
- [x] (完整档) migration 遵循 db-migration.md,写了建表步骤和回滚考虑。
- [x] (完整档) 上线后验证能发现问题。
- [x] (AI 类) 非确定性行为有评测设计。
- [x] (AI 类) 估了 token 成本,说明了是否随规模放大。
- [x] 风险包含触发条件和对策。
- [x] 已知妥协没有被包装成已解决。
