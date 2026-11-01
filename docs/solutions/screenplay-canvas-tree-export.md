# 通用画布：树状编排、资源快照与开发交接导出

> 状态：方案草案，尚未实施。日期：2026-09-22。
> 已确认方向：复用现有画布，支持树状编排，导出给游戏引擎或开发团队。编排与导出同时覆盖剧本和非剧本画布。
> 格式决策：当前未指定引擎及插件，首版定义通用、带版本号的 JSON 交接契约；不承诺引擎原生导入。特定引擎适配由接入团队实现，确定插件后再单独评估。

## 1. 背景与范围

作者需要把影游的剧情分支、选项和汇合关系画出来，并把结构及正文交给开发团队。同一项能力也应覆盖小说章节、大纲、人物关系、世界观和纯便签画布。现有画布已有便签、资源引用、带标签的连线、自由摆位和持久化，适合承载这些需求。

本方案沿用 `canvases`、`canvas_nodes`、`canvas_edges`，增加场次引用、树状排列与通用画布导出。资源内容仍由各自编辑器维护，画布保存引用；导出时生成有明确类型的内容快照。场次是其中一种资源，通用格式不以场次或剧情树为前提。

### 当前实现依据

- [场次板](../../lib/desktop/features/screenplay/board.dart)按场次顺序生成线性连接，不是本次的扩展入口。
- [画布入口](../../lib/desktop/widgets/sidebar/rail.dart)已经由小说和剧本共用，无需再加“剧情树”顶级导航或新页面。普通画布位于工作区，`CanvasEditorPage` 当前主要用于演示画布。
- [画布服务](../../lib/shared/services/canvas_service.dart)支持节点、连线及标签，但引用类型缺少剧本场次。
- [自动整理](../../lib/shared/models/canvas_auto_layout.dart)保留已有行层级，只调整列位，不能自动生成剧情层级。
- [文件导出](../../lib/shared/services/asset_export/save.dart)已有桌面保存和移动端临时文件分享范例；`archive`、`file_selector`、`xml` 已在项目依赖中。

旧[画布方案](infinite-canvas.md)中的“独立页面”“不做自动布局”描述已落后于当前代码。本方案以当前实现为准，新增布局是一项明确的范围扩展。旧[剧本方案](screenplay-writing.md)排除的剧本导出也不作为本次限制；此次只导出画布引用到的内容。

### 交付目标

1. 作者从现有画布引用任意季、集的场次，点击节点打开正确正文。
2. 作者按阅读目的选择整理现有布局、层级排列或网格排列。分支与汇合可排成层级图，纯便签可排成网格，保存后重开位置不变。
3. 导出包含稳定 ID、所有节点与边、完整便签及直接引用资源内容的开发交接包，普通小说画布无需先建立剧本。
4. 开发团队仅凭交接包即可恢复任意图结构、查阅引用内容，并识别需要自行实现的运行规则。

首版不增加试玩、变量计算、条件执行、视频资产绑定、视频播放、引擎插件、反向导入或双向同步。连线标签是作者说明；“好感度 ≥ 50”不会自动成为表达式。入口和结局也不根据节点标题猜测。

### 平台边界

沿用既有画布的桌面范围，覆盖 macOS、Windows、Linux。手机端目前没有通用画布入口，本次不新增手机画布或导出页面；手机编辑、移动或删除章节、人物、场次等资源后，导出必须正确反映共享数据库变化。导出内容采集与文件编码放在共享层，为后续移动端入口保留正常调用边界，不提前实现无人调用的移动端保存分支。

## 2. 方案决策

| 方案 | 取舍 | 决策 |
| --- | --- | --- |
| 现有画布增加场次引用、布局和交接导出 | 复用编辑入口与三张表，保留自由编排 | 采用 |
| 只用便签画图并导出图片 | 可以立即人工使用，但正文要复制，开发方需要重新录入结构 | 作为零开发成本的临时办法 |
| 新建影游编辑器和可执行剧情模型 | 能承载条件与试玩，但超出此次编排和交接需求 | 不采用 |

新增 `canvases.layout` 一列，保存上次成功使用的布局类型；不新增表、索引或数据库约束，不改变旧画布坐标。数据库结构 v18 已随应用正式版本发布，本次将 `schemaVersion` 从 18 升至 19，新增独立迁移，具体规则见第 4.7 节。不修改后端 REST API，不增加第三方依赖、账号或网络服务。文件格式有自己的版本号，与数据库版本无关。

关键前提是接收方接受 Reveric 定义的通用画布数据，并负责映射到自己的系统。JSON 是通用载体，本方案的字段约定不是行业统一格式。如果要求直接导入某个引擎插件并运行，必须另行确定入口、结局、选项顺序、条件和状态变量的执行契约；本方案不能被当作这部分的完成证明。

## 3. 场次引用与正文跳转

### 3.1 数据与显示

- 在画布专属 `canvasNodeRefTypes` 中增加 `screenplay_scene`。不要加入通用 `entityTypes`，避免顺带影响实体关系图等模块。
- `canvas_nodes.type` 仍为 `reference`，`ref_type` 为 `screenplay_scene`，`ref_id` 保存稳定场次 ID。场号、标题、所在集均用于显示，不作为关联键。
- 资源选择器在剧本作品中增加“场次”，按季、集分组，可搜索标题或场号。沿用已在画布上的资源禁用规则；历史或 AI 创建的重复引用仍能正确显示和导出。
- 节点显示场次标题及“季 / 集 / 场号”；未命名时使用本地化的场次编号。详细梗概放在节点详情中，不把完整正文塞入卡片。
- 场次投影通过共享层按作品批量监听。直接复用或扩展 `watchScenesOfScreenplay`，不要对每个节点新建一条正文查询。

### 3.2 打开正文

节点详情增加“打开场次”。点击后重新读取有效场次，按它当前的 `episodeId` 查询所在集、季，更新已有剧本工作区选择，再发送 `WorkspaceNavigationRequest` 到 `screenplay_script`。不新增路由，不让画布自行持有另一套剧本编辑器。

移动或重排场次后仍打开同一 ID 的内容。拆场保留原节点引用，不自动给新场建节点；合场中被吸收的场次引用显示失效，不偷偷改指向。删除场次、集、季也保留失效节点，使用现有清理入口由作者处理。

