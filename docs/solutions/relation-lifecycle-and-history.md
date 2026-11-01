# 实体关系当前状态与变化历史

> 状态：完整方案，业务代码尚未实施。已确认的产品规则见 ADR 0037、0038、0039；本文补齐实现契约、迁移、接入点和验收。
>
> 编写基线：2026-09-24，内容库 schema 19。涉及数据库、共享服务、AI 工具、桌面和移动端 UI、内置技能，超过 8 个文件，作为一个完整功能交付。
>
> 决策依据：[展示与查询](../adr/0037-relation-search-matches-current-state-only.md)、[关系生命周期](../adr/0038-relation-transitions-preserve-record-identity.md)、[快照存储](../adr/0039-relation-history-uses-structured-snapshots.md)、[领域术语](../../CONTEXT.md)。

## 1. 背景

### 现状

- `EntityRelations` 已有实体端点、单一 `relation_type`、`proof`、互斥的 `chapter_id / scene_id`、排序与时间戳；没有关系状态、变化历史和软删除列。
- `tools_graph.dart` 负责 Create 关系与 GraphSearch。`tools.dart` 的资源契约只开放关系的 Read、Create、Remove，没有 Write；`tools_read.dart` 明确拒绝关系字段路径。
- `EntityRelationsService.updateRelation()` 已支持修改类型、properties 和证据位置，但没有快照，也不能更新 proof。手动编辑及证据引用清理存在不同写入路径。
- GraphSearch 从两端展开关系，当前没有生效状态过滤。`Read /relations` 返回当前记录的完整字段，支持类型、端点和证据位置过滤。
- 桌面选中人物后展示关系列表与详情；移动端点击关系条目直接打开编辑对话框。两端都使用共享图谱数据，尚无历史区域。
- `relations.md` 要求修改时 Remove 再 Create，小说和剧本事实提取附件还要求移除失效关系。服务中的 Remove 目前是物理删除。

### 问题

朋友变敌人、情侣分手后复合，都需要保留经历。直接更新类型丢失过去；删建会换 ID、丢记录，并可能在两次调用之间失败。把所有旧状态作为独立边返回，又会让 AI 与用户把历史关系当作当前关系。

本次需求是查询当前关系、按需查看单条历史，不需要按历史类型搜索，也不需要重建任意章节时刻的关系图。

### 约束

- 推荐两个实体复用一条关系记录，每条只有一个主要类型；数据库不加端点唯一约束，不清理、合并或任意选取存量重复记录。
- 两端身份与方向保持稳定。对称关系查重时看两个方向；有向关系不自动交换端点或反转含义。
- `Read /relations` 必须包含已结束记录；只有 GraphSearch 和默认图谱排除它们。
- 历史只记真实剧情变化，不增加纠错事件。字段录错用 Edit 修正当前与最新快照；整次变化误录用 Remove 将快照从 change_logs 数组中实际移除。
- 按本次用户明确确认，关系行与误录快照采用硬删除，范围记录于 [数据删除规则](../../.agents/rules/data-deletion.md) 的关系例外。“已结束”仍用 ended 保留，不能通过删除表达剧情终止。
- 不把业务判断放进 schemaless properties；当前状态使用列，history 使用有明确模型的 JSON。
- 不修改 REST API、后端、平台权限，不增加依赖或新的 AI 工具名称。桌面与移动端同步交付。
- 本文中的工具 description 是供实施审批的具体草案，本次只写方案，未修改运行时文案。

## 2. 目标

1. 朋友 → 敌人 → 朋友沿用同一 relation ID，并保留完整变化。
2. 分手但没有后续关系时保留 lover 类型、状态设为 ended；复合恢复同一记录为 active。
3. GraphSearch 只返回并沿 active 边展开；Read 可读取 active 和 ended，均不匹配 change_logs 内的历史类型。
4. 用户可以从人物关系列表找到已结束记录，查看当前信息、展开单条历史、删除误录。
5. 删除最新变化恢复前一个有效状态；删除较早变化保留后续真实变化及当前状态。
6. 所有写入入口保持当前列与最新有效快照一致，操作失败不留下半写入状态。
7. 旧库升级保留关系 ID、证据、顺序和重复记录，不伪造过去的演变。
8. Edit 可修正当前类型、状态和依据，未涉及字段保留；同步最新快照但不增加历史，无历史旧记录也不因修正生成 baseline。

非目标：历史检索、时间点图谱、全书故事时间轴、多主类型关系、强制唯一或自动合并、自动批量清理历史、批量推断旧关系是否结束。

| 成功信号 | 验证方式 |
|---|---|
| 同一记录完成转变、结束、恢复 | 服务与工具测试，断言 ID 不变 |
| 已结束边不能带出二度结果 | GraphSearch 回归测试 |
| 无生效边的人物仍能打开历史 | 桌面、移动端手工验收 |
| 两种历史删除语义正确 | 快照序列、当前列与重启后读取测试 |
| 旧数据未被归并或改写 | 冻结旧结构的迁移测试 |

## 3. User Stories

- 作为作者，我希望打开人物关系时先看到当前情况，需要时再展开分手、反目、和解等经历。
- 作为作者，我希望删除 AI 误记的剧情变化后，当前关系与剩余历史一致，而不是留下虚假的纠错剧情。
- 作为 AI，我需要先读取已有关系，包括已结束记录，再决定更新、恢复还是新建，避免重复创建。
- 作为旧版本用户，我希望升级后原关系仍可见，已有多条记录不会被自动合并。
- 作为维护者，我希望 UI、工具和内部任务共用写入规则，避免只有某个入口会保存历史。

## 4. 解决方案

| 方案 | 做法 | 优点 | 代价 | 结论 |
|---|---|---|---|---|
| 当前列＋结构化 JSON 快照 | 单条关系维护当前值和 change_logs | 稳定 ID，查询简单，适合单条历史 | 每次历史写入重写该行 JSON | 采用 |
| 每阶段独立 relation | 阶段之间建立前后关联 | 适合历史图查询 | 改动去重、查询、链关联及迁移 | 不采用 |
| 独立历史表 | 当前表关联历史条目 | 可独立分页和索引 | 当前需求无需跨关系历史查询 | 暂不采用 |
| 自由文本日志或删建 | 手写经过，或删除后新建 | 初始代码少 | 无法可靠回退，历史易丢失 | 不采用 |

普通列是当前状态查询的真源；快照仅用于历史展示和明确的恢复操作。类型描述主要关系，状态描述该关系是否仍成立。兄弟反目可以以 enemy 为主类型，把血缘背景写入依据；按 sibling 不会命中这条 enemy 记录。

需要区分已确认规则与本方案的实施细化：初始快照、工具子路径、并发检查及旧库初始化在下文给出具体方案，不视为已经实现。

| 关键假设 | 如果不成立 | 应对 |
|---|---|---|
| 历史只用于单条查看 | 出现历史筛选、统计或图谱回放需求 | 重新评估独立历史表，不在 JSON 上偷偷增加业务查询 |
| 一条关系的变化数量可控 | JSON 写放大明显 | 测量后迁移存储，不静默截断历史 |
| 当前状态由用户或 AI 明确确认 | 倒叙、补录无法判断当前状态 | 不按章节号自动覆盖；需要确认的内容不提交 |
| 旧版本仍将所有现存记录视作当前关系 | 存量实际包含失效记录 | 升级保持旧行为，后续依据事实标记 ended，不猜测迁移 |

