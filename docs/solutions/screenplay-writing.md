# 剧本写作第一期：数据库、桌面端与移动端

> 状态：可实施
> 日期：2026-09-03
> 设计依据：WIP `ac33fdde5` 中的 [`data.jsx`](../../designs/desktop/screenplay/data.jsx)、[`views.jsx`](../../designs/desktop/screenplay/views.jsx) 与 [`screenplay.css`](../../designs/desktop/screenplay/screenplay.css)
> 修订：2026-09-08 追加 [R1：整集编辑与场标题节点](#revision-r1)。第 1 至 15 节保留第一期方案；涉及编辑边界、拆合场及撤销时，以 R1 的修订建议为准。R1 尚未实施。

## 1. 背景

当前作品库、创建流程和编辑器都按小说设计。主库的 `novels` 表保存作品元数据，每部作品再对应一个独立内容库；内容库已有章节、人物档案、小说大纲和实体关系，但没有剧本项目、季、集、场次和剧本正文的数据结构。

最新 WIP 已经画出剧本的概览、剧本正文、大纲、节拍、场次板、场次表和人物关系。Mock 数据把场次正文、出场人物和节拍关系放在 JavaScript 对象中，不能直接作为持久化模型。第一期需要把这些信息拆成稳定的业务表，同时给桌面端和移动端提供完整入口。

本方案的范围约定：第一期只支持剧集，一个剧本作品代表整部剧集，内容库里始终至少有一季，每季始终至少有一集。季和集都保存实际记录，可以新增、删除、切换；季号与每季内的集号都是从 1 开始的连续展示序号，重排或删除中间项会触发重新编号，稳定引用分别使用 `season_id` 与 `episode_id`。规划集数属于季（`screenplay_seasons.planned_episode_count`），只是可选元数据；实际集数超过规划数仍显示分子/分母并标为“已超出规划”，不阻断创作。只有一季时 Season 在 UI 和普通 AI 对话中隐藏，唯一一季作为隐式当前季；新增第二季后才展开季管理。剧本格式与数据解耦，格式只决定渲染排版，`screenplays.format` 以固定值 `asian` 占位。场次正文的对话角色必须先有人物档案，元素只保存 `character_id`，显示名实时解析。场景地点关联 `locations` 实体，`location_id` 可空、显示名实时解析。剧本工作区接入现有 AI 工具体系，不新增工具名，剧本资源以新的路径命名空间加入并按工作区类型隔离，详见第 9 节。

正文以**元素行**建模：每个元素一行，落在 `screenplay_scene_elements` 子表，不使用 JSON 列，也不对 AI 暴露成自由文本。AI 读写正文收发的都是结构化数组，不存在解析与猜测环节，理由与取舍见 5.9 与 9.3。

跨作品读取用显式绝对路径寻址：以 `/works/{work_id}/` 开头的路径解析到指定作品；`chapters/{chapter_id}`、`profile`、`story_state` 等相对路径从当前作品解析。兼容带前导斜杠的旧路径是解析器内部行为，不进入 AI 的公开路径说明。跨作品读取用于从原著小说改编剧本，规则见 9.9，第一期**只读**；用户没有明确提出引用、比较或改编其他作品时，AI 不读取 `/works`。

### 现状约束

- `Novel.type` 已用于原创、续写、同人、衍生和素材等创作来源，不能改作小说与剧本的分类字段。
- 每部作品有独立内容库，主库与内容库不能组成一个 SQLite 事务。
- 人物继续复用内容库现有的 `character_profiles`，不能再建一套剧本人物档案。
- 业务关系必须显式建模，不能把 `beat_id`、集归属或人物关联塞进 `metadata`、标签或正文元素。
- 用户业务数据默认软删除。
- 当前只支持亚洲式剧本格式，不向用户暴露格式选择。
- 桌面端现有 `NovelEditorPage` 已是大型存量页面，新功能不能继续向它的 `build` 堆状态。
- 移动端现有小说编辑页已有大量分区，剧本需要独立页面，不能再追加一组小说式 tab。

## 2. 目标

### 目标

1. 作品创建时可选择“小说”或“剧本”；第一期创建的所有剧本都是剧集。
2. 一个作品管理整部剧集，Season 是正式实体；每季拥有自己的集与规划集数，人物、地点、关系和资料在各季间共享。场次、节拍和正文始终归属于某一集。
3. 场次支持场景标题、梗概、状态、结构化正文、`beat_id`、出场人物和派生统计。
4. 大纲、节拍板、场次板、场次表和出场矩阵使用同一份场次数据，不维护平行副本。
5. 桌面端和移动端都能创建、打开和编辑剧本，并能打开另一端创建的数据。
6. 现有小说、小说创建流程、小说导入和快速开书不改变行为，旧数据迁移后统一得到 `content_kind = novel`。
7. 剧本工作区能用 AI 读取、新增和编辑季，并读写集、场次、节拍、场次正文与出场人物，复用现有工具名；场次和节拍用业务锚点移动，不暴露内部 `sort_order`，季重排与删除只在用户显式季管理界面执行。常规操作以一次 AI 回合冻结的当前季为默认作用域，不强迫单季用户理解 `season_id`。为支持 `scene_id`、结构化元素数组和跨作品 GraphSearch，工具 input schema 做一次全局加法式调整，调整后在两种工作区保持静态且完全相同。小说工作区的工具执行行为和按体裁过滤后的可用能力不受影响；两种工作区的 path schema 都新增只读 `/works/{work_id}/…` 路径，代价见 9.1。
8. AI 能以只读方式跨作品访问关联的原著小说，用于改编：读原著章节、大纲与设定，写进当前剧本。跨作品写法收在 `/works/` 前缀内；当前作品使用相对路径，解析器继续兼容存量的前导斜杠写法，不需要迁移用户自建的 SubAgent 与 AgentSkill。

### 非目标

1. 不支持分镜、镜头、分镜图或镜头表。
2. 每季的规划集数只是可选元数据，不驱动任何流程：不要求填写，达到或超过规划集数也不阻止新增集；超出时以“已超出规划”警示呈现。
3. 不支持剧本格式切换，第一期固定使用亚洲式格式。
4. 不支持小说与剧本之间的转换；`content_kind` 创建后永久只读，即使作品尚无正文也不能切换。改编由 AI 跨作品只读原著、逐场写入剧本完成，不提供“一键整本转剧本”；创建时选错类型就新建作品。
5. 不支持制片阶段锁定场号，例如 `12A`、`12B`。
6. 不新增剧本文件导入导出、打印、PDF 排版或剧本专用历史版本。
7. 不新增剧本专用工具名。现有通用工具的 input schema 只做本方案列明的全局加法式调整，不按工作区、用户数据或运行时状态动态变化。
8. 不新增剧本专用的 SubAgent 种子，也不改写 `writer`、`review`、`style_polish`、`chronicler` 等既有 SubAgent 的 prompt；剧本第一期不委派正文类 SubAgent，见 9.7。
9. 不把剧本资源接入章节嵌入检索和发布后编年史流程。
10. 不新增剧本人物之间的关系表。人物关系继续使用现有 `entity_relations`。
11. 第一期不支持电影剧本；将来如需支持，必须单独设计数据模型、创建流程与迁移。
12. 不开放跨作品写入。`/works/` 路径只支持 `Read`、`Glob`、`Grep`；`GraphSearch` 通过可选 `work_id` 选择任一有效本地作品。`Create`、`Write`、`Edit`、`Replace`、`Remove` 命中 `/works/` 一律拒绝，理由与放开条件见 9.9。
13. 不把正文以自由文本形式暴露给 AI，也不提供文本到元素的解析器。正文的读、写、改一律用结构化数组与元素路径，理由见 9.3。
14. 待审阅改动里没有元素级条目。正文的待审阅状态只有场次级一种，同一 AI session 的单元素写入合并进同一条；同场跨 session 的 active 正文写入串行化，理由见 9.4。
15. 不提供季、集、场次、节拍或正文元素的回收站与恢复入口。软删除仅保留数据安全基础，第一期用户侧依靠删除确认。

### 成功信号

| 信号 | 验证方式 |
| --- | --- |
| 旧作品升级后仍按小说打开 | 主库 migration 测试和桌面、移动端冒烟测试 |
| 剧本始终至少有一季，每季始终至少有一集；场次、节拍和正文归属于实际存在的一集 | DAO、Service 和 Widget 测试 |
| 单季作品不显示 Season 控件；新增第二季后才显示季切换与管理，删回一季后再次隐藏 | 双端 Widget 测试 |
| 每季只展示实际创建的集数与该季规划集数 | 创建、增集和删除集测试 |
| 大纲、节拍、场次和人物矩阵修改后同步刷新 | Drift stream 集成测试 |
| 桌面端与移动端读写同一份内容库 | 双端手动回归 |
| 数据库没有分镜表 | schema 断言 |
| 正文元素落在 `screenplay_scene_elements` 行上，内容库没有正文 JSON 列 | schema 断言 |
| 小说会话除新增 `/works/{work_id}/…` path schema 行外，与本功能实施前逐字一致 | prompt golden 测试 |
| 工具名不变；input schema 完成本方案列明的一次加法式调整后，两种工作区拿到完全相同且静态的工具定义 | tool schema 快照测试 |
| 小说会话调用剧本路径、剧本会话调用章节路径都被拒绝并给出替代路径 | 工具负向测试 |
| AI 写入的场次正文与人工写入走同一条 Service 与统计路径 | Service 集成测试 |
| 场次和节拍的工具 schema、响应与 Service 公共契约不出现 `sort_order`，只使用派生编号与 before/after 业务锚点 | schema 快照、Service 与工具测试 |
| 不以 `works` 开头的路径解析结果与实施前完全一致 | 路径解析 golden 测试 |
| 剧本会话能只读关联原著的章节与设定，写入类工具命中 `/works/` 被拒绝 | 跨作品工具测试 |
| 正文的待审阅条目只有场次级一种，仓库里没有元素级 `resourceType`；同一 session 连续写入合并，跨 session 冲突不覆盖 | working overlay 并发测试与代码检查 |

## 3. 用户路径

1. 作为编剧，我新建剧本后直接进入第 1 集，系统已在内部创建第 1 季，但单季界面不要求我理解或操作 Season。
2. 作为剧集编剧，我可以按需要新增集，系统不要求填写规划集数；确实需要多季时，我从低频入口新增一季，界面才展开季切换与管理。
3. 作为编剧，我在大纲里调整场次顺序或梗概后，场次板和剧本正文立即使用新顺序与新内容。
4. 作为编剧，我可以给场次分配已有角色，人物页能看到角色出现在哪些场次。
5. 作为移动端用户，我可以选集、查看大纲和节拍，并用单场全屏编辑器继续写正文；多季作品才显示季选择入口。
6. 作为旧小说用户，我升级后仍进入原来的小说编辑器，不会看到剧本字段或空的剧本页面。
7. 作为编剧，我可以让 AI 读当前集的场次和节拍、排一场新戏、写这场的正文，写完的正文出现在场次编辑器里，改动可以审阅或退回；单季时 AI 不主动谈论“第 1 季”。
8. 作为多季剧集编剧，我切换季后，集列表和编辑区域只显示该季内容；一次 AI 回合里省略的 `season_id` 始终落到回合开始时的当前季，不会因执行中切换界面而漂移。
9. 作为小说作者，我的 AI 面板不出现剧本资源；path schema 额外列出只读的 `/works/{work_id}/…` 跨作品路径。
10. 作为改编编剧，我建剧本时指定改编自哪部小说，之后可以让 AI 去读原著的章节、大纲和设定，再把这一场改写进当前剧本；AI 不会、也不能改动原著。

## 4. 解决方案

### 方案对比

#### 剧本结构

| 方案 | 做法 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- | --- |
| A. 复用章节与小说大纲 | 用章节代表场次，用 `outlines` 和 `outline_beats` 保存剧本结构 | 新表少 | 章节、场次和剧集语义混在一起；人物矩阵与 `beat_id` 需要额外约定；现有小说工具容易误操作剧本 | 放弃 |
| B. 新建规范化剧本表 | 剧本、季、集、场次、节拍和场次人物关联分别建表 | 关系清楚；适合查询、排序和软删除；整部剧集共享人物与设定；桌面与移动端可共用 | 表和 DAO 较多，需要完整 migration | 采用 |
| C. 整部剧本保存为一个 JSON | 项目、集、场次、人物和节拍都放进一列 | 初期写入简单 | 无法稳定做局部更新、关联查询、出场矩阵和软删除；大文档每次保存成本高 | 放弃 |

#### 正文形态

正文的**落库形态**与**对 AI 的暴露形态**是两个独立决策，早期草案把它们绑在一起（“库里是元素数组，所以对 AI 暴露成文本”），这里拆开评估。

| 方案 | 落库 | AI 写整场 | AI 改一句 | 结论 |
| --- | --- | --- | --- | --- |
| D. JSON 列 + 文本投影 | `screenplay_scenes.elements` JSON | 自由文本，一次调用 | `Edit` 字符串替换 | 放弃 |
| E. 元素子表 + 元素路径 | `screenplay_scene_elements` 行 | 逐元素 N 次调用 | 元素路径，精确 | 放弃 |
| F. 元素子表 + 数组接口 | `screenplay_scene_elements` 行 | 一次 `Write`，载荷是元素数组 | 元素路径，精确 | 采用 |

放弃 D 的理由是它把结构**有损编码成文本，再靠解析器猜回来**。结构本来就在模型手里，中间这一道压扁再还原换不来任何东西，却要为此维护块切分、归一化表、强制转义、冒号行三分类、slugline 拦截、往返对齐等一整套规则，且规则集不收敛——每多一种正文写法就多一条规则。数组没有这个环节：类型是显式字段，不需要从冒号猜；`character_id` 是显式字段，不需要从人名匹配。

放弃 E 的理由是写入粒度。画布的 `canvas/{name}/nodes` 是一节点一次 `Create`，一张画布十几个节点可以接受；一场戏 40–80 个元素、一集 30 场，逐元素调用不成立。

F 用一次 `Write` 带整个数组解决了 E 的粒度问题，同时保留 E 的精确寻址。相对 D 的代价是 JSON 骨架带来约 50–80% 的 token 增量（正文本身占大头，不是成倍），换掉的是一整套解析器及其失败重试。

`Edit`、`Grep`、分页读、整场审阅这四项能力在 F 下都不丢：`Grep` 直接在元素行上做 SQL 匹配并返回元素路径，比在长文本里定位更准；分页按元素区间切；`Edit` 由元素路径的精确写入取代；待审阅卡把最新元素数组**渲染**成整场正文预览——渲染是结构到文本的无损方向，不含解析，见 9.4。

#### 跨作品读取

| 方案 | 做法 | 结论 |
| --- | --- | --- |
| G. 创建时导入快照 | 建剧本时把原著人物、地点、章节梗概复制进新内容库 | 放弃：快照会过期，且重复存储原文 |
| H. `source/*` 别名前缀 | 源作品挂在一个固定别名下，路径写 `source/chapters` | 放弃：别名把“哪一部”藏进了前缀本身，多源时无处安放 |
| I. 裸作品段 | 首段没命中集合表就当作品段，写 `{作品}/chapters` | 放弃：判据是启发式，拼错的集合名会被误判 |
| J. 显式前缀 `/works/{work_id}` | 首段是 `works` 就是跨作品，其余全部解析到当前作品 | 采用 |

J 与 I 的差别是判据从启发式变成了确定式。I 要靠“首段是否命中 `_collectionSchemas`”来区分，于是 `Read charactors/ch_123`（集合名拼错）会被判成作品段并报“作品不可达”，把模型引向完全错误的修法。J 没有这个问题：首段不是 `works` 的路径照旧走 `unknown_collection`。

J 与 H 的差别是“哪一部”用稳定的 `work_id` 写在路径里，而不是藏在前缀语义里，所以作品改名不影响路径，也不把跨作品读取错误绑定到单一改编来源。第一期可读任一有效本地作品，写入仍只允许当前作品（9.9）。

J 的零迁移不靠论证，靠隔离：存量路径没有一条以 `works` 开头，`works` 也不与任何现有集合名冲突，所以不以 `works` 开头的路径解析逻辑完全不变。用户自建的 SubAgent、AgentSkill里硬编码的路径不受影响——这些是用户可编辑的库内记录，没法靠改 asset 迁移，与 9.6 不改既有 SubAgent prompt 是同一条理由。详见 9.9。

### 决策

主库给 `novels` 增加 `content_kind`（值只允许 `novel` 或 `screenplay`）与 `source_novel_id`（可空，改编来源）。内容库新增七张业务表：

- `screenplays`
- `screenplay_seasons`
- `screenplay_episodes`
- `screenplay_scenes`
- `screenplay_beats`
- `screenplay_scene_characters`
- `screenplay_scene_elements`

正文元素一元素一行，落在 `screenplay_scene_elements`。季、集、节拍和人物关联保持关系型结构，避免为了省表而牺牲查询和约束。一个作品保存整部剧集，人物、地点、关系与资料自然跨季共享；不用规则文本或跨作品关联表达季。人物关系继续用 `entity_relations`，只给它补一列证据场次 `scene_id`（5.11）。

AI 侧不新增工具，剧本资源作为新的相对路径命名空间 `screenplay` 接入现有工具，并按工作区类型在执行期与 prompt 装配期隔离（第 9 节）。这是与画布相同的做法：通用工具 + 专属路径 + 专属 Bundled AgentSkill。正文以结构化数组收发，不做文本投影（9.3）。跨作品读取由绝对路径 `/works/{work_id}` 表达，第一期只读（9.9）。

### 命名约定

- `Novel` 暂时保留为现有代码和主库的兼容名称，产品界面统一称为“作品”。
- `content_kind` 表示作品的内容是小说还是剧本，并据此决定编辑器路由。
- `Novel.type` 继续表示原创、续写、同人等创作来源。
- `prose` 的本义是散文体或非韵文写作，但产品和数据库都不使用这个词，统一使用 `novel` 和“小说”。
- “大纲”是场次数据的一个阅读和编辑视图，不是独立业务实体。
- “季数”只指实际存在的 `screenplay_seasons` 记录；“季号”是从 1 开始的连续展示序号，重排或删除中间季都会重新编号，稳定引用使用 `season_id`。
- “集数”只指当前季实际存在的 `screenplay_episodes` 记录；“规划集数”专指 `screenplay_seasons.planned_episode_count` 这个可选元数据。实际集数高于当前季规划集数是有效状态，显示为“已超出规划”。
- “集号”是从 1 开始的连续展示序号：读取 `episode_number` 得到当前季内位置，写入有效目标号表示把该集移动到本季该位置，Service 会平移中间集并保持连续。它不是稳定标识，需要稳定引用时使用 `episode_id`；标题也可修改且不要求唯一，只用于展示。
- “场号”与“节拍号”分别是按集、按幕派生的 `scene_number` / `beat_number`，只用于读取展示。调整位置使用另一个场次或节拍的稳定 ID 作为 before/after 锚点，不能提交数据库内部的 `sort_order`。
- “当前季”是本机为该作品记住的编辑器选择，也是一次 AI 回合冻结的默认季作用域；它不是剧本业务字段，不等于最新季，也不跨设备同步。只有一季时该概念在 UI 与普通 AI 回复中隐藏。

### 核心原则

1. 场次是大纲、场次板、场次表和正文导航的共同真源。
2. 节拍到场次是一对多关系，由 `screenplay_scenes.beat_id` 表达，节拍不保存场次 ID 列表。
3. 场次到人物是多对多关系，由关联表表达，场次不保存人物名称数组。
4. 场景标题和出场人物不重复写进正文元素。
5. 列表和统计查询不读取正文元素行，聚合由 SQL 完成。
6. 所有用户业务表使用软删除，级联行为由 Service 事务完成。
7. 第一期开设的剧本均为剧集。每部剧集至少有一季，每季至少有一集，场次与节拍的 `episode_id` 一律非空。
8. 正文对 AI 只有结构化一种形态。系统内部可以把元素**渲染**成文本用于显示与检索，但不接收文本并解析回元素。
9. `/works/{work_id}` 前缀决定去哪个内容库；没有这个前缀就是当前作品。剥掉前缀之后，同一套集合路径在两种情况下形状完全一致。
10. 正文的待审阅状态只有场次级一种，并以 AI session 区分归属；元素级路径是**写入入口**，不是**审阅单位**。同场跨 session 不叠加整场快照。

## 5. 数据模型

### 5.1 实体关系

```text
App DB
Novel
  ├── 通过 content_database_path 打开对应内容库
  └── 0..1 source_novel_id ── N..1 Novel（改编来源，跨作品只读）

Content DB
Screenplay
  └── 1..N Season
          └── 1..N Episode
                  ├── 0..N Beat
                  └── 0..N Scene
                          ├── 0..1 Beat
                          ├── 0..1 Location
                          ├── 0..N SceneCharacter ── N..1 CharacterProfile
                          └── 0..N SceneElement
                                  └── 0..1 CharacterProfile（type = character 时非空）
```

`Novel` 与 `Screenplay` 的关系跨数据库，只做逻辑关联。内容库内不保存 `novel_id`；所有 Episode 必须属于一个有效 Season，所有场次和节拍必须属于一个有效 Episode。CharacterProfile、Location、entity relation 与资料仍在同一内容库内由整部 Screenplay 共享，不复制到 Season。

### 5.2 主库 `novels`

新增字段：

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `content_kind` | TEXT NOT NULL | `novel` | `novel` 或 `screenplay`，决定编辑器路由；只在创建时写入，之后只读 |
| `source_novel_id` | TEXT NULL | NULL | 剧本可选的原作小说，指向同库一条有效且 `content_kind = novel` 的 `novels.id`；用于 UI 标记和改编流程提示，不是跨作品读取权限 |

不修改 `type`。标题、作者、简介、封面、分类、标签、总字数和书架状态仍由 `novels` 保存，剧本表不复制这些字段。

`content_kind` 是作品创建时确定的不可变身份，不是可编辑设置。小说与剧本会初始化不同的内容库根记录、默认结构和编辑器路由；系统不尝试判断一个作品是否“足够空”以安全切换，也不删除另一类型的残留数据。主库 Service、桌面与移动端编辑表单、AI 工具都不提供修改入口。以后如果要支持小说转剧本，需要单独设计数据转换流程。

`source_novel_id` 的跨作品引用放主库，不放内容库，内容库保持自包含可搬运。源作品被删除或路径失效时，界面按 id 解析失败即显示“来源作品不可用”，不保留会过期的冗余标题。新增索引 `novels_by_source_novel_id`。

`source_novel_id` 只表达剧本可选的原作小说，不是外键，也不产生级联：删除源作品不影响剧本，也不自动清空该字段，界面只把来源标记为“来源作品不可用”；AI 显式读取该作品时返回 `work_not_found`。若原作以后恢复为有效本地作品，同一个 id 自动重新解析，不需要重建关联。创建后仍可改选另一部有效小说或清空为原创；修改只影响来源展示与改编流程提示，不重写人物、场次、正文或任何其他业务数据。创建与修改时校验引用方是剧本、目标是有效小说；它不限制 AI 读取其他作品，任一目标路径是否合法仍由目标作品的 `content_kind` 在运行期判定（9.9）。同人小说基于原作的引用是后续能力，第一期不在小说创建、编辑或 AI 流程中使用此字段。

引用的真源是 id，路径里用的名字是按这个 id 实时解析出来的（9.9）。源作品改名后，`works` listing 立刻给出新名字，引用本身不受影响——这与人物、地点「存 id、显示名实时解析」是同一条模式。

### 5.3 `screenplays`

每个剧本内容库只有一条未删除的根记录。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | TEXT PK | 剧本 ID |
| `kind` | TEXT NOT NULL | 固定为 `series`；保留作品形态字段，第一期不接受其他值 |
| `format` | TEXT NOT NULL DEFAULT `asian` | 剧本格式，只决定渲染排版；第一期固定 `asian` |
| `created_at` | INTEGER NOT NULL | Unix 秒时间戳 |
| `updated_at` | INTEGER NOT NULL | Unix 秒时间戳 |
| `deleted_at` | INTEGER NOT NULL DEFAULT 0 | 软删除时间，0 表示有效 |

约束与索引：

- `kind` 固定校验为 `series`；将来扩展其他剧本形态时，必须单独设计语义与迁移。
- `format` 做枚举校验。
- 不设项目级 `stage`，书架状态沿用 `novels.status`，不在剧本表再立一个进度真源。
- 不保存 `current_season_id`；当前季属于版本化的本机工作区状态（6.5），不能成为多人或跨设备共享的剧本事实。
- `screenplays_by_deleted_at_u` 是 `deleted_at = 0` 条件下的唯一索引，保证内容库只有一个有效根记录。

格式与正文数据解耦：同一份 `elements` 可以按亚洲式或其他格式渲染，切换格式不改写任何正文数据。当前 `format` 只允许 `asian`，是有意保留的只读持久化字段，不因第一期只有一个值而删除；界面不展示，也不提供切换入口。以后开放格式时新增枚举值和对应渲染器即可，不需要新增列或回填既有剧本。`format` 列在内容库 v16 未发布前合入，避免发布后再为此单独提升 schema version。

### 5.4 `screenplay_seasons`

Season 是持久化实体，但不强迫单季用户管理它。新建剧本时自动创建第 1 季；只有一个有效 Season 时，双端 UI 隐藏季选择器和管理层级，唯一一季作为隐式当前季。新增第二季后才展示季切换与管理；删回一季后再次隐藏。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | TEXT PK | 季 ID |
| `screenplay_id` | TEXT NOT NULL | 所属剧本 |
| `season_number` | INTEGER NOT NULL | 用户可见季号，从 1 开始 |
| `title` | TEXT NOT NULL DEFAULT `''` | 可选季标题；为空时只显示“第 N 季” |
| `planned_episode_count` | INTEGER NULL | 本季规划集数；为空表示未设定 |
| `created_at` | INTEGER NOT NULL | 创建时间 |
| `updated_at` | INTEGER NOT NULL | 更新时间 |
| `deleted_at` | INTEGER NOT NULL DEFAULT 0 | 软删除时间 |

约束与索引：

- `season_number > 0`；有效季号从 1 开始连续。重排季或删除中间季时在同一事务内重新编号，稳定引用一律使用 `season_id`。
- `planned_episode_count` 为空或大于 0，只是指导值，不限制新增集。
- 每个有效剧本至少保留一个有效季；唯一有效季不提供删除入口。
- `screenplay_seasons_by_screenplay_id_season_number_u` 保证有效季号不重复。
- `screenplay_seasons_by_screenplay_id_season_number` 支持读取季列表。

单季时，作品设置里的“规划集数”写入唯一 Season；多季时文案变为“本季规划集数”。来源作品仍属于整个 Work，不下沉到 Season。

### 5.5 `screenplay_episodes`

这张表只保存已经创建的集。新建剧本时在第 1 季下创建实际的第 1 集；新增 Season 时也同时创建该季第 1 集。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | TEXT PK | 集 ID |
| `screenplay_id` | TEXT NOT NULL | 所属剧本 |
| `season_id` | TEXT NOT NULL | 所属季，必须指向同一剧本的有效 Season |
| `episode_number` | INTEGER NOT NULL | 用户可见集号，从 1 开始 |
| `title` | TEXT NOT NULL DEFAULT `''` | 集标题 |
| `target_duration_seconds` | INTEGER NULL | 本集目标时长 |
| `created_at` | INTEGER NOT NULL | 创建时间 |
| `updated_at` | INTEGER NOT NULL | 更新时间 |
| `deleted_at` | INTEGER NOT NULL DEFAULT 0 | 软删除时间 |

约束与索引：

- `episode_number > 0`。
- 对已有集写 `episode_number` 的合法范围是 `1..当前季有效集数`；写当前值是无变化，超出范围返回 `invalid_episode_number`。Service 把它解释为季内移动并在同一事务内平移受影响集，不允许调用方直接制造重复或断号。
- 每个有效 Season 至少保留一个有效集；删除该季最后一集时返回 `last_episode_required`，不修改数据。
- `screenplay_episodes_by_season_id_episode_number_u` 保证同季有效集号不重复。
- `screenplay_episodes_by_screenplay_id_season_id_episode_number` 支持按剧本与季读取集列表。

界面按 `season_id` 统计有效记录并显示当前季实际集数；设定了本季规划集数时显示“2/8 集”，未设定时只显示“2 集”。实际集数超过规划数时仍显示如“10/8 集”，并标为“已超出规划”，不阻止新增、删除或下调规划数。

### 5.6 `screenplay_scenes`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | TEXT PK | 场次 ID |
| `screenplay_id` | TEXT NOT NULL | 所属剧本 |
| `episode_id` | TEXT NOT NULL | 所属集，必须指向同一剧本的有效集 |
| `beat_id` | TEXT NULL | 关联节拍，可为空 |
| `sort_order` | INTEGER NOT NULL | 在所属集内的顺序 |
| `interior_exterior` | TEXT NULL | `interior`、`exterior` 或 NULL；NULL 表示尚未确定，标题渲染时省略这一段 |
| `location_id` | TEXT NULL | 场景地点，关联现有 `locations.id`；可空，先排梗概后排标题的场次允许为空 |
| `time_label` | TEXT NOT NULL DEFAULT `''` | 日、夜、昏、同时等自由文本 |
| `synopsis` | TEXT NOT NULL DEFAULT `''` | 场次梗概，也是大纲正文 |
| `stage` | TEXT NOT NULL DEFAULT `draft` | `draft` 或 `final` |
| `page_eighths` | INTEGER NOT NULL DEFAULT 0 | 八分之一页为单位的派生缓存，`1 6/8` 保存为 14 |
| `estimated_duration_seconds` | INTEGER NOT NULL DEFAULT 0 | 估算时长的派生缓存 |
| `dialogue_line_count` | INTEGER NOT NULL DEFAULT 0 | `dialogue` 元素行数的派生缓存，界面显示为台词句数 |
| `word_count` | INTEGER NOT NULL DEFAULT 0 | 正文元素字数的派生缓存 |
| `created_at` | INTEGER NOT NULL | 创建时间 |
| `updated_at` | INTEGER NOT NULL | 更新时间 |
| `deleted_at` | INTEGER NOT NULL DEFAULT 0 | 软删除时间 |

正文不在本表。元素行在 `screenplay_scene_elements`（5.9），本表只留派生统计。

`stage` 是可自由切换的编辑标签：新建场次默认为 `draft`，表示正在创作或尚未认可；`final` 表示当前认可版本。`final` 不锁定场次，人工与 AI 都可继续编辑并随时显式改回 `draft`；修改正文、梗概或其他场次字段不会自动降级，修正错字也不会偷偷改变用户标记。制片阶段的锁定不属于第一期。场次是否已有正文由有效元素是否为空表达，不再用第三个状态重复记录。

四个统计列保留为缓存而不是每次 SQL 实时聚合：概览与大纲要按集或按剧本汇总几十到几百个场次，实时 join 元素表在长剧集上不划算；`novels.word_count` 的同步链路也已经建立在“场次上有一份字数”这个前提上。缓存由 `ScreenplayService` 在元素写入的**同一个事务**内从元素行重算，不存在“先写正文、后补统计”的窗口。

场号不单独保存。第一期的场号是有效场次按 `sort_order` 排序后的序号，移动或删除场次后自动变化。制片阶段的锁定场号以后另加字段，不能提前把派生序号写死。

地点与人物采用同一套引用模式：只存 `location_id`，显示名从 `locations` 实时解析，改名即时传播。仍被有效场次引用的地点不允许删除，删除入口先展示使用处并引导更换或清空。查询仍能解析软删除记录，供旧数据、恢复旧场次或异常状态显示“原名（已删除）”，但这只是容错，不是正常删除流程。场景标题编辑器从有效地点列表选择，支持就地输入名字快速建地点，不打断排场流。

约束与索引：

- `episode_id` 必须指向同一剧本的有效集。
- `interior_exterior` 为空或为 `interior` / `exterior`。为空时不显示占位文案；内外景转换必须拆成两个场次，不使用 `both` 表达。
- `location_id` 非空时必须指向同内容库的有效地点。地点删除前检查有效场次引用，存在任何引用时返回 `entity_in_use`，不得软删除。
- `beat_id` 必须指向同一剧本、同一集范围内的有效节拍。
- `sort_order`、页数、时长、台词数和字数不能为负数。
- `screenplay_scenes_by_episode_id_sort_order_u` 保证集内有效场次顺序唯一。
- `screenplay_scenes_by_screenplay_id_episode_id_sort_order` 支持主列表查询。
- `screenplay_scenes_by_beat_id` 支持节拍聚合。

### 5.7 `screenplay_beats`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | TEXT PK | 节拍 ID，也是场次保存的 `beat_id` |
| `screenplay_id` | TEXT NOT NULL | 所属剧本 |
| `episode_id` | TEXT NOT NULL | 所属集，规则与场次一致 |
| `act_number` | INTEGER NOT NULL | 幕分组编号，从 1 开始，不限三幕 |
| `title` | TEXT NOT NULL DEFAULT `''` | 节拍标题 |
| `description` | TEXT NOT NULL DEFAULT `''` | 节拍说明 |
| `sort_order` | INTEGER NOT NULL | 同一幕内顺序 |
| `created_at` | INTEGER NOT NULL | 创建时间 |
| `updated_at` | INTEGER NOT NULL | 更新时间 |
| `deleted_at` | INTEGER NOT NULL DEFAULT 0 | 软删除时间 |

节拍不保存 `scene_ids` 或页数。场次数量、场号列表和页数都从关联场次聚合，空节拍也允许存在。

约束与索引：

- `act_number > 0`，不在数据库层或 Service 限制只能有三幕；四幕、五幕等结构合法。
- 幕不是独立实体，只是节拍的正整数分组编号；UI 按实际存在的 `act_number` 分组，不保存幕标题或幕记录。
- `episode_id` 规则与场次相同。
- `screenplay_beats_by_episode_id_act_number_sort_order_u` 保证集内排序唯一。
- `screenplay_beats_by_screenplay_id_episode_id_act_number_sort_order` 支持节拍板查询。

### 5.8 `screenplay_scene_characters`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | TEXT PK | 关联 ID |
| `scene_id` | TEXT NOT NULL | 场次 ID |
| `character_id` | TEXT NOT NULL | 现有 `character_profiles.id` |
| `sort_order` | INTEGER NOT NULL | 场次出场人物显示顺序 |
| `created_at` | INTEGER NOT NULL | 创建时间 |
| `updated_at` | INTEGER NOT NULL | 更新时间 |
| `deleted_at` | INTEGER NOT NULL DEFAULT 0 | 软删除时间 |

约束与索引：

- `screenplay_scene_characters_by_scene_id_character_id_u` 保证一个人物在同一场只关联一次。
- `screenplay_scene_characters_by_scene_id_sort_order` 支持场次人物列表。
- `screenplay_scene_characters_by_character_id` 支持人物出场统计。
- 场次 `cast` 必须包含正文中所有 `character` 元素引用的人物，但可以额外包含没有台词的出场人物。正文写入发现缺失人物时保留已有 `cast` 顺序，把缺失人物按正文首次出现顺序追加到末尾。从 `cast` 移除仍被正文引用的人物时，整次拒绝并返回 `dependent_elements_exist` 与相关元素路径；必须先删除或改派这些对话块。不能静默移除，也不能报告成功后自动补回。
- 可选择列表只查询未删除的 `character_profiles`。人物删除前检查有效场次人物关联和正文人物元素，存在场次引用时返回 `entity_in_use`；关系与画布引用继续沿用现有删除清理语义。读取旧数据或恢复记录时仍能解析软删除档案并显示“原名（已删除）”，不能崩溃或静默隐藏。

场外音、画外音和接续等表演方式属于具体台词元素，不放进场次人物关联。这样一个人物在同一场既出镜又有画外音时不会产生冲突。

### 5.9 `screenplay_scene_elements`

正文一元素一行。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | TEXT PK | 元素 ID，全生命周期稳定 |
| `scene_id` | TEXT NOT NULL | 所属场次 |
| `sort_order` | INTEGER NOT NULL | 场次内顺序 |
| `type` | TEXT NOT NULL | 元素类型，见下表 |
| `text` | TEXT NOT NULL DEFAULT `''` | 元素文本；`character` 类型恒为空串 |
| `character_id` | TEXT NULL | 仅 `type = character` 时非空，指向同内容库 `character_profiles.id` |
| `extension` | TEXT NOT NULL DEFAULT `''` | 仅 `type = character` 时可非空的自由文本，保存时 trim，如 `V.O.`、`O.S.`、`CONT'D`、“画外音”“电话中” |
| `created_at` | INTEGER NOT NULL | 创建时间 |
| `updated_at` | INTEGER NOT NULL | 更新时间 |
| `deleted_at` | INTEGER NOT NULL DEFAULT 0 | 软删除时间 |

第一期支持的元素类型：

| `type` | 非空字段 | 用途 |
| --- | --- | --- |
| `action` | `text` | 动作与场面描述 |
| `character` | `character_id`，可选 `extension` | 对话人物提示 |
| `parenthetical` | `text` | 对话前的括号提示 |
| `dialogue` | `text` | 台词 |
| `transition` | `text` | 转场 |
| `note` | `text` | 只在编辑态显示的创作注释；不属于成稿正文或派生统计 |
| `subtitle` | `text` | 字幕或时间地点说明 |

约束与索引：

- `type` 做枚举校验。
- `sort_order >= 0`。
- `screenplay_scene_elements_by_scene_id_sort_order_u` 保证场次内有效元素顺序唯一。
- `screenplay_scene_elements_by_scene_id_sort_order` 支持按场次读取正文。
- `screenplay_scene_elements_by_character_id` 支持“这个人物有哪些台词”的反查与人物删除时的影响面查询。
- `type = character` 时 `character_id` 必须非空且指向同内容库的有效人物档案；`extension` 可省略或传任意自由文本，保存时只 trim，不限制枚举，也不参与统计或业务判断。其余类型 `character_id`、`extension` 必须为空。若旧数据或恢复记录遇到软删除人物，读模型返回 `character_deleted: true` 和原名，写入则要求先替换或移除该引用。
- `type = character` 时 `text` 必须为空串：人物显示名不冗余存储，见下。
- 序列硬校验只保证归属关系：`dialogue` 与 `parenthetical` 前面必须存在同一连续块里的最近 `character`；遇到 `action`、`transition`、`note`、`subtitle` 或另一个 `character` 时，前一个对话块结束。
- `character` 后允许暂时没有任何子元素，作为写作中的未完成块保存；UI 显示“待补台词或表演”警告，但不阻止自动保存。
- 对话块允许只有 `parenthetical`、没有 `dialogue`，用于“角色：（沉默）”这类无声表演，不显示未完成警告。
- 不校验台词长度、标点、角色连续说话次数、动作内容、幕结构或文学质量。第一期没有完整剧本语法解析器，只用一次 O(n) 邻接扫描检查上述归属。

这套最小校验补上了原草案遗漏的一侧：原规则没有禁止场景开头直接出现 `dialogue`。现在“没人说的台词”仍是硬错误，但人物提示可以悬空保存，疑似格式问题只作为警告，不让编辑器在真实写作中频繁拒绝自动保存。

去掉了 JSON 列，随之去掉的三样东西：`ScreenplayElementListConverter`、`elements_schema_version`、以及“遇到未来版本或损坏元素时保留原始 map 并生成占位”的兼容策略。元素行由数据库列约束，没有解析失败这一类，也就没有需要保留的未知数据；新增元素类型走正常的枚举扩展与 migration。

对话角色必须先建档再引用。`character` 元素只保存 `character_id`，编辑器在插入对话前提供角色选择和就地快速建档入口。保存场次时按元素中的 `character_id` 补建缺失的场次人物关联；删除最后一条台词时不自动删除人物关联，因为人物可以无台词出场。

人物显示名不进元素行，渲染时按 `character_id` 从 `character_profiles` 解析：人物改名立即传播到全部正文。正常流程中，有有效出场或台词引用的人物不能删除；若旧数据、恢复场次或异常数据库状态仍引用软删除人物，正文显示“原名（已删除）”，场次进入引用错误状态并要求先替换或移除。编辑器打开期间把内容库人物表（id、名称、删除标记）读成内存 map，正文渲染不逐元素发起查询。`note` 在编辑态和待审阅正文预览中可见，但成稿渲染跳过它。

场景标题来自 `interior_exterior`、`location_id` 指向的地点名称和 `time_label`，不是元素。`interior_exterior` 为空时标题直接省略内外景段，不显示“未定内外景”。出场人物来自 `screenplay_scene_characters`。Mock 中的 `scene` 与 `cast` 元素不落库。

#### 元素行的删除与表体积

元素行按项目默认走**软删除**，不申请硬删除例外。代价是编辑抖动会留下废行，因此整场写入必须做 **reconcile 而不是先清空再插入**：按 `id` 对齐已有行，只 `UPDATE` 变化的、`INSERT` 新增的、软删真正消失的。正常写作里净删除量小，表体积随内容增长而不是随编辑次数增长。

先清空再插入会让一场戏每改一次就留下几十条废行，且元素 `id` 每次重生成，等于把已经避开的 id 不稳定问题重新引入。这条是硬要求，不是优化。

如果实测表体积仍成问题，正确做法是把本表加进 `StorageCleanupService` 的 retention 清理白名单并**单独取得用户对该范围的确认**，不是在 Service 里私自改成硬删除。

### 5.10 派生数据

以下内容不建独立表：

- 大纲：按集和 `sort_order` 读取场次，再连接节拍与人物关联。
- 节拍页数和场次数：按 `beat_id` 聚合场次。
- 场号：按当前父级内有效场次排序得出。
- 实际集数：统计有效 `screenplay_episodes`。
- 出场矩阵：读取有效场次与 `screenplay_scene_characters`。
- 概览统计：用 SQL 在 `screenplay_scenes` 的缓存列上聚合场次数、页数、时长、台词数、人物数、地点数（按 `location_id` 去重，空值不计）和节拍数，不下探到元素行。

列表、概览和大纲查询只选择场次的元数据列，**不 join `screenplay_scene_elements`**。移动端正文只在打开当前场时按 `scene_id` 加载；桌面连续剧本使用一个按 `episode_id` 参数化的只读 projection stream，一次订阅当前集全部有效场次与元素的渲染字段，切集或离开页面即释放。当前场另订阅完整编辑模型，非当前场只持有 projection 里的不可变预览，不创建 controller、焦点或 selection 状态。

场次保存时，由共享的 `ScreenplayMetrics` 从**非 `note` 元素行**重新计算 `page_eighths`、估算时长、台词数和字数，并与元素写入放在同一内容库事务中。作品总字数通过 SQL `SUM(word_count)` 得出，再同步到主库已有的 `novels.word_count` 缓存。

`ScreenplayMetrics` 的输入是元素列表而不是数据库，纯函数：UI 的未提交编辑态可以用它实时预览页数与时长，落库时 Service 用同一个函数算出要写的值，两边不会算出不同结果。第一期明确标注为“预估”，不承诺制片排版精度，但算法仍需固定，避免同一场在不同入口跳数：

- 字数复用 `countWordUnits()`，不另造中英文统计口径；`note` 不计入。
- 按显式换行分段估算占用行数：`action`、`subtitle` 每行 28 个文本单元，`dialogue` 每行 16 个，`parenthetical` 每行 12 个；`character` 与 `transition` 各计 1 行；`note` 不占成稿行数。每段至少 1 行，空正文或只有 `note` 的正文为 0。
- 每页按 36 行估算，`page_eighths = ceil(estimated_lines * 8 / 36)`；空正文为 0。
- 采用“一页约一分钟”的行业粗估，`estimated_duration_seconds = round(page_eighths * 7.5)`。

这些常量集中在 `ScreenplayMetrics`，UI 只展示结果和“预估”标签；将来做正式打印时替换为排版引擎，不改变数据字段。

### 5.11 关系证据字段

人物关系继续使用 `entity_relations`，不新建剧本关系表。该表现有的证据列 `chapter_id` 指向章节，剧本没有章节，因此新增一列：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `scene_id` | TEXT NULL | 产生该关系的证据场次，指向 `screenplay_scenes.id` |

约束与业务规则：

- `chapter_id` 与 `scene_id` 至多有一个非空；小说工作区有章节证据时写 `chapter_id`，剧本工作区有场次证据时写 `scene_id`。
- 两列允许同时为空。当前 `entity_relations.chapter_id` 本来就是 nullable，现有 UI 也会创建无章节证据的关系；本方案不收紧该公共契约。
- 删除场次时沿用章节证据的现有语义：保留关系本身，把引用该场的 `scene_id` 清空。
- 新增索引 `entity_relations_by_scene_id`，支持“这一场产生了哪些关系”的反查。
- 该列合入未发布的内容库 v16，不新增 schema version；`entity_relations` 无软删除列，沿用该表现有语义，本方案不改动。

不复用 `chapter_id` 存场次 ID：同一列承载两种实体会让所有既有查询和展示都要先判断作品类型，也违反显式建模的约定。

AI 侧的 `Create relations` 由此调整：把现有误设为必填的 `chapter_id` 改为可选，并新增可选 `scene_id`；两者同时传入时返回 `mutually_exclusive_fields`。工具 schema 本身保持静态，两种工作区看到同一份定义；两者都省略时创建一条无证据范围的关系，行为与现有 Service 和 UI 一致。

## 6. 业务规则与写入流程

### 6.1 创建作品

1. 桌面端创建弹窗或移动端创建页收集作品类型。
2. `NovelActionsService.createNovel()` 增加向后兼容的 `contentKind`，默认 `novel`；值为 `screenplay` 时初始化剧集内容库。
3. 剧本路径先保存调用方原本请求的 `requestedDraft`，再以 `draft = true` 创建暂不进入书架的主库记录并初始化内容库；这个临时隐藏态不能改变“快速开书草稿”的业务语义。小说路径保持现状。
4. 小说沿用当前初始化逻辑。剧本统一创建一条 `screenplays`、第 1 季和该季实际的第 1 集；Season 始终存在，不另建“无季”分支。
5. 内容库初始化成功并关闭句柄后，在一个主库事务中同时写入 `content_database_path` 并把 `draft` 恢复为 `requestedDraft`；普通创建由 true 变 false 后进入书架，调用方本来要求草稿时仍保持 true。转换上报只在这个 finalize 事务成功后发生。
6. 创建流程以已生成的 `novel_id` 为补偿边界：外层 `try/catch` 包住内容库初始化与主库 finalize，内容库句柄保存在局部变量；内层 `try/finally` 完成根记录/第 1 季/第 1 集写入，并对已打开句柄恰好 `await close()` 一次，随后才执行主库 finalize。任一步失败都保留原异常，记录包含表名、操作和 ID 的数据库日志，并在句柄关闭后调用 `NovelDao.softDelete(novel_id)` 隐藏已创建的主库记录；补偿本身失败时追加记录补偿异常，但不能覆盖最初失败。失败流程不删除封面或内容库文件，避免未经确认删除业务数据。

创建表单可以选填规划集数，值写到自动创建的第 1 季；表单不询问季数，也不展示 Season 概念。快速开书、TXT 导入和远程创建等入口继续传默认值 `novel`。

### 6.2 场次编辑

1. 新增场次时，Service 用 SQL `MAX(sort_order)` 取得目标集内下一个顺序，并校验集归属。
2. 场景标题、梗概、状态和正文元素作为一个场次编辑会话提交。
3. Service 的硬校验只覆盖元素枚举与字段配对、台词/括号提示的角色归属、元素 ID 所属场次、新增或改变的 `character_id` / `location_id`、以及 `beat_id` 同集关系。悬空 `character` 与疑似场景标题动作行作为 warnings 随结果返回，不阻止保存（5.9、9.3）。
4. 元素写入按稳定 `element_id` 做 reconcile，也就是把“客户端提交的完整目标数组”与“数据库当前数组”对齐后只写差异：命中当前场已有行且内容变化的 `UPDATE`；不带 `element_id` 的新元素由 Service 生成 ID 后 `INSERT`；本次数组里消失的已有行软删除；顺序按数组下标重排。调用方传了不存在或属于其他场次的 `element_id` 时整次拒绝，不把未知 ID 当成新元素。不做“先清空再插入”（5.9）。
5. 出场人物的增删与重排在同一事务中更新关联表；元素里新出现的有效 `character_id` 自动补进关联表。删除场次人物关联前检查正文元素，仍有引用时返回 `dependent_elements_exist` 与元素路径；人物仍被场次人物关联或正文元素使用时，人物档案删除操作被拒绝。
6. Drift watch stream 推送新场次、大纲、节拍统计和人物矩阵，页面不手写多份缓存。
7. 内容库事务完成后同步主库总字数。同步失败会记录错误并向用户提示统计暂未更新，场次正文不回滚。

桌面与移动端使用相同的 Service。UI 只管理尚未提交的局部编辑态，不直接调用 DAO。

作品创建、场次信息和节拍信息等多字段提交使用 `lib/third/form` 管理校验、脏状态与重置。正文元素编辑器使用局部 controller 和 hooks 管理输入、焦点与防抖保存，不把每次按键写进 Riverpod。

### 6.3 重排与跨集移动

- `sort_order` 只属于表内存储和 DAO 查询，不进入 UI 表单、AI schema、工具响应或 Service 的公开调用契约。场次 listing 返回从 1 开始的派生 `scene_number`，节拍 listing 返回幕内从 1 开始的派生 `beat_number`；两者都不是稳定标识，也不可写。
- `ScreenplayService` 对场次只公开三个业务动作：`moveSceneBefore(sceneId, anchorSceneId)`、`moveSceneAfter(sceneId, anchorSceneId)`、`moveSceneToEpisodeEnd(sceneId, episodeId)`。前两个动作允许锚点位于另一集，锚点所属集就是目标集；第三个动作表示明确追加到目标集末尾。UI 拖拽和 AI 的业务字段都映射到这三个动作，不传数值顺序。
- 场次 Write 的 `before_scene_id`、`after_scene_id`、`episode_id` 最多表达一个移动意图：`before_scene_id` 与 `after_scene_id` 互斥；带锚点时不再同时接受 `episode_id`，目标集由锚点确定；只写与当前值不同的 `episode_id` 表示追加到目标集末尾。锚点等于自身返回 `invalid_scene_anchor`，锚点或目标集无效返回 `invalid_scene_ref` / `invalid_episode_ref`，任一失败都不修改数据。
- 场次跨集移动时，如果原 `beat_id` 不属于目标集，事务会清空 `beat_id`；同一 Write 显式提供了属于目标集的 `beat_id` 时则直接改绑。界面明确提示被自动清空的节拍需要重新选择。
- `ScreenplayService` 对节拍只公开 `moveBeatBefore(beatId, anchorBeatId)`、`moveBeatAfter(beatId, anchorBeatId)`、`moveBeatToActEnd(beatId, actNumber)`。第一期不支持节拍跨集移动；锚点必须属于同一集，跨幕锚点的幕就是目标幕，`moveBeatToActEnd` 表示追加到指定正整数幕的末尾。已有节拍的 Write 带任一锚点时不再同时接受 `act_number`；只写不同的 `act_number` 才表示移到目标幕末尾。锚点等于自身或属于另一集分别返回 `invalid_beat_anchor`、`beat_anchor_outside_episode`，无效幕号返回 `invalid_act_number`。
- DAO 在上述业务动作内部先写临时顺序，再统一写从 0 开始的最终 `sort_order`；源、目标分组的连续重排与父级/幕更新放在一个事务中。调用方永远不读取或写入这个临时值。
- 季的顺序就是用户可见季号。多季管理页支持重排，Service 先写临时号再统一写从 1 开始的连续 `season_number`；新增季取有效季号最大值加一，并同时创建该季第 1 集。
- UI 新增季前先 flush 当前场；创建事务返回新 `season_id` 与第 1 集 `episode_id` 后，工作区状态立即切到这两个稳定 ID，并清空当前场选择。AI 按明确用户意图新增季时也通过活动上报让已打开的编辑器跟随到新季第 1 集；编辑器未打开时只创建数据，不额外改写本机工作区快照。
- 集的顺序就是本季用户可见集号。UI 拖拽与 AI 写 `episode_number` 都调用同一个季内移动事务：目标号必须在 `1..当前季有效集数`，Service 用临时号避开唯一索引后平移区间并写入最终连续编号；新增集取当前季有效集号最大值加一。
- 集跨季移动是显式操作：调用方提供目标 `season_id`，Service 先确认目标是同一剧本的有效季、源季仍会保留至少一集；目标无效返回 `invalid_season_ref`，移动的是源季唯一有效集时返回 `last_episode_required`，两者都不修改数据。只提供 `season_id` 时把该集追加到目标季末尾；同时提供 `episode_number` 时，目标号按移动前目标季的 `1..有效集数 + 1` 校验，并把该集插入该位置。Service 在一个事务中保留集及全部场次、节拍、正文的稳定 ID，重新编号源季与目标季，并一起提交同次 Write 中的标题、目标时长等单集字段。普通场次与节拍操作不需要知道 Season。
- 跨季移动不修改源季或目标季的 `planned_episode_count`。规划数只是各季独立的指导值，移动后低于规划或超出规划都有效，界面按实际结果展示。
- UI 移动当前打开的集前先 flush 当前场，成功后把工作区当前季切到目标季并继续打开同一个 `episode_id`；移动其他集不改变当前季。AI 移动当前集时，活动跟随同样让 UI 进入目标季，但该 AI 回合已经冻结的默认季仍是移动前的季，只有下一回合才采用新的当前季。

### 6.4 删除

- 删除单个正文元素时，软删除该行并把同场后续元素的 `sort_order` 依次前移；同事务重算场次派生统计。
  - 删除后面仍紧跟 `parenthetical` 或 `dialogue` 的 `character` 时拒绝操作，返回 `dependent_elements_exist`，不得隐式删除台词。
  - UI 提供明确的“删除整个对话块”操作并二次确认；也可以先把从属元素重新归给另一人物，再删除原人物提示。
  - AI 删除整个对话块时，使用整场 `Write` 明确提交不含该块的目标数组，或先删除从属元素再删除人物提示。
  - 删除 `dialogue` 或 `parenthetical` 不反向删除 `character`；剩下悬空人物提示时显示未完成警告。
- 删除场次时，软删除场次、场次人物关联和该场的正文元素行，清空以该场为证据的关系 `scene_id`，但保留关系本身。节拍保留，聚合结果自动减少；证据处理与现有章节删除时清空 `chapter_id` 的行为一致。
- 删除节拍时，先清空有效场次的 `beat_id`，再软删除节拍。
- 删除集前先确认同一季还有其他有效集；唯一有效集返回 `last_episode_required`。允许删除时，在一个事务中软删除该集、所属节拍、场次、场次人物关联和这些场次的正文元素行，清空以这些子场次为证据的关系 `scene_id`，并把该季后续有效集的 `episode_number` 依次减一（先软删再改号，避开有效集号唯一索引的瞬时冲突）。关系只失去场次证据，不随集删除。
- 删除季只在至少还有另一有效季时允许；唯一有效季返回 `last_season_required`。允许删除时，沿用删集级联范围软删除该季全部集、节拍、场次、场次人物与正文元素，清空子场次的关系 `scene_id`，再把后续季号连续前移。人物、地点、关系本身与共享资料不随季删除。
- 删除的是当前季时，UI 在同一操作完成后选择原列表位置上的下一季；若被删的是最后一季，则选择前一季。切换前先 flush 当前场次。这个选择只更新本机工作区状态，不进入删除事务或剧本表。
- 删除季、集或场次不额外查询、接受、退回或改写相关 `working_changes`，与现有章节删除保持一致；不为剧本新增跨 `ScreenplayService` 与 working overlay 的删除编排。目标资源删除后仍存在的待审阅条目继续服从现有 overlay 行为，第一期不单独修正。
- 删除人物档案前，Service 在同一内容库内检查 `screenplay_scene_characters` 与 `screenplay_scene_elements.character_id`。存在有效场次引用时返回 `entity_in_use`，按场次和台词分类返回使用处；桌面与移动端只提供“查看使用处”，用户替换或移除全部场次引用后才能继续删除。
- 删除地点前，Service 检查 `screenplay_scenes.location_id`。存在有效场次引用时返回 `entity_in_use` 并列出场次；清空或替换后才能继续删除。
- 场次引用检查与删除放在同一内容库事务内，避免检查结束到删除之间新增引用。若没有场次引用，人物的关系/画布清理和地点的关系/画布/子地点/地图清理继续走现有小说语义，本功能不改变它们。旧数据、恢复软删除场次或外部数据库修改仍可能产生失效引用，读模型按 5.6/5.9 显示“（已删除）”作为兜底。
- 删除剧本根记录只随作品删除流程发生，第一期不提供单独按钮。

第一期没有回收站或恢复入口。上述软删除用于避免不可逆的数据移除，并为后续单独设计恢复流程保留可能；当前 UI 与 AI 工具都不暴露恢复操作。

### 6.5 读写状态

读模型使用参数化的 Drift `watch()` 和 Riverpod `StreamProvider`。写入统一走 `ScreenplayService`，采用“Stream 读 + Service 写”模式，不再建一个平行的缓存 Notifier。

Provider 按根记录、季列表、当前季集列表、当前集场次、大纲、节拍和人物矩阵拆分。编辑器打开期间由页面订阅，离开后自动释放，不为每个剧本永久 `keepAlive`。加载完成前，编辑控件显示明确的 loading 或 disabled 状态，不使用空对象冒充真实数据。

当前季、当前集、当前场与工作区 section 使用按作品分 key 的版本化 `app_states` 快照持久化，沿用现有桌面小说工作区选择的模式，但桌面与移动端共用剧本状态 Provider。打开作品时先恢复快照，再用有效季、集和场次列表修复：保存的 `season_id` 有效就恢复；失效或没有保存值时选择第一个有效季；集与场次再在修复后的季内按同样原则恢复。修复结果重新写回快照。该状态只属于本机，不进入内容库、备份业务模型或跨设备同步。

## 7. 桌面端

### 7.1 路由与边界

新增通用 `WorkspaceEditorPage`。它读取 `Novel.contentKind` 后进入现有 `NovelEditorPage` 或新的 `ScreenplayEditorPage`。所有书架、最近作品、任务入口和创建成功跳转统一经过该路由，避免某个入口仍把剧本送进小说编辑器。

剧本 UI 放在 `lib/desktop/features/screenplay/`。`ScreenplayEditorPage` 通过独立的剧本工作区状态 Provider 管理导航、当前季、当前集、当前场和视图模式，不把新状态加进 `NovelEditorPage`。右侧 AI 面板复用小说编辑器的同一套外壳与会话，工作区类型由页面注入（见 9.1）；面板要接线 `active_workspace_target`（当前季、当前集与当前场）、场次跳转回调和待审阅改动入口，依赖章节结构的动作按 9.7 关闭。

### 7.2 页面

- 概览：单季时直接显示项目信息、实际集数、场次、篇幅、时长、台词、人物、地点和节拍，不出现季级控件；多季时增加整部剧集统计和可进入的各季摘要。
- 剧本：按当前集连续排版；场景标题与人物列表来自关系型字段，人物显示名按 `character_id` 实时解析。
- 大纲：按集分组显示场景标题、梗概、状态、节拍、篇幅和人物，可编辑梗概与顺序。
- 节拍：按幕分栏，显示节拍说明、关联场次和派生页数；幕数不设上限，桌面端出现横向滚动时用 `HorizontalWheelScroll` 包裹并使用它提供的 controller，让普通鼠标滚轮可操作。
- 场次：支持场次卡和场次表，两种视图使用相同查询。
- 人物关系：左侧复用人物档案，右侧显示当前集的出场矩阵，并复用现有 `entity_relations` 展示人物关系。

分镜入口不显示，也不放一个不能使用的空页面。格式切换和导出按钮同样不显示。

### 7.3 桌面交互

- 左侧上下文栏在单季时只显示实际集列表与“新增一集”，作品设置沿用“规划集数”文案，不显示“第 1 季”或季选择器。低频的“新增一季”固定放在集选择器底部，与桌面设计稿一致，不再保留作品菜单这一备选落点。
- 新增第二季后，左侧上下文栏顶部才出现季选择器，显示当前季；选择器列出季标题、实际集数与规划集数，底部进入内联“管理季”区域。管理区支持新增、改名、编辑本季规划集数、进入、重排和删除，不用常驻多层季集树，也不用普通编辑弹窗承载管理。
- 从任一桌面入口新增季成功后，立即进入新季自动创建的第 1 集，不停留在旧季；新增前先 flush 当前场，失败时保持原选择。
- 多季作品的集菜单提供“移动到其他季”，选择目标季后把该集追加到目标季末尾；源季只有一集时入口禁用并解释必须至少保留一集。移动当前集前 flush，成功后跟随它进入目标季。
- 多季删回一季后，季选择器和管理层级自动隐藏；唯一一季没有删除入口。
- 场次板是横向主要操作区，必须由 `HorizontalWheelScroll` 包裹，并使用它提供的 controller，让普通鼠标滚轮可用。
- 场次表是宽表格，不接管垂直滚轮，提供始终可发现的横向滚动条。
- 剧本页用 `CustomScrollView` / sliver 显示当前集的连续场次，但同一时间只有**当前场次**挂载可编辑控件。其他场次只渲染轻量只读预览；点击或键盘移动到另一场时，先 flush 前一场，再把编辑器挂载到新场的原位置，因此视觉上仍是一份连续剧本。
- 当前集订阅唯一的 Episode 级轻量 projection stream：DAO 一次返回按场次和元素顺序组织的不可变渲染模型，当前集任一场次被人工或 AI 修改后由 Drift 自动刷新，不做逐场懒加载，也不维护手写缓存。当前场次另订阅完整编辑 stream；不要为整集约 1500 行同时创建 `TextEditingController`、FocusNode 和 selection 状态。切集或离开页面时释放上一集 projection。
- 页面级 `SceneSaveCoordinator` 串行化保存：每次编辑增加本地 revision，600ms debounce 后提交最新场次快照；同一时间最多一个写入在途，在途期间的新修改合并为下一份最新快照，不为每次按键排队。旧 revision 完成时不能覆盖较新的本地状态；切场、切集、切季、返回和关闭窗口都调用 `flush()`，等待在途写入并保存最后一份快照。
- 保存失败时保留当前场本地草稿和 dirty 状态，停止自动切场并显示重试；不能用失败前的 stream 数据覆盖输入框。移动端单场编辑器复用同一个 `SceneSaveCoordinator`，只是没有连续只读场次壳。
- 人工与 AI 同时写同一场沿用小说编辑器现状，不新增数据库 revision、CAS、场次锁或 `stale_scene` 错误。stream 不覆盖 dirty 的本地 controller，`SceneSaveCoordinator` 只串行化本编辑器自己的保存；若两路写入确实交错落库，后完成的写入生效。第一期不为缺少实际使用场景的并发编辑增加额外协议。
- 场次正文编辑器插入对话前必须选择已有角色；角色不存在时就地输入名字快速创建人物档案并自动关联，入口放在插入对话的位置，不打断写作流。
- 场景标题编辑器的地点从 `locations` 选择，支持就地输入名字快速建地点；地点为空的场次仍可排梗概，标题显示“未定地点”占位。
- 概览、状态栏等高频变化区域与长正文拆成独立 Widget，避免重建整份正文。
- 全屏壳使用桌面 chrome 背景规则，场次卡等内容块使用不透明 elevated surface。

## 8. 移动端

### 8.1 独立编辑器

新增 `MobileWorkspaceEditorPage` 作为统一入口，并新增 `lib/mobile/features/screenplay/`。剧本进入 `MobileScreenplayEditorPage`，现有 `MobileNovelEditorPage` 只处理小说，避免在已有大页面继续追加状态和分区。

页面根使用 `Scaffold(backgroundColor: colors.canvas)`。手机采用单列全屏路由，平板通过 `LayoutBuilder` 在空间足够时显示列表与详情双栏；判断只看可用约束，不看设备型号或横竖屏。

### 8.2 移动端页面与交互

- 顶部为自绘 header。单季时只显示当前集 pill，点击后打开 `showModalBottomSheet` 选择或新增实际集；“新增一季”作为低频项放在 sheet 底部。多季时才在集 pill 前增加当前季 pill，点击打开季选择 sheet。
- 季选择 sheet 列出季标题、实际集数与规划集数，并可进入全屏“管理季”页面；页面支持新增、改名、编辑规划集数、进入、重排和删除。删回一季后季 pill 自动隐藏。
- 从任一移动端入口新增季成功后，关闭 sheet 或管理页并进入新季自动创建的第 1 集；新增失败时保留原选择和页面。
- 多季作品的集操作 sheet 提供“移动到其他季”，目标季用单选列表选择；移动当前集后关闭 sheet 并跟随它进入目标季。源季只有一集时不允许移动。
- 移动端与桌面端读取同一个剧本工作区状态契约：重开作品时恢复本机上次选择的有效季、集和场，失效时按 6.5 修复；不另建只在移动端生效的默认规则。
- 概览使用单列或双列统计区域；单季不显示范围切换，多季才提供整部剧集与当前季摘要。规划集数仅在设定后作为当前季分母显示，实际集数超过它时显示“已超出规划”警示。
- 大纲以场次列表呈现，点场次进入全屏场次编辑页。
- 节拍在手机上按幕纵向排列，平板空间足够时显示多栏。
- 场次表在手机上改成信息卡列表，不强行压缩桌面宽表。
- 剧本正文使用“场次列表 -> 单场全屏编辑器”，不在手机上渲染整集长文。
- 单场正文编辑器插入对话同样要求先选已有角色，场景标题的地点从 `locations` 选择；两者都支持就地输入名字快速建档并自动关联。
- 人物关系在手机上分成“本场人物”和“人物出场场次”两个列表；平板可显示自适应矩阵。
- 可删除的集、场次和节拍从列表左滑进入删除确认，次要操作放到底部 sheet，触控区域不小于 44pt。季删除只放在全屏管理页，不给快捷左滑入口。
- 正文编辑保持默认键盘避让，自动保存需要 debounce，并在页面退出前 flush。
- AI 入口复用现有移动端聊天页，由剧本页传入工作区类型、当前季、当前集和当前场；手机上 AI 写入后回到场次列表并高亮被改动的场次。当前季在 AI 回合开始时冻结，界面随后切季不改变该回合省略 `season_id` 的目标。

移动端与桌面端共享模型、DAO、Service、Provider、校验、统计和元素渲染逻辑，只分别实现平台外壳。AI 侧同样共享：工具、门禁、跨作品解析和 prompt 装配都在 `lib/shared`，两端只接线宿主回调。

## 9. AI 工作区接入

剧本工作区直接复用当前 `aiToolCatalog` 的完整工具集合，包括 Read、Glob、Grep、Create、Write、Edit、Replace、Remove、GraphSearch、Run、WebSearch、WebFetch、SpawnAgent、ForkAgent、AgentSkill、TodoWrite、AskUser、SuggestNextAction；不在方案里维护另一份可能漂移的工具白名单，也不新增工具名。input schema 只做本方案列明的一次全局加法式调整：relations 新增可选 `scene_id` 并把 `chapter_id` 改为可选，GraphSearch 新增可选 `work_id`，通用字段种类支持结构化元素数组。调整后的工具定义保持静态，两种工作区完全相同。剧本能力以一个新的相对路径命名空间 `screenplay` 加入，做法与画布 `canvas` 一致：通用工具 + 专属路径 + 专属 Bundled AgentSkill。

### 9.1 隔离原则

| 层 | 做法 | 结果 |
| --- | --- | --- |
| 数据 | 剧本资源挂在 `screenplay` 下，不复用 `chapters`、`volumes`、`outlines` | 两套结构不会互相污染，也不需要在同一路径上判断作品类型 |
| 工具定义 | 工具名、input schema 与 tool description 保持静态，不按工作区裁剪 | 遵守 AGENTS.md 第 13 条，工具定义缓存与调用契约不失效 |
| 执行期 | 按**目标作品**的 `content_kind` 门禁：越界路径返回 `content_kind_mismatch`，并给出该作品的替代路径 | 小说会话调不动剧本资源，剧本会话调不动自己的章节资源，但读得到原著的章节资源 |
| Prompt | 路径规则、场景指引、AgentSkill 索引与 SubAgent 索引按工作区类型装配 | 按体裁过滤后的内容保持不变；两种工作区都显示只读 `/works/{work_id}/…` 路径 |

`contentKind` 的唯一真源是主库 `novels.content_kind`。宿主读出后注入 `AiServiceConfig.contentKind` 与 `AiSessionContext.contentKind`，默认 `novel`；工具层与 prompt 层都读这一份，不再由内容库另行推断（同一事实两处判断必然分叉）。剧本宿主还把回合开始时的 `currentSeasonId` 同时注入工具配置与会话上下文，工具层把它当成省略 `season_id` 时的默认作用域；会话上下文只在多季作品里把当前季渲染给模型，单季时不显示 Season 术语。没有打开作品的会话按 `novel` 处理，此时内容库为空，剧本路径本来就无处可读。

会话的 `contentKind` 只决定 prompt 装配与当前作品的门禁。`/works/` 路径改由**目标作品**的类型判定（9.9）——这两件事必须分开，否则剧本会话读原著章节会被自己的类型误杀。

门禁放在执行期而不是裁剪工具 schema，与画布权益门禁 `_requireCanvasAccess` 同一条理由。区别是画布未授权时可以拉起升级后放行，工作区类型不匹配无法补救，直接返回结构化错误让模型改用正确路径。

#### 剧本 schema 在哪几层出现

「schema 由 bundled skill 按需暴露、不常驻」这件事需要分三层说，因为它们是三个不同的机制，`hidden: true` 只管得住其中一层。把它们混成一个开关会得到错误的预期。

| 层 | 渲染函数 | 看 `hidden` 吗 | 剧本集合的处理 |
| --- | --- | --- | --- |
| 字段字典（字段含义、必填、只读、枚举） | `pathSchemaFieldNotes()`（`tools_support.dart:1644`） | 看，只渲 `hidden: false` | `screenplay` 与 `works` 都设 `hidden: true`，**完全不出现**，字段说明由「剧本写作指南」按需载入 |
| 路径模板清单（`screenplay/scenes/{scene_id}` 这种拼法） | `_buildPathGrammarReference()`（`:1594`） | **不看** | 靠 `pathSchemaBlock()` 的 `kind` 参数按工作区过滤：小说会话不渲剧本路径，剧本会话不渲章节、卷、大纲、伏笔；两侧都保留只读 `/works/{work_id}/…` |
| 静态 tool description | `_buildQueryableFieldReference()`（`tools_read.dart:21`）、`_buildCreateOnlyCollectionList()`（`tools_write.dart:14`） | **不看** | **裁不掉**，两种工作区都会多出这几行 |

前两层都在每轮常驻的 system prompt 里，都能收干净：字段字典靠 `hidden`，路径清单靠工作区过滤。注意 `_buildPathGrammarReference()` 的现有注释明写它「必须覆盖全部集合，包括 hidden 的 canvas / relations」——理由是路径怎么拼每轮都要用。给它加工作区过滤不违背这条：剧本会话确实用不到章节路径，过滤掉的是**当前会话根本调不动的集合**，不是「按需载入的细节」。

第三层裁不掉，因为 tool description 是 tool schema 的一部分，AGENTS.md 第 13 条禁止按运行时状态改它。代价就是 `Read` 的可查询字段清单、`Write` 的 create-only 集合清单会因为新增 `screenplay` 与 `works` 而各多出一两行，小说会话也看得到。这是「schema 静态」的必然结果，接受它，不要为了省这几行去做按工作区裁描述——那会打掉工具定义缓存与调用契约。

### 9.2 资源路径

`screenplay` 在 `_collectionSchemas` 中按 `usesNamePath` 声明（与 `canvas`、`outlines` 同一套解析）：末段命中字段名时切成 `field`，否则整串留在 `namePath`。`seasons`、`episodes`、`scenes`、`beats`、`elements` 是保留段名，**不能**进 `screenplayPathFieldSegments`——同 `canvas` 的 `nodes`/`edges`，它们要留在 `namePath` 当子资源段用，否则 `/elements/{element_id}` 切不出来。

路径 schema 的占位符必须使用资源专名，不再渲染含义不明的 `{id}`：作品是 `{work_id}`，章节是 `{chapter_id}`，季是 `{season_id}`，集是 `{episode_id}`，节拍是 `{beat_id}`，场次是 `{scene_id}`，正文元素是 `{element_id}`，人物和地点分别是 `{character_id}`、`{location_id}`。这只改变 schema、prompt 与错误提示中的模板名称，不改变真实 URL 中 ID 值，也不要求修改 `ParsedPath.id` 这个内部通用槽位。`_CollectionSchema` / 子资源 schema 需要声明自己的 `idPlaceholder`，由 `_buildPathGrammarReference()` 渲染，例如 `chapters/{chapter_id}`、`screenplay/seasons/{season_id}`、`screenplay/scenes/{scene_id}`、`/works/{work_id}/chapters/{chapter_id}`。

作品级通用资源拆成两个单例：`profile` 只放标题、作者、简介、分类、状态与标签；`story_state` 只放 AI 累积维护的叙事状态。两者都不属于小说或剧本的结构命名空间，因此当前作品与 `/works/{work_id}` 指向的目标作品都可以读取；`story_state` 不因 `content_kind` 返回 `content_kind_mismatch`。旧输入 `/novel` 与 `/novel/current_state` 只在解析层分别兼容到 `profile` 与 `story_state`，不会出现在 tool description、path schema 或 prompt 中。

| 路径 | 用途 |
| --- | --- |
| `screenplay` | 剧本根记录与整部剧集概览：`kind`、`format` 与派生的季数、集数、场次数、篇幅、时长、台词数 |
| `screenplay/seasons` | 季 listing；`Create` 新增一季并同时创建该季第 1 集 |
| `screenplay/seasons/{season_id}` | 单季：`title`、`planned_episode_count` 可写，`season_number` 只读 |
| `screenplay/episodes?season_id=` | 集 listing；当前作品省略 `season_id` 时读回合冻结的当前季，显式传入时读取指定季；跨作品省略规则见 9.9；`Create` 新增一集 |
| `screenplay/episodes/{episode_id}` | 单集：`title`、`target_duration_seconds`、`episode_number` 与用于显式跨季移动的 `season_id` 可读写；`episode_number` 是用户可见集号而不是内部排序字段，ID 已唯一定位集，不再要求季参数 |
| `screenplay/beats?episode_id=` | 节拍 listing，附派生的关联场次数与页数 |
| `screenplay/beats/{beat_id}` | 单个节拍：`act_number`、幕内派生且只读的 `beat_number`、`title`、`description`；移动使用只写的 `before_beat_id` / `after_beat_id`，不暴露 `sort_order` |
| `screenplay/scenes?episode_id=&beat_id=&stage=&search=` | 场次 listing，只含元数据、派生 `scene_number` 与统计，不含正文或 `sort_order` |
| `screenplay/scenes/{scene_id}` | 单场：结构字段、梗概与派生统计；移动使用 `episode_id` 或只写的 `before_scene_id` / `after_scene_id` |
| `screenplay/scenes/{scene_id}/synopsis` | 场次梗概，也是大纲正文 |
| `screenplay/scenes/{scene_id}/elements` | 正文元素 listing；`Write` 整场替换，`Create` 追加或插入单个元素（可选 `after_element_id` 定位，省略时追加到末尾） |
| `screenplay/scenes/{scene_id}/elements/{element_id}` | 单个元素：`type`、`text`、`character_id`、`extension` |
| `screenplay/scenes/{scene_id}/elements/{element_id}/text` | 单个元素的文本 |
| `screenplay/scenes/{scene_id}/cast` | 出场人物：读回 `[{character_id, name}]`，写入传 `character_id` 数组，整表替换 |
| `screenplay/scenes/{scene_id}/open` | 写 `true` 让宿主把编辑器切到该场 |
| `/works/{work_id}/…` | 只读访问指定有效本地作品；`work_id` 从 `/works` listing 获取 |

路径与字段规则：

- Season 路径只用于季管理与显式跨季操作，不把普通集、节拍、场次路径嵌套到 `screenplay/seasons/{season_id}/...` 下。单季作品的常规调用直接省略 `season_id`；模型不应为了确认唯一一季而先读 `screenplay/seasons`，也不应在普通回复里主动引入“第 1 季”。
- 当前作品的 `Create screenplay/episodes` 与 listing 使用同一可选 `season_id`：省略时使用本回合冻结的当前季，显式传入时在指定季新增。回合中即使用户切换 UI，默认季也不漂移；下一回合才采用新的当前季。若冻结的季在回合中被删除，省略参数的后续操作返回 `season_not_found`，不静默改投另一季。跨作品路径只读，不存在跨作品 Create；读取其他剧本的省略规则见 9.9。
- AI 可以读、新增和编辑 Season，但 `Remove screenplay/seasons/{season_id}` 始终返回 `season_delete_requires_user_action`。删除季只能由用户进入双端显式季管理界面、查看级联范围并二次确认后执行；不能通过 AskUser 后重试工具调用绕过。
- AI 也不能重排 Season：`season_number` 保持只读，写入返回标准 `read_only_field`；不提供接收完整季 ID 数组或目标位置的重排路径。季重排只由显式季管理 UI 调用 Service 的事务方法。
- `Create screenplay/seasons` 只在当前用户任务明确要求新增、下一季、第二季或多季规划时调用。超过 `planned_episode_count`、故事篇幅增长、AI 自己认为适合分季，或作品已经有多季，都不构成创建授权；AI 可以建议分季，但必须等待用户明确要求。这个约束属于 orchestrator 与「剧本写作指南」的行为规则，不给 Create 增加无法验证的确认字段，也不动态修改 schema。
- `Create screenplay/seasons` 返回新 Season 和自动创建的第 1 集完整路径与 ID。已打开的编辑器跟随进入新季第 1 集，但本 AI 回合冻结的默认季不变；模型要在同一回合继续操作新季，必须使用返回的 `season_id`、`episode_id`，不能继续省略季参数并假设默认值已经切换。
- 写单集的 `season_id` 表示把该集显式移动到目标季，不是重复声明当前父级。目标 ID 必须来自 `screenplay/seasons` listing；省略 `episode_number` 时追加到目标季末尾，同时提供时原子地插入目标季该集号，合法范围为 `1..目标季移动前有效集数 + 1`。源季只剩该集时返回 `last_episode_required`，无效目标返回 `invalid_season_ref`，目标号越界返回 `invalid_episode_number`。
- 单独写 `episode_number` 表示在该集当前所属季内移动到目标号，合法范围为 `1..有效集数`；超出范围返回 `invalid_episode_number`。读回的同一字段仍是移动完成后的用户可见集号，不另加 `position` 或 listing 级顺序替换协议。
- `season_id` 与当前所属季相同时不算跨季移动：只写相同 ID 是无变化，同时带 `episode_number` 时按季内 `1..有效集数` 规则重排，不触发源季最少一集检查，也不使用跨季的 `目标季集数 + 1` 范围。
- 场次可写的持久业务字段是 `episode_id`、`beat_id`、`interior_exterior`、`location_id`、`time_label`、`synopsis`、`stage`、`cast`；移动命令字段是只写的 `before_scene_id`、`after_scene_id`。`before_scene_id` 与 `after_scene_id` 互斥，带任一锚点时目标集由锚点确定，不再同时接受 `episode_id`；只写不同的 `episode_id` 表示追加到目标集末尾。派生 `scene_number` 与统计只读，内部 `sort_order` 不进入 schema。正文不是场次字段，走 `elements` 子资源。
- 节拍可写的持久业务字段是 `act_number`、`title`、`description`；移动命令字段是只写的 `before_beat_id`、`after_beat_id`。两个锚点互斥，已有节拍带锚点时不再同时接受 `act_number`；锚点必须属于同一集，跨幕锚点的幕就是目标幕。只写不同的 `act_number` 表示追加到目标幕末尾。派生 `beat_number` 只读，内部 `sort_order` 不进入 schema。第一期没有节拍跨集移动字段。
- 写 `elements` 时，新出现的有效 `character_id` 会自动补进 `cast`：已有顺序不动，多个缺失人物按正文首次出现顺序追加；只有无台词出场的人物需要单独写 `cast`。删掉最后一句台词不会自动移除该人物。反向写 `cast` 时，仍被正文 `character` 元素引用的人物不能移除，返回 `dependent_elements_exist` 与相关元素路径；旧数据中的删除人物引用可读但不可写，必须先替换或移除。
- 根记录不做字段路径（`usesNamePath` 下单段会被当成资源名）。读 `screenplay` 拿整份，写用 `Write screenplay` 加 `fields`；`kind` 与 `format` 只读。
- 根记录随作品创建生成，`Create screenplay` 返回错误并说明由创建作品流程产生。
- `Create screenplay/scenes` 与现有 `Create chapters` 对齐：一次调用接收场次结构字段、可选 `synopsis`、`cast` 与初始 `elements`，由 `ScreenplayService` 一次创建完整场次；位置必须用 `episode_id`（追加末尾）、`before_scene_id` 或 `after_scene_id` 三者之一表达，锚点本身决定目标集。初始正文仍遵守 9.3 的数组契约。创建成功后只产生一条场次级 `create` working change，不为这次调用里的梗概或正文另建 change。
- `Create screenplay/beats` 必须提供 `episode_id` 与正整数 `act_number`，默认追加到该幕末尾；可选 `before_beat_id` 或 `after_beat_id` 精确定位，锚点必须属于同一集与目标幕。场号与节拍号都从当前父级顺序派生，只出现在读取结果中，不可写。
- `season_id`、`episode_id`、`beat_id`、`location_id`、`character_id`、`element_id` 一律从对应 listing 的 `entries[].id` 原样复制，与既有路径规则一致。
- 场次 listing 与概览查询不读取元素行，与 5.10 的约束一致；正文只在读 `elements` 时加载。
- `Remove` 支持元素、场次、节拍与集，语义就是 6.4 的软删除与级联；集的删除会重编号，工具返回受影响的集列表；删除最后一集返回 `last_episode_required`。
- `Edit`（精确文本替换）只对 `/synopsis` 与 `/elements/{element_id}/text` 开放，两者都是自由文本单字段。场次与元素 listing 不进 `editableFields`。
- 元素级路径（`Write`、`Edit`、`Remove` 打到单个元素）是写入入口，产生的待审阅条目仍然是场次级的（9.4）。

### 9.3 场次正文的数组契约

正文对 AI 只有结构化一种形态：读回元素数组，写入也收元素数组。**不提供自由文本入口，也不实现文本到元素的解析器。**

`Read screenplay/scenes/{scene_id}/elements` 返回：

```json
{"entries": [
  {"element_id": "el_1", "type": "action", "text": "李默推开门。"},
  {"element_id": "el_2", "type": "character", "character_id": "ch_7", "name": "李默", "extension": "V.O."},
  {"element_id": "el_3", "type": "parenthetical", "text": "压低声音"},
  {"element_id": "el_4", "type": "dialogue", "text": "你来了。"}
]}
```

`name` 是按 `character_id` 实时解析出的**只读**展示字段（含软删除记录，失效时附 `character_deleted: true`）。它存在的原因是模型读正文时需要知道这句是谁说的，不能只给一个 uuid；写入 schema 不接受 `name`，调用方必须提交 `character_id`。

`Write screenplay/scenes/{scene_id}/elements` 收去掉只读展示字段后的元素数组，**整场替换**，语义与 `cast` 一致：

- 带 `element_id` 且命中该场已有元素 → 按数组顺序更新该行。
- 不带 `element_id` → 由 Service 生成 ID 并新建元素行。
- 带了未知或属于其他场次的 `element_id` → 整次拒绝，不能把调用方提供的未知 ID 收编成新行。
- 本次数组里没有出现的已有元素 → 软删除。
- 最终 `sort_order` 就是数组下标。

落库由 `ScreenplayService` 做 reconcile（6.2 第 4 条）。“reconcile”不是一种额外数据形态，而是差量同步算法：把提交数组视为目标状态，按 `element_id` 对齐当前状态，最终得到最少的 UPDATE / INSERT / 软删除操作。这样已有元素 ID 稳定，修改一句台词不会把全场几十行删掉重建。模型改一句台词的推荐做法是 `Write screenplay/scenes/{scene_id}/elements/{element_id}` 或 `Edit .../text`，不必重发整场——但要注意元素级路径只是**省 token 的写入入口**，它产生的待审阅条目仍然是场次级的那一条（9.4）。

`character` 元素只接受 `character_id`，从 `characters` listing 或本场 `elements` 读回后原样复制。`name` 只用于读取展示，不参与写入，不做名称或别名解析；若写入载荷包含 `name`，整次拒绝。角色不存在时先 `Create characters`，再使用返回的 ID。

`extension` 是人物提示后的可选表演或声源标记，接受任意字符串并在保存时 trim；工具 schema 不给它枚举。`V.O.`、`O.S.`、`CONT'D`、“画外音”“电话中”等都合法，空白归一化为空串。它只参与正文渲染，不改变 `cast`、台词归属或派生统计。

写入校验（任一条不过则整次拒绝，不部分落库）：

| 错误码 | 触发 |
| --- | --- |
| `invalid_character_ref` | `character_id` 不指向当前内容库的有效人物档案；旧数据中的删除引用可读，但场次再次写入前必须替换或移除。提示说明跨作品 ID 不能直接复用，必须先在当前作品建档 |
| `invalid_element_id` | 提交的 `element_id` 在当前场不存在 |
| `foreign_scene_element_id` | 提交的 `element_id` 属于其他场次 |
| `missing_required_fields` | `type = character` 缺 `character_id`；其余类型缺 `text` |
| `unexpected_field` | 非 `character` 类型带了 `character_id` 或 `extension`；`character` 类型带了 `text` 或只读展示字段 `name` |
| `invalid_element_sequence` | `dialogue` 或 `parenthetical` 前面没有同一连续块里的 `character`；悬空 `character` 不触发错误 |
| `dependent_elements_exist` | 单独删除的 `character` 后仍有属于它的 `parenthetical` 或 `dialogue`，或从 `cast` 移除的人物仍被正文 `character` 元素引用；返回相关元素路径，需先明确删除或重新归属 |
| `invalid_element_type` | `type = scene`、`slugline` 或其他未支持枚举；错误提示说明场景标题应写 `interior_exterior` / `location_id` / `time_label` |

写入成功时可附带非阻塞 `warnings`：悬空 `character` 返回 `incomplete_dialogue_block`；`action` 文本整体像场景标题（`内/外景 … 日/夜`、`INT.`/`EXT.`）返回 `possible_scene_heading_in_content`，提示检查三个结构字段。形状启发式不能作为硬错误，因为“外景。山路，夜色压下来”也可能是作者有意写的动作描述。UI 与 AI 都可继续保存，模型收到 warning 后自行决定是否修正。

场景标题不是元素：它由 `interior_exterior`、`location_id` 和 `time_label` 派生，模型改标题要写这三个字段。这与 5.9 的“不重复写进正文元素”是同一条约束在 AI 侧的表述。

`Grep` 在元素行上做 SQL 匹配，命中返回元素路径 `screenplay/scenes/{scene_id}/elements/{element_id}` 与该元素文本，模型可以直接拿去改，不需要先定位场次再通读正文。

不需要双向编解码模块。元素到文本的**渲染**仍然需要（待审阅改动的整场正文预览、编辑器之外的只读展示），但它是单向的、纯展示的，放在 9.4。

### 9.4 写入路径与可审阅性

所有剧本写入都走 `ScreenplayService`，与 UI 共用校验、事务、重排和派生统计，工具层不直接调 DAO（对应 6.5 与风险表的“派生统计过期”）。在此之上分两类：

| 操作 | 落库方式 | 理由 |
| --- | --- | --- |
| 场次 `synopsis`；场次正文的任何改动（整场写、单元素写、单元素删除） | 立即落库并进入 working overlay；用户接受时确认当前值，退回时恢复写入前的值 | 与章节正文对齐：正文是最高风险写入，必须可审阅、可退回。删一句台词和改一句台词同样是正文改动 |
| AI 建场 | 一次 `Create` 写入场次结构、梗概和初始正文，创建后立即可见，只记录一条场次级 `create` working change；接受或在场内保存人工修改时确认保留，退回时软删除该场次及其关联数据 | 与现有 Chapter 一致，初始内容属于创建预览，不拆成额外文字 change；退回不能留下空场次，人工接管后也不能再删除用户成果 |
| 其余允许的结构操作：建季、编辑季、建集、改 `episode_number`、跨季移集、建节拍、用锚点移动场次或节拍、改 `beat_id`、改 `cast`，以及删除集、场次、节拍 | 直接落库并上报活动 | 与画布一致：这些结构变更没有文本 diff 语义，逐条冻结反而会与后续重排互相打架；季重排与删除是明确例外，只能由用户在季管理界面执行 |

分界线是**改的是不是正文**，但 AI 新建场次是一个例外：创建资源必须可退回，避免正文被拒绝后留下空壳。`Create screenplay/scenes` 的初始梗概与正文都收进唯一的 `create` 条目预览；只有创建完成后的再次写入，才产生普通 `synopsis` 或 `elements` change。其他场次结构不进审阅。删场次会连带软删它的元素行（6.4），这些元素不再单独产生待审阅条目；底层保留软删除数据，但第一期没有恢复界面。

接受与退回沿用 Chapter 当前机制，不新增“场次提议”聚合层或场次级原子接受 API。待审阅弹窗仍一次处理传入的全部 active changes；`create` 被退回时删除整场。初始内容只有这一条 create change，因此随建场自然一起接受或删除；之后对该场的独立修改仍按各自 change 进入现有机制。

AI 第一阶段保留直接删除集、场次和节拍的权限。`Remove` 调用成功即执行 6.4 的软删除与级联，不创建 working change，也不依赖 UI 二次确认；最后一集仍受 `last_episode_required` 保护。Season 不沿用这项权限：AI 删除季始终被拒绝，用户必须在桌面或移动端季管理界面查看影响范围并二次确认。其他用户侧删除也继续显示二次确认。

#### 审阅单位是场次，不是元素

正文的待审阅条目只有一种：`resourcePath = /screenplay/scenes/{scene_id}/elements`、`resourceType = screenplay_scenes`、`resourceId = scene_id`、`field = elements`。无论入口是整场还是单元素路径，stage 前都归一到这条场次正文路径；**没有元素级 resourceType。**

元素级路径（`Write .../elements/{element_id}`、`Edit .../text`、`Remove .../elements/{element_id}`）照常可用，它们省的是模型重发整场的 token；但落进 overlay 时一律折算成这一场、当前 AI session 的元素数组。会话身份在 Tool Manager 边界按 `_currentToolExecutionContext.sourceSessionId ?? sourceSessionId ?? _currentToolExecutionContext.sessionId ?? sessionId` 解析，最终仍为空时返回 `missing_session_context`；working overlay 不自行猜身份。合并键固定为 `resourcePath + source = ai + resolvedSessionId`：

- 当前 session 对该场已有 active 的 `elements` 条目 → 以当前已落库数组（也就是该条目的最新 `new_text`）继续修改，更新同一条的 `new_text`，最初的 `old_text` 不动，并立即应用新数组。
- 当前 session 没有，且该场不存在其他 session 的 active `elements` 条目 → 以写入前的当前元素数组为 `old_text`，改完的数组为 `new_text`，为当前 session 新建一条并立即应用新数组。
- 该场已被另一 session 持有 active `elements` 条目 → 返回 `working_change_conflict`，附场次路径并提示先处理已有待审阅正文；不合并两个 session、不隐式接受旧条目，也不写数据库。已有条目被接受、退回或人工保存接管后，另一 session 才能继续写这场。
- “检查其他 session → 查找/创建当前 session 条目 → 应用数组”必须在同一个内容库事务中完成；并发首次写入只能有一个成功，不能因先查后插的竞态产生两条 active 正文快照。

这么定的理由是 overlay 采用立即应用语义：同一 session 先整场 `Write` 后，数据库已经是新数组；再 `Edit` 其中一句时，必须合并进该 session 的同一条场次级 active change，保留最初的 `old_text`，只推进最新的 `new_text`。不同 session 若同时保留整场快照，两条改动会竞争同一份有序元素集合，单独退回任意一条都可能覆盖另一条；因此审阅身份按 session 保留，但同一场正文的 active 写入跨 session 串行化。这样接受得到当前 session 的最新数组，退回也能确定地恢复该 session 开始写入前的整场数组。

正文审阅不做逐行 diff，也不提供逐行勾选或部分退回。待审阅卡只把最新 `new_text` 渲染成整场正文预览，操作只有接受整场正文改动或用最初 `old_text` 退回整场正文；不能把一部分 AI 元素留下、另一部分恢复。`synopsis` 仍是普通文本字段，继续使用现有文本 diff 与按行退回。这样不需要把渲染后的行反向映射回结构化元素，也不会破坏人物提示、括注和对白之间的依赖关系。

#### 人工保存会接管待审阅正文

用户在同一场存在 active AI `elements`、`synopsis` 或场次 `create` change 时继续人工编辑并完成第一次 600ms 防抖自动保存，沿用现有 `commitManualSave()` 的先后顺序：先把该场全部 active AI change 标为 committed，再提交人工 change。人工修改以当前已应用的 AI 结果为基线，因此这次保存构成对先前 AI 文本以及 AI 所建场次本身的**隐式接受**；待审阅列表不再允许随后用最初的 `old_text` 退回正文，也不能再通过退回 `create` 删除整场。

这是数据安全边界，不只是历史记录排序。如果保留 AI 文本 change 为 active，之后退回会恢复整场最初快照，覆盖用户在其上继续做的人工修改；如果保留 AI 场次 `create` change 为 active，之后退回会直接删除包含人工成果的整场。第一期不做三方合并或逐元素冲突解决，也不为自动保存增加阻断式确认。场内任一成功的人工自动保存都表示用户已经接管该场，不要求修改的恰好是 AI 改过的字段；仅聚焦、移动光标或尚未成功落库不触发接受。

这不扩展成通用的人机并发协议。与小说正文一致，AI 工具写入不要求额外 revision，人工编辑器只保护尚未保存的本地草稿并串行化自己的保存；极端的同时落库按后完成者生效，不增加场次锁、CAS 或 `stale_scene`。

#### 正文如何进 overlay

`working_changes` 只有 `old_text` 与 `new_text` 两个字符串列，装不下结构化数组，也不该为剧本单独扩表。做法是**存结构、显示渲染**：

- `old_text` / `new_text` 存元素数组的 JSON。
- 待审阅列表渲染这一条时，只把最新 `new_text` **渲染**成可读的整场正文预览，不把 JSON 交给 diff 组件，也不展示旧稿与新稿的逐行差异。渲染是结构到文本的单向函数，不含解析，与 9.3 拒绝的“文本解析回元素”不是一回事。
- stage 时在同一事务中 decode `new_text`，调用 `ScreenplayService.replaceSceneElements()`，所以编辑器与后续工具读取立即看到新正文；接受只把 active change 标为 committed 并写入历史，不重复应用正文。
- 退回时在标记 rejected 前 decode 最初的 `old_text`，调用同一个 Service 恢复整场数组；恢复失败则条目标记 conflicted，不谎报已退回。

##### overlay JSON 的规范形状

历史回退与漂移检查会用 `_readCommittedFieldText` 回读当前数组，并与已提交条目的 `new_text` 逐字比对；同一场的连续 AI 写入也需要稳定地保存最初 `old_text` 与最新 `new_text`。因此这份 JSON 必须是**规范形式**，否则无关展示变化也会制造假漂移。写入 overlay 与回读当前值走同一个序列化函数，规则：

| 规则 | 说明 |
| --- | --- |
| 字段闭集 | 只含 `element_id`、`type`、`text`、`character_id`、`extension`。**不含** `name`、`character_deleted`、`sort_order`、`created_at`、`updated_at`、`deleted_at` |
| 字段顺序固定 | 按上面列出的顺序输出，不依赖 map 迭代顺序 |
| 空值省略 | 值为空串或 null 的字段整个省略，不输出 `"text": ""` |
| 顺序即数组下标 | `sort_order` 不进 JSON，元素在数组里的位置就是顺序 |
| 无缩进无换行 | 紧凑输出，避免格式差异造成的假不等 |

`name` 被排除是关键一条：它是按 `character_id` 实时解析的展示字段（9.3），人物改名就会变，留在 JSON 里等于让人物改名被误判为正文漂移。`updated_at` 同理——它每次写入都变，留着就无法稳定比较当前数组与历史 `new_text`。

渲染函数放 `lib/shared/models/screenplay_element_render.dart`，接收「人物 id ↔ 名称映射」的纯函数，UI 与 overlay 共用。它只有一个方向，没有反向解析入口。序列化函数与它同文件，也是纯函数。

working overlay 需要新增的分支：

| 位置 | 新增 |
| --- | --- |
| `_applyTextPatch` | `screenplay_scenes` / `elements` 分支：stage 传 `new_text`、退回传 `old_text`，decode 数组后调 `ScreenplayService.replaceSceneElements()`；`/ synopsis` 分支走普通文本字段。接受不调用此分支 |
| `_readCommittedFieldText` | 按上面的规范形状序列化当前元素行，用于已提交历史的回退与漂移判断；比较基准是历史条目的 `new_text` |
| `_deleteCreatedResource` | 退回新建场次时软删除 |
| 展示路径拼接 | 现在是 `'/${item.resourceType}/$resourceId'`（`working_overlay.dart:1566` 的 `_resourceScopeForItem` 等三处），对剧本会拼出 `/screenplay_scenes/xxx` 这种不存在的路径。该表已有 `resourcePath` 列，且在 `resourceId` 为空时就回落到它，因此改法是让剧本条目写对 `resourcePath` 并把这几处改成优先取非空 `resourcePath`，而不是按 `resourceType` 加一串拼接分支 |

前三处的 `default` 分支目前会落到 `getItemById` / `deleteItem`，必须显式加 case，不能靠兜底。

活动上报参照 `CanvasAiActivity` 增加 `ScreenplayAiActivity`（当前季、当前集、当前场、动作类型），编辑器据此跟随定位并显示“AI 正在处理这一场”。单季 UI 不渲染活动里的季信息。未打开剧本编辑器时 reporter 为空，静默跳过，不影响工具语义。

### 9.5 门禁与错误

门禁在每个工具进入路径分支前执行，`Read`、`Glob`、`Grep`、`Create`、`Write`、`Edit`、`Replace`、`Remove` 都覆盖。

判据是**目标作品**的 `content_kind`，不是会话的。不以 `works` 开头时目标作品就是当前作品，两者相同；以 `works` 开头时目标作品是该 `work_id` 指向的作品（9.9）。这一条必须写清楚，否则剧本会话读原著的 `/works/{work_id}/chapters` 会被自己的会话类型误杀。

| 场景 | 结果 |
| --- | --- |
| 目标作品 `content_kind = novel`，路径命中 `screenplay*` | `content_kind_mismatch`，说明该作品是小说，章节走 `chapters` |
| 目标作品 `content_kind = screenplay`，路径命中 `chapters`、`volumes`、`outlines`、`foreshadowing` | `content_kind_mismatch`，并按路径给出替代：章节与大纲改用 `screenplay/scenes` |
| 任一工作区访问结构中立集合 | 放行，见 9.7 |
| `/works/` 路径命中写入类工具 | `cross_work_write_denied`，见 9.9 |
| 读取其他多季剧本的 Episode listing 但省略 `season_id` | `season_id_required`；提示先读目标作品的 `screenplay/seasons`，不借用当前作品的 Current Season |
| AI 调用 `Remove screenplay/seasons/{season_id}` | `season_delete_requires_user_action`；提示前往季管理界面，不返回可供 AI 绕过的确认参数 |
| AI 写 `season_number` 或尝试提交季顺序 | `read_only_field` 或 `unsupported_operation`；提示季重排只能在季管理界面完成 |
| AI 给场次、节拍或元素提交 `sort_order` | `unknown_field`；提示改用 `episode_number`、`act_number`、`before_*_id`、`after_*_id` 或元素数组顺序表达业务位置 |
| 场次同时传 `before_scene_id` / `after_scene_id`，或锚点等于自身 | `mutually_exclusive_fields` / `invalid_scene_anchor`；数据不变 |
| 节拍同时传两个锚点、或对已有节拍同时传锚点与 `act_number`；锚点等于自身或属于另一集 | `mutually_exclusive_fields` / `invalid_beat_anchor` / `beat_anchor_outside_episode`；数据不变 |
| 另一 AI session 已持有同场 active 正文条目 | `working_change_conflict`；提示先接受或退回已有待审阅正文，不合并快照或覆盖现值 |
| AI 剧本正文写入无法解析 source/current session ID | `missing_session_context`；不创建无归属的 active 正文条目 |

当前作品根目录的 listing 按**当前作品**的类型过滤集合，`Read /works/{work_id}` 按**该作品**的类型过滤（这是工具**返回值**，不是 schema，可以随运行时事实变化）。`Glob` 与 `Grep` 通过根 listing 递归发现路径，因此自动继承同一份过滤，不需要各自再写一遍。

错误消息沿用画布的结构化英文（`error_code` + `message` + `hint`），不进 i18n；用户可见的待审阅改动标签需要新增 locale key。

### 9.6 Prompt 装配

装配入口按 `contentKind` 分支。小说分支除统一新增的只读 `/works/{work_id}/…` path schema 行外，输出必须与实施前逐字一致，用 golden 测试锁住。不新增跨作品 prompt 片段；`source_novel_id` 不影响 prompt 装配。

| 位置 | 剧本工作区的变化 |
| --- | --- |
| `pathSchemaBlock()` | 增加 `kind` 参数并透传给 `pathSchema()`：小说渲染时路径清单不含剧本集合，剧本渲染时不含章节、卷、大纲、伏笔；两侧都保留只读 `/works/{work_id}/…`。字段字典那半边不需要动，`hidden: true` 已经挡住（9.1）。调用点四处：`ChatPromptUseCase`、`ModePromptUseCase`、`spawn_agent_handler`、`chat_turn_runner` |
| `assets/prompts/agent/orchestrator.md` | 用 `{{#screenplay_workspace}}` / `{{^screenplay_workspace}}` 包住「大纲写作」「正文写作」「工作规划」「连续性核对」「审查闭环」，补一份剧本分支：持久化结构是季 → 集 → 节拍 → 场次，正文写场次；常规工作从当前季的集开始，只有季管理或显式跨季任务才谈 Season；新增 Season 必须有当前用户任务的明确多季意图，超出规划或 AI 的结构判断只能触发建议，不能触发 Create；连续性核对可读取通用 `story_state`，不使用章节路径 |
| `assets/prompts/fragments/chapter_reading_boundary.md` | 不改。剧本分支引用新片段 `scene_reading_boundary.md`：按当前季、当前集读场次 listing，只读需要的场次元素，不整集拉正文，不遍历所有集；单季时不要求先读取季 |
| 新增 `assets/prompts/fragments/screenplay_craft.md` | 剧本手艺：只写镜头看得见、话筒听得见的东西；不写内心活动与背景说明；一场一个目的，进晚出早；台词承担潜台词而不是交代信息；篇幅与时长的直觉 |
| `assets/prompts/fragments/writing_craft.md` | 不改，剧本工作区继续使用：入场即画面、对话即交锋、情绪靠行为、进晚出早、声音不可互换在剧本同样成立 |
| `assets/prompts/fragments/prose_quality_baseline.md` | 不改。剧本分支在 `screenplay_craft.md` 里补一句：重复密度的计数单位从「每章」改为「每场」 |
| AgentSkill 索引 | 剧本工作区隐藏「创作向导」，显示「剧本写作指南」；小说工作区隐藏「剧本写作指南」。画布、关系图谱、图像、规则与技能管理类两侧都显示 |
| SubAgent 索引 | 剧本工作区只保留结构中立的内置 SubAgent 与用户自建 SubAgent，见 9.7 |
| environment 块 | 剧本工作区不渲染「章节」行，定位信息来自 `active_workspace_target`。多季作品显示回合冻结的当前季、当前集与当前场；单季作品只显示当前集与当前场，不出现 Season 术语 |
| `setup_phase` 门控 | 剧本工作区不启用：创作向导的引导内容与 references 按小说设计 |

不改既有 SubAgent 的 prompt asset。它们是用户可编辑的库内记录，种子 `prompt` 为空时才回落到 asset；已经改过自己副本的用户拿不到 asset 里新增的剧本分支，靠改 asset 兜底会得到「一半用户有、一半用户没有」的行为。

### 9.7 现有 AI 能力在剧本工作区的开关

| 能力 | 剧本工作区 | 依据 |
| --- | --- | --- |
| Chat 主控与通用工具 | 开 | 场景指引换成剧本分支 |
| `screenplay` 路径 | 开，但 AI 重排、删除 Season 关闭 | 季顺序是低频全局结构，删除级联范围大且第一期无恢复入口；其余边界见 9.2 与 9.4 |
| 跨作品只读（`/works/{work_id}/…`） | 开 | 改编需要读原著，见 9.9；小说工作区同样可用 |
| 跨作品写入 | 关 | 审阅入口、活动上报与事务边界都不支持，见 9.9 |
| `characters`、`locations`、`lore`、`materials`、`skills`、`items`、`factions`、`creatures` | 开 | 结构中立，剧本同样需要 |
| `profile` | 开 | 标题、简介、分类、标签、状态与作品类型无关 |
| `story_state` | 开 | 作品级累积叙事状态，不按作品类型关闭 |
| `chapters`、`volumes`、`outlines`、`foreshadowing` | 关 | 章节结构专属；剧本的大纲是场次视图，不是独立资源 |
| `canvas` | 开 | 与作品类型无关 |
| `relations` 与 GraphSearch | 开 | 证据字段改用 `scene_id`，见 5.11 |
| 圆桌、小剧场、角色扮演、内心独白 | 开 | 只读人物与设定，工具集是 Read/Glob/Grep/WebSearch/WebFetch/GraphSearch，受同一套门禁约束 |
| SubAgent：资料收集、用户自建 | 开 | 结构中立 |
| SubAgent：正文写手、内容核验、文风润色、编年史者 | 关 | prompt 按章节设计，且用户副本无法通过改 asset 覆盖；剧本正文由主控亲自写 |
| 写入后的审查闭环 | 关（第一期） | 依赖审查类 SubAgent，见上一行；主控写入后自查并如实汇报，不假称已审查 |
| 快捷动作（扩写、改写、摘要） | 部分 | 只对场次梗概等纯文本字段开放；正文选段不接入，行语义会被破坏 |
| 章节嵌入检索、发布后编年史 | 关 | 入口都在小说编辑器，剧本编辑器不接线，不需要额外拦截 |
| 记忆、Dreaming、封面工作台 | 开 | 不依赖章节结构；工具调用同样受门禁约束 |

关闭项一律靠门禁与索引过滤实现，不在剧本界面上放一个点了会报错的入口。

### 9.8 剧本写作指南（Bundled AgentSkill）

新增第九个 Bundled Control Skill，`callName` 为「剧本写作指南」，asset 放 `assets/bundled_skills/screenplay-writing-guide.md`，`agent_scopes: [chat]`，无对应 Run 命令。

`screenplay` 与 `works` 在 `_collectionSchemas` 里都保持 `hidden: true`，**字段字典完全不进常驻 system prompt**，字段含义、必填标记、只读标记与枚举取值全部由这份技能按需载入 —— 与画布、关系图谱同一条 token 预算取舍。路径模板清单是另一层，由 `pathSchemaBlock()` 的工作区过滤处理，不归 `hidden` 管，三层的分工见 9.1。

技能内容：

- 路径速查表：读、新增和编辑季，读当前季的集、写 `episode_number` 做季内移集、显式读其他季的集、跨季移集、读场次 listing、读单场正文、建场、改梗概、用 `before_scene_id` / `after_scene_id` 排场、用 `before_beat_id` / `after_beat_id` 排节拍、整场写正文、改单个元素、改出场人物、打开某一场。说明普通路径保持扁平，当前季操作省略 `season_id`，已有 `episode_id` 时不再补季参数；只有移动已有集时才给单集写目标 `season_id`，与 `episode_number` 同时提供可指定目标季位置，省略集号则追加末尾。场次、节拍和元素都不接受 `sort_order`。
- 跨作品剧本范围：其他作品没有本会话的 Current Season；目标只有一季时可省略 `season_id`，目标有多季时先读它的 Seasons listing 再指定，不能套用当前作品的季 ID，也不能猜第一季或最后一季。
- Season 管理边界：AI 可新增、改名和修改规划集数，但不能重排或删除 Season；相关请求应明确告知用户需在季管理界面完成，不要构造整表顺序，也不要用 AskUser 取得口头确认后再次调用 Remove。
- 新增季的授权边界：只有当前用户任务明确要求新增季、下一季或多季规划时才调用 Create。超出规划集数不是自动分季条件；AI 自己判断“故事太长”时只能建议，不能先创建再汇报。
- 字段清单与取值：`interior_exterior` 可省略，非空时只接受 `interior` / `exterior`；`stage`、`act_number` 的合法值与含义，`scene_number` / `beat_number` 只读；场次和节拍用 `before_*_id` / `after_*_id` 或目标父级表达移动，`sort_order` 不存在于工具契约；内外景转换必须拆场。
- 正文元素数组的形状与七类元素的字段配对、`character` 只接受 `character_id`、角色必须先建档（9.3），含一次完整的写场示例与一次单元素改台词示例。
- 整场 `Write` 与单元素 `Write` 的选择：新写一场用整场，改一两句用元素路径，不要为改一句重发整场。两者产生的待审阅条目都是场次级的那一条（9.4），选哪个只影响 token，不影响用户看到什么。
- 排场顺序：先在当前季定集与节拍，再排场次骨架与梗概，最后逐场写正文；不要一上来就写正文。只有作品已有多季或用户明确要求新增、切换、比较季时才引入 Season 概念。
- 改编流程（有 `source_novel_id` 时）：先用 `Read /works` 拿到原著稳定的 `work_id`，再读原著大纲与人物，把要用的人物、地点在**当前剧本**里建档，然后归并事件成集与节拍，最后排场写正文。原著的资源 ID 不能直接用在剧本里（9.9）。
- 反模式：单季常规任务先读季列表或反复提“第 1 季”、把所有资源嵌套进 Season 路径、把场景标题写进正文、用动作行代替台词、一场塞多个地点、给不存在或已删除的角色写新台词、批量拉取整集正文、把原著的 `character_id` 写进剧本场次、用标题代替 `works` listing 返回的稳定 `work_id`。

### 9.9 跨作品路径

改编场景需要 AI 读原著小说的章节、大纲与设定，而原著在**另一个内容库文件**里。做法是给跨作品路径一个显式前缀 `/works/`。

| 写法 | 解析目标 |
| --- | --- |
| 当前作品路径：`chapters/{chapter_id}`、`screenplay/scenes/{scene_id}` | 当前作品 |
| 跨作品路径：`/works/{work_id}/chapters/{chapter_id}` | 指定有效本地作品 |

#### 绝对路径与相对路径

模型可见契约由前导斜杠区分：`chapters/{chapter_id}`、`screenplay/scenes/{scene_id}` 等相对路径从当前作品解析；只有 `/works/{work_id}/…` 是跨作品绝对路径。文档、tool description、path schema、prompt 片段与「剧本写作指南」统一按此书写。路径模板的占位符遵循 9.2 的资源专名规则，不再出现通用 `{id}`。

解析层继续兼容已有的 `/chapters` 等当前作品输入，以及缺少前导斜杠的 `works/…` 输入；这只是存量调用兼容，不进入任何模型可见说明，也不改变上面的公开语义。内部仍可在 `_normalizePath` 去掉首尾斜杠后按首段 `works` 分流：

```text
segments[0] == 'works'
  len == 1   → 本地作品 listing
  len == 2   → workId = segments[1]，目标作品的根 listing
  len >= 3   → workId = segments[1]，用 segments.sublist(2) 重走原有解析逻辑
segments[0] != 'works'                     → 目标 = 当前作品，解析逻辑一个字节不变
```

这条判据是确定式的，没有回退分支，也不需要论证「集合名与作品标识不会碰撞」：

- `works` 不在现有 `_collectionSchemas` 与 `_rootCollections` 里，新增它不与任何存量集合冲突。
- 存量当前作品路径没有一条以 `works` 开头，所以解析结果与实施前一致，**零迁移**。用户自建的 SubAgent、AgentSkill里硬编码的旧输入不受影响——这些是用户可编辑的库内记录，没法靠改 asset 迁移，与 9.6 不改既有 SubAgent prompt 是同一条理由。
- 集合名拼错照旧报 `unknown_collection`。`charactors/ch_123` 首段不是 `works`，不会被误判成跨作品然后报「作品不可达」，把模型引向错误的修法。

`ParsedPath` 增加一个 `workId`（`String?`，null 表示当前作品）。剥掉 `/works/{work_id}` 之后，`collection`、内部通用 `id` 槽位、`namePath`、`field`、`queryParameters` 的切分完全复用现有逻辑，所以下游 handler 不需要重复解析，只需要在拿内容库时选择当前库或跨作品 lease。内部字段叫 `id` 不会暴露到 path schema；对模型展示的模板始终是 `chapter_id`、`scene_id` 等资源专名。

#### 只接受 `work_id`

`/works/` 之后只接受主库 `novels.id`，对 AI 的领域字段名统一叫 `work_id`。`work_id` 是稳定地址，作品标题改名、包含 `/` 或 `?` 都不影响路径。内部仍可沿用 `Novel.id` 与 `source_novel_id` 的兼容命名，不需要为了路径契约重命名数据库表列。

resolver 只做精确 ID 校验：等于当前作品 ID 时使用当前内容库；命中主库任一未删除、非草稿且有 `content_database_path` 的作品时获取该作品 lease；未命中或目标不可打开时返回 `work_not_found`。标题只用于展示，不参与匹配，也不新增字符限制或唯一索引。

#### 发现入口与单作品范围

`works` 是一个新的只读集合：

| 路径 | 用途 |
| --- | --- |
| `/works` | 有效本地作品 listing：`work_id`、`title`、`content_kind`、与当前作品的关系；不含当前作品自己；当前作品为剧本且命中 `source_novel_id` 时，条目标记为原作小说 |
| `/works/{work_id}` | 该作品的根目录 listing，按它自己的 `content_kind` 过滤集合 |

跨作品剧本没有本会话的 Current Season。读取 `/works/{work_id}/screenplay/episodes` 时按**目标是否为当前作品**和目标有效季数解析：

- `work_id` 恰好是当前作品，或路径本来就没有 `/works` 前缀：省略 `season_id` 时使用本回合冻结的 Current Season。
- 目标是其他剧本且只有一个有效 Season：省略 `season_id` 时自动使用这唯一一季，不要求为了单季引用先读季列表。
- 目标是其他剧本且有多个有效 Season：省略 `season_id` 返回 `season_id_required`，附带读取 `/works/{work_id}/screenplay/seasons` 的 hint；模型取得目标季 ID 后再显式查询。
- 绝不把当前作品的 `currentSeasonId` 填进其他作品，也不猜目标的第一季、最后一季或最近更新季。Beat 与 Scene 路径已有 `episode_id` 或稳定资源 ID，不需要额外季作用域。

这项判断是 handler 对目标数据的运行时解析，input schema 仍然只有同一个可选 `season_id`，不会按季数动态变化。

读取权限不由 `source_novel_id` 限制，任一有效本地作品都可显式读取。性能边界放在**单次调用必须明确一个 `work_id`**：`Read /works` 只返回主库 metadata，不打开内容库；`Read /works/{work_id}/…`、`Glob`、`Grep` 与 GraphSearch 每次只解析一个作品。`Glob /works/**`、从 `/works` 根递归的 Grep 等可能遍历多库的调用返回 `work_id_required`，提示先 `Read /works` 再选择一个作品。这样不限制可访问作品，也不会一次把全部 SQLite 内容库打开并常驻。

跨作品 resolver 不直接返回裸 `NovelContentService`，而是返回带所有权的 `CrossWorkLease { workId, service, release }`。`release()` 是同步、幂等的所有权归还入口：resolver 的实现从 `NovelContentDatabase(filePath)` 缓存工厂取得数据库，归还时触发 `close()`；当前 `close()` 会在第一次 `await` 前同步递减 `referenceCount`，真正关闭最后一个 executor 的异步尾部由 lease 捕获并记录错误，不把未等待的异常泄漏到 Zone。

`AiToolManager` 按 `work_id` 缓存 acquisition future 和 lease，同一会话并发调用共享同一份 acquisition 与 lease，只增加一次数据库 `referenceCount`。Manager 增加幂等的同步 `dispose()`：先禁止新 acquisition，再释放已完成且没有在途调用的 lease；尚在获取的 future 完成后立即释放，仍在使用的 lease 由该次工具调用的 `finally` 在在途计数归零时释放。获取失败从缓存移除且不调用 `release()`；已经取得但还没交给缓存所有权的异常路径必须在 `try/finally` 中释放。`AiClient.dispose()` 在把 `_toolManager` 置空前调用它，因此不需要把现有同步 dispose 契约扩散成全局异步 API。

#### 第一期只读

`/works/` 路径只支持 `Read`、`Glob`、`Grep`。`Create`、`Write`、`Edit`、`Replace`、`Remove` 命中 `/works/` 一律返回 `cross_work_write_denied`。

注意 `isReadOnly` 挡不住 `Create`：`tools.dart:716` 的注释写明它「只约束 Write/Edit，不影响 createTool」。因此 `works` 集合除了声明 `isReadOnly: true`，还要在 `Create` 的路径分支里单独拒绝，`Remove` 同理。光靠集合标志会漏。

GraphSearch 没有 path 参数，因此用一个可选 `work_id` 支持同样的目标选择：

- 省略 `work_id`：沿用现有行为，在当前作品的关系图中搜索。
- 传当前作品的 `work_id`：等价于省略，不打开新内容库。
- 传任一有效本地作品的 `work_id`：通过同一 `CrossWorkLease` 在目标作品中只读搜索。
- 传未知、已删除、草稿或没有内容库的 `work_id`：返回 `work_not_found`。
- 返回值顶层增加 `work_id`，资源 path 按目标作品决定是否带 `/works/{work_id}` 前缀。

这是一次静态、加法式 input schema 变更：只给现有 GraphSearch schema 增加 optional `work_id`，现有必填 `type` 与 `id` 暂不重命名，避免破坏用户已有 AgentSkill；`id` 在这里表示通用的起始实体 ID，不是 path schema 的 `{id}` 占位符。两种工作区看到完全相同的 GraphSearch 定义。

只读不是保守，是四条具体的缺口：

1. 待审阅改动列表绑当前编辑器，写到一部没打开的作品，改动没有审阅入口，用户看不见。
2. `ScreenplayAiActivity` / `CanvasAiActivity` 的 reporter 同样绑当前编辑器，跨作品写入没有跟随定位。
3. 两个内容库不能组成一个 SQLite 事务，跨作品的多步写入只能补偿，失败会留半途状态。
4. 模型写错一个作品名就写进别的作品。软删除能恢复，但用户不会知道发生过。

改编的写入方向本来就是“从源读、往当前写”，只读覆盖全部需求。将来要放开跨作品写，前置条件是：待审阅列表按作品分组并能跳转到目标作品、活动上报支持无宿主降级、以及一套跨库补偿事务——三样齐了再放，不要单点放开。

#### 跨库 ID 不能复用

跨作品读回来的 `character_id`、`chapter_id`、`location_id` 属于**源作品的内容库**，直接写进当前剧本会指向不存在的记录。边界如下：

- 跨作品响应顶层与资源条目都带 `work_id`，`_links` 与 `path` 一律渲成带 `/works/{work_id}` 前缀的完整路径，模型看得见它不属于当前作品。
- 当前作品的写入校验只查询当前内容库；引用 ID 不存在或已失效时返回该资源现有的无效引用错误，例如人物使用 `invalid_character_ref`，并提示跨作品 ID 不能直接使用、应先在当前作品 `Create characters` 建档。系统不为定位 ID 来源而扫描其他作品，也不维护会话级 ID 来源表。

这条对改编流程是高频路径：原著人物必须在剧本内容库里重新建档，剧本正文的 `character_id` 只能指向剧本自己的 `character_profiles`（5.9）。「剧本写作指南」要把这一步写在排场之前。

## 10. Migration

### 10.1 版本策略

当前分支主库 `schemaVersion = 32`，内容库 `schemaVersion = 16`。最近正式版本 `v0.9.9` 分别是 30 和 13，因此当前 32 与 16 仍属于未发布 migration。本功能实施时：

- 主库保持版本 32，把 `content_kind`、`source_novel_id` 与索引 `novels_by_source_novel_id` 合入现有 `migrateToV32()`。
- 内容库保持版本 16，把七张表（含 `screenplay_seasons` 与 `screenplays.format`）、`entity_relations.scene_id` 和全部索引合入现有 `migrateToV16()`。
- `onCreate` 的当前 schema、migration 和 Dart 数据模型必须同时更新。
- 不新增运行时幂等补列、启动 fallback 或额外 schema version。

如果实现开始前 32 或 16 已随新版本发布，则停止使用本节的合并策略，分别新增主库 33 和内容库 17，并补正式升级路径。

已实测当前分支：`app_database.dart:1539` 为 32，`novel_content_database.dart:1698` 为 16，与本节假设一致。实施开始前需再次核对正式 tag。

### 10.2 旧数据

- 从主库 30 升级时，所有已有 `novels.content_kind` 回填为 `novel`，`source_novel_id` 保持 NULL。
- 从内容库 13 升级时，创建七张空表和索引，给 `entity_relations` 加一列可空 `scene_id`，不修改章节、人物、大纲或既有关系数据。
- 按 `.agents/rules/db-migration.md`：新增列后必须搜索这两张表的全部历史 `TableMigration` 与手写表重建，逐个核对源版本实际拥有的列。`novels` 是老表且经历过多次重建，`entity_relations` 同理，裸 `TableMigration(novels)` 会把新列带进历史版本的 copy SQL。
- migration 后用 Typed DAO 读取一部旧小说，确认数据类型和默认值正确。
- 当前开发数据库若已经处于 32 或 16，migration 不会再次执行。实现阶段用 SQLite skill 对明确的开发数据库手动增加列、创建表和索引，再查询 `PRAGMA user_version`、`PRAGMA table_info` 与 `PRAGMA index_list` 验证。不能把本地兼容逻辑留在应用运行时。

### 10.3 回滚

本次 schema 增加主库两列一索引、内容库一列、七张表和索引。代码回滚时旧小说仍可读取，新增表会留在数据库中但不被旧代码使用。已经产生剧本数据后不能通过 drop table 回滚，也不能自动删除内容库文件；需要重新启用支持剧本的版本才能继续编辑。

## 11. 改动清单

### 主库与领域模型

#### NEW: `lib/shared/models/content_kind.dart`

- 定义 `novel`、`screenplay` 常量、校验和产品标签映射。
- 不定义 `prose` 别名，避免一份数据出现两种值。

#### NEW: `lib/shared/models/screenplay.dart`

- 定义项目、季、集、场次、节拍、场次人物关系和各状态枚举，以及格式常量（`asian`）。
- 定义概览、大纲、节拍统计和出场矩阵等只读模型。

#### NEW: `lib/shared/models/screenplay_element.dart`

- 定义正文元素的类型化模型与七类元素的字段配对约束；`character` 元素只携带 `character_id` 与可选 `extension`，不缓存人物显示名。
- 不定义 schema 版本，也没有未知元素保留策略——元素形状由数据库列与枚举约束，不存在解析失败（5.9）。

#### NEW: `lib/shared/models/screenplay_element_render.dart`

- 元素列表到可读剧本文本的**单向**渲染，纯函数，输入包含人物 id ↔ 名称映射。
- 成稿渲染跳过 `note`；编辑态与待审阅整场预览显示 `note`，让作者能审阅当前提议。**不提供反向解析入口**，新增反向函数等于把 9.3 拒绝的文本投影方案偷偷放回来。
- 同文件提供 overlay 用的规范序列化：字段闭集、固定顺序、空值省略、紧凑输出（9.4）。写入 overlay 与回读 committed 必须调同一个函数，否则漂移判断会假报。

#### `lib/shared/database/app_database.dart`

- 给 `Novels` 增加 `contentKind` 与可空 `sourceNovelId`。

#### `lib/shared/database/app_database_migrations.dart`

- 把主库两列与 `novels_by_source_novel_id` 合入未发布的 v32，旧行 `content_kind` 回填 `novel`。
- 核对 `novels` 的全部历史 `TableMigration` 与手写重建，按 10.2 处理。

#### `lib/shared/database/daos/novel_dao.dart`

- 创建作品时写入 `contentKind` 与可选 `sourceNovelId`，旧调用默认 `novel` / NULL。
- 提供路由需要的类型化读取，不允许随意切换已有作品类型。
- 提供按 `work_id` 读取任一有效本地作品及其 `contentDatabasePath` 的查询，供跨作品 resolver 使用（9.9）；`sourceNovelId` 另用于剧本原作标记，并校验引用方是剧本、目标是有效小说。
- 提供创建专用的 finalize 写入，在同一主库事务中设置 `contentDatabasePath` 并把临时 `draft = true` 恢复为调用方的 `requestedDraft`；不能复用“加入书架”这一用户动作去隐式改变原始草稿意图。

### 内容库、DAO 与服务

#### `lib/shared/database/novel_content_database.dart`

- 注册七张剧本表与 `ScreenplayDao`。
- 给 `EntityRelations` 增加可空 `sceneId`。
- 为时间戳、软删除和逻辑父级采用现有内容库约定。

#### `lib/shared/database/novel_content_database_migrations.dart`

- 把建表、`entity_relations.scene_id` 与索引合入未发布的 v16。
- `onCreate` 与升级路径使用同一组索引创建方法。

#### `lib/shared/database/type_converters.dart`

- 不改。正文不再有 JSON 列，无需 `ScreenplayElementListConverter`。

#### NEW: `lib/shared/database/novel_content_daos/screenplay_dao.dart`

- 提供根记录、季、集、场次、节拍、人物关联和正文元素的 watch 与写入方法。
- 元素写入提供按 `scene_id` 的 reconcile 方法（对齐 / 更新 / 插入 / 软删 / 重排），不提供“清空后批量插入”。
- 提供不读取元素行的概览聚合、大纲、节拍统计和出场矩阵查询。
- 提供 `watchEpisodeScriptPreview(episodeId)`：一次订阅当前集全部有效场次及元素的只读渲染 projection，按场次和元素内部顺序分组；任一场次被人工或 AI 写入后自动刷新，切集后由 Provider 释放。它不创建逐场 stream 或手写缓存（7.3）。

#### NEW: `lib/shared/services/screenplay_service.dart`

- 作为 Provider 管理的无状态单例，负责校验、季与集的连续编号、事务、重排、软删除、派生统计和总字数同步。
- 跨季移集校验同剧本目标季与源季最少一集；省略目标 `episode_number` 时追加末尾，同时提供时按目标季移动前数量校验并插入指定位置。移动、两边重排和同次单集字段更新在一个事务完成，不复制记录。
- 场次与节拍顺序只公开 6.3 的锚点式业务方法；Service 公共参数和返回模型不出现 `sortOrder`。DAO 在事务内部维护存储顺序，读取模型只返回派生 `sceneNumber` / `beatNumber`。
- 硬校验元素类型与字段配对、`dialogue`/`parenthetical` 的连续角色归属、`character_id` 指向同内容库有效人物档案、非空 `location_id` 指向有效地点；悬空 `character` 与疑似场景标题动作行只返回 warnings。
- 校验 `character_id` 指向同内容库的有效人物；不提供名称或别名到 ID 的写入解析（9.3）。
- UI 与 AI 工具共用同一批写入方法，不为 AI 另开一条落库路径。
- 每个数据库写入点按项目规则记录 `[DB]` 错误日志。

#### NEW: `lib/shared/services/screenplay_metrics.dart`

- 从元素列表计算 `page_eighths`、估算时长、台词数与字数的纯函数。UI 预览与 Service 落库调同一份，见 5.10。

#### `lib/shared/services/novel_content.dart`

- 给现有 `deleteEntityWithRelations()` 增加默认空的事务内 `validateBeforeDelete` 回调，在删除关系与实体行之前执行；存量调用不传时行为不变。`NovelContentService.deleteCharacterProfile()` 通过该回调查询场次人物关联与正文 `character_id`，命中时返回 `entity_in_use` 与使用处，否则保持现有关系清理和人物删除语义（6.4）。检查与删除由同一个现有事务包住，不能在调用 helper 前先查一次。
- 小说内容库没有有效场次人物引用，删除行为与实施前一致。

#### `lib/shared/services/maps_service.dart`

- 地点删除的真实入口是 `LocationsService.deleteLocation()`。在现有子地点、`map_locations`、关系与地点行清理前增加有效 `screenplay_scenes.location_id` 查询，并纳入同一内容库事务；命中时返回 `entity_in_use` 与场次使用处，否则保持当前 `cascadeOrphans`、地图和关系清理语义。

#### `lib/shared/services/entity_relations_service.dart`

- `queryRelations()`、`createRelation()`、`updateRelation()` 增加可选 `sceneId`，Service 层统一校验 `chapterId` 与 `sceneId` 至多一个非空；这条约束覆盖 UI、AI 与其他直接调用方，不能只写在工具 handler。
- 新增 `getRelationsForSceneEvidence(sceneId)` 与 `clearSceneReferences(sceneId)`；后者与当前 `clearChapterReferences()` 对称，删除场次、集或季时只清空证据列，不删除关系。
- 非空 `sceneId` 必须指向同内容库的有效场次，否则返回 `invalid_scene_ref`；两种证据同时传入返回 `mutually_exclusive_fields`，整次不写入。

#### `lib/shared/services/novel_actions.dart`

- 扩展创建参数（含 `contentKind`、`sourceNovelId`），并按 `contentKind` 初始化小说或剧本内容库。
- 按 6.1 处理跨数据库创建失败：捕获 `requestedDraft`，内容库句柄在 `finally` 中恰好关闭一次，随后软删除已创建的主库记录；保留并重抛原始异常，补偿异常只追加日志，不删除内容库文件或封面。为内容库打开、seed、剧本根事务、主库 finalize 四个失败边界分别测试。

#### NEW: `lib/shared/providers/screenplay_providers.dart`

- 暴露 `ScreenplayService` 和按内容库参数化的 StreamProvider。
- 保持 Stream 读与 Service 写，不建立第二套缓存状态。

#### NEW: `lib/shared/models/screenplay_workspace_state.dart`、`lib/shared/providers/screenplay_workspace_state_provider.dart`

- 定义版本化的当前 section、`season_id`、`episode_id` 与 `scene_id` 快照，按作品写入主库 `app_states` 的 `screenplay_workspace:{work_id}` key；只保存本机 UI 状态，不给 `screenplays` 增列。
- 桌面与移动端共用同一 Provider；恢复后按有效父子层级逐级 reconcile，失效季回退第一季，失效集或场次只在修复后的父级内回退。
- 删除当前季后由调用方传入原位置，优先选占据该位置的下一季，没有则选前一季；切换和关闭前等待状态写链 flush，沿用 `NovelWorkspaceStateController` 的串行持久化模式。

### 创建与路由

#### `lib/shared/models/novel_form_fields.dart`

- 增加只在新建时使用的 `contentKind` 与 `sourceNovelId` 表单字段；规划集数与改编来源均为选填，规划集数写入自动创建的第 1 季。

#### `lib/desktop/widgets/novel_form_dialog.dart`

- 新建态显示作品类型，选择剧本后呈现规划集数与“改编自”作品选择器，不询问季数或显示 Season。
- 编辑态不允许修改作品类型；改编来源可在编辑态修改，只影响来源标记与改编流程提示，不影响跨作品读取权限或已有数据。

#### `lib/mobile/pages/novel_create_page.dart`

- 与桌面端使用相同字段和校验，规划集数与改编来源选填，不在创建流程中增加季步骤。

#### NEW: `lib/desktop/pages/workspace_editor_page.dart`

- 根据 `contentKind` 路由到小说或剧本编辑器，保留现有入口参数。

#### NEW: `lib/mobile/pages/workspace_editor_page.dart`

- 根据 `contentKind` 路由到移动端小说或剧本编辑器。

#### 现有编辑器入口

- 书架、最近作品、首页卡片、任务入口、创建完成跳转和系统托盘统一改用对应平台的 `WorkspaceEditorPage`。
- 快速开书和导入创建继续默认 `contentKind = novel`。

### 桌面端

#### NEW: `lib/desktop/features/screenplay/`

- `editor_page.dart`：剧本编辑器壳和区域组合。
- `context_panel.dart`：单季时显示实际集列表与当前场次列表；多季时增加当前季切换入口。
- `season_manager.dart`：新增第二季后才进入的季管理区域，负责改名、规划集数、重排和删除。
- `episode_move_sheet.dart`：多季时从集菜单选择目标季，源季唯一集禁用；移动当前集后更新工作区选择。
- `overview.dart`：项目概览和 SQL 聚合统计。
- `script.dart`：按场次连续显示与编辑正文，人物名按 `character_id` 实时解析。
- `outline.dart`：场次大纲与重排。
- `beats.dart`：按幕显示节拍及派生场次。
- `scenes.dart`：场次板和场次表。
- `characters.dart`：人物档案、出场矩阵和人物关系。

每个可见区域独立持有局部视图状态。宿主页只组合区域，不传递超过五个零散状态参数。

### 移动端

#### NEW: `lib/mobile/features/screenplay/`

- `editor_page.dart`：移动端剧本首页和分区导航。
- `episode_picker_sheet.dart`：当前季的实际集选择与新增；单季时在底部提供低频“新增一季”。
- `season_picker_sheet.dart`、`season_manage_page.dart`：多季时的切换与全屏管理；删回一季后入口隐藏。
- `episode_move_sheet.dart`：多季时选择目标季并移动当前或指定集，复用桌面端同一 Service 语义。
- `overview.dart`：响应式概览。
- `script_page.dart`：场次列表与单场全屏正文编辑。
- `outline_page.dart`：大纲列表和场次入口。
- `beats_page.dart`：手机纵向、平板多栏的节拍页。
- `scenes_page.dart`：移动场次卡列表。
- `characters_page.dart`：场次人物与人物出场列表，平板可显示矩阵。

### AI 工具与 Prompt

#### NEW: `lib/shared/services/ai/tools_screenplay.dart`

- `part of 'tools.dart'`：`screenplay` 的路径谓词、工作区门禁与 Read/Create/Write/Edit/Remove handler。
- 结构操作直接调 `ScreenplayService`。AI `Create screenplay/scenes` 一次接收结构字段、梗概与初始元素数组，成功后只追加一条含整场预览的场次级 `create` working change；不得再为同一次创建里的 `elements` 与 `synopsis` 分别 stage。创建完成后的正文与梗概修改才由 working overlay 立即应用并保留可退回记录。
- 场次与节拍 handler 只接收 `episode_id` / `act_number` 及 `before_*_id` / `after_*_id` 业务字段并映射到 6.3 的 Service 方法；不接收、返回或自行计算 `sort_order`。移动成功返回资源稳定 ID、派生新编号和受影响资源的 ID/编号列表。
- Season 支持读取、创建和编辑；`season_number` 留在 read-only fields，也不实现 listing 级重排 handler。Remove handler 对 Season 在调用 Service 前固定返回 `season_delete_requires_user_action`，不接受确认字段。UI 仍可直接调用 `ScreenplayService` 的季重排与删除事务。
- Season Create 返回新季与自动创建 Episode 1 的 ID、完整路径；活动上报携带两者，让已打开的双端编辑器更新工作区选择。工具经理保留本回合原 `currentSeasonId`，不能因 reporter 跟随而重建或修改冻结配置。
- 单集 Write 接受 `episode_number`：单独提供时调用季内移动事务，返回新集号与受影响集列表，越界映射为 `invalid_episode_number`。可选 `season_id` 作为跨季移动命令；若同时提供 `episode_number`，在同一事务插入目标季指定位置，否则追加末尾。响应返回新的季 ID、集号和两边受影响的集列表；无效目标映射为 `invalid_season_ref`，源季唯一集映射为 `last_episode_required`。同一 payload 的标题与目标时长也在事务内一起更新，任一校验失败都不部分落库。
- 元素数组的入参校验与 9.3 的错误码映射。

#### NEW: `lib/shared/services/ai/tools_cross_work.dart`

- `part of 'tools.dart'`：`/works/` 前缀解析后的 `work_id` 校验、目标库 lease、单作品查询范围、跨作品只读门禁，以及响应中 `work_id` 与完整资源路径的标注（9.9）。
- `works` 集合的 listing handler，返回稳定 `work_id`、标题、类型和来源关系。
- 读取其他剧本的 Episode listing 时先解析目标有效 Season：单季可隐式使用唯一 ID，多季省略参数返回 `season_id_required`；`work_id` 等于当前作品时仍使用回合冻结的 `currentSeasonId`。这只影响 handler，不动态重建 path schema。

#### `lib/shared/services/ai/tools.dart`

- 在 `_collectionSchemas` 增加 `screenplay` 集合与 `seasons`/`episodes`/`scenes`/`beats`/`elements` 子资源声明，集合与子资源一律 `hidden: true`（字段字典不常驻，9.1）；这些固定子资源段不进 `screenplayPathFieldSegments`。
- Episode schema 把 `episode_number` 定义为可读写数字而不是 read-only field；字段说明写清“单独写是季内目标位置，与 `season_id` 同写是目标季位置”。`season_id` 在 Create 省略时使用冻结当前季，在已有 Episode 的 Write 中表示跨季移动。这些参数语义留在 schema 字段说明与 Bundled Skill，不在工具总 description 重复清单。
- Scene/Beat schema 不声明 `sort_order`：读取分别给派生只读的 `scene_number` / `beat_number`，写入用只写的 `before_scene_id` / `after_scene_id`、`before_beat_id` / `after_beat_id`。互斥、父级和锚点约束写在各字段 schema description 与 9.2 的跨字段规则中，工具总 description 不重复字段清单。
- 剧本正文 stage 前按 `_currentToolExecutionContext.sourceSessionId ?? sourceSessionId ?? _currentToolExecutionContext.sessionId ?? sessionId` 解析 session 身份并显式传给 working overlay；最终为空返回 `missing_session_context`，不能创建 `sourceSessionId = null` 的剧本正文条目。这个收紧只用于新剧本正文分支，不改变存量工具的归因语义。
- `relations` schema 新增可选 `scene_id`，把现有 `chapter_id` 从 `requiredFields` 移除；handler 只拒绝二者同时存在，两者都省略时沿用无证据关系语义。
- 增加只读集合 `works`（`isReadOnly: true`、`hidden: true`）。注意 `isReadOnly` 只约束 Write/Edit（见 `tools.dart:716` 注释），`Create` 与 `Remove` 命中 `works` 要在各自的路径分支里单独拒绝。
- 各工具入口增加 `isScreenplayPath` 分支，与 `isCanvasPath` 同一位置；再增加 `works` 前缀分支，位置在所有集合分支之前。
- 根目录 listing 按目标作品类型过滤 `_rootCollections`。

#### `lib/shared/services/ai/tools_graph.dart`

- GraphSearch input schema 增加可选 `work_id`；省略时保持当前作品行为，传入时接受任一有效本地作品。
- 跨作品搜索通过 `CrossWorkLease` 取得目标 `NovelContentService`，返回顶层 `work_id`，并为资源路径补 `/works/{work_id}` 前缀。
- 现有 `type`、`id`、`relation_type`、`depth` 字段保持兼容；这次不把 GraphSearch 的通用起始实体 `id` 重命名，因为它不是 path schema 占位符且可能被用户 AgentSkill 直接调用。

#### `lib/shared/services/ai/tools_support.dart`

- `ParsedPath` 增加 `workId`；`parse()` 在 `segments[0] == 'works'` 时把 `segments[1]` 切成 `workId`，再用 `segments.sublist(2)` 重走原有解析逻辑；首段不是 `works` 时**一个分支都不进**，解析结果与实施前逐字一致。`collection`/内部 `id` 槽位/`namePath`/`field` 的切分逻辑不改（9.9）。
- `pathSchema()` 与 `pathSchemaFieldNotes()` 增加工作区类型参数；新增按集合名过滤的渲染，novel 分支输出保持不变。
- `_CollectionSchema` 与子资源 schema 增加 `idPlaceholder` 和路径模板覆写字段：既有章节渲染 `{chapter_id}`，剧本子资源分别渲染 `{season_id}`、`{episode_id}`、`{beat_id}`、`{scene_id}`、`{element_id}`；`screenplay` 的固定子集合段推导不出来，不能靠通用模板渲染。
- `_CollectionSchema` 与 `_SubSchema` 增加默认空、静态的 `writeOnlyFields`：它参与 Write/Create 的可写字段校验，但不进入 Read 可选字段、listing 响应或 queryable fields。场次和节拍的 before/after 锚点放这里，并各自在 `fieldDescriptions` 记录目标 ID、互斥和父级含义；字段字典渲染器对非 hidden 集合可标为 write-only。其他存量 schema 默认空，行为不变。构造时断言它与 `readOnlyFields`、普通只读派生字段不重叠，避免同一字段同时宣称只读和只写。
- `_FieldValueKind` 增加对象数组种类，并让 `_ObjectFieldValue` 能描述数组元素的形状——现有 `list` 只支持字符串数组（`aliases`、`tags`），装不下元素数组。
- `_attachReadResourcePath` 增加剧本分支与 `works` 分支：有 `workId` 时响应 `path` 必须渲成带 `/works/{work_id}` 前缀的完整路径（9.9）。

#### `lib/shared/services/ai/ai_service_config.dart`、`chat.dart`

- 增加 `contentKind`、当前 `workId`、`sourceNovelId` 与剧本 `currentSeasonId`，以及按 `work_id` 取得只读 `CrossWorkLease` 的 resolver 回调，透传给 `AiToolManager`；默认 `novel` / null / 空实现。`currentSeasonId` 在一次 AI 回合创建时取工作区状态已经恢复并修复完成的当前值，再冻结给该回合，供省略 `season_id` 的工具调用解析默认季。
- resolver 由宿主实现：按 `work_id` 查询任一有效本地作品的 `content_database_path`，交给已有的 `NovelContentDatabase(filePath)` 缓存工厂，返回带同步幂等 `release()` 的 `CrossWorkLease`。`AiToolManager` 按 9.9 的所有权规则维护 acquisition future、lease 与在途计数，并新增幂等同步 `dispose()`；`AiClient.dispose()` 必须在 `_toolManager = null` 前调用它。现有 `AiClient.dispose()` 的同步签名和调用方不改。

#### `lib/shared/models/ai_chat_models.dart`

- `AiSessionContext` 增加 `contentKind`、冻结的 `currentSeasonId` 与是否多季，供 prompt 装配选择工作区分支和定位范围。单季时 prompt renderer 不输出 Season 行；多季时输出当前季。`sourceNovelId` 不进入 prompt context；来源关系只由工具运行时用于 `/works` listing 标记，不能改变 prompt 装配。

#### `lib/shared/services/ai/prompts/`

- `PromptFragments.pathSchemaBlock()` 增加工作区类型参数，四处调用点同步。
- `ChatPromptUseCase` / `ModePromptUseCase`：按类型选择场景指引分支、过滤 AgentSkill 与 SubAgent 索引、剧本下不渲染章节行、剧本下关闭 `setup_phase`。

#### `lib/shared/services/working_overlay.dart`

- 只新增 `screenplay_scenes` 一类 resourceType（`field` 取 `elements` 或 `synopsis`，新场次创建时为空）：apply、回读当前值、退回新建场次。**不新增元素级 resourceType**（9.4）。
- 新建场次与 Chapter 一致只有一条 `field = null` 的 `create` change，`new_text` 是包含场景标题、梗概和初始正文的展示预览；不把初始正文另存成 `field = elements` change。接受/退回继续使用现有批量按钮和逐 change Service，不新增场次聚合状态。
- `elements` 的 `old_text` / `new_text` 存元素数组 JSON，按 9.4 的规范形状序列化；stage 时 apply `new_text`，退回时 apply `old_text`，都 decode 后调 `ScreenplayService.replaceSceneElements()`，不经过文本中间态；接受只提交变更记录。
- 整场、单元素 Write/Edit/Remove 在 stage 前统一使用 `/screenplay/scenes/{scene_id}/elements` 作为 `resourcePath`，不能把元素 ID 留在路径里，否则同一 session 的合并键会分裂。
- 接收 Tool Manager 已解析的非空 `resolvedSessionId`；正文条目的唯一性按 `resourcePath + source = ai + resolvedSessionId` 计算，同一 session 的连续写入合并到一条。查找/创建、跨 session active 冲突检查与 apply 放进同一事务；另一 session 已持有同场正文时返回 `working_change_conflict`，不叠加两份整场快照。
- 场内任一字段第一次人工防抖保存成功时，`commitManualSave()` 先提交同场全部 active AI change（包括场次 `create`、`elements` 与 `synopsis`），再提交人工 change，防止之后退回 AI 快照或删除已有人工成果的场次；不弹确认框，保存没有产生数据库写入时不触发。
- 三处 `default` 兜底不再覆盖新类型，必须显式 case。
- 展示路径拼接：`_resourceScopeForItem`（`working_overlay.dart:1566`）等三处改为优先取非空 `resourcePath`，剧本条目落 `/screenplay/scenes/{scene_id}`；不按 `resourceType` 加拼接分支。

#### 待审阅改动 UI

- `screenplay_scenes` / `elements` 条目用 `screenplay_element_render.dart` 只把 `new_text` JSON 渲染成整场正文预览，不显示 old/new diff，也不接入 `rollbackChangeLines()`。
- 元素级写入不产生单独条目，用户看到的始终是这一场的整场预览；条目只提供整体接受或整体退回（9.4）。`synopsis` 保持现有文本 diff 与按行审阅。

#### `lib/shared/services/bundled_control_skills.dart`

- 当前代码已有九个 Bundled Control Skill；新增第十个「剧本写作指南」，无 Run 命令，并把文件顶部“九个”计数注释同步为“十个”。

#### `assets/bundled_skills/screenplay-writing-guide.md`

- 路径速查、字段取值、正文行语法、排场顺序、Season 权限与明确创建意图边界、反模式。

#### `assets/prompts/agent/orchestrator.md`

- 用 `{{#screenplay_workspace}}` / `{{^screenplay_workspace}}` 分出剧本分支；小说渲染结果不变。

#### `assets/prompts/fragments/scene_reading_boundary.md`、`screenplay_craft.md`

- 新增两份片段，并注册进 `PromptFragmentPaths`。跨作品读取只通过 path schema 的 `/works/{work_id}/…` 行告知，不另加 prompt 片段。

#### `lib/shared/models/novel_workspace.dart`

- 复用现有 `overview`、`characters`，新增四个稳定且会进入本机快照的枚举名：`screenplay_script`、`screenplay_outline`、`screenplay_beats`、`screenplay_scenes`。分别把当前 `scene_id` / `beat_id` 映射到 `screenplay/scenes/{scene_id}/elements`、`screenplay/scenes/{scene_id}/synopsis`、`screenplay/beats/{beat_id}`、`screenplay/scenes/{scene_id}`，供 `active_workspace_target` 与引用 chip 使用；不把当前季编码进枚举或资源路径。
- 同步修改当前代码中对 `NovelWorkspaceSection` 做穷尽 switch 的 `lib/shared/models/feature_id.dart`、`lib/shared/services/ai/chat_prompt_builder.dart`、`lib/shared/services/ai/chat_session_controller.dart` 与 `lib/desktop/widgets/ai/chat/composer.dart`；四个剧本专属 section 第一期不新增 FeatureId，映射为 null。实施前用 `rg "NovelWorkspaceSection" lib` 建立完整调用点清单，再以 analyzer 穷尽性检查收口，不能只等运行时撞到遗漏。

#### `lib/shared/models/canvas_ai_activity.dart` 同级新增剧本活动模型

- `ScreenplayAiActivity`：当前季、当前集、当前场与动作类型，供编辑器跟随定位；AI 新增季时携带新季与 Episode 1，跨季移动当前集时携带目标季，让 UI 跟随稳定 ID，但都不改写已创建 AI 回合的冻结季。

### 文案与生成文件

#### `lib/shared/localization/locale_keys.dart`

- 增加作品类型、剧集、集、场次、节拍、状态、空状态和错误提示键。
- 增加待审阅改动列表里 `screenplay_scenes` 的资源类型标签（只有这一个，正文没有元素级条目）。
- 增加改编来源选择器与“来源作品不可用”提示的文案键。

#### `assets/translations/en/screenplay.json`

- 新增英文剧本文案 namespace。

#### `assets/translations/zh-CN/screenplay.json`

- 新增中文剧本文案 namespace。

修改 Drift schema、`@DriftAccessor` 和 Riverpod 生成源后运行 `make codegen`，检查全部生成 diff。新增 Dart 文件按项目要求填写职责、关联文件和 Rules 文件头。

## 12. 实施顺序

本功能仍作为一个发布单元交付，不能只发布桌面端或只发布移动端；Git 提交按可独立验证和回退的能力边界拆分。第一笔先交付跨作品只读，它只建立在现有小说资源上，不包含剧本 schema、`content_kind` / `source_novel_id` migration、剧本路径或 UI。该提交合并后，现有小说工作区已经可以用 `/works/{work_id}/…` 读取其他小说；后续剧本任务只扩展目标作品类型和返回元数据，不重做解析、lease 与只读门禁。

`T1` 会横跨 path parser、通用工具 handler、内容库 lease、prompt path schema 与测试，文件数预计超过 8 个；这是一个能力闭环 commit，不再按文件层拆成“只有 parser、暂时不能读取”的中间提交。剧本数据模型本身虽然不需要跨作品读取，但提交顺序仍固定为先 `T1`、再 `T2`；`T1` 单独合并时已经可用，后续提交则以它为既定基础继续扩展。

```text
T1 跨作品只读（现有小说，可独立 commit）
  └── T2 剧本数据模型、migration、DAO、Service
        └── T3 创建流程与跨平台编辑器路由
              ├── T4 桌面端剧本编辑器 ────────────────┐
              ├── T5 移动端剧本编辑器 ────────────────┼── T7 全量回归与验收
              └── T6 AI 剧本工作区接入 ───────────────┘
```

| 任务 | 内容 | 依赖 | 完成条件 |
| --- | --- | --- | --- |
| T1 | 现有小说资源的跨作品只读闭环：`ParsedPath.workId`、资源专名占位符、`works` 前缀解析、`/works` 与单目标根 listing、`work_id` resolver、`CrossWorkLease` 与 Tool Manager 生命周期、`Read` / `Glob` / `Grep` 只读门禁、GraphSearch 可选 `work_id`、跨库 ID 和完整 path 标注、作品级 `profile` / `story_state` 单例、相对/绝对路径说明与回归测试。旧 `/novel` / `/novel/current_state` 仅保留输入解析兼容。此提交不增加数据库字段，也不声明 `screenplay` 子路径；`/works` 首版只返回当前已有的 `work_id`、标题等通用作品元数据 | 无；第一笔独立 commit | 任一现有有效小说可显式读取另一部小说并跨作品 GraphSearch；写入类工具全部返回 `cross_work_write_denied`；一次调用只打开一个目标库；并发读取同一作品只持有一份 lease；dispose、获取失败与在途调用都正确释放；模型说明中当前作品使用相对路径且仅 `/works/{work_id}` 是绝对路径，未明确要求时不跨作品读取 |
| T2 | 七表 schema（含 Season）、`novels.content_kind` / `source_novel_id`、`entity_relations.scene_id`、元素模型与渲染函数、`ScreenplayMetrics`、DAO（含元素 reconcile 与 Episode 预览 projection）、Service（含锚点式场次/节拍移动）、剧本工作区状态和 migration 测试；同时给 T1 的 `/works` listing 加上最终的 `content_kind` 与原作关系元数据 | T1（实施顺序；数据模型本身无技术依赖） | 新旧内容库均可打开；每部剧集至少一季、每季至少一集与连续编号事务通过；场次/节拍公开契约不出现 `sort_order`；工作区选择可恢复并修复；元素 reconcile 的 id 稳定性测试通过；`/works` listing 能区分小说、剧本与原作关系 |
| T3 | 创建表单、Season 1 / Episode 1 初始化和统一路由 | T2 | 小说兼容，剧本创建后进入不显示 Season 的单季编辑器；重开恢复本机有效选择 |
| T4 | 桌面概览、季管理、正文、大纲、节拍、场次和人物 | T3 | 单季隐藏、多季管理、键鼠操作与全局背景回归通过 |
| T5 | 手机与平板页面、单场编辑、季与集选择 | T3 | 单季隐藏、多季管理、手机单列和平板双栏回归通过 |
| T6 | `screenplay` 路径与工作区门禁、目标作品按 `content_kind` 过滤、跨作品剧本的 Season 解析、当前季默认作用域、元素数组契约、working overlay 分支（只有场次级）、prompt 装配、剧本写作指南；复用 T1 的 parser、resolver、lease 与只读门禁，不建立第二套跨作品执行链 | T1、T3；可与 T4/T5 并行，AI 面板接线在 T4/T5 落地后收口 | 小说跨作品读取回归不变；跨作品可读取单季或显式指定季的剧本，多季省略 `season_id` 返回明确错误；单季对话不引入 Season，多季默认操作落入回合冻结的当前季；端到端排场与写正文通过 |
| T7 | 双端数据互通、性能、错误与 migration 回归 | T4、T5、T6 | 第 13 节全部通过 |

## 13. 验收标准

### 数据与业务

| 类别 | 标准 | 验证方式 |
| --- | --- | --- |
| Migration | 主库 30 升到当前版本后，旧作品均为 `novel`，内容和索引不变 | 真实旧 schema fixture 测试 |
| Migration | 内容库 13 升到当前版本后，七张表与索引存在，旧章节和人物数量、字段值不变 | fixture、PRAGMA 与 Typed DAO 读取 |
| 创建 | 剧本创建一条根记录、第 1 季和该季实际的第 1 集，`kind = series`、`format = asian`；创建表单不要求填写季 | Service 集成与双端 Widget 测试 |
| 创建失败补偿 | 内容库打开、seed、剧本根事务或主库 finalize 任一步失败时，已打开句柄都恰好关闭一次，主库记录被软删除且原始异常不被补偿异常覆盖；内容库文件和封面不删除。成功时路径与 `requestedDraft` 原子落定，普通作品可见、调用方请求的草稿仍为草稿 | `NovelActionsService` 故障注入测试、缓存 referenceCount 断言与日志断言 |
| 类型不可变 | 小说或剧本创建完成后，无论是否已有正文，主库 Service、双端编辑表单与 AI 都没有修改 `content_kind` 的入口；直接尝试修改返回只读字段错误且数据不变 | Service、Widget 与工具负向测试 |
| 来源可编辑 | 剧本创建后可把 `source_novel_id` 改为另一部有效小说或清空；只更新来源标记，不修改人物、集、场次、节拍和正文；小说不能设置该字段 | Service 与双端 Widget 测试 |
| 来源失效 | 删除原作后 `source_novel_id` 保留，剧本照常打开并显示“来源作品不可用”，AI 读取返回 `work_not_found`；以同一 id 恢复原作后自动重新显示 | Service、工具与双端 Widget 测试 |
| 格式预留 | `screenplays.format` 列存在且新建剧本固定写 `asian`；双端不展示格式或提供切换，AI 读取可见但写入返回只读字段错误 | schema、Widget 与工具测试 |
| 季不变量 | 每部有效剧集至少有一季；新增季会同时创建该季第 1 集；桌面和移动端都不能删除最后一季，返回 `last_season_required` 且数据不变 | Service 事务与双端 Widget 测试 |
| 新增季跟随 | 双端 UI 新增季前 flush 当前场，成功后进入新季 Episode 1 并清空当前场；失败时原选择不变 | Service、Provider 与双端 Widget 测试 |
| 季号 | 新增、重排或删除中间季后，有效季在同一事务中按从 1 开始的连续序号重新编号，稳定引用的 `season_id` 不变 | 事务测试 |
| 单季呈现 | 只有一季时双端不显示季选择器、“第 1 季”或季管理层级；新增第二季后显示，删回一季后再次隐藏 | 双端 Widget 测试 |
| 当前季状态 | `screenplays` 与 Season 表没有 `current_season_id`；每个作品在本机 `app_states` 保存最后选择的季、集和场，重开时恢复，保存 ID 失效时按有效父子层级修复并写回 | schema、Provider 与双端 Widget 测试 |
| 规划集数 | 规划集数属于 Season；当前季新增两集后显示“3 集”，设定后显示“3/8 集”，未设定时无分母；超过规划时显示“10/8 集，已超出规划”，不阻止新增或下调规划数 | DAO、Widget 和 schema 测试 |
| 集号 | `episode_number` 可读写；写入 `1..当前季有效集数` 会把该集移动到目标位置并平移中间集，写当前值无变化，越界返回 `invalid_episode_number`；删除中间集后仍保持连续，其他季集号不变 | Service、工具与 Widget 事务测试 |
| 最后一集 | 每一季都不能删除自己的唯一有效集；桌面、移动端与 AI 返回 `last_episode_required` 且数据不变 | Service、工具与 Widget 测试 |
| 跨季移集 | 显式提供目标 `season_id` 可把一集连同场次、节拍和正文移入另一季；省略 `episode_number` 时追加末尾，同时提供时插入目标季 `1..原有效集数 + 1`，稳定 ID 不变并重排两边；目标无效、目标号越界或源季只有这一集时整次不修改数据；两季规划集数不自动变化 | Service、工具事务与双端 Widget 测试 |
| 父级 | 每集必须指向同一剧本的有效 Season；场次与节拍必须指向同一剧本的有效集，`season_id` 与 `episode_id` 不可为空 | Service 负向测试 |
| 场次 | 新增、锚点重排、追加到集末尾、跨集锚点移动和删除后，派生 `scene_number` 连续且顺序一致；锚点等于自身、无效锚点或互斥字段组合整次失败；Service 公共参数与返回模型不出现 `sortOrder` | DAO、Service 与工具测试 |
| 场次状态 | 新场默认 `draft`；只接受 `draft`、`final` 且可自由切换；空正文仍是合法 `draft`；人工或 AI 修改 `final` 场次的正文、梗概或其他字段后仍保持 `final`，只有显式写 `stage` 才改变 | Service 与工具测试 |
| 场景内外 | `interior_exterior` 可空，空值在标题中不显示占位；非空时只接受 `interior` / `exterior`；`both` 被拒绝并提示内外转换应拆场 | Service、Widget 与工具测试 |
| 场次证据 | 删除场次或删除集级联删除子场次时，都会清空关联关系的 `scene_id`，但保留关系本身；行为与删除章节时清空 `chapter_id` 一致 | Service 事务测试 |
| 关系证据契约 | `EntityRelationsService` 的 query/create/update 支持 `sceneId`；`chapterId` 与 `sceneId` 同时提供、或 `sceneId` 无效时整次不写入；UI 与 AI 直调得到相同结果 | Service 正向与负向测试 |
| 节拍 | 删除节拍后场次保留且 `beat_id` 被清空 | 事务测试 |
| 幕分组 | `act_number` 接受任意正整数，四幕、五幕均可；零和负数拒绝；节拍可用锚点在同集内重排或跨幕移动，派生 `beat_number` 在每幕内连续；跨集锚点拒绝；数据库没有幕表或三幕上限 | DAO、Service、工具与 Widget 测试 |
| 节拍横滚 | 桌面节拍按幕分栏溢出时，普通鼠标纵向滚轮可以驱动横向滚动；栏内纵向滚动仍优先响应 | Widget 测试 |
| 人物 | 增删场次人物后，场次 chips、出场矩阵和人物出场列表一致 | Stream 集成测试 |
| 正文 | 七类元素落成元素行；枚举、字段配对、ID 归属和台词角色归属违例时整场拒绝且不部分落库，创作格式问题不作为硬错误 | Service 负向测试 |
| 对话块语法 | 悬空 `character` 可以保存并返回 warning；`character` + `parenthetical` 不带 `dialogue` 正常保存；场景开头直接出现 `dialogue`、或 `dialogue` / `parenthetical` 被独立元素与另一人物提示隔开时拒绝 | Service 正向与负向测试 |
| 对话块删除 | 单删仍有从属元素的 `character` 返回 `dependent_elements_exist` 且数据不变；明确删除整个对话块才移除台词；删完最后一个 `dialogue`/`parenthetical` 不反向删除 `character`，而是返回未完成 warning | Service、工具与 Widget 测试 |
| 正文 ID 稳定 | 同一场连续写入 10 次，未改动元素的 `element_id` 全程不变；净删除的元素行数等于实际删除数；未知或属于其他场次的 `element_id` 整次拒绝 | DAO reconcile 测试 |
| 正文人物 | `character` 元素缺少 `character_id`、写入只读 `name`、或引用删除档案时拒绝；旧数据删除引用仍可读出原名和错误标记 | Service 正向与负向测试 |
| 正文删除 | 场次编辑不产生“清空后重插”的废行；元素行只软删除，没有业务 SQL `DELETE` | DAO 测试与 diff 检查 |
| 引用删除 | 人物或地点存在有效场次引用时返回 `entity_in_use` 且数据不变；移除场次使用处后可按既有语义删除；桌面与移动端都能打开场次使用处；小说的既有级联行为不变 | Service 事务与双端 Widget 测试 |
| 失效引用兜底 | 旧数据或恢复记录引用软删除人物/地点时显示“原名（已删除）”，不崩溃；写入前要求替换或移除 | Service 与 Widget 测试 |
| 删除 | 季、集、场次、节拍和元素只更新 `deleted_at`，没有业务 SQL `DELETE`；删除季级联其集、场次、节拍与正文并清空关系的 `scene_id`，`entity_relations` 本身沿用现有无软删除语义 | DAO 测试与 diff 检查 |
| 删除当前季 | 删除当前季前先 flush 当前场；删除成功后优先选择原位置的下一季，没有下一季时选择前一季，并把新选择写入本机工作区状态 | Service、Provider 与双端 Widget 测试 |
| 删除与待审阅 | 删除季、集或场次不修改其现有 `working_changes`，与章节删除行为一致；实现中没有为剧本增加 working-overlay 清理编排 | Service 回归测试与代码检查 |
| 删除恢复 | 双端与 AI 均没有回收站或恢复入口；用户界面删除前明确确认，已允许的 AI 结构删除直接执行，底层仍保留软删除数据 | Widget、工具 schema 与 DAO 测试 |
| 统计 | 概览在场次缓存列上聚合，查询不 join `screenplay_scene_elements` | DAO 查询测试 |
| 统计一致 | 固定中英文元素 fixture 得到确定的预估行数、八分之一页与时长；`note` 不改变字数、页数或时长；元素写入后缓存与 `ScreenplayMetrics` 直接结果相同，UI 显示“预估” | 纯函数与 Service 集成测试 |
| 来源 | `source_novel_id` 只能指向有效小说；源作品删除后剧本仍可正常打开 | DAO 负向测试 |

### 桌面端

| 标准 | 验证方式 |
| --- | --- |
| 所有旧入口打开剧本时进入 `ScreenplayEditorPage`，小说仍进入原编辑器 | 路由 Widget 测试 |
| 单季时上下文栏不显示 Season；新增第二季后显示季选择与内联管理，切季只展示该季集，删回一季后入口消失 | Widget 测试 |
| 关闭再打开多季作品会恢复本机上次有效的季、集和场；无效快照回退到第一季并修复子级，不把当前季写进剧本业务表 | Provider 与 Widget 测试 |
| 普通鼠标滚轮可横向滚动场次板 | macOS 和 Windows 手动测试 |
| 场次表有可见横向滚动条，滚轮仍可滚动外层页面 | 桌面手动测试 |
| 桌面连续剧本只建立一个当前 Episode projection stream；切集只加载新集元素行，非当前场不创建编辑 controller，AI 修改同集其他场后预览自动刷新；概览和普通列表查询不 join 元素表 | DAO/Provider/Widget 测试和性能检查 |
| 全局背景开启后壳层透明，卡片保持可读 | 亮色、暗色和图片背景截图回归 |

### 移动端

| 标准 | 验证方式 |
| --- | --- |
| 手机可以创建剧集、选集、增集、排场、改节拍和编辑单场正文；单季流程不出现 Season | 真机或模拟器流程测试 |
| 新增第二季后出现季 pill 与季选择 sheet；季删除只在全屏管理页执行，删回一季后季入口隐藏 | Widget 与真机流程测试 |
| 移动端重开作品遵守与桌面相同的本机选择恢复和失效修复规则 | Provider 与 Widget 测试 |
| 手机不出现横向宽表，场次和人物信息改用卡片与列表 | 小屏截图回归 |
| 平板在宽度足够时显示列表与详情双栏，窄窗口自动回到单列 | 多尺寸 Widget 测试 |
| 键盘弹出后正文仍可滚动和编辑，退出页面会完成最后一次保存 | Widget 与真机测试 |
| 所有主要触控目标不小于 44pt，删除需要二次确认 | Widget 和人工检查 |

### AI

| 类别 | 标准 | 验证方式 |
| --- | --- | --- |
| 小说不受影响 | `contentKind = novel` 的 system prompt 除 `/works/{work_id}/…` path schema 行外与实施前逐字一致 | prompt golden 测试 |
| 工具定义静态 | 两种工作区拿到的工具名、input schema 与 description 完全相同，且不随权益、数据或会话状态变化 | tool schema 快照测试 |
| 字段字典不常驻 | `pathSchemaFieldNotes()` 的输出里没有 `screenplay`、`works` 的任何字段行；剧本会话也没有 | prompt 单元测试 |
| 路径清单按工作区过滤 | `pathSchemaBlock(kind: novel)` 不含剧本路径模板，`kind: screenplay` 不含章节、卷、大纲、伏笔；两者都含只读 `/works/{work_id}/…` | prompt 单元测试 |
| 门禁 | 小说会话读写 `screenplay*`，剧本会话读写 `chapters`、`volumes`、`outlines`、`foreshadowing` 均返回 `content_kind_mismatch` 并带可用替代路径；两种工作区都可访问 `profile` 与 `story_state` | 工具负向测试 |
| 根 listing | 当前作品根 listing 按工作区类型返回对应集合；`Glob`、`Grep` 不会走进被关闭的集合 | 工具测试 |
| 路径 | 季可读、建、改名和改规划；集、场次、节拍、元素的读、建、写、业务化移动和删除可用，id 只能从 listing 复制；场次、节拍和元素 schema/响应不含 `sort_order`，提交它返回 `unknown_field` | 工具集成与 schema 快照测试 |
| AI 不删季 | `Remove screenplay/seasons/{season_id}` 无论是否多季、是否先经 AskUser 确认，都返回 `season_delete_requires_user_action` 且数据不变；工具 schema 没有确认令牌或绕过字段 | 工具负向与 schema 快照测试 |
| AI 不重排季 | `season_number` 只读，写入返回 `read_only_field`；不存在接收季 ID 顺序或目标位置的 AI 路径，季重排只能由双端管理 UI 调用 Service | 工具负向、schema 快照与代码检查 |
| 当前季默认 | `screenplay/episodes` 与 `Create screenplay/episodes` 省略 `season_id` 时使用回合开始时冻结的当前季；显式 `season_id` 可操作另一季；已有 `episode_id` 的路径不要求再传季 | 工具集成测试 |
| AI 跨季移集 | `Write screenplay/episodes/{episode_id}` 显式带目标 `season_id` 时移动该集；不带 `episode_number` 追加末尾，两者一起提供则原子插入目标季指定位置，并返回两边受影响列表 | 工具与 Service 集成测试 |
| AI 季内移集 | `Write screenplay/episodes/{episode_id}` 写 `episode_number` 可在当前所属季内移动该集；读回得到新集号，受影响集保持连续且稳定 ID 不变 | 工具与 Service 集成测试 |
| 当前季冻结 | AI 回合开始后切换 UI 季不改变该回合默认目标，下一回合才采用新季；冻结季在回合中被删除时返回 `season_not_found`，不自动改投其他季 | 工具与会话集成测试 |
| 移集后冻结 | AI 把当前集移到另一季后，UI 跟随该集进入目标季，但同一 AI 回合省略 `season_id` 的后续操作仍指向移动前冻结的季；下一回合才采用目标季 | 工具、活动上报与 Widget 集成测试 |
| 当前季来源 | AI 回合只在工作区状态恢复和失效修复完成后冻结 `currentSeasonId`；不会从最大季号、最近更新时间或剧本业务字段推断 | 会话集成与代码检查 |
| 单季 AI 呈现 | 单季时 environment、常规编排和回复不出现“Season”或“第 1 季”，也不为普通集/场次任务预读 `screenplay/seasons`；多季时 environment 显示当前季 | prompt golden 与端到端测试 |
| AI 不自主开季 | 用户只要求继续规划当前剧集、当前季超出规划集数或 AI 判断故事过长时，AI 最多建议分季，不调用 `Create screenplay/seasons`；用户明确要求新增、下一季或多季规划时可以创建 | prompt 场景评估与端到端测试 |
| AI 建季跟随 | `Create screenplay/seasons` 返回新季与 Episode 1 的 ID 和完整路径；已打开编辑器跟随到新季第 1 集，但本回合省略 `season_id` 仍落在创建前冻结的季，AI 继续写新季时使用返回 ID | 工具、活动上报、Widget 与会话集成测试 |
| 正文契约 | 七类元素读回包含只读人物 `name`，写入只接受 `character_id`；提交 `name` 返回 `unexpected_field`，无名称匹配或别名解析路径 | 工具集成与负向测试 |
| 人物提示后缀 | `extension` 接受英文缩写、中文和项目自定义文本并 trim；schema 没有枚举；它不改变人物关联、台词归属和统计 | Service、工具 schema 与渲染测试 |
| 正文契约 | 场景标题形状的 `action` 写入成功并返回 `possible_scene_heading_in_content` warning；悬空 `character` 返回 `incomplete_dialogue_block` warning；`parenthetical` 脱离对话块返回 `invalid_element_sequence` | 工具正向与负向测试 |
| `cast` 完整性 | 正文新增说话人物会补入 `cast`，已有顺序不变，多个缺失人物按正文首次出现顺序追加；`cast` 可额外包含无台词人物；移除仍被 `character` 元素引用的人物返回 `dependent_elements_exist` 与元素路径且数据不变 | Service、工具与双端 Widget 测试 |
| 无文本入口 | 不存在接收自由文本正文的路径；仓库里没有文本到元素的解析函数 | 工具 schema 测试与代码检查 |
| 单元素改动 | `Write .../elements/{element_id}` 与 `Edit .../text` 只影响该元素，同场其他元素的 `element_id` 与 `updated_at` 不变 | 工具集成测试 |
| 派生统计 | AI 写入正文后页数、时长、台词数、字数与人工写入结果一致 | Service 集成测试 |
| 可审阅 | AI 写的 `elements` 与 `synopsis` 立即落库并出现在待审阅改动里；`elements` 只显示最新整场正文预览，不显示 JSON、old/new diff 或逐行退回入口，整体接受不重复写入、整体退回后恢复原正文；`synopsis` 保持文本 diff 与按行退回 | working overlay 与 Widget 测试 |
| 审阅单位 | 整场 `Write` 后再 `Edit` 其中一句，数据库立即得到两次改动叠加的结果，待审阅列表仍然只有一条场次级条目；`old_text` 保持首次写入前数组，`new_text` 是最新数组 | working overlay 集成测试 |
| Session 唯一 | 同一 AI session 对同场并发或连续写入只产生一条 active `elements` 条目；另一 session 在该条目解决前写同场返回 `working_change_conflict` 且数据不变；接受、退回或人工接管后另一 session 可继续；全部 session 来源都为空时返回 `missing_session_context`，不产生 null 归属条目 | working overlay 并发事务与工具集成测试 |
| 建场审阅 | `Create screenplay/scenes` 同时传结构字段、梗概与初始 `elements` 后，只产生一条 `field = null` 的场次级 `create` change；预览包含完整初始内容，退回该 change 会删除整场；同一次创建不产生 `synopsis` 或 `elements` change | 工具与 working overlay 集成测试 |
| 人工接管 | 同场存在 active AI `create`、`elements` 或 `synopsis` change 时，任一人工修改的第一次 600ms 防抖保存成功后先提交该场全部 AI change、再提交人工 change，不弹确认；仅聚焦或保存失败不接受；之后待审阅列表既不能恢复旧正文，也不能退回建场而删除人工成果 | working overlay 与 Widget 集成测试 |
| 人机写入一致性 | 与小说相同：dirty 本地正文不被外部 stream 值覆盖，连续自动保存保持单飞；工具 schema 和场次表均没有 revision、CAS、锁或 `stale_scene` | Widget 测试、schema 快照与代码检查 |
| 无元素级条目 | 元素级写入与删除都不产生 `screenplay_scene_elements` 类型的 `working_changes` 行；仓库里没有这个 resourceType | overlay 测试与代码检查 |
| overlay 规范形状 | 人物改名不会改变规范元素 JSON；已提交条目做漂移检查时，当前数组仍与其 `new_text` 相等；序列化不含 `name`、`updated_at`、`sort_order` | overlay 单元测试 |
| 结构操作 | 建集、建节拍、改序、改出场人物直接落库且不进待审阅列表；AI 建场连同初始梗概和正文只产生一条场次级 `create` 条目，退回后软删除该场 | 工具测试 |
| AI 结构删除 | AI 可直接删除集、场次和节拍且不产生 working change；级联与最后一集保护和人工删除一致 | 工具与 Service 事务测试 |
| 关系 | `chapter_id`、`scene_id` 都可省略且至多一个非空；同时传入返回 `mutually_exclusive_fields` | Service 负向测试 |
| 存量路径兼容 | 模型可见说明只出现相对的 `chapters`、`screenplay/scenes/{scene_id}` 与绝对的 `/works/{work_id}/…`；解析层仍接受 `/chapters`、`//chapters` 等旧输入且结果不变 | 路径 schema 与解析 golden 测试 |
| path schema | 路径模板只出现 `{work_id}`、`{chapter_id}`、`{season_id}`、`{episode_id}`、`{beat_id}`、`{scene_id}`、`{element_id}` 等资源专名，不出现通用 `{id}`；普通剧本资源不嵌套到 Season 路径下 | schema 快照测试 |
| `works` 前缀 | 首段是 `works` 才切 `workId`；`/works` 单段是本地作品 listing；`/works/{work_id}` 是根 listing；`/works/{work_id}/a/b` 的剩余段解析与当前作品的 `a/b` 完全相同 | 路径解析单元测试 |
| 拼错集合名 | `charactors/ch_123` 报 `unknown_collection`，不报作品不可达 | 工具负向测试 |
| 错误归属 | `/works/{work_id}/chapterz` 报“该作品下没有 chapterz”，不报“没有叫 works 的集合” | 工具负向测试 |
| 稳定作品地址 | `/works/{work_id}` 只按 ID 精确解析；修改作品标题、标题含 `/` 或 `?` 都不改变路径 | 工具集成测试 |
| 跨作品只读 | 剧本会话可读 `/works/{work_id}/chapters`、`/works/{work_id}/characters`；`Write`、`Create`、`Edit`、`Replace`、`Remove` 命中 `/works/` 返回 `cross_work_write_denied`（`Create` 与 `Remove` 单独覆盖，`isReadOnly` 挡不住它们） | 工具负向测试 |
| 跨作品季范围 | 读取其他单季剧本的 `/works/{work_id}/screenplay/episodes` 可省略 `season_id` 并命中唯一季；其他多季剧本省略时返回 `season_id_required`，显式目标季后只返回该季；当前作品即使用 `/works/{current_work_id}` 也仍采用冻结 Current Season | 工具集成与负向测试 |
| GraphSearch 作品范围 | 省略 `work_id` 搜当前作品；传任一有效本地 `work_id` 搜对应作品；未知、删除、草稿或无内容库的作品返回 `work_not_found`；两种工作区 schema 相同 | 工具 schema 与集成测试 |
| 单作品范围 | `/works` 能列出全部有效本地作品且不打开内容库；显式 `work_id` 可读任一作品；`Glob /works/**` 等多库递归返回 `work_id_required` | 工具测试与打开句柄断言 |
| 跨库门禁 | 剧本会话读源小说的 `chapters` 放行，读自己的 `chapters` 返回 `content_kind_mismatch` | 工具测试 |
| 跨库 ID | 把源作品的 `character_id` 写进当前剧本时按当前库不存在处理，返回 `invalid_character_ref` 并提示先在当前作品建档；校验不打开或扫描其他作品，也没有会话级 ID 来源表 | 工具负向测试与代码检查 |
| 跨库 lease | 同一会话并发 Read、Grep、GraphSearch 同一目标作品只增加一次 `referenceCount`；`AiClient.dispose()` 经 `AiToolManager.dispose()` 恰好释放一次。dispose 发生在 acquisition 未完成或工具仍在途时，lease 在完成/归零后释放；获取失败不留缓存或 lease；重复 dispose 安全 | 并发单元测试、故障注入与句柄断言 |
| 技能索引 | 剧本会话看得到「剧本写作指南」、看不到「创作向导」；小说会话相反 | prompt 测试 |
| SubAgent 索引 | 剧本会话的可用列表不含正文写手、内容核验、文风润色、编年史者 | prompt 测试 |
| 跨作品提示最小化 | 不存在 `cross_work_paths.md`；`source_novel_id` 不改变 prompt，跨作品读取只由两种工作区共有的 `/works/{work_id}/…` path schema 行告知 | prompt golden 测试与文件检查 |
| 端到端 | 从只有隐式第 1 季与第 1 集的空剧本出发，AI 不提 Season，能建集、排三场、写完一场正文并让编辑器定位到该场 | 手动回归 |
| 端到端改编 | 从设了来源的空剧本出发，AI 能读原著章节、在剧本里建人物档案、排场并写完一场正文 | 手动回归 |

### 建议验证命令

Flutter 测试串行执行：

```text
make codegen
fvm flutter test test/shared/database/app_database_migration_test.dart
fvm flutter test test/shared/database/novel_content_database_migration_test.dart
fvm flutter test test/shared/database/screenplay_dao_test.dart
fvm flutter test test/shared/services/screenplay_service_test.dart
fvm flutter test test/shared/services/novel_actions_screenplay_creation_test.dart
fvm flutter test test/shared/services/entity_relations_service_test.dart
fvm flutter test test/shared/services/working_overlay_screenplay_test.dart
fvm flutter test test/shared/models/screenplay_element_render_test.dart
fvm flutter test test/shared/services/ai/tools_support_path_test.dart
fvm flutter test test/shared/services/ai/tools_screenplay_test.dart
fvm flutter test test/shared/services/ai/tools_cross_work_test.dart
fvm flutter test test/shared/services/ai/prompts/
fvm flutter test --timeout 10m test/desktop/features/screenplay/
fvm flutter test --timeout 10m test/mobile/features/screenplay/
fvm flutter analyze
```

实际文件名可按测试目录现状调整，但不能省略两类 migration、Service 事务、元素 reconcile 的 id 稳定性、锚点移动、创建失败补偿、关系证据约束、session 唯一 overlay、路径解析 golden、工具门禁、跨作品只读与 lease 生命周期、prompt golden、桌面 Widget、移动端 Widget 和双端手动回归。订阅 Drift stream 的 Widget 测试在结尾拆树并 `pumpAndSettle()`。

## 14. 风险

| 风险 | 触发条件 | 影响 | 对策 |
| --- | --- | --- | --- |
| 主库与内容库创建只完成一半 | 第二个数据库写入失败或进程退出 | 产生不可见的残留记录、未关闭句柄或文件 | 主库记录先隐藏；已打开内容库在 `finally` 恰好关闭一次；失败后软删除主库记录并保留原异常；不自动删封面或内容库文件 |
| 派生统计过期 | 写入绕过 `ScreenplayService` | 概览、页数和书架字数不一致 | UI、后台与 AI 写入都只走 Service；统计与元素在同一事务内由 `ScreenplayMetrics` 重算；测试禁止 DAO 外写 |
| 元素表随编辑膨胀 | 整场写入实现成“清空后重插”而不是 reconcile | 一场戏改十次留下几百条废行，元素 id 每次重生成 | reconcile 是硬要求（5.9）；用连续写入 10 次的 id 稳定性测试锁住 |
| 长剧本重建开销过大 | 桌面同时给整集所有元素挂 controller、焦点和选择状态，或为每场建立独立查询 | 输入延迟、内存增长、N 次查询和滚动卡顿 | 连续 sliver 中只有当前场挂编辑器；其余场次来自唯一 Episode projection stream；切场先 flush，切集释放旧 projection |
| 自动保存乱序覆盖 | debounce 期间连续编辑或快速切场，多个异步写入完成顺序与发起顺序不同 | 新内容被旧 revision 覆盖 | `SceneSaveCoordinator` 单飞写入、合并最新快照、旧 revision 不覆盖本地状态；切场与退出 `flush()` |
| 极端人机同时落库 | 用户与 AI 在同一时刻修改同一场 | 后完成者覆盖先完成者 | 沿用小说行为：保护 dirty 本地 controller、串行化本编辑器保存，不为没有实际协作场景的并发写作增加 revision 或锁；若真实使用出现再单独设计 |
| 人工修改后仍退回 AI 提议 | 同场 active AI 文本或 `create` change 与后续人工修改并存 | 退回 AI 时整场恢复到最初状态，或场次连同人工成果一起被删除 | 场内任一人工保存先提交同场全部 active AI change，再提交人工 change；测试锁定顺序与最终数据 |
| 两个 AI session 竞争同一场正文 | 两个 session 各保存一份立即应用的整场数组快照 | 后退回的旧快照覆盖另一 session，结果依赖操作顺序 | 同一 session 内合并；同场跨 session active 写入互斥，检查与 stage/apply 同事务，冲突返回 `working_change_conflict` |
| 隐式当前季写错目标 | AI 回合执行中用户切季，或调用方把实时 UI 选择直接用于每次工具调用 | 同一回合的连续操作分散到不同季 | 回合开始冻结 `currentSeasonId`；省略 `season_id` 始终使用冻结值，跨季操作必须显式传 ID；冻结目标消失时失败而非改投 |
| AI 建季后默认范围误切换 | reporter 让 UI 跟随新季，同时工具配置读取实时工作区选择 | 同一 AI 回合后续省略季参数的操作突然改投新季 | 工具经理在回合创建时复制并冻结 `currentSeasonId`；活动只更新下回合使用的工作区状态；建季响应返回新季与 Episode 1 供本回合显式操作 |
| 跨季移集制造空季、复制数据或部分更新 | 移动源季唯一集、用复制后删除实现移动，或先改父级再单独改目标集号 | 破坏每季至少一集不变量，产生重复场次、新 ID 或错误中间位置 | Service 事务先校验全部字段；只更新原集的 `season_id` 并在同一事务重排两边和提交其他字段，子资源 ID 全部不变，任一失败不部分落库 |
| 工作区快照指向失效资源 | 季、集或场被删除后重新打开作品 | 页面空白，或 AI 得到已删除的默认季 | 恢复后按有效父子列表逐级 reconcile 并写回；季失效回退第一季，集与场只在新父级内选择 |
| AI 自主引入多季 | 当前季超出规划，或模型认为故事篇幅过长 | 单季用户突然看到新的季层级，导航与创作范围改变 | orchestrator 与剧本写作指南要求当前用户任务有明确多季意图；否则只能建议；用正反 prompt 场景评估锁定 |
| 删除季级联范围过大 | 用户在多季作品删除一季 | 该季全部集、场次、节拍和正文一起不可见 | 只在显式季管理界面提供删除、展示季名与资源计数并二次确认；AI Remove 固定拒绝；最后一季不可删除；事务测试锁定级联与关系证据清理 |
| AI 直接删除结构数据 | 模型误删集、场次或节拍，且第一期没有恢复入口 | 用户需要重新创建被删结构；删集还会连带软删除正文 | 明确暴露软删除语义和级联范围；最后一集不可删除；工具测试锁定精确目标与返回的受影响资源 |
| 入口漏改 | 某个旧调用仍直接打开小说编辑器 | 剧本进入错误页面 | 统一路由组件并用搜索结果建立路由回归清单 |
| 软删除后的唯一约束错误 | 唯一索引没有排除已删除记录 | 删除后无法重新创建同集号或同顺序记录 | 使用 `deleted_at = 0` 条件唯一索引并覆盖删除后重建测试 |
| 内部顺序泄漏成工具契约 | handler 直接复用表模型或让模型提交 `sort_order` | 模型依赖脆弱数值位置，并可制造重复或断号 | schema/响应只暴露派生编号和 before/after 锚点；Service 只公开业务移动方法；快照与负向测试禁止 `sort_order` |
| 人物或地点删除留下场次失效链接 | 场次人物、正文人物或场景地点引用检查漏项 | 正常流程制造不可写的场次引用 | 场次引用查询与删除同事务；命中时返回 `entity_in_use`；小说及非场次引用继续沿用既有清理语义 |
| 写作流被建档打断 | 对话角色必须先有人物档案 | 作者绕开结构，把台词写进动作行 | 编辑器内就地快速建档并自动关联，入口放在插入对话的位置 |
| 当前 migration 已经发布 | 实施期间发布了 schema 32 或 16 | 同版本数据库不会执行新迁移 | 实施开始前再次核对正式 tag；若已发布则提升版本 |
| 小说 prompt 被顺手改坏 | 为剧本分支改 orchestrator 或片段时动了公共部分 | 所有存量小说用户的行为漂移 | 除 `/works/{work_id}/…` path schema 行外，novel 分支渲染结果用 golden 锁定；剧本内容只放进条件块与新片段 |
| 剧本资源挤占常驻 token | 把 `screenplay` 翻成 `hidden: false`，或忘了给 `pathSchemaBlock()` 传 `kind`，或往响应里塞字段契约 | 每轮 system prompt 变长，小说会话也受影响 | 保持 `hidden: true`，字段说明只放「剧本写作指南」；prompt golden 会在漏传 `kind` 时红 |
| 文本入口被重新引入 | 有人为了“省 token”给正文加一个接收文本的写入路径，或给渲染函数补一个反向解析 | 9.3 拒绝的一整套解析歧义全部回来，且与数组路径形成两套真源 | 渲染函数单向、无反向入口；验收有一条“仓库里没有文本到元素的解析函数”的检查 |
| 场景标题被写进正文 | 模型先验极强，倾向在正文首行写 slugline | 场景标题三个字段空着，作者在编辑器里看到的是一条动作描述 | 返回 `possible_scene_heading_in_content` warning 并指向三个字段；不因启发式误判阻止真实动作描写 |
| 门禁漏在某个工具上 | 新增工具或新增路径分支时忘记调门禁 | 剧本会话写坏章节表，或反之 | 门禁做成路径分支的统一入口；每个工具补一条负向测试 |
| 跨作品打开过多内容库 | 从 `/works` 根执行递归 Glob/Grep，或同一调用隐式遍历全部作品 | 一次调用打开用户全部作品的 SQLite 库并常驻缓存 | 读取权限不限制作品，但内容查询必须显式单个 `work_id`；多库递归返回 `work_id_required`；打开句柄数量断言 |
| 跨作品 lease 泄漏 | acquisition 尚未完成、工具中途失败，或 `AiClient.dispose()` 直接丢弃 manager | 内容库 `referenceCount` 长期不归零 | Manager 缓存 acquisition future、跟踪在途调用并幂等 dispose；完成、失败、取消和重复 dispose 都做 referenceCount 断言 |
| 跨作品误借当前季 | 读取另一部多季剧本时把当前编辑作品的 `currentSeasonId` 当默认值，或猜目标第一季 | ID 不存在，或静默读错一季 | 其他单季作品只解析唯一季；其他多季作品省略时返回 `season_id_required`；目标为当前作品才使用冻结 Current Season |
| overlay 漂移假报 | 序列化里留了 `name` 或 `updated_at` | 人物改个名或任何一次写入就让全部待审阅正文作废 | 规范形状定死字段闭集与顺序（9.4）；写入与回读共用同一个序列化函数；改名后不漂移的单元测试 |
| 跨库 ID 被直接复用 | 模型把源作品的 `character_id` 写进当前剧本 | 正文指向不存在的人物档案 | 跨作品响应显式带 `work_id`；当前库写入返回 `invalid_character_ref` 并提示先在当前作品建档 |
| 用户自建 SubAgent 带章节语义 | 用户把小说用的 SubAgent 拿到剧本工作区委派 | 委派任务反复调用被拒绝的章节路径 | 门禁错误带替代路径，模型可自纠；剧本分支的场景指引说明正文不委派 |

## 15. 已知妥协

1. 第一阶段的篇幅与时长是编辑器计算后的缓存，不是制片排版系统。需要支持正式打印或 PDF 交付时，再设计固定纸张、字体和分页规则。
2. 原作小说由主库 `novels.source_novel_id` 表达，第一期仅剧本改编可引用它；其他说明使用现有作品简介，不新增剧本专用备注字段。这个引用不追踪“哪一章改成了哪一场”——场次上没有 `source_chapter_id`。同人小说基于原作的引用留待后续设计；需要改编进度视图（“原著还有哪几章没排场”）时再加这一列，第一期不做。
3. 场号会随排序变化，不能用于制片通知单。进入拍摄管理范围后需要独立的锁定场号和修订色规则。
4. 现有整库备份会自然包含新表，但第一期没有行业剧本格式的导入导出。
5. 剧本工作区第一期不委派正文类 SubAgent，也没有写入后的审查闭环：审查类 SubAgent 的 prompt 与流程按章节设计，而它们是用户可编辑的库内记录，改 asset 兜不住已经改过副本的用户。剧本审查需要独立的 SubAgent 与 prompt，放到后续版本。
6. 剧本工作区不启用创作向导的初始化引导，用户自定义规则要自己写或由主控在对话中引导。创作向导的 references 按小说体裁组织，直接复用会给出错误的引导路径。
7. 场次的结构操作（建集、建节拍、用业务锚点移动、改出场人物、删除）不进待审阅改动列表，只有正文与梗概可以审阅退回。正文只显示最新整场预览并整体接受或退回，梗概保留文本 diff 与按行退回。AI 建场是例外：它产生场次级 `create` 条目，退回时软删除整场，不能留空壳。其余结构操作没有文本 diff 语义，冻结后与后续重排会互相打架；它们仍是软删除，但第一期没有面向用户的恢复入口。
8. 正文元素以行存储，一场戏 40–80 行，一季 12 集约 1.8 万行。这个量级 SQLite 无压力，但整场写入必须走 reconcile 而不是清空重插（5.9），实现上比一次性写 JSON 列复杂。这份复杂度换来的是 id 稳定、`character_id` 可 join、统计可 SQL 化和元素级写入。
9. 元素行只软删除，编辑抖动会留下废行。第一期不申请硬删除例外，靠 reconcile 把废行控制在净删除量。实测体积成问题时，正确做法是把该表加进 `StorageCleanupService` 的 retention 清理并单独取得用户确认。
10. 快捷动作只对场次梗概等纯文本字段开放，正文不接入：整段替换会破坏元素边界与角色引用。
11. 静态 tool description 里那两处由 schema 渲出的清单（`Read` 的可查询字段、`Write` 的 create-only 集合）会因为新增 `screenplay` 与 `works` 各多出一两行，小说会话也看得到。这一层裁不掉——AGENTS.md 第 13 条禁止按运行时状态改 tool schema。常驻 system prompt 侧的两层都收干净了：字段字典靠 `hidden: true` 压到零，路径清单靠工作区过滤（9.1）。
12. 电影不属于第一期。将来支持电影前，必须单独设计数据模型、创建流程、迁移与双端交互。
13. 跨作品第一期只读，可显式读取任一有效本地作品；`source_novel_id` 只是剧本改编对原作小说的标记。同人创作的来源引用不属于第一期。单次内容查询只进入一个 `work_id`，不支持从 `/works` 根递归遍历多库；跨作品写入和多作品关系图谱合并仍不支持。
14. 跨作品只用稳定 `work_id` 寻址，不支持标题别名。路径可读性略低，但作品改名和标题特殊字符不会让 AgentSkill 或历史消息里的地址失效。
15. 正文的审阅粒度是“场次 + AI session”：同一 session 的连续修改合并成一条待审阅卡，只显示该 session 最新写出的整场正文，不比较旧稿与新稿，也不能逐行或逐元素退回。不同 session 不合并身份，但同一场同时只允许一个 session 持有 active 正文条目；另一 session 必须等它接受、退回或被人工接管后再写。这个串行限制换来确定的整场退回语义（9.4）。若以后需要跨 session 并行或局部审阅，必须新增基于 `element_id` 的结构化合并模型，不能叠加整场快照或复用普通文本按行回退。
16. 正文对 AI 只有数组一种形态，比自由文本多约 50–80% 的 token。这是明知的取舍：换掉的是一整套文本解析器及其歧义规则，而那套规则集不收敛。若将来 token 成本成为主要约束，正确的省法是收窄读取范围（按元素区间分页、只读改动的场），不是重新引入文本入口。
17. 人物与地点只有被有效场次引用时才新增 `entity_in_use` 保护；关系、画布、子地点和地图等非场次引用继续沿用既有清理语义。这样避免剧本产生失效场次引用，同时不改变小说用户已经熟悉的删除行为。
18. AI 的正文与梗概提议在接受前已经写入当前剧本，编辑器和后续工具都会看到它；待审阅列表表示“可退回的已应用改动”，不是隔离预览。这样与现有 working overlay 一致，也让连续 AI 编辑基于同一份当前状态；代价是用户拒绝前，未接受文本会参与实时展示与派生统计。
19. 用户在带有待审阅 AI change 的场次内修改任一字段，第一次 600ms 防抖自动保存成功时会隐式接受该场先前的全部 AI change，包括 AI 所建场次本身。这样避免日后退回旧快照时覆盖人工成果，或退回建场时删除整场；代价是没有额外确认步骤，成功的自动保存本身就是接管信号。仅聚焦或保存失败不算接管，第一期不做三方合并。
20. 作品类型创建后不可修改，哪怕作品还没有正文。这样避免为“空作品”定义跨两套内容模型的清理与转换协议；代价是用户选错小说或剧本时只能重新创建作品。
21. 集或场次删除不联动清理待审阅 AI change，完全沿用章节删除的现状。目标资源消失后可能留下无法正常退回的 active 条目；第一期接受这个边缘状态，不为剧本单独引入跨 Service 编排，也不顺带修改小说。
22. 一部剧集的所有季共用一个 Work 和内容库。这样人物、地点、关系与资料天然共享，也避免跨作品维护“系列组”；代价是季不能拥有独立封面、权限、发布状态或文件生命周期。以后真有独立发行需求，应新增明确的发行实体，不能把 Season 偷换成 Work。
23. 单季作品的数据里仍有 Season，但 UI 与常规 AI 对话隐藏它；普通 AI 路径以回合冻结的当前季为默认，跨季才显式传 `season_id`。这减少大多数用户的操作成本，代价是工具执行必须维护稳定默认作用域，并在目标季消失时明确失败。
24. AI 可以直接删除集、场次和节拍，却不能删除 Season。这个权限边界并不完全对称，但 Season 的级联范围覆盖整季且第一期没有恢复入口，因此要求用户在显式管理界面查看范围并二次确认；AI 对话里的口头确认不能代替这一步。
25. AI 可以新增和编辑 Season，却不能重排 Season。季顺序是低频的全局结构，第一期保留给显式管理界面，避免为它增加一套 listing 级顺序替换协议；代价是用户要求 AI 调整季序时，AI 只能引导用户打开季管理。
26. 当前季、集和场是本机工作区状态，不是作品内容。它们按作品恢复但不跨设备同步，也不会写进内容库；不同设备打开同一作品可能停在不同季。这避免把个人导航选择误建模成共享业务事实，AI 只使用当前设备已经恢复并修复的选择。
27. 跨季移集省略 `episode_number` 时追加到目标季末尾，同时提供目标集号时在同一事务插入指定位置，并可一起更新标题、目标时长等字段。这个组合契约比固定追加复杂，但避免两次调用之间留下已移动、未重排的中间状态；移动仍保留集和全部子资源 ID，源季唯一集则拒绝移动。
28. AI 新增 Season 的限制是行为约束，不是工具层权限证明。Create handler 无法可靠判断一句自然语言是否构成用户授权，因此不增加 `confirmed` 一类自报字段；靠 orchestrator、剧本写作指南和场景评估约束。若以后真实误建率不可接受，应把 AI 建季整体关闭，而不是增加形式化但不可验证的布尔值。
29. 新增 Season 后编辑器立即进入它的第 1 集，但正在执行的 AI 回合仍冻结在创建前的当前季。这会让 UI 所见与该回合的省略参数默认值暂时不同；换来的是一个回合内寻址不漂移。Create 响应必须返回新季和 Episode 1 的稳定 ID，AI 在同回合继续新季任务时显式使用它们。
30. 其他作品没有当前会话的 Current Season。跨作品读取单季剧本仍可省略 `season_id`，多季剧本则必须先读 Seasons listing 再指定；这让同一个 Episode listing 路径在运行时可能要求补参，但避免静默猜季，且不需要按目标数据动态改变 schema。

<a id="revision-r1"></a>

## 16. R1：整集编辑与场标题节点

> 日期：2026-09-08
> 状态：修订建议，尚未实施；本次只更新方案。
> 目标：整集使用统一选区、剪贴板和撤销历史，场标题参与连续编辑，并能明确表达拆场、合场及场次删除。

### 16.1 评估结论与适用边界

**采用按集持久化的元素序列，新增 `scene_heading` 类型，保留独立场次实体。** `ScreenplaySceneElements` 增加 `episodeId`，`sceneId` 仍为非空；`sortOrder` 改为集内元素顺序。场标题与动作、人物提示和对白都是有稳定元素 ID 的真实记录。本文早先“标题只作编辑投影、不落元素表”的建议由本次修订取代。

这个结论经过三项取舍：

| 选择 | 收益与代价 | 决定 |
| --- | --- | --- |
| 每场独立编辑，只增加跨场高亮 | 改动少，但输入、剪切、撤销和保存仍有多个边界，需要逐项拼接 | 不采用 |
| 整集编辑文档，标题由场次表投影 | 可以跨场选择，但保存与撤销需要把两类对象重新组合；适合小范围交互修补 | 不采用 |
| 标题落为元素，统一使用集内节点顺序 | 正文与标题有一致的身份、排序和编辑入口；需要迁移字段、改造查询与跨场事务 | 采用；移除场次表的独立顺序，避免双重排序 |

**每个有效场次恰好有一个有效标题元素，其正文连续，场次列表顺序从标题元素顺序派生。** 空场只包含一个标题元素；标题字段可以未填，但场次身份必须存在。`episode_id` 决定文档归属，`scene_id` 显式记录业务归属，两者不是独立编辑选项。保留 `scene_id` 让单场读取、人物关联和 AI 单场写入继续精确寻址；结构命令负责让它与标题边界保持一致。

最小选项是让标题可选、可复制，拦截包含标题的写入。它能改善跨场阅读操作，但仍不能自然地剪切和替换一段跨场正文。本修订选择完整的结构命令，最小选项不作为最终交付，也不拆成一个等待后续才能可编辑的阶段。

不增加表、配置开关或第三方依赖。元素表增加集归属和标题专用字段，场次表移除被迁出的字段；新增一种编辑文档模型和一个人工保存 Orchestrator。普通标题字段和正文改动都写元素表，拆合场仍会改变场次及关联，不能承诺所有操作只写一张表。统一持久化序列减少的是文档组合与身份映射成本，不替代结构事务。

### 16.2 Laper 证据与本项目现状

Laper 的浏览器实测显示：整集编辑器的顶层节点包含 `scene_heading`、`action`、`character`、`dialogue` 等类型；场标题与正文平级，节点有独立 `id`，场标题可以带 `sceneId`、地点及时间属性。此前用鼠标选中过“动作 → 下一场标题 → 动作”，编辑器返回跨三个顶层节点的同一个选区，正文未改变。其前端代码还显示每集有 `plateScript` 与独立 `scenes` 集合，但本地快照和增量以项目为单位保存；“每集一份文档”不等于“服务端每集存一张表或一条记录”。

这里只借鉴平级节点和文档级选区。Laper 的合场、结构撤销及服务端数据库没有实测证据，下面的规则是 Reveric 的设计决定，不能标为竞品已验证行为。

截至本修订，Reveric 已有：

- `screenplay_scenes` 保存集归属、顺序、标题字段、梗概、节拍和状态。
- `screenplay_scene_elements` 保存有稳定 ID 的正文行，按 `scene_id + sort_order` 排列。
- `ScreenplayEditingController` 已实现整场文本投影、跨元素替换、撤销与输入法保护；每场分别实例化控制器和 `ScreenplayEditingScope`，因此选区无法自然跨场。
- `reconcileElements()` 只接受属于当前场的既有元素 ID。移动正文到另一场不能直接循环调用这个单场方法。
- 桌面及移动编辑器调用 `commitManualSave(manualChangeIds: const [], ...)`，而该方法在 ID 列表为空时直接返回。第 9.4 节描述的人工接管规则尚不能由这些调用保证；现有 overlay 测试传入了真实人工 change ID，不能证明编辑器入口已接通。

### 16.3 编辑节点与存储映射

增加共享的 `ScreenplayDocument` 模型，直接持有当前集按顺序读取的元素；`ScreenplayElementType` 在现有七类上增加 `scene_heading`。这是状态分类枚举，Dart 值、落库值统一使用 `snake_case`，不使用 `sceneHeading`。表名暂保留 `screenplay_scene_elements`，避免把物理改名与这次模型调整绑定；名称不再决定排序作用域。

| 内容 | 编辑文档中的身份 | 保存方式 |
| --- | --- | --- |
| 场标题节点 | 独立且稳定的元素 ID；`scene_id` 指向另一条场次记录 | 与正文存于同表，保存结构化标题字段，不保存完整标题字符串 |
| 既有正文节点 | 稳定元素 ID 对应的编辑键 | 更新原元素记录；跨场移动保留 ID |
| 新场与新元素 | 编辑会话内稳定的草稿键 | 保存返回正式 ID 映射，后续编辑及撤销沿用原键 |
| 人物、地点名称与派生场号 | 展示数据，不构成节点身份 | 从实体和标题元素顺序解析，改名不产生正文修改 |

场标题编辑仍提供内外景、地点和时间字段。它是参与选区的结构对象，不把整句标题当自由文本解析；在时间字段输入只修改该元素的 `time_label`，不会改写场次身份。出场人物行是辅助展示，不新增 `cast` 元素，也不混入复制的正文。

编辑文档中的排列如下。这里只描述对象关系，不规定类的实现语法：

```text
当前集文档
  e1  scene_heading  episode=E  scene=A  order=0
  e2  action         episode=E  scene=A  order=1
  e3  character      episode=E  scene=A  order=2
  e4  dialogue       episode=E  scene=A  order=3
  e5  scene_heading  episode=E  scene=B  order=4
  e6  action         episode=E  scene=B  order=5

界面行及标题字段
          ↓ 编辑命令
共享文档控制器（节点、选区、操作历史）
          ↓ 受影响场次的变更集
人工保存 Orchestrator
          ├─ ScreenplayService → 内容库场次、元素及关联
          └─ WorkingOverlayService → AI 改动接管
          ↓ 提交结果与 ID 映射
共享文档控制器
```

文档范围由宿主传入：桌面剧本区域是当前整集，移动单场入口是该场。每个范围仅有一个控制器、一个选区作用域和一个串行保存队列。场次 Widget 不再持有第二套正文状态。

#### 元素字段与类型约束

| 字段 | 约束与用途 |
| --- | --- |
| `id` | 主键，所有类型统一使用独立元素 ID；标题 ID 不等于场次 ID |
| `episode_id` | 新增非空列，所属整集文档，必须等于所关联场次的 `episode_id` |
| `scene_id` | 保留非空列，包含标题自身在内的每行都关联有效场次 |
| `sort_order` | 保留列名，语义改为有效元素的集内位置，标题占一个位置；不再从每场的 0 重新计数 |
| `type` | `scene_heading`、`action`、`character`、`parenthetical`、`dialogue`、`transition`、`subtitle`、`note` |
| `text` | 正文文本；标题和人物提示恒为空串，不缓存地点名、人名或完整标题 |
| `character_id`、`extension` | 保持仅人物提示可用；标题不可携带这两个字段 |
| `interior_exterior` | 新增可空列，仅标题使用，允许 `interior`、`exterior` 或 NULL |
| `location_id` | 新增可空列，仅标题使用，非空时关联同内容库的有效地点 |
| `time_label` | 新增可空列；标题必须为字符串，允许空串，其他类型必须为 NULL |
| 创建、更新、删除时间 | 保持现有规则，全部业务删除使用软删除 |

用 `time_label` 的 NULL 与空串区分“不适用”与“标题尚未填写”，不为每种类型另加一份 JSON 载荷。标题没有填写地点和时间仍是合法空场，ID、集和场次归属不能缺失。

| 元素类型 | 必需与允许字段 | 结构作用 |
| --- | --- | --- |
| `scene_heading` | 允许三个标题字段；`text = ''`、`character_id = NULL`、`extension = ''` | 开始一场，重置对话角色上下文 |
| `character` | 有效 `character_id`，可选 `extension`；`text = ''` | 开始对话块，所有标题字段为 NULL |
| `dialogue`、`parenthetical` | `text` 可为空；人物引用和标题字段为空 | 继承本场当前对话块的人物，不另存 `character_id` |
| `action`、`transition`、`subtitle`、`note` | `text` 可为空；人物引用和标题字段为空 | 结束当前对话块；`note` 不进成稿统计 |

Dart 模型与写入服务校验类型和字段配对。校验原始输入后再做 trim 等规范化，不能把非法 `character_id`、`extension` 或标题字段先清空，再把请求当成合法写入。

#### 场次表与排序真源

`screenplay_scenes` 保留 `id`、`screenplay_id`、`episode_id`、`beat_id`、`synopsis`、`stage`、派生统计及时间戳。`interior_exterior`、`location_id`、`time_label` 迁入标题元素后删除旧列；`sort_order` 及其唯一索引也删除。标题字段不双写，场次表不保留顺序缓存。

场次列表查询将有效场次与其唯一有效标题元素关联，按标题的 `sort_order` 排列，派生 `scene_number`。仍可只取标题行及统计而不加载正文文本，但第 4 节“列表不读取任何元素行”的限制需改成“不读取正文元素”。节拍板、大纲、矩阵和移动端标题都复用此查询。

地点改名仍由 `locations` 实时传播；地点删除的占用检查改查有效标题元素与有效场次的关联，不再查旧场次地点列。只更新标题时不重算正文统计；正文统计显式排除 `scene_heading` 和 `note`。

采用以下索引，旧场内排序索引在迁移时替换：

- `screenplay_scene_elements_by_episode_id_sort_order_u`：集内有效元素位置唯一，条件为 `deleted_at = 0`。
- `screenplay_scene_elements_by_scene_id_type_u`：每场最多一个有效标题，条件为 `deleted_at = 0 AND type = 'scene_heading'`。
- `screenplay_scene_elements_by_scene_id_sort_order`：支持含标题的单场范围读取。
- `screenplay_scene_elements_by_character_id`：保留人物引用检查。
- `screenplay_scene_elements_by_location_id`：新增地点引用检查。

“至少一个标题”和连续归属由事务内序列校验保证：非空文档首行必须为标题；每遇到标题切换当前 `scene_id`，后续行的 `scene_id` 必须与其一致；同一场不能再次出现，元素的集必须与场次一致。唯一索引不能独自证明这些跨行不变量。若数据库中已有损坏关系，明确报错，不按最近标题在读取时偷偷改写归属。

每次结构命令显式产生需要更新的 `scene_id`，保存时再验证边界一致性。既不从文字猜场次，也不允许调用方分别改 `episode_id` 和 `scene_id` 制造不一致。完整跨集移动必须在一个事务中更新场次的集、整段元素的集及两边排序。

#### 类型转换与已有调用方

标题使用同一个元素模型，但转换不是普通的枚举赋值。普通元素类型轮转排除 `scene_heading`；“场次”按钮执行拆场。标题菜单中的合场或删除按 16.5 执行，不允许将标题直接改成 `action` 后留下无标题场次。

在普通正文行使用“场次”时按当前光标拆分，不把整行文字猜成地点和时间；新标题后的原正文保留。单独改变已有元素的类型不会改变其 ID，拆场则创建新场和新标题 ID。

共享读模型将 `episodeId`、`sceneId` 和标题字段纳入元素记录；持久化 `ScreenplayElementType` 与 AI 正文允许类型不再是同一个集合。原有 AI `screenplay/scenes/{scene_id}/elements` 继续只表示该场七类正文：读取、Grep、正文统计、overlay 序列化和整场替换均排除标题；该路径提交 `scene_heading` 明确拒绝，不能因为它已是有效数据库枚举就放行。旧正文快照退回只替换标题后的该场区间，不删除标题，不采用场内下标直接覆写集内顺序。

已有场次字段接口继续接收内外景、地点和时间，由 `ScreenplayService` 定位唯一标题元素写入；场次摘要仍返回这些字段，因此 AI 无需为本次内部模型迁移改用新的路径。新建场次接口在一个事务中创建场次、标题和可选初始正文。普通 AI 单场写入不得接收外场元素 ID；人工文档命令使用单独的批量校验入口。

接口只提交稳定元素身份、目标内容及 before/after 锚点；集内 `sort_order` 是 DAO 内部事实。普通单场替换长度改变时，DAO 同事务重排必要的后续元素，不能只重排这一场导致全局位置冲突。

### 16.4 选区、输入与查找

选区端点使用稳定节点键和节点内偏移；既有字符串偏移只作为与输入框、查找工具交互的投影。场标题与人物提示在投影中是不可拆分对象，有前后两个位置；文字节点保留真实字符偏移。改变场号、地点名或人物名时，不因展示字符串长度变化把光标映射到别的段落。

- 拖过标题时显示整个标题的选中状态；从标题文字区拖动也可发起选择，字段按钮和菜单保留点击行为。
- 跨行之后由文档作用域接管鼠标选区；所有正文行和标题节点注册到同一作用域。单个输入框内部继续使用现有输入和选词行为。
- 复制将选区内的标题和人物引用渲染为可读文字，内部对象占位符不进入剪贴板。选区中未出现的出场人物行不追加到复制结果。
- 本修订的粘贴保持纯文本语义，不承诺保留跨场复制的结构。粘贴出的 `INT.` 或“内景”不会自动建场；需要标题时使用“场次”命令。结构化剪贴板另行设计，不能用自由文本启发式恢复场次。
- 查找可以命中标题的展示文字，但标题匹配只导航并打开相应字段，不参加正文替换。替换全部只处理可编辑正文匹配，明确显示跳过的结构匹配数量，全部有效替换形成一次操作。
- 中文输入法组词期间不转换节点、不拆合场、不提交未完成的组合文本；组词完成后再形成文档操作。
- 对话角色上下文在每个场标题处重置。插入标题或删除选区不能使下一场对白借用上一场的人物提示。

### 16.5 场标题对应的结构操作

标题进入文档不等于允许无约束地删除业务结构。下表定义命令的目标状态，所有命令先验证，再一次应用；不静默跳过标题、只修改选区中的部分正文。

| 用户动作 | 目标行为 |
| --- | --- |
| 修改标题字段 | 更新原标题元素的结构字段，标题与场次 ID 均不变，地点选择沿用有效实体与就地建档规则 |
| 在正文光标处插入场标题 | 拆分当前场：前半留在原场，后半移入其后新建场次；新场有独立 ID |
| 在标题字段按普通 Enter | 结束字段编辑或进入正文，不隐式创建另一场 |
| 删除 B 场标题，前面有 A 场 | 将 B 正文接到 A 末尾，移走正文后软删除 B；标题 A 保留 |
| 在 B 场开头退格，跨到标题边界 | 发起与删除 B 标题相同的合场命令，不能只让光标跳过结构边界 |
| 只删除整集第一个标题 | 保留该标题并提示不能留下无所属场次的正文；可用“删除场次”删除其完整范围 |
| 从 A 正文中选到 C 正文中并删除或替换 | 保留 A 前缀和 C 后缀，中间被选正文删除，替换文字插在 A 的选区起点；C 后缀归 A，选中的中间标题对应场次退出有效列表 |
| 从某场标题选到下一场标题之前 | 删除完整场次，不把上一场合进来；选区终点处未选中的标题保留 |
| 全选整集后删除 | 明确确认后删除全部场次；集仍存在，显示空文档。继续输入会创建首场和动作节点 |
| 拖动场标题的排序手柄 | 移动整场及其正文，映射为 before/after 场次命令；不单独移动一个标题去重新解释两侧正文 |

拆场默认值固定：新场继承当前场的内外景、地点、时间与同集节拍，状态为 `draft`，梗概为空；出场人物从移入正文的角色引用生成，不复制原场无台词的出场分配。原场已有出场分配保留。界面在建场处展示可编辑的新标题字段，不复制标题字符串。

如果拆分点位于一个对话块内部，新场首段需要人物提示，命令会复制最近的人物提示为一个新元素，复用其 `character_id` 与 `extension`；被移动的既有正文元素 ID 不变。不能复制原人物提示的元素 ID，也不能把这一步留给失败后的补救。

合场的目标场保留自己的标题、节拍、梗概和状态；被吸收场的这些值保留在软删除记录中，不自动拼接梗概或改绑节拍。目标场出场人物取原分配与被吸收场分配的去重并集，再补入保留正文需要的角色。完全删除、没有正文并入目标场的中间场次不贡献人物分配。

以退出有效列表的场次为证据的关系清空 `scene_id`，关系本身保留，不能自动把证据改指目标场。现有产品没有分镜表，本修订不增加分镜迁移逻辑。

**删除标题、跨场剪切与替换都展示一次结构影响确认**：哪些场合并或删除、哪场保留、非空梗概及不同节拍是否将归档、多少关系证据会清空。普通场内文字删除不增加确认。取消时正文、选区和剪贴板均保持原状；确认过程中受影响数据改变则作废本次计划，重新计算后再确认。

人物提示被删除而其后对白仍保留时，先计算完整结果并沿用对话块保护规则；若需要扩大删除范围，必须在同一次影响确认中列出。不得生成无法通过角色归属校验的半个操作。

### 16.6 保存、并发与撤销

新增一个短生命周期的人工保存 Orchestrator，以方法参数接收文档变更、当前内容库及相关服务。文档控制器只提交变更意图；数据库事务与跨服务顺序不放进 Page 或 Widget。

保存顺序如下：

1. 在同一内容库事务中读取受影响场次、正文、排序锚点及关联，校验所属集和变更基线。普通文字改动只比较其涉及场次；拆合场还比较受影响结构和关系。只比较业务字段与稳定 ID，不拿地点显示名、统计或更新时间当正文版本。
2. 接管本次实际改变场次的 active AI change，包括这些场次的 `create`、`elements` 与 `synopsis`，避免旧提议随后退回覆盖人工成果。仅加载、选择和复制不接管，也不接受整集其他场次的提议。
3. 按稳定 ID 保存新增、更新、跨场移动及软删除；同步更新场次顺序、出场关联、证据引用与内容库统计。
4. 以上步骤全部成功后提交事务，返回正式 ID 映射、受影响场次的最终值和结构操作的逆向快照。失败时 AI 接管状态也回滚。
5. 主库作品字数在内容库提交后单独同步；失败只提示统计待更新，不能重放已经成功的拆合场操作。

这里明确修订第 9.4 节对极端并发的“后完成者生效”妥协：人工文档写入若基线已变，返回 `stale_screenplay_edit`，保留本地草稿，不用旧整场数组覆盖新值。检查与写入在一个内容库事务中完成，不新增 revision 列或分布式锁，也不改变 AI 工具 schema。失败后不自动三方合并；用户可复制保留草稿，或明确放弃该草稿后加载最新内容。

批量 DAO 对本次涉及的全部场次统一做 ID 归属检查，允许现有元素在范围内修改 `scene_id`，未知 ID、重复 ID 或未经跨集移动命令声明的外集元素仍拒绝。先安排临时顺序，再更新归属与最终顺序，避免集内有效元素唯一索引碰撞；临时值由查询到的占用范围计算，不能假定固定大数永不冲突。合场时被保留的正文先移走，被吸收场的标题软删除，之后才清理退出列表的场次，不能直接套用旧的整场级联方法把保留正文一起删除。

现有 `commitManualSave()` 的空 ID 早退需要在这条保存链路中解决：为人工保存提供显式、限定资源范围的 AI 接管入口，内部复用既有提交逻辑，并能参加外层内容库事务；不为触发接管而伪造空白人工 change。原方法和小说调用方的行为保持原状。正文人工 change 如需沿用既有历史机制，传入真实 ID；结构命令的撤销由本节的会话历史负责，不伪装成 `elements` JSON。

撤销规则：

- 一次用户操作对应一条文档历史，保存防抖不能把两个独立结构命令合成一条。文本连续输入仍沿用现有合并策略。
- 拆合场快照覆盖标题元素与正文的原 ID、字段、集内顺序及场次归属，场次资料、人物关联、被清空的证据和操作前选区。只存本次涉及的数据，不为每次按键复制整集所有关联。
- 尚未保存时撤销只取消草稿；已保存时撤销通过相同事务入口恢复原 ID、排序、软删除状态及关系。重做复用已分配的 ID。
- 已被人工接管的 AI change 不因撤销再次变为 active。撤销恢复内容，不恢复旧提议对新内容的控制权。
- 外部更新改变了操作涉及的数据时，该旧结构操作不能直接撤销覆盖新值；明确提示历史失效。地点或人物仅改显示名不使历史失效。
- 这是当前编辑会话的撤销能力，不新增跨启动的结构历史、回收站或任意软删除记录恢复入口。

保存队列以文档范围为单位串行执行。保存期间的新编辑保留为更新的草稿；旧结果只推进已保存基线和身份映射，不替换最新文档或清空撤销栈。离开文档前 flush，失败保留页面和草稿。

### 16.7 双端范围与性能

桌面当前集的正文使用统一文档；左侧场次导航按稳定 `sceneId` 查找其标题元素 ID。场号与场次板统一从有效标题元素的集内顺序派生。

移动端保留“场次列表 → 单场编辑”的现有导航，但使用同一文档模型、命令校验和保存 Orchestrator。单场入口内插入标题会把本次文档范围扩为拆出的连续两场，在当前页面继续编辑；不能只保存新场却隐藏它。已显示的连续场次之间支持同样的选择和合场规则。未加载的前后场不会因边界退格被隐式合并，需从明确场次操作入口选择目标。平板使用整集视图时与桌面行为一致。这是范围差异，不维护另一套场标题语义。

每集约 30 场、每场 40 至 80 个正文元素，加上标题约有 1,230 至 2,430 个节点。统一控制器不意味着每次输入重建全部行：正文行按稳定键订阅自身内容，选区只刷新涉及行；普通文本及标题字段保存只更新实际变化的元素，角色和地点继续批量读取。插入、删除和移动可能更新后续行的集内顺序，这是连续整数排序的明确成本；不因此重写未变正文或生成新 ID。节点偏移索引避免在每次鼠标移动时重算整份文档。页面刷新和自身保存回流保留选择、滚动与当前数据，不切回整页 loading。

### 16.8 对原方案的明确修订

| 原章节 | R1 的取代或保留 |
| --- | --- |
| 4 核心原则、5.9、9.3：“场景标题不是元素” | 改为真实的 `scene_heading` 元素；仅 AI 旧单场正文数组继续排除标题 |
| 5.6 场次及 5.9 元素表 | 元素新增 `episode_id` 与标题字段；标题字段从场次表迁出，场次顺序改从标题元素派生 |
| 4 列表不读取元素行、5.6 地点占用检查 | 列表读取标题元素，不加载普通正文；地点占用检查改查标题元素 |
| 6.2 按场编辑会话、6.3 切换前 flush 当前场 | 桌面及连续场次编辑使用文档范围的会话和保存队列，离开前 flush 整个当前范围 |
| 6.2 元素 ID 只能属于当前场 | 原单场接口保留约束；新增文档事务入口允许校验范围内的跨场迁移 |
| 6.4 删除不编排 working overlay | 普通旧删除入口维持原契约；本修订的人工结构编辑必须在事务内接管受影响场次的 AI change |
| 7、8 桌面与移动正文交互 | 替换为 16.4、16.5、16.7 的统一命令和不同文档范围 |
| 9.3 AI 数组、9.4 场次级审阅 | AI 继续按场次及七类正文路径读写，schema 静态；数据库完整元素与旧正文数组使用显式不同的查询和允许类型 |
| 9.4 人工保存接管、无并发基线检查 | 补齐真实编辑器调用链，新增人工文档事务的基线比较，见 16.6 |
| 15 无结构操作撤销与恢复入口 | 当前会话支持结构撤销；仍无跨启动结构历史与通用回收站 |

本修订主动调整存储真源：标题字段和顺序都由元素表拥有。`scene_id` 的保留增加了一项边界一致性校验，换来稳定的业务寻址和单场查询；不得为了省掉这项校验把它改为可空字段，或在读取时根据相邻文字猜测归属。

### 16.9 实施落点与交付方式

这是一项超过 8 个文件的编辑链路改动，新增一个 Orchestrator，不新增常驻 Service。模型、界面、保存及撤销作为同一项功能交付；内部可分提交，但不把“能选不能保存”的中间状态视为可发布阶段。

| 文件或区域 | 责任 |
| --- | --- |
| 新增 `lib/shared/models/screenplay_document.dart` | 整集元素文档、稳定位置、结构命令的变更与逆向快照 |
| `lib/shared/models/screenplay_element.dart`、`screenplay_element_render.dart` | 新增 `scene_heading` 与集、场次归属和标题字段；补字段配对校验、渲染及旧正文序列化过滤 |
| `lib/shared/database/novel_content_database.dart`、`novel_content_database_migrations.dart` | 调整元素列、迁移标题字段及排序，替换索引，检查历史表重建 |
| `lib/shared/models/screenplay_editing.dart` | 保留元素身份与对话块规则，供拆场和文档编辑共用 |
| `lib/shared/widgets/screenplay/editing_controller.dart` | 从元素列表升级到文档节点，统一命令、选区和会话撤销 |
| `editing_scope.dart`、`editing_row.dart` 同目录 | 注册标题与正文节点，接线键鼠、查找与复制 |
| `lib/desktop/features/screenplay/script.dart`、`script_elements.dart` | 整集宿主、标题字段及命令入口，移除每场独立控制器和保存队列 |
| `lib/mobile/features/screenplay/scene_editor.dart`、`script_page.dart` | 单场及拆场后的连续范围，退出 flush 和触摸操作 |
| 新增 `lib/shared/services/screenplay_edit_orchestrator.dart` | 人工编辑的事务、基线检查与 AI 接管编排 |
| `lib/shared/services/screenplay_service.dart`、`lib/shared/database/novel_content_daos/screenplay_dao.dart` | 批量校验、元素迁移、拆合场、逆向恢复；拆出可参加外层事务且不提前同步主库的内部写入步骤 |
| `lib/shared/services/scene_save_coordinator.dart` | 将既有串行机制用于文档范围，名称与调用方同步调整，避免同时保留两套队列 |
| `lib/shared/services/working_overlay.dart` | 增加事务内、限定场次范围的人工接管入口，保留既有小说语义 |
| `lib/shared/services/ai/tools_screenplay.dart`、相关场次及地点查询调用方 | 分开完整文档与旧七类正文契约，场次标题字段改写真实标题元素，保留地点引用保护 |
| `locale_keys.dart` 与双语 `screenplay.json` | 结构影响确认、基线冲突、历史失效及查找限制文案 |

实现不新增 REST API、AI 工具名、运行开关或凭证要求。AI 的旧单场 Service 接口继续可用；新增文档入口不接受数据库数值顺序作为公共参数。

#### 数据迁移与回退

这次需要正式的数据迁移设计，旧客户端不能直接读取新结构。实施时核对 schema 发布状态：若受影响版本未发布，按项目总规则合并进未发布 migration，并通过 SQLite 技能对具体开发库做一次明确升级；已发布则提升内容库 schema 版本并新增迁移。当前代码版本号不能作为“未发布”的证据。本次不修改任何开发库，也不预设最终版本号。

迁移按以下顺序在事务内执行：

1. 先检查所有元素的 `scene_id` 能否找到场次、场次能否找到集，包括软删除行；孤儿数据使迁移明确失败并回滚，不能静默丢弃或猜测归属。
2. 为所有已有元素从场次回填 `episode_id`，保留元素 ID、文本、人物、扩展及删除状态。场次与元素有效状态矛盾时报告数据问题，不把异常行直接投入新文档。
3. 每个场次创建一个标题元素，复制原三个标题字段。有效场次创建有效标题；软删除场次创建同删除状态的归档标题，以保留其历史字段。标题生成新元素 ID，场次 ID 不变。
4. 对每集按原有效场次顺序，再按原场内元素顺序展开：先标题、后正文，生成连续的集内顺序。归档行不参与有效序列，其原顺序仅供保留历史，不影响唯一索引。
5. 校验正文行数量与 ID、标题字段、单场内容及引用均一致，验证每场一标题、集场一致和场次块连续；然后移除场次标题列及独立顺序、替换元素索引，并由 Typed DAO 读取迁移结果。迁移不更新业务正文统计，因为标题不计入正文。
6. 搜索涉及两张表的全部历史 `TableMigration` 和手写复制路径，保证受支持旧 schema 可直接升级；字段复制必须显式列名。新建库直接建立最终结构，不再创建旧列后补改。

场次字段路径及旧正文 overlay JSON 不变，因此已有正文提议无须改写；但每个回读、应用和退回分支都必须经过新 DAO 映射。旧客户端直接访问旧列的方式不兼容，需要同步升级两端代码。

迁移失败整次回滚。升级前保留数据库备份；升级后回退旧客户端需恢复升级前备份，不能只回退代码。备份之后的新编辑不会自动带回旧结构。本修订不加入长期双写、运行时补列或自动降级转换层。

### 16.10 验收与本次验证状态

| 验收场景 | 必须成立 |
| --- | --- |
| 跨场选区 | 正反向鼠标拖选、Shift 扩选及边缘自动滚动经过标题，复制得到标题和正文，不含占位符 |
| 插入标题 | 中间、首尾、空场均可拆分；既有正文 ID 保留；对话中拆场补正确人物提示 |
| 合场与删除 | 两场及多场选区按 16.5 处理，取消无修改；目标场字段、人物并集、归档场和关系证据结果准确 |
| 首标题与全选 | 不留下无归属正文；全选删除保留集，继续输入可建立首场 |
| 撤销与重做 | 保存前后均一次恢复完整结构和选区，人物与证据同时恢复，不生成重复 ID |
| 原子性 | 任一场校验或写入失败，正文、排序、关系、统计和 AI 接管全部回滚 |
| 保存竞争 | 旧保存回流不覆盖新输入；第二次编辑能继续保存；外部变更导致基线冲突时不覆盖 |
| AI 边界 | 使用真实编辑器保存入口测试接管；只处理脏场次，失败和只选择不接受 AI 提议 |
| 名称变化 | 人物、地点改名及派生场号变化不写正文，不错位选区，不制造历史漂移 |
| 双端输入 | 中文组词、选词、软换行及移动端拆场后的连续编辑正确 |
| 规模 | 约 2,400 个节点下实测拖选、输入与保存，确认未整集重建或全量重写；记录设备和测量结果 |
| 数据结构 | 所有元素有正确集和场次；每场一标题；有效集内顺序唯一、场次块连续；旧场次标题及排序列已移除 |
| 类型约束 | 七类正文不能携带标题字段；标题不能携带正文、人名引用或扩展；未知类型和非法字段不得靠清空后通过 |
| 兼容性 | 原单场 AI 写入仍拒绝外场元素和标题类型，正文快照退回保留标题；小说路径与旧数组快照不变 |
| 迁移 | 空场、多集、软删除行及跨版本升级保留原 ID、文字与标题值；异常归属中止迁移，Typed DAO 可读取最终结构 |
| 排序成本 | 普通打字不改顺序；结构操作只改必要顺序，不重写其他场正文；单场替换、整场重排和跨集移动均无位置冲突 |

扩展现有控制器、Service、overlay、migration 和桌面正文测试；为移动场标题和整集文档补对应测试。测试应验证操作结果及失败后的数据，不能仅验证控制器字段。结构命令的确认到提交之间还需覆盖数据发生变化的情况。

实施后的基础验证命令如下，Flutter 测试串行运行，Widget 测试按项目规则设置超时：

```bash
fvm flutter test test/shared/models/screenplay_editing_test.dart test/shared/widgets/screenplay/editing_controller_test.dart
fvm flutter test test/shared/services/screenplay_service_test.dart test/shared/services/working_overlay_screenplay_test.dart
fvm flutter test --timeout 2m test/desktop/features/screenplay/script_region_test.dart
fvm flutter test test/shared/services/ai/tools_screenplay_test.dart
fvm flutter test test/shared/database/screenplay_migration_test.dart
```

新增文档模型、Orchestrator 和移动交互测试也必须加入实施验证，不能以现有测试通过替代。实际修改 Drift schema 后必须使用 `make codegen` 或 `fvm flutter pub run build_runner build` 生成并检查 diff，再执行上述测试及受影响目录静态分析。

本次仅做代码与方案的只读核对，并追加 R1；没有实现上述功能，也没有运行这些 Flutter 验证命令。Laper 已验证范围只限 16.2 列出的节点与选区证据。