`canvasInvalidNodeIdsProvider` 当前仅依赖画布内容变化，源场次删除不会必然触发重算。场次节点的标题、位置说明和有效性必须同时订阅场次投影；导出时再次从数据库校验，不能只信 UI 缓存。

## 4. 布局选项与树状编排

### 4.1 操作约定

布局按图的连接方式和阅读目的制定，同一张小说或剧本画布可以使用全部适用选项，不按作品类型锁定布局。

默认状态始终是自由摆放，打开画布就使用已保存坐标。自由摆放不是另一套算法，也不是切换后会恢复旧坐标的模式；任何排列结束后都能继续手动移动。

现有浮动工具条的“整理布局”扩展为以下菜单：

| 菜单选项 | 适用场景 | 位置与关系规则 |
| --- | --- | --- |
| 整理现有布局 | 已经按行组织，只想缩短跨行连线 | 沿用现有算法，保留主干行及网格外节点，只调整部分网格节点 |
| 层级排列 → 从左到右 | 剧情分支、流程、因果发展 | 按有向连线分层，前置在左、后续在右，分支上下展开 |
| 层级排列 → 从上到下 | 想纵向阅读的同一套层级关系 | 使用同一算法按纵向重新计算，父层在上、后续在下 |
| 网格排列 | 灵感便签、资源清单、暂未建立连接的内容 | 按稳定顺序排成整齐卡片，不使用连线决定节点次序，不增删任何连接 |

左右和上下是层级排列的方向参数，不是两套布局。首版不开放节点间距、引力、迭代次数、根节点等算法参数，不提供一个会静默替用户选算法的“智能布局”。复杂人物关系网先保留自由摆放；专用关系网或放射布局不在此次交付范围。

层级排列与网格排列会移动当前整张画布，包括作者手动摆过的节点，菜单说明“重新排列当前画布全部节点”。整理现有布局使用的是坐标是否在网格上的启发式，不承诺识别所有手动调整过的节点。首版不新增锁定节点、固定锚点或局部选区排列。

排列通过用户点击菜单，或 AI 在用户要求的建图、整理任务中显式调用工具执行。打开画布、单次增删节点、改正文、窗口尺寸变化或导出本身都不会触发重排。重排后同时保存节点坐标与画布的 `layout` 字段，后者表示上次成功使用的布局，不是持续生效规则。之后手动拖动只更新坐标，不清空布局选择。导出同时携带布局类型和最终坐标，接收方无需重新运行布局算法。

### 4.2 可用性与推荐规则

- 空画布和只有一个节点时，排列命令禁用；拖拽或编辑保存尚未完成时先等待其结束。
- 至少有一条有效有向边才启用层级排列；没有时显示“需要有向连线，可使用网格排列”，不悄悄替换成另一种算法。纯循环图仍允许层级排列，由循环组规则处理。
- 存在有向边时，在“从左到右”旁显示推荐标记。完全没有连线时推荐网格；只有无向关系时不推荐树形算法，也不自动挪动现有关系图。
- 推荐只依据节点和连线结构，不读取 AI 判断，不根据节点标题猜“主角”“开场”或“结局”，不产生网络请求。
- 首版统一处理整张画布。完成后轻提示“已排列 N 个节点”，不再加二次确认弹窗。没有坐标变化但布局字段发生变化时提示“已保存布局选择”；两者都没变化则提示“位置未变化”。撤销排列列为可选增强，不纳入首版必做范围。

本次保持现有边类型。时间线、因果、伏笔兑现是有向边，参与分层；人物关系、通用关联是无向语义，只展示，不用其数据库端点顺序推导上下级。影游作者使用时间线边表达先后或选项分支，标签记录选项文案。布局不赋予这些边运行时含义。

层级排列是可选布局，导出不要求图是树。纯人物关系图、带环网络、混合关系图和无连线便签板都可以导出。已有章节、地点或资料目录的 `parent_id` 保存在资源内容中，不自动变成画布连线，也不用于推断层级排列的父节点。

```text
场次 A ──调查──> 场次 B ─┐
      └─离开──> 场次 C ─┴─> 场次 D

便签、角色和其他参考节点仍可保留在同一张画布。
```

### 4.3 层级排列算法

新增 `lib/shared/models/canvas_tree_layout.dart`，作为纯布局函数，输入节点 ID、稳定排序键、实际尺寸和有向边，输出节点坐标、循环边标识及布局诊断。使用最长路径分层机制，布局计算与画布业务数据模型分离。

1. 校验端点，忽略悬空边对布局的影响并返回诊断。按 `sortOrder`、ID 建立稳定节点顺序，同一对端点的多条边在分层计算中去重，展示和导出仍保留全部边。
2. 求有向图强连通分量，将循环组收缩为临时计算节点。循环内的真实节点按稳定顺序排成一列；不增删数据库节点或连线。
3. 对收缩后的有向无环图做拓扑排序，以所有父节点的最长路径决定层级，汇合节点只出现一次，并位于全部前置节点之后。
4. 每层以稳定顺序初始化，进行四轮前后邻居重心排序，减少交叉；同值以稳定键决定顺序，保证重复执行结果一致。
5. 按真实卡片宽高计算层宽、层内间距和连通分量边界。主方向层间距至少 120，层内间距至少 80，画布起点留 56 / 44 的边距。
6. 多个独立分量沿副方向排列；不参与任何有向边的节点排在独立参考区。无向连线保持原样可见。
7. 上下排列按交换后的宽高重新计算，不简单交换最终 x、y，避免不同尺寸的便签重叠。

循环连线按现有画布连线机制渲染，保留真实方向。首版不保证回路线和所有跨层边完全避开其他边；不新增专用走线路点表，也不承诺零交叉。大循环组会比无环剧情图更宽或更高。

### 4.4 网格排列算法

在既有 `canvas_layout.dart` 中增加纯函数，沿用 `canvasGridColumnsPerRow` 的每行最多 6 列。节点按 `sortOrder`、ID 稳定排序，先从左到右填满一行，再换行；不使用当前坐标作为排序依据，避免窗口大小或上次手动位置影响重复排列的结果。

每列宽度取该列实际节点宽度的最大值，每行高度取该行节点高度的最大值；沿用横向 120、纵向 80 的间距和 56 / 44 的起点边距。节点在各自单元格左上角对齐，短行靠左，不创建占位节点。引用卡片和可变尺寸便签混排时也不重叠。