## 5. 方案实施

### 5.1 数据模型

保留 `entity_relations`，不新增关系表或历史表。

| 列 | 类型与默认值 | 语义 |
|---|---|---|
| id、source_type/id、target_type/id | 保持现状 | 关系身份及方向，创建后不可通过变更接口改写 |
| relation_type | 保持现状 | 单一当前主要类型，按端点组合校验 |
| proof、chapter_id、scene_id | 保持现状 | 当前状态的依据；结束时记录结束依据，先前依据在快照中 |
| status | TEXT NOT NULL DEFAULT 'active' | 仅 active、ended，Dart 与静态 schema 校验 |
| change_logs | TEXT NOT NULL DEFAULT '[]' | 使用 TypeConverter 映射为 List<RelationStateSnapshot> |
| properties、sort_order、created_at、updated_at | 保持现状 | properties 不承担状态和历史业务判断 |

新增 `RelationStateSnapshot`：

| 字段 | 类型 | 说明 |
|---|---|---|
| id | String | 稳定且独立生成，历史寻址不使用数组下标 |
| kind | baseline / change | baseline 是开始追踪时的状态，不冒充过去发生的转变 |
| relation_type | String | 该状态的主要类型 |
| status | active / ended | 该状态的生效性 |
| proof | String | 该状态的完整依据 |
| chapter_id / scene_id | String? | 证据位置，互斥，可都为空 |
| reason | String | 这次变化原因；baseline 可为空 |
| recorded_at | DateTime | 录入时间；JSON 使用 UTC ISO 8601，不表示故事时间 |

JSON 由 `type_converters.dart` 的专用 converter 编解码，业务代码不手写 jsonEncode/jsonDecode。未知 kind/status、非法结构、重复快照 ID 明确报错，不把损坏 JSON 当空历史继续写入。

同一模型文件定义不包含 change_logs 的 `RelationSummary`。列表、GraphSearch、当前人物网络和图谱 watcher 用明确列投影生成它，禁止 `select(table)` 后先解析所有历史再丢弃。单条详情才读取完整记录并计算 history_count。历史解析失败时，该条历史显示错误并停止变更；仍可从普通列读取当前摘要，这不是吞掉错误的空历史 fallback。

这里的删除采用硬删除：整条关系沿用现有 DELETE，连同行内 change_logs 一并移除；单个误录从 JSON 数组中移除并写回，不保留删除标记或纠错条目。关系表和快照都不增加 deleted_at，也不要求为所有读取追加软删除过滤。该例外只适用于关系数据，不改变章节、人物、物品等实体的删除规则。

#### 快照不变量

1. 新建关系写入一个 baseline；legacy 的空数组表示此前尚未追踪历史。
2. 首次变更旧关系时，在同一事务里用修改前的旧行冻结 baseline，再追加 change。baseline.recorded_at 明确取旧行 updated_at，本次 change.recorded_at 取本次操作时间；先捕获旧值，再更新当前行。普通 Read 不回写数据库。
3. 有效历史按数组追加顺序排列，录入时间仅用于展示；同一时间戳不影响顺序。
4. 最新有效快照的类型、状态、proof 与当前列相同。证据目标已删除时，当前外链可归一为空，历史仍保留原引用及依据。
5. baseline 不单独删除；初始整条关系就是误建时 Remove 父资源。变化历史计数为数组内 change 的数量，不包含 baseline。
6. 删最新 change 后恢复数组中前一个状态；删中间 change 不改后续完整快照。展示时从相邻有效快照推导“前 → 后”，不保存一套易失效的 before 字段。
7. 不允许客户端整包覆盖 change_logs、自行指定 snapshot ID 或 recorded_at。
8. Edit 可原位修正最新快照的状态字段，保持其 id、kind、recorded_at、reason 不变；普通变更用 Write 追加，整次误录用 Remove 移除。快照不是不可改写的审计日志。

旧行 updated_at 表示这份初始状态最后一次数据更新时间，不表示关系建立时间或剧情发生时间。UI 将它标为“初始记录”，时间说明使用“原记录更新时间”；不使用 created_at 代替，因为当前冻结的状态可能在创建后已经改变。新建关系的 baseline.recorded_at 与该行 created_at／updated_at 使用同一个操作时间。历史顺序始终按数组位置，不因旧时间戳异常而重新排序。

状态机：

```text
active --明确转变--> active（可更换主要类型）
active --关系终止--> ended（保留类型）
ended  --明确恢复--> active（沿用关系 ID）
active / ended --误建删除--> DELETE 关系行及行内历史
```

重复提交相同当前状态、依据与最近一次 reason 时返回 changed=false，不增加快照。只变 recorded_at 不构成变化。

### 5.2 对象关系与调用边界

```text
Entity A ── source ── EntityRelation ── target ── Entity B
                            |
                            +── current columns
                            +── change_logs [baseline, change, ...]
                                      |
                                      +── optional chapter OR scene evidence

Desktop / Mobile / AI tools / Internal writers
                            |
                EntityRelationsService
                            |
            one transaction, one relation row
                            |
               NovelContentDatabase
```

端点关系只推荐复用，不建 UNIQUE、FOREIGN KEY、CHECK 或触发器。端点删除沿既有 deleteRelationsForEntity 调用链硬删除关联行，不制造“剧情结束”事件。证据章节或场次删除只清理当前有效外链，历史保留引用和文字；UI 显示“证据已删除”，不提供失效跳转。

同一对实体有多个存量记录时全部保留，查询返回各自 ID。UI 明确选择某条；AI Read 后依据内容选择，无法区分时不能按最新时间或第一条静默更新。

### 5.3 服务与业务流程

`EntityRelationsService` 统一管理单行原子写入，不新增通用服务或事件框架。

- `createRelation()`：沿用现有参数，增加 status 的可选初值，默认为 active，创建 baseline。
- `recordChange()`：按 ID 读取最新行，校验完整目标状态、reason、proof 和证据，追加快照并更新当前列。
- `removeChange()`：按 relation ID 与 snapshot ID 删除指定变化，决定是否恢复当前列，返回恢复结果。
- `correctCurrentFields()`：修正当前字段，并原位同步最新快照的对应字段，不增加日志。工具 Edit 每次只传一个字段；UI 和内部已确认的资料修正可一次提交多个字段，在同一事务校验。无历史的旧记录只改当前列，不冻结 baseline。
- `deleteRelation()/deleteRelationsForEntity()`：保留现有硬删除。已删除行自然不再被 SQL 查询命中，不增加软删除列或过滤层。
- `clearChapterReferences()/clearSceneReferences()`：清理当前外链，不追加剧情变化，不抹掉旧快照中的历史证据。
- `queryRelationSummaries()/watchRelationSummaries()/getRelationSummaryById()`：只投影当前列，供普通 Read、图谱、概览及列表；历史有独立单条读取入口。
- 旧 `updateRelation()` 不再承担不明确的类型覆写。调用方按真实变化或录入修正分别改走 recordChange 或 correctCurrentFields；不保留一个绕过历史的新旧双写入口。

#### 记录变化

