# SG：宫格切分、分镜组与通用分组

> 本文定义制作画布上「宫格切分」「宫格高清生成」以及通用分组（普通组／分镜组）的功能合同与实施拆分。进度只在[实施任务](README.md#实施任务) SG-01 至 SG-06 维护。

[返回方案总览](README.md) · [片段与制作](production.md) · [视角与构图](view-composition.md) · [功能验收](verification.md)

## 背景

作者常用「九宫格」「25 宫格」一类预设一次生成多镜头拼图（见[视角与构图](view-composition.md)的预设），但拼图生成后只能整张使用：不能把其中一格单独连给视频节点作首帧，也不能只把某几格放大成高清图。画布上也没有任何分组能力，多张相关图片只能靠摆放位置表达关系。

### 现状

- 画布节点只有平铺一层：`CanvasNodes` 没有父子关系列（`lib/shared/database/novel_content_database.dart` `class CanvasNodes`）。场次色带 `_BandLayer`（`lib/desktop/features/production/board.dart`）是唯一的「整组框选、整组拖动」能力，成员由片段的 `sceneId` 推出，不是可编辑的分组。
- 派生素材已有完整链路：`library.importFile` 登记资产，`canvas_service.addDerivedOutput` 建素材节点并以 `derived_output` 边连回来源（全景截图 `panorama_service.dart` 即如此）。
- 派生生成已有链路：`canvas_service.addDerivedImage` 在一次 `write` 内建图片生成节点、写输入与预设（`view_derive_orchestrator.dart`）。
- 节点卡片尺寸在渲染时由 `productionNodeSize(node, aspect:)`（`node_card.dart`）按画面比例算出，`CanvasNodes.width/height` 不参与展示。
- 画布使用仓库内置的 `lib/third/flow/vyuh_node_flow`，其中已有 `GroupNode`，支持 `explicit`（成员显式、外框自动包住成员）与 `parent`（成员显式、外框手动调整大小、整组拖动带成员）两种行为。生产画布尚未使用。
- 内容库 schema 当前为 v20；本地 tag `v2.3.2` 发布的是 v19（核对于 2026-10-17），v20 未发布。

## 目标与非目标

| 目标 | 成功信号 |
|---|---|
| G1 宫格切分 | 任意有图的图片节点选 4／9／16／25 宫格或自定义 R×C，进入切分态，勾选格子后「创建分镜组」，画布出现紧凑排列的分镜组，每格是独立图片素材节点，可单独连给视频节点 |
| G2 宫格高清 | 切分态勾选格子，选 2 倍／4 倍后「生成高清图片」，画布出现一个分镜组，每格是以该格裁图为参考的图片生成节点，按现有任务流程生成 |
| G3 通用分组 | 分组节点与成员关系持久化；整组拖动、删除、解组；分镜组与普通组可以互相转换，重启后状态不变 |
| G4 分镜组编辑 | 分镜组工具栏的比例、宫格、序号、拼接、清空、空格位补图都能用，结果持久化 |

不包含：在画布多选后新建普通组、把节点拖进或拖出分组改变成员（只通过本文列出的操作改变成员）、分组嵌套、高清提示词的真实模型评测、宫格自动识别分割线（只按等分切）、Agent 专用分组工具（现有画布工具只做兼容，见[服务与编排](#服务与编排)）、移动端入口（制作画布不在移动端）。数据模型不阻止以后补上前两项。

## 用户流程

### 宫格切分

1. 选中有可用图片的图片节点（生成节点的采用结果或图片素材节点）。节点工具栏新增「宫格切分」下拉：4 宫格 (2×2)、9 宫格 (3×3)、16 宫格 (4×4)、25 宫格 (5×5)，以及「自定义 ›」二级面板：5×5 方格，悬停高亮左上到当前格的范围并显示 `R×C`，点击确认；1×1 不可选。没有可用图片时下拉禁用并说明原因。
2. 选定后节点进入**切分态**：图片上叠加等分网格线，节点工具栏换成切分工具栏：关闭（×）、宫格规格（可再切换）、「已选 N 个宫格」、创建分镜组、生成高清图片 + 倍数下拉（2 倍／4 倍，默认 2 倍）。
3. 点击格子切换选中，选中格高亮并显示 `行-列`（如 `2-2`）。切分态与选中格只存在于本次界面会话（Hooks 本地状态），不入库；取消选中节点、按 Esc 或点 × 退出。
4. 「创建分镜组」：未选任何格子时切全部格子，否则只切选中格。完成后退出切分态并选中新分镜组。
5. 「生成高清图片」：至少选中 1 格才可用。完成后退出切分态并选中新分镜组，各格开始生成。

### 分组的显示与操作

- **分镜组**：外框紧贴成员，左上方标题「宫格分镜组（N 张）」，N 为当前成员数，自动计算不入标题。格子按 `行×列` 紧凑平铺，间隙 2 px；单格尺寸取 `productionNodeSize` 对分组比例给出的尺寸（与同比例的普通图片卡片一样大），外框 = 列数 × 格宽 + 间隙，标题在外框上方、不占格子区域。格内图片按分组比例 cover 显示，不显示各节点的卡片标题；保留 AI 生成角标与各自的输出端口，每格可单独连线。空格位显示「+」。
- **普通组**：外框可拖动四角调整大小，但不能小于成员外接矩形加内边距；左上方标题默认「分组 N」；成员按各自的实际显示尺寸、各自位置显示，带卡片标题。
- **选中与拖动**：点击外框空白或标题选中分组节点，工具栏换成分组工具栏；拖动外框整组移动（成员与外框一起）。分镜组的格子可单独选中（连线、预览、作为参考、删除），但不能单独拖动，显示位置始终由分组布局算出；普通组成员可在框内自由拖动，拖出框外时外框跟着扩大，不会离开分组。
- **框选**：框选结果包含分镜组格子但不含其分组时，可以删除，拖动时不移动这些格子；包含分组时按整组拖动。
- **端口**：分组节点左侧只有接收来源的入口（同 `productionNodePorts` 的 `derived`），右侧出口只承载拼接结果的 `derived_output`，不能拖出生成输入连线。
- **删除**：「…」菜单删除分组时确认，提示将一并删除 N 个成员；单独删除某格后该格位留空。
- **解组**：删除分组节点并清空成员的 `parent_id`。分镜组解组前先按「转普通组」的规则恢复尺寸和重排，避免紧凑格子在恢复原尺寸后重叠。

### 分镜组工具栏

| 按钮 | 行为 |
|---|---|
| 比例 | 16:9、9:16、4:3、3:4、1:1、21:9；只改格子显示比例，不改图片文件 |
| 宫格 R×C | 与切分同款的规格选择。新规格容量不能小于当前成员数，否则该项禁用；切换后成员按当前顺序重新紧凑排列，空格位移到末尾 |
| 拼接(2k) | 按当前比例、宫格、顺序把格子在本地拼成一张 PNG，长边 2048，空格位填底色；开启序号时序号一并画入。结果登记为图片资产，用 `addDerivedOutput` 放在分组右侧，`derived_output` 边连回分组节点。不调用模型 |
| 序号 | 开关；开启后每格左上角显示 1…N（按格位，空格位也计数） |
| 清空 | 确认后软删除所有成员，保留空分组与宫格规格 |
| 空格位「+」 | 打开现有资产选择器（`asset_picker.dart`）选图片，在该格位建图片素材节点作为成员 |
| 转普通组 | 布局改为普通组：成员恢复 `productionNodeSize` 的实际显示尺寸，按宫格顺序以卡片间距重排，外框按成员外接矩形加内边距；去掉比例、宫格、序号设置 |
| 解组 | 见上 |

普通组工具栏：重命名、转分镜组、解组。「转分镜组」要求所有成员都是图片节点（否则禁用并说明），按成员当前位置先行后列排序，选择能放下成员数的最小方阵（如 7 个 → 3×3），比例取第一个成员的最近比例。

## 数据与真源

### 模型

```text
canvas_nodes（已有表）
- type            新增取值 'group'（canvasNodeTypeGroup）
- parent_id       新增：nullable text，指向同一画布上 type='group' 的节点 id
- sort_order      已有：分组内顺序；分镜组中即格位下标 = 行 × 列数 + 列
- x / y           已有：分组节点为外框左上角；成员仍为画布绝对坐标
- width / height  已有：分组节点外框尺寸（普通组可手动调整；分镜组由布局算出后写回）
- title           已有：分组标题；分镜组为空时显示「宫格分镜组」
- style           已有 JSON：分组节点上的 group 键，见下
```

分组节点 `style.group`：

```json
{"layout": "storyboard", "cols": 5, "rows": 5, "ratio": "16:9", "numbered": false}
{"layout": "free"}
```

- `layout` 只有两个取值：`storyboard`（分镜组，紧凑宫格）和 `free`（普通组）。转换就是改写这个键，分组节点 id、成员和连线都不变。
- `cols/rows/ratio/numbered` 只在 `storyboard` 时存在；转普通组时一并移除。
- 写入沿用 `style` 的合并规则（见[视角与构图](view-composition.md#数据与真源)）：只改 `group` 键，保留其他键。

### 成员与连线规则

| 内容 | 规则 |
|---|---|
| 分组成员 | `parent_id` 指向的节点必须是同一画布、未删除、`type='group'`；分组不能有 `parent_id`（不嵌套） |
| 分镜组成员 | 只能是图片节点：图片素材节点（资产 type=image）或 kind=image 的图片生成节点。`sort_order` 在 `[0, cols×rows)` 内且组内唯一；空缺即空格位 |
| 普通组成员 | 与分镜组相同，只能是图片节点。本轮普通组只来自「转普通组」，成员天然是图片；限制为图片也避免片段节点同时受场次色带和分组两套整组拖动 |
| 切分产物 | 每格一个图片资产（原像素裁切的 PNG，名称「源标题 行-列」），一个图片素材节点（`ref_type=asset`） |
| 高清产物 | 每格一个 kind=image 生成节点：输入为该格裁图资产 `ProductionInput.asset(…, reference_image)`，预设 `ImageGenerationMethod.upscale`，分辨率 2 倍→2K、4 倍→4K，比例取所选模型支持的最接近裁图宽高比的值 |
| 来源连线 | 源图片节点 → 分组节点一条 `derived_output` 边；拼接结果由分组节点 → 拼接节点一条 `derived_output` 边。`derived_output` 的注释从「视频处理」放宽为「由来源节点本地派生」 |
| 分组节点作输入 | 分组节点不能作为生成输入：连线落点校验拒绝以分组为来源的 `generation_input` |
| 分镜组成员坐标 | 库里的 `x/y` 是布局结果的副本，供连线端点、落点避让和 Agent 读取；分组移动或布局变更时整组重写。单独修改分镜组成员坐标的请求被拒绝 |
| 指向已删除分组 | 读取时 `parent_id` 指向不存在或已软删除的分组，视为不在分组中，不报错 |

以上全部在 Dart 服务层校验，不加 CHECK、外键或触发器。

### 为什么这样存

- 用 `parent_id` 列而不是在分组 `style` 里存成员列表：成员关系需要被查询（删除节点时找分组、读画布时分组），列加索引可以直接查；列表放在 JSON 里，删除、复制成员时每处都要同步改另一个节点。
- 成员坐标保持绝对坐标：现有拖动、连线、落点、选择和 `derived_placement` 都按绝对坐标工作，改成相对坐标要改整条链路，收益只是拖动分组时少写成员坐标。
- 布局参数放 `style`：它描述「这个分组怎么摆」，与全景预览状态放在 `style.panorama` 同理；`layout` 决定可用的工具栏，但不改变成员的业务数据。

## 关键流程

### 创建分镜组（切分）

1. 读源节点可用图片（`canvas.inputAsset(ProductionInput.node(源, reference_image))`），在后台 isolate 用 `image` 包解码。
2. 按 `x_i = round(i × W / cols)`、`y_j = round(j × H / rows)` 等分，逐格裁切编码 PNG，写入临时目录。
3. 逐格 `library.importFile(purpose: production_output, source: 'grid_split')` 登记资产。
4. 确定分组规格：切全部格子时沿用切分规格；只切选中格时，选中格按原「先行后列」顺序紧凑排入能放下 N 格的最小方阵（与「转分镜组」同一规则，如 3 格 → 2×2）。`ratio` 取裁图宽高最接近的比例。
5. 在一次 `canvas.write` 内：建分组节点（`style.group` 为 storyboard）→ 按格建素材节点（`parent_id`、`sort_order`、按布局算出的坐标）→ 写源 → 分组的 `derived_output` 边。
6. 分组放在源节点右侧，按 `productionDerivedPlacement` 让位。
7. 失败：裁切或登记中途失败时整体放弃，不建分组；已登记的资产留在资产库（与全景截图一致，不硬删），错误经 `productionRun` 提示。

### 生成高清图片

1. 面板侧解析模型：用户默认生图模型（`resolvedAiModelOptionForKindProvider(kind: image)`），按 `ProductionImageCapabilities` 过滤支持 2K／4K 的规格；不支持的倍数在下拉中禁用并说明，不静默降级。没有可用生图模型时按钮禁用。
2. 裁切与资产登记同上，只处理选中格。
3. 分组规格按切分第 4 步的规则确定；一次 `canvas.write` 内建分组节点与 N 个图片生成节点（`shots.createImage` + `ensureClipNode`，写输入、预设、比例、分辨率、模型），写源 → 分组边。
4. 逐个按 `ViewDeriveOrchestrator.run` 的方式提交任务：任务行建好即返回，后续进度、失败与重做走图片节点既有交互。单个提交失败只在该格显示失败，不回滚分组和其他格。

### 分组移动、转换与解组

- 拖动外框：flow 层以 `GroupNode` 的 `parent` 行为带动成员，拖动结束一次 `moveNodes` 写入分组与全部成员坐标（同场次色带）。
- 布局变更（比例、宫格、转换）由 `ProductionGroupService` 计算新坐标，在一个 `write` 内改 `style.group` 与成员坐标。
- 解组：同一事务内软删除分组节点（及其 `derived_output` 边）、清空成员 `parent_id`。

### 删除

- 删除分组：软删除分组节点与全部成员（成员为图片生成节点时按 `removeNode` 软删除对应片段）。
- 删除成员：只软删除该节点；分组保留，空格位显示「+」。普通组最后一个成员被删除后分组仍保留，由作者删除或继续使用。
- 删除源节点：分组不受影响，与现有 `derived_output` 产物一致。

## 界面落点

| 位置 | 内容 |
|---|---|
| `lib/desktop/features/production/view/actions.dart` | 「宫格切分」下拉与自定义二级面板，进入切分态 |
| NEW `lib/desktop/features/production/grid/split_overlay.dart` | 切分态的网格线、格子选中与 `行-列` 标签 |
| NEW `lib/desktop/features/production/grid/split_bar.dart` | 切分工具栏：关闭、规格、已选数、创建分镜组、生成高清图片与倍数 |
| NEW `lib/desktop/features/production/grid/group_node.dart` | 分组外框、标题、空格位「+」、序号层；分镜组与普通组两种外观 |
| NEW `lib/desktop/features/production/grid/group_bar.dart` | 分镜组与普通组工具栏 |
| `lib/desktop/features/production/board.dart` | 分组节点接入 flow `GroupNode`；分镜组成员尺寸由分组布局给出、隐藏卡片标题；普通组外框调整大小 |
| `lib/desktop/features/production/node_card.dart` | `productionNodeSize` 增加分组布局给定尺寸的入口 |
| `lib/desktop/features/production/node_bar.dart` | 选中分组时显示分组工具栏；切分态显示切分工具栏 |

界面文案进入 `assets/translations/{en,zh-CN}/production.json`；重命名、删除、取消等通用动作复用 `common.*`。删除分组的确认说明使用专用 key。

## 服务与编排

| 文件 | 职责 |
|---|---|
| `lib/shared/database/novel_content_database.dart` | `CanvasNodes.parentId`、`canvasNodeTypeGroup` 常量；`canvasEdgeTypeDerivedOutput` 注释放宽 |
| `lib/shared/database/novel_content_database_migrations.dart` | `migrateToV20` 补 `parent_id` 列与 `canvas_nodes_by_parent_id` 索引 |
| NEW `lib/shared/models/production/group_layout.dart` | `style.group` 的解析与写回；分镜组格位 ↔ 坐标、外框尺寸、转换重排的纯函数 |
| NEW `lib/shared/services/production/grid_split.dart` | isolate 内解码与等分裁切，返回每格 PNG 与行列 |
| NEW `lib/shared/services/production/group_service.dart` | 分组建立、成员校验、布局变更、转换、解组、删除、空格位补图 |
| NEW `lib/shared/services/production/grid_orchestrator.dart` | 切分建组与高清生成：裁切 → 登记资产 → `group_service` 一次写入 → 逐个提交生成任务；拼接(2k) 的本地合成与登记 |
| `lib/shared/models/production/view_presets.dart` | 新增 `ImageGenerationMethod.upscale` 与提示词；不进入 composer 预设面板和「九宫格」菜单 |
| `lib/shared/services/production/canvas_service.dart` | `readContent` 带出分组；`removeNode` 删除分组时连同成员；`move`／`moveNodes` 拒绝单独移动分镜组成员；连线校验拒绝分组作生成输入 |
| `lib/shared/services/ai/tools_production.dart` | 兼容现有画布工具：节点数据增加 `parent_id`；删除节点（含 `remove_types`）改走 `canvas_service.removeNode`，删除分组时连同成员；`position` 移动分镜组成员时返回 `invalid_config`，移动分组节点时由 `group_service` 一并移动成员。不新增工具，也不改 tool description |
| `lib/desktop/features/production/grid.dart` | 平铺视图排除分组节点，成员照常列出 |

高清提示词草稿（与其他预设一样只维护一份中文，不做 i18n）：`以参考图为准，输出同一画面的高清版本：保持构图、人物身份、服装、道具、场景与光线完全不变，补全清晰细节，去除模糊、噪点与压缩痕迹，不添加新元素。`

## 迁移

- 内容库 v20 未发布（`v2.3.2` 为 v19），按仓库约定把 `parent_id` 列和 `canvas_nodes_by_parent_id` 索引并入 `migrateToV20`，`schemaVersion` 保持 20；新建库走表定义与同一索引创建入口。
- 已有数据：全部节点 `parent_id` 为 NULL，即不在任何分组，无需回填。
- 开发库：用 SQLite 对 Debug 内容库执行 `ALTER TABLE canvas_nodes ADD COLUMN parent_id TEXT` 与建索引，并查询验证；不加运行时补列兼容层，不动 Release 库。
- 回滚：列可空、默认 NULL，旧代码忽略该列；`type='group'` 的节点在旧代码中会显示为未知节点，属开发期可接受范围。

## 运行成本

- 切分、拼接、转换均在本地完成：每格一个 PNG，25 宫格 1280×720 源图约 25 个 40–70 KB 文件，计入本地存储与备份。
- 高清生成：每个选中格一次图片生成，按所选模型 2K／4K 单价计费，单次最多 25 次；按钮文字显示将生成的张数。失败重做按图片节点现有规则计次。

## 实施拆分

| ID | 内容 | 依赖 | 完成标准 |
|---|---|---|---|
| SG-01 | `parent_id`、分组节点类型、`group_layout` 纯函数、`group_service`（建组、校验、布局、转换、解组、删除）与迁移 | B-01 | 迁移测试：v19 升级与新建库都有列和索引。服务测试：嵌套、跨画布、分镜组非图片成员、格位越界与重复被拒；转换往返后成员与连线不变；解组清空 `parent_id`；删除分组连带成员；删除成员保留空格位；单独移动分镜组成员被拒绝；`parent_id` 指向已删除分组时视为无分组。Agent 画布工具回归：读取含 `parent_id`，删除分组连带成员，移动分镜组成员返回 `invalid_config` |
| SG-02 | 画布渲染：分组节点、分镜组紧凑布局、普通组外框与调整大小、整组拖动、分组工具栏的转换／解组／删除／重命名 | SG-01 | Widget 测试：重开画布后布局与模式不变；拖外框成员同步移动且一次写库；分镜格子不能单独拖动但可连线；Windows／macOS／Linux 三个布局分支工具栏不溢出；目视检查紧凑排列无缝隙错位 |
| SG-03 | 宫格切分入口、自定义规格、切分态与创建分镜组 | SG-02 | 裁切测试：非整除尺寸边界无重叠无缺像素；只选部分格时格位映射正确；中途失败不建分组。Widget 测试：选格、计数、Esc 退出 |
| SG-04 | 生成高清图片 | SG-03、VC-01 | 倍数按模型能力禁用；每格输入为裁图资产、分辨率与比例正确；单格提交失败不影响其他格；fake 渠道下任务全部建行 |
| SG-05 | 分镜组工具栏：比例、宫格、序号、清空、空格位补图 | SG-02 | 宫格容量不足时禁用；切换后顺序不变；清空保留空组；补图写入正确格位 |
| SG-06 | 拼接(2k) | SG-05 | 输出长边 2048、比例与格位正确、序号开关生效、空格位为底色；结果节点与 `derived_output` 边正确 |

SG-01 至 SG-06 不调用收费模型，测试使用 fake 渠道。

## 验收

- 切分：任意有图的图片节点都能切 2×2 至 5×5 及自定义规格；产物为原像素裁图，格子可单独连给视频节点作参考；源节点不变。
- 高清：每格生成节点的请求只带该格裁图；任务、历史、采用、重做沿用图片节点。
- 分组：拖动、转换、解组、删除、清空、补图后重开应用状态一致；备份恢复后分组、成员与连线完整。
- 平台：Windows、macOS 各实机运行一次切分、拖动与转换；只在一个宿主上通过的测试不计作跨平台验收。Android 不在本方案验收范围。

## 风险

- `GroupNode` 的 `parent` 行为在生产画布未用过，与现有场次色带、`ProductionSelectionLayer`、节点拖动会话的组合未运行验证。SG-02 第一步先用 Widget 测试确认整组拖动与单格选中；若不成立，退路是沿用 `_BandLayer` 的做法自绘分组层、手动带动成员，数据模型不变。
- 分组节点与成员的层级：分组外框必须画在成员之下、连线之上不遮挡端口。若 flow 的层级不能满足，按色带方式放在 grid 之后的独立层。
- 大图切分耗内存：8K 源图解码约 128 MB，放在 isolate 中串行处理并逐格写盘，不同时持有所有格子的编码结果。
- 图生图「高清」可能改变细节或人物外貌；本方案不安排真实模型评测，提示词以上文草稿为准；作者可在格子节点里改提示词重做。