网格算法不分析边，不改变类型、标签、方向或资源顺序。它让卡片排列整齐，不承诺缩短连线；有复杂连接的图应由作者选择是否使用。

### 4.5 保存与失败恢复

`CanvasService` 保留现有 `autoLayout` 调用契约，新增层级排列和网格排列入口。三种操作共用计算与提交边界：读取完整节点、边和当前 `layout` 后计算位置，在同一事务中更新节点坐标、`canvases.layout` 及相应 `updatedAt`。批量节点写入复用 `CanvasDao.updateNodePositions`，外层事务覆盖画布字段写入；不要提前提交其中一部分。

提交前在同一事务重新比对节点集合、尺寸、位置、边集合及上次读取的 `layout`，发现用户或 AI 已修改则返回冲突，坐标和布局类型都不覆盖。画布行使用只包含 `layout` 与 `updatedAt` 的局部更新，避免旧快照覆盖用户新改的名称或描述。AI 的 `auto` 仍使用原有算法，并记录 `layout=auto`；新布局必须使用第 4.6 节的明确取值。

`moved=0` 只说明没有节点需要挪动，仍须保存本次成功选择的布局。若坐标与布局类型都相同，则不做无意义的写入或更新时间戳。失败时事务整体回滚，不能出现新布局类型配旧坐标。重排按钮运行期间禁止重复点击，耗时计算使用不可变快照在 isolate 执行；UI 与数据库对象不传入 isolate。

撤销排列作为可选增强单独保留，不是上述保存流程的依赖。若以后实施，应同时恢复上一次坐标与布局类型，并在有后续结构或位置变化时阻止覆盖。首版不增加撤销按钮、撤销记录或对应必过测试。

### 4.6 AI 如何操作布局

AI 与用户菜单调用同一套排列能力，不模拟鼠标点击，不新增专用工具名。沿用 `Write canvas/{name}/layout`，将它的静态可写枚举从 `auto` 扩展为 `auto / tree_lr / tree_tb / grid`。

| 用户要求 | AI 调用的 value | 行为 |
| --- | --- | --- |
| “帮我画一个分支剧情树” | `tree_lr` | 建完全部节点和连线后，从左向右排列一次 |
| “改成从上往下展开” | `tree_tb` | 对已有图执行一次纵向层级排列 |
| “把这些便签整齐排好” | `grid` | 对已有节点执行一次网格排列 |
| “整理现有布局”且未指定新布局 | `auto` | 沿用现有整理规则，不改成另一种算法 |
| “只修改这个节点的内容” | 不调用布局 | 保留已有位置 |

具体例子：用户要求“主角发现线索，可以调查或离开，两条路线最后在车站汇合”。AI 先创建画布，用默认摆位建立“发现线索、调查、离开、车站汇合”四个节点，再用创建结果中的节点 ID 建好四条有向连线。等待这些写入成功后，最后调用一次 `Write`，输入如下：

```json
{
  "path": "canvas/分支剧情/layout",
  "value": "tree_lr"
}
```

程序读取该画布的节点与连线，计算并保存位置，画布随数据更新显示结果。AI 只选择布局类型，不逐个计算最终像素坐标。生成过程中允许节点暂时使用默认位置，不在每创建一个节点或一条边后反复重排。

对已有画布做局部修改时，不顺带整理整张图；用户明确要求重排才调用布局。建图任务本身包含完成初次排版，用户说“画剧情树”后不要求用户再点一次菜单。修改完成后也不额外调用 `auto`，避免覆盖刚得到的层级或网格结果。

工具执行器必须读取通过校验的 value，并分派到与 UI 相同的服务函数，不能沿用当前忽略 value、始终调用 `autoLayout` 的实现。`Read .../layout` 保留现有 `node_count`、`edge_count`、`off_grid`、`grid_pitch` 统计摘要，增加可空的 `mode` 字段，读取实际保存的 `canvases.layout`。成功响应沿用 `ok`、`path`、`moved`；即使 `moved=0`，合法调用仍按第 4.5 节保存本次布局选择。

无效枚举仍返回 `invalid_fields`，不回退到 `auto`。不足两个节点时返回成功且 `moved=0`；多节点图没有有效有向边却请求 `tree_lr` 或 `tree_tb` 时，返回 `layout_requires_directed_edges`，不自动改网格。发生第 4.5 节的并发变更则返回 `layout_conflict`，AI 应重新读取图，不能改用逐节点坐标写入绕过冲突。

更新 `assets/bundled_skills/canvas-composition-guide.md` 正文中的布局调用表、收尾示例和自检规则，使其采用上述顺序与取值。原指南中“收尾一律 auto”“始终保留原有行”的规则只适用于原有整理，不能继续约束显式层级或网格布局。工具 schema 保持静态，布局选择不改变其字段或枚举；本次不修改任何工具整体描述或参数 description。

### 4.7 布局字段与数据库升级

| 项目 | 约定 |
| --- | --- |
| 表与字段 | `canvases.layout`，Dart 字段同名 |
| 存储类型 | 可空 `TEXT`，Dart 为 `String?` |
| 初始值 | `NULL`，表示尚未成功执行过布局选择 |
| 有效非空值 | `auto`、`tree_lr`、`tree_tb`、`grid` |
| 业务含义 | 上次成功使用的布局类型，不保证手动调整后的坐标仍符合该算法 |
| 写入时机 | 用户或 AI 排列成功后，与最终节点坐标同事务写入 |
| 读取用途 | 菜单标记“上次使用”，AI 读取摘要，JSON 导出 |

服务层校验取值，不新增 SQL CHECK、表级约束或枚举索引。新建和旧画布默认 null；不按坐标、画布名称或连线猜测旧图的布局。重命名画布、手动拖动、增删节点和局部改正文都保留该值，打开画布只恢复坐标，不因字段非空而再次排列。`Write .../layout` 仍是执行排列的操作，不开放绕过坐标计算、单独写布局标签的另一条入口。

发布依据已于 2026-09-22 核验：应用 v2.0.1 于 2026-09-20 正式发布，该标签对应的内容数据库代码 已使用 `schemaVersion=18`。数据库结构版本与应用版本是两套编号；本次必须按已发布数据库升级处理，不使用未发布 migration 合并例外。