1. 调用方提交目标字段、reason、proof 与证据位置。UI 将它作为一次表单提交，AI 使用一次 Write。
2. 在数据库事务内重读关系；不存在（包括已被删除）或端点类型组合非法时返回业务错误。
3. 校验证据属于本作品且有效。两种证据 ID 不能同时存在；都为空允许设定依据，proof 必须说明。
4. 以最新行补齐未修改的 type/status。证据作为本次完整依据提交，不隐式继承上一场变化的章节。
5. 完全重复请求返回 changed=false，不写历史。旧关系首次发生真实变更时冻结 baseline，recorded_at 使用事务重读所得旧行 updated_at；本次变化使用当前操作时间。
6. 追加快照、更新当前列和 updated_at，一次提交；失败整体回滚。
7. 返回当前状态、change_id、history_path，不返回整个历史数组。

#### 修正当前记录

Edit 表达录入修正，与 Write 的真实演变分开；不引入 record_change 开关。

1. 在事务内重读当前记录，对目标字段验证 old_text，再生成替换后的完整字段值。
2. 仅合并明确修改的字段，其他字段全部保留，包括证据位置；不要求 reason 或重新提交未修改的 proof。
3. 校验修改后值：类型与端点组合、状态枚举、证据互斥及引用有效性。proof 被修改时不得变成空白；旧记录未修改的空 proof 不触发补造证据。
4. 修改当前列；有历史时只修改最新快照中的对应状态字段，保持该快照 id、kind、recorded_at、reason 和数组长度不变。更早快照不改动，不追加纠错条目。
5. 无历史时只修改当前行，不创建 baseline；之后首次 Write 再用修正后的旧行冻结初始状态。
6. 更新当前行 updated_at，原子提交；精确替换未匹配或校验失败时，当前列和快照均不写入。新旧值相同时返回 changed=false。

当前行只有 baseline 时，Edit 同步修正该 baseline 的字段，不重新标记初始时间。Edit 只修正当前字段，不能修改快照的 reason 或过去某条事件；若错误的是整次变化，应删除该变化，而不是将它改造成另一段剧情。

#### 删除误录

事务内重新定位 snapshot ID，不能依赖 UI 的旧数组下标。

- 最新 change：从数组中移除，恢复前一个快照的类型、状态、proof 和仍有效的证据位置，更新 updated_at。
- 较早 change：从数组中移除该项，保留后续状态，更新 updated_at。
- baseline：返回 initial_snapshot_not_removable，提示删除整条误建关系。
- 已删除／不存在项：普通请求返回 not_found；Remove force=true 沿用已有幂等语义。
- UI 确认时持有的最新快照 ID 与提交时不同，返回 relation_changed，刷新后重新确认，不执行与提示不一致的回退。

删除最新变化不恢复关系的旧 updated_at 或端点，不增加恢复事件。两种删除共用服务，UI 不自行拼接数组。

#### 并发与维护入口

事务内完成读、校验、数组修改和写回，避免两个调用以旧数组互相覆盖；UI 表单保存前检查起始快照及当前值是否变化，禁止静默覆盖后台更新。多连接发生锁或写冲突时返回可重试错误，不提交部分历史。

仅排序、properties 维护不追加历史。章节／场次删除、场次文档 apply 的证据重映射必须走统一维护方法；还原历史时重新解析证据有效性，不能复活无效引用。

直接读取也纳入 T3 审计，重点检查语义与结果，而非增加软删除条件：screenplay_service 的证据快照读取必须包含现存 ended；图谱及当前网络只读 active；普通 Read 保留 ended。除服务外，任何新发起的直接查询都不能取得已硬删除行。已有 UI watcher 在提交后刷新，不继续提供已删除关系的写操作。

### 5.4 AI 工具契约

沿用 Create、Read、Write、Edit、Remove、GraphSearch 的现有顶层 schema，不新增 UpdateRelation 工具。资源字段、子路径及限制统一登记到 `tools.dart`，由 `/_schema/relations` 按需提供。

| 调用 | 行为 |
|---|---|
| Create /relations | 创建关系与 baseline，默认 active；已有同对记录时优先 Read 后复用，服务不强制唯一 |
| Read /relations | 默认返回现存 active＋ended，不展开历史 |
| Read /relations?relation_type=lover | 过滤当前列，仍包含 ended；不匹配 change_logs；可选 status 只缩小本次读取范围 |
| Read /relations/{relation_id} | 当前详情、status、history_count、history_path |
| Read /relations/{relation_id}/{field} | 对 Edit 白名单字段返回原始值，证据为空返回 null，供精确匹配与预览 |
| Read /relations/{relation_id}/change_logs | 返回数组内 baseline 与变化快照，按记录顺序倒序；误录删除后不再存在 |
| Read /relations/{relation_id}/change_logs/{change_id} | 返回单个有效快照及自身 id/path |
| Write /relations/{relation_id} | 一次记录完整变更，允许改变 type/status/proof/evidence |
| Edit /relations/{relation_id}/{field} | 修正单个当前字段并同步最新快照，不新增日志；具体白名单与校验见下文 |
| Remove /relations/{relation_id}/change_logs/{change_id} | 删除误录并按是否最新决定恢复 |
| Remove /relations/{relation_id} | 删除整条误建记录；不能用来表达分手或关系终止 |
| GraphSearch | 只匹配当前 active 关系，每一层在取邻边时仅筛选 status=active |

第一版 Write 只开放关系资源路径，要求 `fields`，不开放单独写 status/type 的字段路径，避免缺少本次依据。跨字段变更属于同一个事件，不能拆成多个 Write。

Write 字段：

- `relation_type`、`status` 可选，未提供保留当前值；至少一个状态或证据字段发生变化。
- `reason`、`proof` 必填且非空；reason 为操作输入，存于新快照，不新增当前 reason 列。
- `chapter_id`、`scene_id` 为本次证据：省略视为 null，不沿用上次证据。允许显式 null，互斥。
- source/target、id、change_logs、created_at 不可写。
- 当前类型、状态或依据录错用 Edit；整次事件虚假用 Remove 历史。Write 只表达实际变化，不加入 record_change 或纠错模式开关。

Edit 字段白名单与语义：

| 字段 | old_text / new_text | 校验 |
|---|---|---|
| relation_type | 完整旧类型 → 新类型 | 沿用规范值与已有别名归一，按端点组合验证 |
| status | 完整旧状态 → active 或 ended | 不接受任意字符串 |
| proof | 原文片段 → 修正片段 | 沿用精确匹配、多处匹配与 all 规则 |
| chapter_id | 完整旧 ID → 新 ID；空字符串表示 null | 有效的本作章节，不能与 scene_id 同时非空 |
| scene_id | 完整旧 ID → 新 ID；空字符串表示 null | 有效的本作场次，不能与 chapter_id 同时非空 |

每次 Edit 只改一个字段。空证据初始化使用 old_text=""；清空使用 new_text=""。切换章节／场次证据时，先清空旧引用，再设置另一个；两次调用各自原子，工具不承诺跨调用回滚。UI 修正表单可把多个修改字段一次提交 correctCurrentFields，统一校验并提交。

端点、id、时间戳、reason 和整个 change_logs 均不开放 Edit。Edit /relations/{id} 缺少字段时给出字段路径；Edit 历史子资源明确拒绝。Read 字段路径严格返回该字段原值，null 不转为包含其他信息的对象。

