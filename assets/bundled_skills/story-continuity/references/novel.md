# 小说事实提取

处理任务指定的小说章节，优先记录能防止后续创作逻辑混乱和角色崩坏的硬事实。

调用细节（参数、路径发现、关系类型枚举、字段合法值）以工具描述与系统 prompt 中的路径规则为准；本指南只规定提取什么、写哪里、以及稳定性门槛。

跨作品参考需注明来源，不能记成当前小说已发生的事实；与当前正文或已确认设定冲突时，记录双方来源，交由编排者向用户确认。关系两端及 `chapter_id` 只能引用本作实体和章节，不能直接复用外部 ID。

## 工作流程

1. **Read 章节** — 用 listing/query 定位本章（如 `/chapters?chapter_num=N`），复制返回的章节 path；再读 `{path}/content` 与 `{path}/outline`（outline 只读，写前规划归用户和编排者）。
2. **Read 已有实体** — 读 `/characters`、`/factions`、`/skills`、`/items` 等集合，了解已有实体。
3. **Read 与 GraphSearch** — Read 已有关系（含 ended）进行查重，GraphSearch 对核心角色展开当前生效网络（depth=2）。
4. **提取并保存** — 按下方范围用 Create / Write / Remove 落库。
5. **连续性核对** — 对角色状态、时间线、地点、关系、道具和伏笔做最小必要核对；明显冲突写入 brief「待核对」，不要编造修复。
6. **更新全书状态快照** — `Write story_state`，在正文中注明覆盖到的章节。

## 提取范围

### 1. 角色（Characters）
对有意义的角色提取信息，**一次性出现的纯路人（无台词、无剧情影响、仅群演/背景）不要提取**。

**字段语义**（稳定 vs 动态）：
- **name**: 全名；与已有名称一致时视为候选同一角色，用 Write 更新
- **role**: `protagonist` / `antagonist` / `supporting` / `minor`
- **gender**: `male` / `female` / `non_binary` / `other` / `unknown`
- **aliases**: 本章明确属于同一人的别名、称号、简称或译名
- **biography**: 稳定历史小传，只补本章明确揭示的新经历
- **appearance**: 稳定视觉外观；不要写临时装束或伤势
- **personality**: 稳定内在性格；须有明确人物判断或多次行为证据，禁止单次表现改写
- **description**: 稳定外在描述（声线、习惯动作、公开印象）；不要写外观、临时伤势或情绪
- **behavior_tags**: `{tag, context}`；单次情境反应不足以建标签
- **current_state**: 本章结束时的动态快照（位置、伤势/消耗、能力、持有物、公开身份、情绪、目标、已知信息）

**同名与创建**：
1. 先 Read `/characters`；entries 的 `id` 即角色 ID。创建前用 `/characters?search=`（匹配 name / aliases / identity）。
2. 能合理对应同一人 → 禁止 Create；合并稳定新事实到 biography/appearance/description；personality / behavior_tags 满足证据门槛才改；以本章证据更新 current_state；返工旧章时保留后续仍成立的动态状态。
3. 同名但明显不是同一人 → 才允许 Create，并在 biography 写清区分点。
4. 无法判断 → 不贸然 Create；不确定性写入 brief「待核对」。
5. 更新 aliases 或 behavior_tags 前先 Read 完整对象，合并保留既有有效项，不要用本章局部结果整表覆盖。

**跳过**：无独立姓名的路人；仅一句群体反应的群演；纯氛围无名角色。

### 2. 关系（Relationships）
记录角色之间、角色与其他实体之间的重要关系。

先按 skill 的附件读取流程加载 `references/relations.md`，按其中的类型、方向与去重规则操作。章节证据使用真实 `chapter_id` 与 `proof`，不填 `scene_id`；ID 必须来自之前工具结果。描述写清触发事件与当前状态，不要只写「关系变好」。仅用 Write 将已核实结束的原关系设为 ended，并提供 reason 与 proof。

### 3. 地点（Locations）
章节中出现的场景地点。同名已存在则不要加序号或括号；用 `Read /locations?search=` 核对。

### 4. 技能与物品（Skills & Items）
新出现用 Create；变化（损坏、进化、转移、消耗）用 Write 反映。与角色的持有/学习关系先 Read 查重，已有关系用 Write 记录变化，缺少时才 `Create /relations`。

### 5. 势力（Factions）
新势力 Create；成员与立场变化用关系与内容更新记录。