1. 将 `NovelContentDatabase.schemaVersion` 从 18 升至 19，更新 `Canvases` 列定义及生成的 `CanvasEntry` / Companion / DAO 类型；新建 v19 库自动包含可空的 `layout TEXT`。
2. 新增 `migrateToV19`，并在 `onUpgrade` 中增加 `from < 19` 调用。为已有 `canvases` 添加可空 `layout` 列，旧记录保留原值和坐标，新字段为 null；不向 `migrateToV18` 追加本次升级行为。
3. 覆盖跨版本路径：`migrateToV15` 使用当前表定义建画布表，从 v14 升级时会提前得到 `layout`；因此 `migrateToV19` 检查列是否存在，缺少时通过 `m.addColumn` 添加，已存在时保留原值。这项检查服务于历史迁移链，不放进 onOpen，不用来掩盖漏加版本号。
4. 已使用 v18 的用户库与本地开发库均通过正式 v18 → v19 路径升级，不需要手工补列或调整 `user_version`，不重建业务表、不删除已有数据。此文档记录实施方案，不直接执行数据库升级。
5. 使用真实历史结构验证 v14、v15、v17、v18 直接升级到 v19，以及新建 v19 数据库。至少包含 v2.0.1 对应的 v18 结构 fixture；检查最终 `user_version=19`、列类型和可空性、旧行及坐标不变，并通过 Typed DAO 读取 null 布局值。另验证历史迁移链提前建好该列时不会重复添加。其他仍受支持的正式版本沿用项目迁移回归要求。

迁移注释只说明“v19 增加画布布局列”等稳定技术事实，不记录“尚未发布”之类的临时状态。若实施时版本 19 已被其他工作占用，按仓库迁移冲突规则核对并确认版本安排，不能覆盖另一条迁移。

## 5. 通用画布导出

### 5.1 文件形式

在画布浮动工具条增加“导出”，提供两个选项：

| 选项 | 文件 | 用途 |
| --- | --- | --- |
| 开发交接包，默认 | `<画布名>.zip` | 发给开发团队，包含结构、说明和预览 |
| 结构数据 | `<画布名>.json` | 导入脚本、版本控制或流水线读取 |

ZIP 内固定包含以下文件，内部路径不使用作者输入：

- `canvas.json`：唯一的机器可读真源，适用于全部画布类型。
- `canvas.schema.json`：该次导出的完整 JSON Schema，无需联网解析外部引用。
- `README.md`：格式版本、身份规则、字段解释、引擎接入说明及检查结果。
- `review.md`：按节点列出标题、便签全文、连接关系及引用资源内容，供人工审阅。
- `preview.svg`：按当前保存坐标生成整张图的矢量预览。

单独 JSON 与 ZIP 中 `canvas.json` 使用同一序列化实现。首版不做 PNG、PDF、Excel 或引擎原生文件；SVG 可直接用于放大审阅，JSON 保留完整结构。

### 5.2 快照与内容范围

导出整张画布，包含所有有效节点及其相互连接。没有选中节点或当前视口范围导出选项，避免遗漏接收方所需的目标节点。跨集引用允许；跨作品、跨画布连接不新增支持。

内容范围按引用来源区分：

- 画布直接引用的资源，导出下表约定的已保存业务内容。正文、小传和说明文本保留完整原值，不截取列表摘要；不包含尚未接受的 AI 提议或临时 overlay。
- 正文中的人物、地点，伏笔的铺垫与兑现对象，以及资源的父级目录等间接依赖，只补类型、ID、标题和有效性，帮助接收方识别引用；不连带导出其完整内容。
- 如果某个间接依赖也被画布直接引用，以完整内容快照为准。资源按 `(type, id)` 去重，画布中的多个引用节点仍各自保留 ID。
- 章节卷、资料文件夹等容器只导出被直接引用的那一条记录，不隐式递归导出子项。大纲节拍属于该大纲自身的内容，按顺序一并导出。
- 父级链补齐仅读取身份信息，使用 visited 集合阻止循环；其他间接依赖不继续展开其关系网络。不会因一个人物节点导出整部小说。

| 资源 `type` | 直接引用时的内容 |
| --- | --- |
| `chapter` | 章节或卷的类型、父级、顺序、正文、写前大纲、写后总结及状态 |
| `outline` | 大纲正文、状态、起始章号和有序节拍 |
| `character` | 人物小传、外观、描述、身份、动机、弧光、性格及其他下文列明的档案字段 |
| `foreshadowing` | 铺垫、兑现、状态及所关联章节或场次的 ID |
| `location` | 地点描述、类型、标签、状态和父地点 ID |
| `item` / `faction` / `skill` / `creature` | 各自说明正文、分类和状态，保留不同资源类型 |
| `document` | 文档正文、类别、标签、状态、父级和文件夹标记 |
| `screenplay_scene` | 场次归属、摘要及有序的动作、角色、对白等元素 |
| 便签 | 标题与全文直接存在节点上，不虚构一条引用资源 |

人物照片、头像、其他附件和媒体文件不打包，也不输出本机文件路径。地点的 `meta`、数据库同步信息、任意未声明字段、聊天和 AI 配置不导出。画布只导出自己保存的边，不自动收集 `entity_relations` 或其他关系表；父子目录结构与画布连线分别保留。

### 5.3 JSON 契约 v1

文件编码为 UTF-8，无 BOM；字段使用 `snake_case`；日期为 UTC ISO 8601；坐标是逻辑像素，单位与屏幕分辨率无关。所有业务 ID 按字符串处理。

| 顶层字段 | 类型与规则 |
| --- | --- |
| `format` | 固定字符串 `reveric.canvas` |
| `format_version` | 固定整数 `1`，破坏性变更升级版本 |
| `exported_at` | 导出快照时间 |
| `source` | `work_id`、`content_kind`、`canvas_id` |
| `canvas` | `title`、`description`、`layout`；layout 为 null 或四种有效布局值，表示上次使用的布局，实际摆位以节点坐标为准 |
| `nodes` | 节点数组，按 `sort_order`、ID 排序 |
| `edges` | 边数组，按 source、target、type、ID 排序 |
| `resources` | 去重后的各类型资源快照，按 type、ID 排序 |
| `analysis` | 结构诊断：`root_node_ids`、`terminal_node_ids`、`cycle_groups`、`isolated_node_ids` |
| `issues` | 问题数组：`severity`、`code`、`node_id`、`edge_id`、`resource_type`、`resource_id`、`message`；无关联的 ID 字段为 null |