例如将误填的 enemy 修正为 friend：

```json
{
  "path": "/relations/r_ab/relation_type",
  "old_text": "enemy",
  "new_text": "friend"
}
```

成功返回当前 relation 摘要及 history_appended=false；已有快照 ID 和数量不变，不因未传证据位置而清空它们。Write 成功追加时返回 history_appended=true；重复 Write 返回 changed=false、history_appended=false。

示例中的 ID 都是已读取的资源 ID，实际调用不可自行拼造：

```json
{
  "path": "/relations/r_ab",
  "fields": {
    "relation_type": "enemy",
    "status": "active",
    "reason": "得知对方背叛后反目",
    "proof": "两人在山门对质，甲确认乙出卖了同伴。",
    "chapter_id": "ch_20",
    "scene_id": null
  }
}
```

结束与恢复仍调用 Write，分别指定 ended、active，并提供各自依据。变更返回至少包含 path、id、status、changed、change_id、history_path、history_appended、chapter_id、scene_id、has_evidence_location。两个证据位置都为空时明确返回 has_evidence_location=false，不让模型误以为旧位置被继承；原来的证据仍在之前快照中。Remove 历史返回 deleted、current_changed 和当前 relation 摘要。路径由现有资源解析器返回，不要求模型猜测。

错误统一使用现有结构化错误结果：

| error_code | 情况与下一步 |
|---|---|
| missing_required_fields | reason／proof 缺失，列出缺少字段 |
| invalid_relation_type | 与端点类型组合不符，返回该组合合法值 |
| invalid_relation_status | 非 active／ended |
| mutually_exclusive_fields | 同时提供章节和场次 |
| invalid_chapter_ref / invalid_scene_ref | 证据不存在、已删除或不属于当前目标作品 |
| not_found | 关系或历史项不存在／已删除 |
| initial_snapshot_not_removable | 不能单删 baseline，误建请 Remove 父关系 |
| relation_changed | UI 确认后数据变化，刷新后重试 |
| invalid_relation_history | 快照结构损坏，停止写入并报告，不静默重置 |
| old_text_not_found | Edit 提供的旧值与当前值不匹配，先 Read 再重试 |

新子路径必须参与资源权限校验、`_contentKindGate`、`_resourceOperationGate`、跨作品 scope 与返回路径绝对化。沿用现有权限，不因为已结束而给额外权限，也不绕过跨作品写入限制。

Relations 继续不进入 Glob/Grep 资源扫描。Read 列表与 GraphSearch 不携带 history 内容，只携带详情入口；读取单条历史才增加上下文。Read 的现有 source/target 过滤保持有向含义，查重推荐分别读取两个方向；不引入模糊的端点自动归一。

预览不得创建 baseline 或快照；Write 成功预览至少表示旧／新类型、状态和依据，Edit 预览必须读取被修改字段的原始值，并使用与真实执行相同的替换及业务校验；预览不写当前列或日志。关系变更沿现有直接生效路径落库，不新增 working change 审批队列；已存在的创建撤销通过 deleteRelation 硬删除整条关系及其行内历史。

### 5.5 UI 与交互

两端复用共享详情和历史组件，不新建独立页面或设计稿。

#### 图谱与列表

- 默认图谱、图例、分类计数、中心点统计、深度扩展和 PNG 导出统一使用当前表中 status=active 的边。
- 人物关系列表默认仅显示 active；“显示已结束”开启后追加 ended，条目明确显示“已结束”，不把这些边重新画入图谱。
- 无 active 边的实体仍可从实体列表选中并查看关系。不能用 active 图谱的节点集合限制列表选择；空图保留实体入口，列表应能打开 ended 历史。
- 列表当前类型筛选只匹配主类型，人物名称搜索保持现有行为，不扩展到历史文字。
- 存量同对多条记录各自展示，不能按端点去重。按 ID 选中和操作。

#### 单条详情

```text
甲 ↔ 乙
朋友    生效中

当前依据
两人在旧城重逢，解释误会后恢复往来。
第 30 章 · 可跳转证据

变化历史（3）                         展开
  最近记录
  敌人 → 朋友
  原因、证据、章节／场次位置
  删除误录

  更早记录……
  初始记录（不计入变化次数）
```

文案中的方向沿现有有向关系读法，不统一使用双向箭头；上面的排版只说明信息层级。

- 当前类型、状态与依据常显；历史默认折叠。选中单条关系后独立加载其历史与计数，展开时倒序构建条目，不预读其他关系的历史。
- 结束显示“情侣 · 已结束”，不新增 ex_lover 等枚举；恢复后仍保留结束记录。
- 最新变化删除确认：“删除后，当前关系将恢复为「{type} · {status}」。”较早变化：“删除此记录，当前关系不变。”
- baseline 不提供单条删除按钮；整条误建记录提供单独“删除关系”，不能与“结束关系”混为同一操作。
- 状态不变而原因／证据变化时展示“依据补充”，不显示“朋友 → 朋友”。
- 证据目标失效时保留原文，显示“证据已删除”；无证据位置时显示设定依据，不生成虚假跳转。
- 切换选择、展开历史及开关列表过滤不重新运行图谱布局。写入失败保留表单输入、选择和滚动位置。

#### 写入入口

新增关系补齐 proof 与章节／场次选择。已有关系的主要操作为“记录变化”“结束关系”“恢复关系”；表单一次提交类型、目标状态、reason、proof 和证据，source/target 只读。新增“修正记录”入口复用表单，提交 correctCurrentFields，不要求变化原因，不追加历史；未改动的字段保留。真实变化与修正使用明确的提交动作，不根据是否改变类型自动猜测用户意图。

使用 `lib/third/form` 管理多字段编辑、校验和提交。桌面仍在现有关系列表下显示详情；移动端点击条目先进入详情面板，再选择编辑动作，替换当前“点击即编辑”的行为。

本地展开、选择和筛选状态由独立 region 管理。共享组件读取 Provider 数据，不让桌面／移动端根 build 继续堆状态。

### 5.6 内置技能与工具文案

目标文件 `assets/bundled_skills/story-continuity/references/relations.md` 保留合法类型和方向表，重写操作、去重与关系变化段落：

1. 删除“已建立的关系不可改写”“Remove 再 Create”。
2. 明确搜索与读取：GraphSearch 查当前生效关系；查重、寻找已结束记录用 Read，不能仅凭 GraphSearch 无结果就 Create。
3. 推荐同对实体复用已有记录；多条存量依据内容选 ID，不合并，不宣称数据库唯一。
4. 一条记录只有一个主要类型，其他关系背景写入依据，不承诺背景也能按类型查询。
5. 新增 Write 转变、结束、恢复，Edit 修正当前字段，以及读取 history、删除误录的完整示例。明确 Write 追加快照，Edit 只同步当前与最新快照。
6. 当前关系与 change_logs 由工具维护，禁止模型生成或覆写整包快照。
7. 字段录错用 Edit，不新增纠错日志；整次变化误录才 Remove。删除最新变化会回退，删除较早变化只移除该条；剧情中的关系结束用 Write ended。
8. 保留证据位置与故事时间的区别，返工旧章或补录倒叙不能按章节顺序覆盖后续已确认状态。
9. 修正“中文 relation_type 建不了”的绝对表述：契约示例统一规范英文值，保留实现已有别名容错，不扩大它。