### 6. 事实落点

| 类型 | 优先写入 |
|------|----------|
| 时间线 / 空间线 / 伏笔 / 信息边界 / 世界规则 / 未结冲突 | brief；仍生效的累积进 `story_state` |
| 单角色位置、伤势、持有物、情绪、目标、已知信息 | 角色 `current_state`；摘要进 brief「状态变化」 |
| 关系建立/强化/破裂 | 缺少记录时 `Create /relations`；已有记录用 `Write /relations/{id}` 记录变化，结束设为 ended；必要时在 brief 点一句 |
| 无独立工具的事实 | 压缩进 brief，不要跳过 |

### 7. 本章总结（Brief）

**不要写 outline。** 总结写进 `{chapter_path}/brief`。

```markdown
## 本章摘要
{100-200 字：主要情节推进、关键冲突和转折、角色行动和决策}

## 状态变化
- {角色}：{位置 / 伤势 / 持有物 / 情绪 / 目标变化}
- {物品}：{获得 / 失去 / 损坏 / 转交}

## 伏笔变化
- 新埋：{标题}
- 推进：{标题}
- 回收：{标题}

## 信息边界变化
- {秘密}：{谁知道了 / 谁仍不知道 / 谁产生误判}

## 实际断章钩子
- 类型：{危机 / 谜题 / 情感 / 反转 / 抉择}
```

### 8. 章内事件（Events）

写 `{chapter_path}/events` 为 `[{title, summary, state_change}]`：

```json
[
  {"title": "密室交易", "summary": "林越用假印信换回妹妹的卖身契", "state_change": "林越持有卖身契，但假印信落在对方手里"}
]
```

1. 按章内时序，通常 3-8 条；只记推动剧情或改变状态的事件
2. `state_change` 写「变成了什么」，与 `summary` 区分；无实质变化时留空
3. brief 与 events 并存：brief 一段话读懂本章，events 定位每一步状态变化

### 9. 紧张度与情绪（Tension & Emotion）

- `{chapter_path}/tension`：1-10 整数，**按全书尺度**打分，不要按本章内部起伏
- `{chapter_path}/emotion`：2-4 字标签数组，写本章主导情绪，不罗列全部出现过的情绪

### 10. 全书状态快照（Current State）

调用：`Write {"path": "story_state", "fields": {"content": "<markdown>"}}`。

后续创作对话靠 `Read story_state` 取用这份快照，是下一章作者最主要的状态来源。

```markdown
# 故事状态（截至第 {N} 章）

## 时间与空间
- 故事内当前时间：{...}
- {角色}：{当前位置}（仅主要角色，≤6 行）

## 角色硬状态
- {角色}：{伤势·消耗} / {持有关键物} / {当前目标} / {最大误判}（≤6 行）

## 信息边界
- {秘密}：{谁知道 / 谁不知道 / 谁误判}（≤5 行）

## 活跃伏笔
- {标题}：{状态} / 预期回收窗口（≤8 行）

## 未结冲突
- {冲突}：{状态} / 双方下一步（≤4 行）

## 近期张力轨迹
- 最近 5 章紧张度：{如 6,7,9,4,5}
- 距上次大高潮：{N} 章（第 {N} 章，紧张度 {X}）

## 写作手法账本（最近 5 章）
- 第 {N} 章：钩子={类型}；主导情绪={...}
```

1. **累积状态**，不是本章摘要。先 Read `story_state`，再增量更新变化项，不要每次从零重写
2. 「近期张力轨迹」和「写作手法账本」从 tension / emotion / brief 汇总，不要凭印象编
3. 行数上限是硬约束；超出时删最不影响下一章的条目
4. 只保留仍生效的状态；已了结冲突、已回收伏笔、已痊愈伤势要删掉
5. 在正文中如实记录覆盖到的章节。返工早期章节时，修正受影响的事实，保留后续仍成立的状态；不要用早期章节摘要覆盖全书当前状态。

## 提取原则

1. **只提取明确信息**：仅从原文提取，不编造未提及内容
2. **完整性**：不遗漏重要角色、地点与会改变续写的硬事实
3. **校正优先**：章节暗示已有设定需修正时用 Write 更新
4. **中文输出**：biography、appearance、personality、description、behavior_tags、current_state 等用中文
5. **面向续写**：优先下一章必须知道的事实，少写评价性语言
6. **产出去向**：brief、events、tension、emotion、实体/关系与 `story_state`；outline 只读不写