节点字段固定为 `id`、`type`、`title`、`content`、`ref_type`、`ref_id`、`x`、`y`、`width`、`height`、`sort_order`、`z_index`、`color_key`。`type` 为现有 `sticky` 或 `reference`；便签的引用字段为 null，引用节点的 `content` 为 null。尺寸解析为最终数值，不输出 null；纸色仅输出项目认可的值，不原样泄漏任意 style 数据。

边字段固定为 `id`、`source_node_id`、`target_node_id`、`type`、`directed`、`label`。`type` 保持既有枚举；`directed` 按共享的边类型规则生成。空标签输出空字符串。无向边虽有两端字段，但不因此拥有剧情方向。

资源字段固定为 `type`、`id`、`title`、`status`、`detail_level`、`payload`。`status` 表示引用有效性，取 `available` 或 `missing`；`detail_level` 为 `identity` 或 `content`。有效且被直接引用的资源使用 `content`，其 `payload` 按 `type` 选择固定结构；仅补充身份或已失效的间接引用使用 `identity`，`payload` 为 null。

`payload` 是文件格式中的有类型内容，不是数据库 metadata，也不接受任意字段。Schema 使用 `oneOf` 与 `type` 常量约束以下结构：

| `type` | `payload` 固定字段 |
| --- | --- |
| `chapter` | `node_kind`、`parent_id`、`sibling_order`、`content`、`outline`、`brief`、`status`、`word_count`；分别映射现有章节记录，不从画布坐标生成章序 |
| `outline` | `content`、`status`、`start_chapter_num`、`beats`；每个 beat 为 `id`、`title`、`content`、`status`、`chapter_count`、`sort_order` |
| `character` | `role`、`gender`、`aliases`、`tags`、`biography`、`appearance`、`description`、`current_state`、`identity`、`age`、`motivation`、`arc`、`personality`、`behavior_tags`、`first_appear_chapter_id`；behavior tag 为 `tag`、`context` |
| `foreshadowing` | `setup`、`payoff`、`status`、`setup_chapter_id`、`payoff_chapter_id`、`setup_scene_id`、`payoff_scene_id` |
| `location` | `description`、`location_type`、`tags`、`status`、`parent_id` |
| `item` / `faction` / `skill` / `creature` | `content`、`category`、`status` |
| `document` | `document_type`、`content`、`category`、`tags`、`status`、`parent_id`、`is_folder` |
| `screenplay_scene` | 下文列出的场次字段 |

字段按源模型类型输出：文本为字符串；章节编号、数量和顺序为整数；文档 `is_folder` 为布尔值；人物 aliases、tags 为字符串数组，behavior_tags、beats、elements 为对象数组；地点与文档 tags 保持源模型的字符串表示。父级、首次出场和铺垫兑现关联 ID 允许 null。`payload.status` 是业务状态，和外层表示有效性的 `status` 含义不同。人物 `current_state` 仅是写作资料快照，不代表游戏存档。

`screenplay_scene` 的 `payload` 固定包含：

- `season`：`id`、`number`、`title`。
- `episode`：`id`、`number`、`title`。
- `scene_number`、`synopsis`、`stage`、`target_duration_seconds`、`estimated_duration_seconds`。
- `elements`：按正文顺序排列，每项包含 `id`、`type`、`text`、`character_id`、`extension`、`location_id`、`interior_exterior`、`time_label`。不适用的引用与场景字段为 null，`text`、`extension` 为字符串。

`elements.type` 固定支持 `scene_heading`、`action`、`character`、`parenthetical`、`dialogue`、`transition`、`subtitle`、`note`。人物和地点通过 `resources` 中相应类型的 ID 解析名称。正文保持顺序、换行及字符原值，不压平成丢失类型的字符串。

`analysis` 的根、末端和循环组只基于有向边计算，候选集仅包含至少参与一条有向边的节点。根节点是入度为零的结构节点，末端是出度为零的结构节点，都不等同于游戏入口或结局；循环图可能没有根或末端。`cycle_groups` 保存循环组的节点 ID 数组。没有任何连接的节点列入 `isolated_node_ids`。只连接无向关系的参考节点不列入根、末端候选。