相邻 `novel.md`、`screenplay.md` 同步把“移除已失效关系”改为记录 ended，避免附件之间冲突。`story-continuity/SKILL.md` 的入口仍指向关系附件，不把完整字段表重新塞进常驻 prompt。AI 提示词不做 i18n。

以下是实施时待用户明确确认的 description 草案，确认范围只涉及列出的文案：

| 位置 | 拟用文案 |
|---|---|
| GraphSearch 行为说明新增句 | “只返回当前生效的关系；已结束关系及历史变化请用 Read 查看。” |
| relation_type | “当前主要关系类型；合法值由 source_type → target_type 决定。Write 记录真实变化，Edit 修正录入。方向按「source 是 target 的 X」读，例外见关系指南。” |
| status | “关系状态：active 表示生效，ended 表示已结束。真实结束或恢复用 Write，状态录错用 Edit。” |
| proof | “本次关系状态的依据；写具体场面或设定说明，不重复关系类型。” |
| reason | “Write 本次关系变化的原因；记录转变、结束、恢复或新的事实依据。Edit 不需要此字段。” |
| chapter_id | “当前状态的证据章节 ID；与 scene_id 互斥。Write 省略时不保留旧章节证据；Edit 其他字段不影响本字段，Edit 本字段传空字符串表示清空。” |
| scene_id | “当前状态的证据场次 ID；与 chapter_id 互斥。Write 省略时不保留旧场次证据；Edit 其他字段不影响本字段，Edit 本字段传空字符串表示清空。” |
| change_logs 子资源 | “这条关系的有效初始记录和变化历史；删除最新变化会恢复前一个状态，删除更早变化不改变当前状态。” |

Write、Edit、Remove 的通用顶层 description 无需增加关系专属段落。新增资源契约与上表必须在实际修改前取得项目要求的文案确认；用户本次要求写方案不等于已经授权修改运行时 description。

### 5.7 改动清单

#### `lib/shared/database/novel_content_database.dart`

- EntityRelations 只增加 status、changeLogs，使用 typed converter；保持现有 ID 与端点结构。
- onCreate 加关系索引创建方法；按 5.9 的版本策略接入 migration。
- 更新生成数据模型，检查 `novel_content_database.drift.dart` 与 `novel_content_database.g.dart` 的实际生成差异。

#### `lib/shared/database/novel_content_database_migrations.dart`

- 在本次目标 migration 增加列与非唯一索引，见 5.9。
- 独立 `createEntityRelationIndexes()` 供 onCreate 与 upgrade 共用。
- 不顺手改写 v3～v5 的历史清理语义，不向旧 migration 加新的数据删除。

#### NEW：`lib/shared/models/entity_relation_history.dart`

- 定义状态、快照 kind、快照模型、有效序列、删除后恢复规则与明确校验错误。
- 定义无历史数组的 RelationSummary，区分当前查询结果与完整历史模型。
- 模型不依赖数据库，便于 converter 和服务共用；按项目 snake_case 枚举规范。
- 不新增通用 event-sourcing 抽象。

#### `lib/shared/database/type_converters.dart`

- 新增 RelationStateSnapshotListConverter，只在此处负责 JSON 编解码；非法值不能默认为空。

#### NEW：`lib/shared/utils/entity_relation_types.dart`

- 从现有工具与编辑对话框收口“端点类型组合 → 合法关系类型”的纯查询函数，保留现有枚举值与方向。
- 服务、工具和 UI 使用同一份组合校验；工具保留别名归一和结构化错误包装。`relationTypesForEntityTypePair()` 可保留委托入口，避免无关调用方重命名。

#### `lib/shared/services/entity_relations_service.dart`

- 实现 recordChange、correctCurrentFields、removeChange 和仅真实变化触发的 legacy baseline 初始化。
- 新增当前列投影读取；GraphSearchLayer／GraphSearchResult 使用 RelationSummary，图谱与当前网络不解码历史数组。
- Read／列表获取保留 ended，GraphSearch 的 _getDirectRelations 每层仅取 active；不追加 deleted_at 过滤。
- `getCharacterNetwork/getFactionMembers/getSkillLearners/getChapterLocations` 等表达当前业务关系的方法只取 active。
- getRelationsBetween 用于复用发现，保留 ended；新增明确的双向候选读取供查重，不改变有向方法旧语义。
- 删除接口沿用硬删除；证据维护不写虚假剧情快照；统一事务与含表名、操作、ID 的 DB 日志。

#### `lib/shared/services/ai/tools.dart`

- 修改 _relationFields 与 relations 的 _ResourceDefinition，注册 Write、五个当前字段的 Read／Edit 及只读／可删除 history 子资源。
- 增加 status 的静态枚举、reason 写入参数、history 的稳定寻址与返回引用。
- reason／proof 的必填约束绑定 Write 操作，不把 Write 的完整事件要求施加给 Edit；Edit 按字段白名单校验。
- _previewWrite/_previewEdit 接入只读预览；不新增顶层工具或动态 schema。

#### `lib/shared/services/ai/tools_graph.dart`

- Create 传入初始状态；GraphSearch 返回 status，但不返回 change_logs 内容。
- _relationToJson 区分当前摘要与详情，不把 history 数组放入每条边。

#### `lib/shared/services/ai/tools_write.dart`

- _executePreparedWrite 分发 relations 到服务，结构化写入一次提交。
- 静态输入预校验与真实执行校验一致，空写和重复写不追加历史。

#### `lib/shared/services/ai/tools_edit.dart`

- 开放 relation_type、status、proof、chapter_id、scene_id 的当前字段修正，替换后走 correctCurrentFields，同步末项相应字段且不追加历史。proof 沿用精确替换与 all；枚举和 ID 要求完整旧值，结果必须通过业务校验。

#### `lib/shared/services/ai/tools_read.dart`

- _readRelation 先识别 history 子资源与五个可修正字段，再走父资源详情，移除对应旧的“全部字段路径不可读”限制。
- _queryRelations 返回 active＋ended；按当前字段过滤，不展开 history；章／场次关系读取同样不隐式隐藏 ended。

#### `lib/shared/services/ai/tools_remove.dart`

- history 子资源优先分发，避免把删除一项误解释为删除父 relation。
- 父资源 Remove 硬删除整条关系；force 不允许跳过 baseline 保护或数据冲突。

#### `lib/shared/services/ai/tools_cross_work.dart`、`tools_support.dart`、`tools_schema.dart`

- 核对新层级的路径解析、权限、错误提示、history_path 与 entries[].path 绝对化。
- relation/history 持续排除 Glob/Grep；静态 schema 对外操作与真实 handler 一致。

#### `lib/shared/entity_graph/providers.dart`、`data.dart`、`entity_list_section.dart`

- 全量现存记录供列表发现；图谱输入派生 active 子集，避免修改 allRelations 的语义。
- 当前列表类型切换为 RelationSummary，保持排序与端点信息，避免通过完整 EntityRelation 间接加载所有历史。
- 增加按 relation ID 的详情／历史加载；列表开关不影响图谱布局。
- 保留只有 ended 关系的人物入口；统计、图例与导出共用 active 过滤。

#### `lib/shared/providers/novel_providers.dart`

- entityRelationsProvider 改用当前列投影，仍返回当前作品匹配实体的现存关系；具体列表是否显示 ended 由调用方决定。
- 核对相关生成文件及调用方类型，不能靠在该 provider 全局过滤 ended 来实现当前图谱。

#### NEW：`lib/shared/widgets/relation/detail.dart`、`history.dart`、`list_region.dart`、`change_form.dart`

- detail 组合当前信息与 history；history 自持展开、加载、删除确认与错误态。
- list_region 自持“显示已结束”和记录选择，供两端组合。
- change_form 负责新建、记录变化、结束、恢复和修正当前的表单。修正模式不展示必填 reason，不承担 DB 编排。
- 每个新增 Dart 文件写职责、关联文件及实际命中规则；含 UI 文案时列出 i18n 三件套。

#### `lib/shared/widgets/relation_edit_dialog.dart`

- 保留已有 show 入口，由新表单承接；新建补 proof，已有记录端点只读。
- 记录变化、结束／恢复、修正记录与删除分开；真实变化走 recordChange，修正走 correctCurrentFields，不再调用语义不明的旧 updateRelation。

#### `lib/desktop/widgets/entity_graph_panel.dart`

- 在现有列表／详情位置组合共享 region，替换 _RelationsTab 中对应部分。
- 保留选择与布局，不增加历史专用页面，不把更多局部状态塞入根 build。

#### `lib/mobile/widgets/entity_graph_panel.dart`

- _RelationListItem 点击进入详情面板，详情再打开变更表单。
- 与桌面使用相同历史和确认组件，窄屏正文换行、长证据可滚动。

#### `lib/shared/widgets/character/character_relations_overview.dart`

- 人物关系概览只统计 active；人物进入关系详情时仍能访问 ended 列表。

#### 其他写入调用方

- 同文件 `_applyWorkspaceFieldEdit` 的直接 select 纳入读取审计：允许读取 ended；关系已被硬删除时明确报不存在，不重新插入或恢复。
- `lib/shared/services/screenplay_service.dart`：_softDeleteSceneTree、文档 apply 的 evidence 修改走统一证据维护路径，兼容历史引用与撤销。
- 同文件读取 entityRelations 生成 evidence 快照的查询保留 ended；父关系硬删除后重读不得再出现在快照中，不新增删除字段过滤。
- `lib/shared/services/novel_content.dart`、`maps_service.dart`：端点删除继续调用关系服务，维持现有硬删除关联行；章节引用清理遵循新规则。
- `lib/shared/services/working_overlay.dart`：_deleteCreatedResource 的 relation 分支仍调用删除服务；撤销新建后 Read／GraphSearch 均不可见。
- `lib/shared/services/demo_novel.dart` 与 batchCreateRelations：原始插入允许默认空历史，走 legacy 初始化规则，不要求示例补写虚构事件。

#### 本地化

- `lib/shared/localization/locale_keys.dart`
- `assets/translations/en/relation.json`、`assets/translations/zh-CN/relation.json`
- `assets/translations/en/entity_graph.json`、`assets/translations/zh-CN/entity_graph.json`

新增并对齐 active、ended、显示已结束、记录变化、修正记录、结束、恢复、历史计数、初始记录、原记录更新时间、删除误录、两类删除影响、证据已删除、关系已更新、保存失败等文案。按项目现有 namespace 分组，避免在 UI 泄露 JSON、snapshot ID 等实现细节。

#### 内置技能与测试

- `assets/bundled_skills/story-continuity/references/relations.md` 为主要修改文件，novel.md、screenplay.md 同步，SKILL.md 仅核对入口。
- 测试文件及新增测试见第 6 节。不运行真实 LLM 评测，除非用户另行明确要求。

### 5.8 实施顺序

一个完整变更集交付，以下是任务依赖，不是允许半套上线的分期。

| 任务 | 内容 | 依赖 | 验证 |
|---|---|---|---|
| T1 | 模型、converter、schema、migration、冻结 fixture | 发布状态复核 | 模型／迁移测试 |
| T2 | 原子服务、快照移除、既有硬删除、证据维护 | T1 | 生命周期／并发测试 |
| T3 | 审计全部直接读取与写入，旧写入接入 | T2 | 读取范围、场次、删除回归 |
| T4 | 工具契约、handler、路径和跨作品返回 | T2 | 工具与契约回归 |
| T5 | 两端共享详情／历史／表单及 i18n | T2、T3 | 共享组件测试＋两端验收 |
| T6 | 技能附件、description 审批后落地 | T4 | 提示词契约与场景评审 |
| T7 | 定点回归、代码生成检查、交付 | T1～T6 | 第 6 节全部必需项 |

T3 扫描 `lib/` 中 entityRelations、entity_relations 和 EntityRelationsCompanion 的引用，包含直接 select、customSelect／SQL、watch 与写入；排除生成文件，逐项记录读取范围，不能只搜索 Companion。该审计用于保护 active／ended 的不同读取语义及硬删除后的不存在结果，不改造成软删除项目。

不在 T2 完成后就发布：否则直接写入口可能破坏快照，或者工具仍指导模型删除重建。

### 5.9 Migration

#### 已核实的版本基线

2026-09-24 查询 GitHub latest release 为 v2.0.1，发布于 2026-09-20。远端标签与本地标签均指向 `e4b269dd0b688ca2e07e2ac9bb77b04fc00eef52`，该标签内容库 schema 为 18；当前工作区 schema 为 19，migrateToV19 目前增加 canvas layout。

因此按根 AGENTS 的未发布 migration 规则，本方案基线合并进 v19，保持 schemaVersion=19；这一规则优先于 db-migration.md 的默认逐次升版要求。实施当天再次核对实际 release、标签及对应代码；若 v19 已发布，改为 v20 新 migration，不追加到已发布步骤。版本号若出现并行冲突，按项目冲突确认规则处理。

核对命令：

```bash
gh api repos/<owner>/reveric/releases/latest --jq '{tag_name,published_at,html_url}'
gh api repos/<owner>/reveric/git/ref/tags/v2.0.1 --jq '.object'
git show v2.0.1:lib/shared/database/novel_content_database.dart
```

#### 正式升级与新建库

1. 只添加 status=active、change_logs=[]，不添加 deleted_at。
2. 保留所有旧 ID、类型、proof、证据、properties、排序、created_at、updated_at，不做去重，不依据文字推断 ended。
3. 默认 active 只是保持旧版本所有现存关系可见的行为，不宣称已核实其剧情有效性。此前没有历史的 UI 显示“尚无变化记录”，不补造过去的变化。
4. 新建库用当前 schema，正常服务创建写入 baseline，时间与该行创建时间一致；旧数据第一次真实变更才冻结原状态，baseline.recorded_at 取修改前的 updated_at，不取升级时间、首次打开时间或首次变更时间。
5. 添加非唯一索引：
   - entity_relations_by_source_type_source_id_status
   - entity_relations_by_target_type_target_id_status
   两端查找均可使用同一前缀；不单建低选择性的 status 索引。