Schema 使用 [JSON Schema Draft 2020-12](https://json-schema.org/draft/2020-12)，通过本地 `$defs` 定义各对象；v1 的上述字段全部必填，可空位置显式允许 null，拒绝未声明字段。新增字段或枚举值按新格式版本发布，导入方必须检查 `format_version`，不能把未知版本静默当成 v1。当前仍在起草 v1，通用命名直接替换原草案的 story 命名，不产生已发布文件的兼容迁移。

### 5.4 ID 与引擎映射

开发方用 `(work_id, canvas_id, node_id)` 标识图节点，用 `(work_id, resource_type, resource_id)` 标识资源。连线使用原 edge ID。大纲资源的 ID 使用其 `documentId`，保留现有引用契约；重命名、移动和重排不生成新 ID，删后重建是新对象。

每次导出是完整快照，不是增量补丁。开发方可以比较相同作用域下前后两次导出，识别增加、修改和消失的节点；导出本身不命令引擎删除任何资源。开发方把自己的资源 GUID、配音或视频引用保存在独立映射中，避免下一次导入覆盖人工接入结果。

画布坐标和 JSON 数组次序不代表选项展示顺序。`label` 也不是机器条件。接入方需明确选择哪些边类型代表流程，以及如何映射入口、结局、选项顺序与条件；首版 README 必须解释这些边界，不写“导入后即可运行”。

现有画布约束同一对端点、同一种边类型最多一条边。若“接受”和“拒绝”两条选项直接指向同一场次，作者需用两个便签表示各自选项，再分别连接目标场次；交接包保留这两个节点。首版不为此修改既有唯一索引，也不把两个选项合并成一个标签来假装支持。

### 5.5 预览与审阅稿

`preview.svg` 从同一份导出快照生成，不截当前屏幕，也不读取 flow controller 的内部 JSON。后者包含 UI 数据、视口及库实现细节，不能当作长期交接契约。

SVG 使用当前坐标、最终节点尺寸、边方向与标签，内容包围盒包括节点、连线和标签，四周留 48 的边距。采用固定浅色背景，显示标题、资源类型与便签摘要；长正文只在 `canvas.json` 和 `review.md` 中完整保存。预览以阅读结构为目的，不承诺逐像素复刻编辑器。

用已有 `xml` 库生成 XML 并转义文本，只输出 `rect`、`path`、`text`、`tspan`、`title` 等静态元素；不输出脚本、外链、`foreignObject` 或磁盘路径。多行文字显式拆分，字体使用系统回落，不打包字体文件。文本规则参考 [SVG Text](https://www.w3.org/TR/SVG2/text.html)。

`review.md` 使用稳定节点 ID 作段落锚点，列出每条连线的 ID、类型、方向和标签。各资源按类型展示自己的字段和正文，场次正文复用 `screenplay_element_render.dart` 并开启 note 输出；同一资源只展开一次，其余节点链接到同一个资源段落。包含换行、反引号和 Markdown 标记时须正确处理，不能使作者正文破坏包内结构。

### 5.6 导出流程与错误处理

```text
CanvasRegion
  -> 等待编辑保存
  -> CanvasExportOrchestrator
       -> 只读事务收集 DAO 快照
       -> 校验引用与图结构
       -> JSON / Markdown / SVG 编码
       -> ZIP 打包
  -> 系统保存面板
```

1. 将编辑焦点交还画布。中文组词尚未提交时提示完成输入，不强制截取 composing 文本。
2. 通过区域级编辑会话 flush 便签与连线标签，等待已发出的写入和拖拽结束保存。现有 `void` 回调需在该边界改为可等待的 Future；等待失败则取消导出，不把旧版本伪装成最新结果。
3. 用同一个只读数据库事务收集画布、节点、边、直接引用资源内容与间接依赖身份。按资源类型批量读取；字段需要的父级身份按层批量补齐，避免每个节点重复查询。事务完成后释放数据库，不把文件面板或 ZIP 编码放进事务。
4. 校验并生成报告。空画布禁用导出。任意直接引用资源失效、边端点缺失、重复 ID、非法数值或无法识别的节点、边及资源类型阻止开发导出，并提供节点定位；规则不按“是不是剧本”区别对待，不静默删除有问题的内容。
5. 空文本、有向边空标签、多个结构根、孤立节点、循环和间接资源失效属于诊断，保留数据并写进 `issues` 与 README。间接失效资源保留类型、ID、可得的标题和 `status=missing`；无标题快照时使用 ID，不编造名字。无向人物图没有剧情入口不视为错误。
6. 将所有文件从同一不可变快照生成。编码使用 isolate；用户此时继续修改画布，不改变已生成的快照时间与内容。
7. 用系统保存面板输出 `.zip` 或 `.json`，区分成功、用户取消、写入失败。文件名清理路径分隔符和控制字符，内部文件名固定；覆盖确认交由系统保存面板。

`severity` 为 `error`、`warning` 或 `info`。错误码固定为 `invalid_direct_reference`、`missing_edge_endpoint`、`duplicate_id`、`invalid_geometry`、`unsupported_type`；警告码为 `empty_content`、`missing_dependency`；信息码为 `empty_directed_edge_label`、`multiple_roots`、`isolated_node`、`cycle`，因为这些图形结构可能是作者本意。`empty_content` 只针对章节正文、大纲正文及节拍均空、场次无正文元素、非文件夹资料文档正文空、便签标题和正文均空；不要求目录或人物每个档案字段都非空。接收方按 code 判断，不解析本地化 message。

编排类命名为 `CanvasExportOrchestrator`，按操作创建，不新增常驻导出 Service。保存逻辑采用项目现有文件导出约定，日志只记录阶段、数量和错误类型，不记录正文、完整用户路径或账号信息。只清理本次创建的 App 临时副本，不在失败时递归删除用户目录；写入失败须告知可能留下不完整的目标文件，不把清理外部文件当成自动回滚。

导出按钮不改变已有画布权益规则，不新增 feature code。排列和导出均复用现有画布编辑权限入口，未授权时沿用现有升级提示。

## 6. 代码落点

本方案涉及超过 8 个文件，预计约 25 至 35 个生产、测试及本地化文件。新增一个短生命周期 Orchestrator；布局、编码和校验优先使用纯函数。

### 场次接入

- `lib/shared/database/novel_content_database.dart`：扩展画布引用类型常量，在 `Canvases` 增加可空 `layout` 列，将 schema version 升至 19 并注册 `from < 19` 升级调用。
- `lib/shared/database/novel_content_database_migrations.dart`：新增 `migrateToV19`，覆盖 v15 使用当前定义建表和 v18 等已有旧画布表两条路径，不修改 v18 的升级行为。
- `lib/shared/services/canvas_service.dart`：解析场次引用与最新标题，增加层级、网格排列入口；统一校验并原子保存布局类型与坐标，保持原有 `auto` 算法。
- `lib/shared/providers/canvas_providers.dart`：接入场次投影监听，使标题、所在集与失效状态响应源数据变化。生成源变更后检查 `.g.dart` diff。
- `lib/desktop/features/canvas/widgets/canvas_resource_picker.dart`：场次分组、筛选及去重选择。
- `lib/desktop/features/canvas/widgets/canvas_node_widget.dart`、`canvas_detail_layer.dart`：场次标签、详情和打开动作。
- `lib/desktop/features/canvas/widgets/canvas_region.dart`：使用已有导航请求连接场次正文，不往 `NovelEditor.build` 追加局部状态。
- `lib/shared/services/ai/tools.dart`：核对 `ref_type` 枚举和 `ref_id` 引用目标识别 `screenplay_scene`；扩展 layout 字段的静态可写枚举，并在读取摘要 schema 中增加可空的 `mode`，保持 `auto` 算法。首版不新增 AI 导出命令，不改任何工具 description。
- `lib/shared/services/ai/tools_canvas.dart`：将经过校验的 layout value 传入执行器，分派到与 UI 相同的服务函数；沿用布局活动通知和 `ok / path / moved` 响应。
- `assets/bundled_skills/canvas-composition-guide.md`：按第 4.6 节更新正文中的取值、调用顺序及局部修改规则，不再要求所有图收尾都执行 `auto`。

### 布局与编辑边界

- 新增 `lib/shared/models/canvas_tree_layout.dart`：有向图分层、循环组、多分量排布和诊断。
- `lib/shared/models/canvas_layout.dart`：增加网格排列纯函数；共享既有卡片尺寸与间距。把边方向判定放到共享层，供导出与布局使用。
- `lib/desktop/features/canvas/canvas_palette.dart`：委托共享的边方向规则，保持原有显示结果。
- `lib/shared/database/novel_content_daos/canvas_dao.dart`：复用批量坐标写入，补画布布局字段局部写入和快照比对；由同一事务覆盖，不加新表或索引。
- `lib/desktop/features/canvas/widgets/canvas_board.dart`：扩展现有浮动操作区，新增排列菜单与导出入口，按保存字段标记上次使用的布局；撤销入口不纳入首版。
- 新增 `lib/desktop/features/canvas/edit_session.dart`：区域级编辑 flush 和等待中的写入，不提前加入撤销记录或全局状态。
- `lib/desktop/features/canvas/widgets/canvas_sticky_editor.dart`、`canvas_detail_layer.dart`：可等待的保存回调与 IME 安全 flush。

### 导出

- 新增 `lib/shared/models/canvas_export.dart`：v1 快照、问题报告和稳定序列化契约。
- 新增 `lib/shared/services/canvas_export/orchestrator.dart`：一致性快照、引用闭包、校验与打包编排，普通画布不要求存在 screenplay root。
- 新增 `lib/shared/services/canvas_export/resources.dart`：按明确资源类型采集白名单字段；复用各资源 DAO，不原样序列化数据库行，不使用猜字段或反射 fallback。
- 新增 `lib/shared/services/canvas_export/format.dart`：JSON、各资源类型的离线 Schema、README 和审阅稿生成；普通文本保留原值，场次复用已有剧本文本渲染。
- 新增 `lib/shared/services/canvas_export/svg.dart`：纯快照到静态 SVG 的转换。
- 新增 `lib/shared/services/canvas_export/save.dart`：桌面保存、取消、失败和临时资源生命周期。
- 新增 `lib/desktop/features/canvas/widgets/export_dialog.dart`：格式选择、问题定位、执行反馈；不得把技术字段说明塞进正常用户操作流程。

新增界面文案同步 `lib/shared/localization/locale_keys.dart`、`assets/translations/en/canvas.json`、`assets/translations/zh-CN/canvas.json`。场次术语优先复用 screenplay namespace。新增 Dart 文件按项目要求补职责与关联文件，使用 Hooks、表单或文件保存时完整读取对应规则。

## 7. 交付顺序与估算

| 阶段 | 可独立交付的结果 | 依赖与主要验证 |
| --- | --- | --- |
| A：场次引用 | 现有画布能引用、显示并打开场次，源数据变更及时反映 | 引用、跨集移动、拆合场、删除、AI 资源契约回归 |
| B：布局选项 | 用户菜单和 AI 的 Write 入口均支持原有整理、左右或上下层级排列及网格排列，并保存布局类型和坐标 | 独立于 A；包含字段迁移、菜单与工具分派、图形边界、确定性、原子写入和并发冲突验证 |
| C：通用开发导出 | 普通小说、剧本和纯便签画布均可输出 JSON 或交接 ZIP，携带布局字段 | 依赖 A、B；全部资源类型完整交付，按已保存坐标导出，不额外重排 |

按单人实现粗估 7 至 11 个开发日，包含全部资源类型的针对性回归，不含游戏引擎导入插件、真机跨平台排障或用户追加的运行规则。主要成本在编辑保存一致性、资源快照、图布局边界及交接契约，不在画布基础组件。

## 8. 验收与验证

### 功能与边界

| 场景 | 必须满足的结果 |
| --- | --- |
| 添加场次引用并打开 | 正确定位实际季、集、场次；不复制正文 |
| 场次重命名、跨集移动、手机修改 | 画布投影刷新，导出来自当前有效数据 |
| 拆场、合场、删除 | 不自动改写作者连线；保留原引用或明确显示失效 |
| 单链、二叉分支、菱形汇合、多根 | 不丢节点、不复制汇合节点，无环边沿主方向前进 |
| 循环、纯循环、孤立节点 | 操作有限时间内结束，节点全部可见，连线和方向不被删除或翻转 |
| 变尺寸便签、左右和上下排列 | 节点矩形不重叠，重复排列结果一致 |
| 网格混排引用卡片与变尺寸便签 | 每行最多 6 列，按稳定顺序排列，无重叠，节点与边数量不变 |
| 纯无向关系图、无边便签板 | 层级排列禁用且说明原因，网格可用；不会自动改算法 |
| 只有有向边、无向有向混合、纯循环 | 层级排列可用，方向参数只改变摆位，不改变业务关系 |
| 打开画布、修改正文、缩放窗口或导出 | 原坐标保持不变，不自动重排 |
| 原有整理菜单与 AI 整理调用 | 继续执行原有主干行与网格位置规则 |
| AI 的 `auto / tree_lr / tree_tb / grid` | 四个值分别进入正确的共用服务，旧 `auto` 结果保持兼容 |
| AI 建立四节点菱形图后调用 `tree_lr` | 工具成功，汇合节点仅出现一次，正文和连线原值不变 |
| AI 请求未知布局或对无向图请求层级排列 | 返回明确错误，不静默执行 auto 或 grid |
| AI 布局时发生并发位置或结构变化 | 返回 `layout_conflict`，无部分回写 |
| AI 仅执行节点正文 Write / Edit | 所有节点坐标不变，不从写内容自动触发布局 |
| 排列中发生 AI 写入或用户拖动 | 检测冲突，整次拒绝写入，不覆盖新状态 |
| 排列成功后重开画布 | 布局字段与坐标都保留，菜单正确标记上次使用，不自动重排 |
| 布局类型写入或节点批量写入失败 | 同一事务整体回滚，字段与坐标均保持原值 |
| `moved=0` 但布局类型变化 | 新布局类型仍保存；字段与坐标均不变时不更新时间戳 |
| 手动拖动、局部改内容、增删节点 | 保留上次 layout 值，不触发重排 |
| 新建库与 v14 / v15 / v17 / v18 历史库升级 | 最终 user_version 为 19，存在可空 TEXT 列 layout，旧行与坐标不变，Typed DAO 可读 null；历史链提前建列不会重复添加 |
| AI Read 布局摘要与 JSON 导出 | 摘要 mode、JSON canvas.layout 和数据库字段一致 |
| 便签输入后立即导出 | 包含最后一次已提交输入；组词中不导出半成品 |
| 导出期间修改正文 | 包内 JSON、SVG、审阅稿来自同一快照 |
| 场次内人物、地点、note、中文和多行对白 | 类型、顺序、换行及名称解析完整 |
| 一个场次被多个节点引用 | 节点实例全部保留，正文资源去重 |
| 两个选项最终汇入同一场次 | 可通过两个便签节点表达，导出不合并节点或丢弃连接 |
| 非法端点、任意类型的失效直接引用、未知类型 | 阻止开发导出并定位问题，无静默跳过 |
| 两次导出只重命名和挪动节点 | 节点、边、资源 ID 不变；不依赖显示名称识别身份 |
| ZIP 与单独 JSON | 同一快照下 JSON 相同，包内 Schema 能校验通过 |
| SVG 与 Markdown 特殊字符 | 能解析，作者文本不产生脚本、外链或破坏包内结构 |
| 系统保存取消、拒绝访问、磁盘写失败 | 不提示成功、不修改业务数据、不删除用户目录 |
| 普通小说画布、纯便签板 | 没有 screenplay root 也能导出，格式保持 `reveric.canvas` |
| 人物关系图、无向网络 | 保留无向语义，不制造入口、结局、父子关系或剧情选项 |
| 章节卷、大纲节拍、地点层级、资料文件夹 | 保留各自已有层级和顺序，既不从坐标推导目录，也不展开未选入画布的容器子项 |
| 混合全部资源类型的画布 | 每种 payload 匹配对应 Schema，资源内容与源记录的白名单字段一致 |
| 一个资源既是直接引用又是间接依赖 | 只输出一份 content 快照，所有节点仍保留 |
| 父级链循环、间接引用失效 | 遍历能结束，失效依赖有明确诊断，不递归导出整部作品 |
| 普通资源在手机端被修改或删除 | 导出重新读共享数据库，采用当前内容或明确阻止失效的直接引用 |

开发测试规模固定覆盖 500 个节点、1,000 条边，布局计算目标小于 1 秒；该数值是验收目标，需在开发机记录设备与实测值。另用 5,000 个节点、10,000 条边验证终止性与不丢数据，不承诺同样时延。正文快照用 10 MiB 中文文本验证完整性，编码期间 UI 保持可响应；不为性能达标截断正文或隐藏节点。

新增测试集中在 `canvas_tree_layout_test.dart`、`canvas_export_test.dart`、`canvas_export_save_test.dart`；网格用例扩展现有 `canvas_layout_test.dart`。Widget 测试覆盖场次引用、排列菜单的可用性和推荐、工具条及保存后立即导出。`canvas_export_test.dart` 必须按本方案的资源类型表逐项验证字段、直接引用与依赖身份、缺失数据及普通小说导出，不得只用剧本 fixture。`tools_canvas_test.dart` 更新原有“layout 只接受 auto”断言，覆盖四种取值分派、错误分支、并发和指南示例；`tools_schema_test.dart` 验证枚举静态且两个作品类型一致。工具测试验证调用契约，不宣称已验证真实模型会在正确时机选择调用；真实模型端到端评估按项目规则由用户另行发起。

实施后按以下顺序运行，Flutter 测试保持串行。下面是计划命令，本轮写方案未运行这些测试。

```sh
make codegen
fvm flutter test test/shared/database/novel_content_database_migration_test.dart
fvm flutter test test/shared/models/canvas_tree_layout_test.dart test/shared/models/canvas_layout_test.dart test/shared/models/canvas_auto_layout_test.dart
fvm flutter test test/shared/services/canvas_export_test.dart test/shared/services/canvas_export_save_test.dart
fvm flutter test test/shared/database/canvas_dao_test.dart test/shared/services/canvas_service_test.dart test/shared/services/screenplay_service_test.dart
fvm flutter test test/shared/services/ai/tools_canvas_test.dart test/shared/services/ai/tools_schema_test.dart
timeout 180s fvm flutter test test/desktop/features/canvas
fvm flutter analyze lib/shared/models/canvas_tree_layout.dart lib/shared/models/canvas_layout.dart lib/shared/models/canvas_export.dart lib/shared/services/canvas_export lib/shared/services/canvas_service.dart lib/shared/providers/canvas_providers.dart lib/desktop/features/canvas
```

`make codegen` 使用项目锁定的 FVM Flutter；检查数据库、DAO 和实际修改 provider 的生成 diff，不手改生成文件。迁移回归扩展 `novel_content_database_migration_test.dart`，原子保存与重新打开验证扩展 Canvas DAO / Service 测试。Widget 测试按项目规则隔离真实翻译资源缓存和数据库 stream，不能用一串无关 provider override 掩盖错误。桌面三平台各手工验证中文文件名、取消、ZIP 打开和场次导航；无法执行的平台要单独记录未验证。移动端验证覆盖既有章节、人物、场次等资源编辑对共享数据的影响，不宣称新增手机画布已完成。撤销排列不属于首版验收项。

## 9. 兼容、风险与回退

- 旧数据库通过 v19 正式迁移新增可空 `layout` 列，不修改原坐标或推断历史布局。原有 `auto` 算法保留，每次成功排列同时记录类型；场次引用仍是现有引用节点，删除画布节点不删除场次正文。
- 旧客户端不认识 `screenplay_scene`，回退应用版本时可能显示未知或失效引用。应用回退不会自动清理这些节点；不能承诺旧版本完整可用，也不得让“清理失效”把版本不识别当成资源已删除。
- 功能代码可停用新增入口，保留已存布局类型与坐标，不删除新增列或执行逆向表重建。数据库升级到 v19 后，不承诺只支持 v18 的旧客户端可直接打开；不能通过手改 `user_version` 伪装降级。应用回退按项目数据库版本兼容策略处理。
- 画布原有边删除规则保持不变，本方案不新增业务数据硬删除入口。导出是只读快照，不写回源资源或修改连线。
- 复杂循环和高密度连线仍可能交叉；首版保证节点布局和数据完整，作者可以手动微调。需要专用回路线通道时另做布局增强。
- 引擎或插件未指定是当前交接边界，不阻塞通用格式实现。接入团队负责维护原生映射，不能把图的根、叶节点和自由文本标签直接当成确定的游戏规则。
- 本方案不修改 AI 工具描述。若实施中发现必须调整工具整体或参数 description，应先列出具体文案与原因，按仓库规则取得明确确认；不要随引用类型接入顺手改提示词。