6. 审计当前定义参与历史建表的路径，避免旧步骤提前创建新列后最新步骤重复添加。允许正式历史升级步骤做实际列检查，不引入 beforeOpen 运行时补列。
7. 本次核查未见该表的 TableMigration 重建；实施时再次搜索 migration 文件，不能把其他表的重建推定为无关而略过全库升级测试。

本地已经是 v19 的开发库，先定位实际库并备份，再按 SQLite skill 手动 ALTER TABLE 添加这两列及索引并查询验证。不能在运行时代码为这些开发库加幂等补列 fallback。本次只写方案，不读取或修改任何用户数据库。

migration 失败必须阻止正常打开并保留原库与失败信息，不能创建空库替代。仅新增列／索引，不需要重建关系表或一次性业务数据脚本。

#### 回滚

新增列可保留，但旧二进制不知道 ended 和历史，可能把 ended 关系重新画出，也可能覆写当前列而不维护快照。开始新写入后不支持直接降级继续写同一库；发布回滚应使用升级前备份，或提供仍理解新模型的修复版本。不通过丢弃 change_logs 回退 schema。

### 5.10 上线后检查

- DB 失败日志包含表、操作、relation ID 与异常，避免记录整段证据正文。
- 抽查一组转变、结束、恢复后的 Read 与 GraphSearch，确认 ended 仅在读取可见，历史不会随每次搜索返回。
- 抽查旧作品的关系数量、重复 ID 集合与更新前后证据；缺少历史是合法 legacy 状态，不作为故障静默“修复”。
- 关注快照解析失败、relation_changed、历史恢复后无效证据引用；错误不得标为操作成功。

## 6. 验收标准

| 类别 | 必须满足 | 验证 |
|---|---|---|
| 转变 | friend → enemy → friend 同 ID，完整证据不丢 | 服务＋工具测试 |
| 结束／恢复 | lover ended 可 Read，不可 GraphSearch；恢复后重新可搜 | 服务＋工具测试 |
| 多层搜索 | A-B ended、B-C active，搜 A depth=2 不返回 B-C | GraphSearch 测试 |
| 列表 | Read 默认含 ended，类型／证据过滤只查当前字段 | Read 测试 |
| 历史读取 | 只按明确 history 路径返回，稳定 ID/path；误录 ID 在原始 JSON 与工具返回中都不存在 | 服务＋工具测试 |
| Edit 类型／状态 | 当前字段与最新快照同步；快照 ID、kind、recorded_at、reason、数量和更早历史不变 | 服务＋工具测试 |
| Edit 证据 | 未涉及的位置完整保留；设置／清空引用通过互斥与有效性校验 | 服务＋工具测试 |
| Edit 旧记录 | change_logs=[] 时只改当前，不补 baseline；随后首次 Write 捕获修正后的状态与 updated_at | 服务测试 |
| Edit 失败 | old_text 不匹配、非法枚举、无效引用或只读字段时不写当前与历史 | 工具测试 |
| Write 证据省略 | 旧快照保留旧位置，当前两种位置变为 null，返回 has_evidence_location=false；同场景 Edit 类型则保留位置 | 工具对照测试 |
| 删除最新 | 最新状态、proof、有效证据一起恢复，事务失败无半写入 | 服务测试 |
| 删除中间 | 当前与后续快照不变，前后展示连接剩余状态 | 模型＋组件测试 |
| baseline | 不可单删，legacy 首次变更只生成一个 baseline | 服务测试 |
| baseline 时间 | 旧行 created_at 与 updated_at 不同时，首次变更的 baseline 精确保留旧 updated_at；新 change 使用本次操作时间，后续变更不重建 baseline | 固定时钟的服务测试 |
| 误建删除 | DELETE 后关系行及行内历史实际不存在，服务、直接 SQL、Read／GraphSearch 的新读取均不能取得该关系；ended 仍可 Read | 删除与直接读取回归 |
| 并发／重试 | 两次不同写入不丢快照，相同请求不重复追加，确认过期不误回退 | 服务测试 |
| 证据 | chapter/scene 互斥、跨作品／无效 ID 拒绝、失效链接不被恢复 | 场次＋工具测试 |
| 旧数据 | 多条同对记录保留；active 默认和空历史不改旧字段 | migration 测试 |
| UI 发现 | 没有 active 边也能经实体列表打开 ended 记录 | 两端手工验收 |
| UI 一致 | 相同类型、状态、历史、删除影响与证据跳转 | 共享组件＋两端验收 |
| 性能 | history 展开不触发图谱重新布局，列表／搜索返回不随历史长度膨胀 | 组件行为与序列化测试 |
| 非法数据 | converter 遇损坏历史明确失败，不空数组覆盖 | converter 测试 |
| 内置技能 | 不再指导失效关系 Remove；查重不只依赖 GraphSearch | 契约测试与人工检查 |

新增测试：

- `test/shared/models/entity_relation_history_test.dart`
- `test/shared/database/entity_relation_history_converter_test.dart`
- `test/shared/database/entity_relation_history_migration_test.dart`
- `test/shared/services/ai/tools_relation_history_test.dart`
- `test/shared/widgets/relation/history_test.dart`
- `test/shared/widgets/relation/detail_test.dart`

扩展现有 `entity_relations_service_test.dart`、`entity_delete_relations_test.dart`、`tools_graph_test.dart`、`tools_resource_links_test.dart`、`tools_remove_test.dart`、`tools_cross_work_test.dart`、`relation_edit_dialog_test.dart`、`screenplay_service_test.dart`、`working_overlay_test.dart` 和图谱测试。

迁移测试至少冻结两份关系 DDL：`test/fixtures/entity_relations_v17.sql` 取自 v1.2.4，`test/fixtures/entity_relations_v18.sql` 取自 v2.0.1。已核对 v1.2.4 是 schema 17 且没有 scene_id，v2.0.1 是 schema 18 且有 scene_id。这覆盖新增场次证据前后的真实结构；其余仍受支持的正式源版本由现有全库升级回归继续覆盖，不借此缩小支持范围。

正式升级测试执行 v17／v18 → 目标版本；已是修改前 v19 的开发库不应被运行时自动补列，单独验证按手动维护 SQL 升级后可读。原有最新 schema 建库再改 PRAGMA 不能代替冻结 fixture。断言版本、列类型、默认值、非唯一索引、旧行数量及字段，最后通过 typed service 读取。

以下为实施后的验证命令，不表示本次已运行。Flutter 命令串行，fixture 及新测试创建后执行：

```bash
make codegen
fvm flutter test test/shared/models/entity_relation_history_test.dart test/shared/database/entity_relation_history_converter_test.dart
fvm flutter test test/shared/database/entity_relation_history_migration_test.dart test/shared/database/novel_content_database_migration_test.dart test/shared/database/screenplay_migration_test.dart
fvm flutter test test/shared/services/entity_relations_service_test.dart test/shared/services/entity_delete_relations_test.dart
fvm flutter test test/shared/services/ai/tools_relation_history_test.dart test/shared/services/ai/tools_graph_test.dart test/shared/services/ai/tools_resource_links_test.dart test/shared/services/ai/tools_remove_test.dart test/shared/services/ai/tools_cross_work_test.dart
fvm flutter test test/shared/services/ai/tools_edit_field_path_test.dart
fvm flutter test test/shared/services/ai/tools_glob_test.dart test/shared/services/ai/tools_grep_test.dart test/shared/services/ai/agent_skills_run_command_handler_test.dart
fvm flutter test test/shared/widgets/relation test/shared/widgets/relation_edit_dialog_test.dart test/shared/entity_graph
fvm flutter test test/shared/services/screenplay_service_test.dart test/shared/services/working_overlay_test.dart
fvm flutter test test/shared/services/working_overlay_screenplay_test.dart
fvm flutter analyze lib/shared/models/entity_relation_history.dart lib/shared/services/entity_relations_service.dart lib/shared/services/ai lib/shared/widgets/relation lib/shared/entity_graph lib/desktop/widgets/entity_graph_panel.dart lib/mobile/widgets/entity_graph_panel.dart
git diff --check
```

含真实本地化资源的 widget 测试，每个 setUp 清理 rootBundle 缓存，使用 EasyLocalization 与 MergingAssetLoader；优先测试共享 region，不堆整页 Provider override。业务方法测试与 widget 测试分开。无现成两端页面测试的部分以共享组件测试及上述手动场景补充，如实报告。

## 7. 评测

本方案涉及 AI 选择更新、结束、恢复和删除的行为，需要场景评审；不自动启动 e2e-evaluation 或真实模型调用。

| 场景 | 输入意图 | 正确选择 |
|---|---|---|
| 朋友反目 | 已有 friend，正文证实背叛 | Write 原 ID 为 enemy，提供新证据 |
| 分手 | 没有明确后续关系 | Write ended，保留 lover |
| 复合 | Read 找到 ended 的原关系 | 恢复原 ID，不因 GraphSearch 无结果而 Create |
| 只查看历史 | 用户问这两人如何反目 | Read 当前，再 Read 单条 change_logs |
| 两个实体多条旧记录 | 多条候选含不同依据 | 读取并明确选择，不能合并或任取 |
| 兄弟反目 | 当前主类型 enemy | 兄弟背景入 proof，按 sibling 不匹配 |
| 当前字段录错 | 原本一直是朋友，当前误填 enemy | Edit relation_type，同步最新快照，不追加、不清空旧证据 |
| 误记最近变化 | 最近反目并未发生 | Remove 该 change，当前恢复 |
| 误记中间变化 | 后续成为恋人仍属实 | Remove 中间项，当前保持 lover |
| 返工旧章／倒叙 | 证据出现得晚但事情更早 | 不凭章号覆盖已确认当前态；无法确定时停止该写入 |

确定性测试检查工具是否允许正确操作、阻止错误操作。人工检查附件是否让模型容易找到路径和结束语义。真实模型是否选择正确工具属于额外评测，只有用户明确要求时运行；若未运行，不能宣称 AI 行为已验证。

## 8. Token 成本

- 不增加模型调用轮次或新工具名称；关系状态增加少量返回字段，具体 token 数由实施后基线测试测量，不在方案中虚报。
- 查重原本就需要读取关系；为发现 ended，改用 Read，而非额外强制一轮 GraphSearch。
- 列表和搜索只返回当前摘要与 history_path，成本随返回关系数增长，不随历史长度增长。
- 单次显式历史读取成本随该关系有效快照数及证据文字长度线性增长。第一版不截断、不摘要改写证据；大量历史带来的单条读取成本列为已知妥协。
- 关系指南按需加载，不把例子和全部枚举重复写进常驻工具描述。无额外模型档位要求，也不依赖外部服务。

## 9. 风险

| 触发条件 | 影响 | 对策 |
|---|---|---|
| 仅改 AI Write，漏掉内部直写 | 当前列与快照分离 | T3 审计所有 EntityRelationsCompanion 写入口，定点测试 |
| 直接读取沿用错误范围或过期结果 | ended 被错误隐藏，或仍对已删除关系提供写操作 | T3 同时审计直接 select／SQL／watch；验证硬删除后的新读取为空、旧写入失败 |
| 把 Read 与搜索用同一 active filter | 已结束记录无法发现 | 方法语义分开，Read ended 作为硬回归 |
| 默认图谱移除唯一边 | 相关人物历史没有入口 | 实体列表候选不依赖 active 节点集合 |
| 旧库默认值或 migration 版本错误 | 列缺失、旧记录不可见 | 正式 release 与标签复核、冻结 fixture、typed 读取 |
| 快照误删与后台更新并发 | 回退到与确认提示不同的状态 | UI 前置状态校验，事务重读，冲突明确失败 |
| JSON 整包重写 | 长历史写放大 | 无全局自动读取／AI 注入；监测后再迁移，不截断 |
| 当前证据失效后回退 | 恢复悬空引用 | 恢复时解析有效性，历史保留文字，当前链接归一 |
| 旧客户端继续写新库 | 无视 ended 或损坏历史一致性 | 禁止共享库降级写入，用备份／修复版回滚 |
| 误删整条关系 | 同行 change_logs 一并移除，无法从应用回收站恢复 | 保留明确的删除确认，与 ended 操作分开，不增加批量清理 |
| 改 tool description 未确认 | 违反项目契约 | 实施前确认 5.6 的具体文案 |
| 资料纠正被当作剧情变化 | 用户使用 Edit | correctCurrentFields 原位同步末项，测试日志数量不变 |

## 10. 已知妥协

1. **单一主要类型**：一条 enemy 记录里提到兄弟，不会被 sibling 类型筛选命中。需要多类型查询时另议模型，不把说明文本用于隐藏的业务筛选。
2. **关系唯一只是约定**：不会从结构上阻止重复，尤其是旧数据和并发创建。先读、选择明确 ID；不添加唯一约束或自动归并。
3. **历史按记录顺序展示**：不是全书故事时间线，也不提供任意历史位置插入。倒叙补录与真假未确认的事实需要人工确认当前态，不能假装排序已经解决。
4. **旧历史无法补回**：现存记录只能作为初始基线，过去删建丢失的经历不能由迁移推断。
5. **单条 JSON 读取／写入随历史增长**：第一版优先保证完整数据。若单条历史性能实际成为问题，再引入独立表与分页；普通图谱查询不使用 JSON 条件。
6. **修正不保留修改前的错误字段值**：Edit 资料修正直接同步当前与最新快照，不记录纠错事件，也不提供纠错审计历史；较早快照保持不变。
7. **硬删除没有回收站**：整条关系删除后，其行内历史也被删除；误录快照移除后不能从删除标记恢复。只对明确选择的关系／误录执行，不增加后台批量清理，也不把该例外扩展到端点实体。

## 11. 实施前确认与本次验证

已确认的产品决策由三个 ADR 记录。本文给出的字段、路径、baseline、写入接入与 migration 是具体实施方案，供整体审阅；没有尚未指定 owner 的技术占位项。

实施前有两个明确关口：

- 用户确认 5.6 的具体工具 description 文案后才能改运行时描述；审批对象已经列全。
- 实施者重新核对发布状态，按 5.9 的确定分支选择 v19 合并或新版本 migration；不得只凭当前源码版本判断。

本次只完成源码与规则核对、release/tag/schema 核验、方案编写及文档检查。未修改数据库、工具、UI 或技能正文，未运行 Flutter 测试或真实 LLM 评测。实际实施完成后必须逐项报告第 6 节结果。
