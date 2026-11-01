# 长篇创作状态管理方案

> 状态：实施中

## 1. 背景

长篇连载的问题不主要发生在单章内部，而发生在章与章之间。当前系统有三个缺口：

1. **状态漂移**：第 40 章用了第 12 章已丢失的物品；角色称呼变化；伏笔被遗忘。根因是跨章状态没有稳定的可读工件，writer 自行决定读什么。
2. **模式收敛**：连续多章用相同断章钩子、相同开场方式。根因是没有跨章的「已用手法」记录。
3. **outline 被覆盖**：chronicler 发布后把章节规划覆盖成摘要，写前规划丢失。

### 现状

- `Chapters.outline` 身兼两职：写前是规划节拍，发布后被 chronicler 覆盖为 100-200 字摘要。
- `CharacterProfiles.currentState` 已有角色级动态状态，但缺少小说级别的汇总视图。
- chronicler 由发布触发，也可由 orchestrator 委派做连续性核对，不绑定发布。

## 2. 目标

1. chronicler 不再覆盖 outline。outline 的写入权归用户和 orchestrator，chronicler 的摘要写到 brief。
2. chronicler 每次处理章节后生成小说状态快照（snapshot），注入 system prompt 供后续写作直接使用。
3. 每章记录紧张度、情绪标签和章内事件序列，可查询、可聚合。
4. snapshot 保留历史，可回溯。
5. snapshot 与单章写后产物用户可见：左侧栏展示当前进展和情绪张力曲线，章节编辑器展示本章事件。

### 非目标

- 不改 plot_architect / pacing_expert（Council 专属，日常写作不涉及）。
- 不做 story_position 注入。
- 不做 brief 历史版本（brief 是当前章的最新总结，覆盖即可）。
- 不给 AI 开放 snapshot 历史版本的读取路径（历史只服务人工排查）。

## 3. 核心决策

### 字段重定义

| 字段 | 含义 | 谁写 | 时机 |
|------|------|------|------|
| outline | 写前规划 | orchestrator / 用户 | 写前；chronicler 不写 |
| brief | 写后总结 | chronicler | 发布后 |
| events | 章内事件序列 | chronicler | 发布后 |
| snapshot | 累积状态 | chronicler / 用户 | 每次运行后 |

outline 的模板结构不硬编码在客户端 prompt 里，由 技能库的「章节规划」skill 维护。现有 skill 已有 4 段结构（章节连续性、当前任务、节拍序列、伏笔操作），需补充断章钩子部分。

### brief 不加表

brief 是 per-chapter 的写后总结，不需要历史版本。加字段到 `Chapters` 即可，与 outline、content 同级。`/chapters/{id}/brief` 是自然字段路径，不需要虚拟路径特殊处理。

### snapshot 要新表

snapshot 是 per-novel 的版本化工件，需要历史用于排查"状态从哪章开始错"。没有现有表能承载（`NovelStates` 是通用 KV，upsert 覆盖无历史）。

### 断章钩子放 outline

钩子是规划内容，属于 outline 模板的一部分（由章节规划 skill 维护），不加独立字段。实际使用的钩子类型由 chronicler 写进 brief，snapshot 的手法账本从最近几章 brief 中编译。

### events 与 brief 的分工

两者都是写后产物，但粒度和用途不同，不是二选一：

| | brief | events |
|---|---|---|
| 形态 | 散文式整章总结 | 结构化事件数组 |
| 粒度 | 整章一段 | 每个事件一条 |
| 用途 | 给人读、给 AI 读上下文 | 可跨章聚合、可做时间线 UI、可按事件粒度查 |

`events[].state_change` 是**单事件**的状态结论，brief 的「状态变化」段是**整章**汇总。两者有部分重叠是有意的：brief 保证一段话能读懂本章，events 保证能定位到具体哪一步改变了什么。

events 使用结构化事件字段，不含 `evidence_quote` —— 正文就在库里，原文引用是冗余。

### snapshot 注入 system prompt

snapshot 不靠 AI 主动 Read，而是**注入 system prompt**，与用户自定义规则（`PromptFragments.userRules`）走完全相同的 tail block 模式：拼在 system prompt 尾部，作为独立段落。

理由：

- snapshot 是每次续写都要用的核心状态，靠 prompt 提示「记得读」会漏；漏读等于没有。
- tail block 在 system prompt 尾部，snapshot 更新不影响前面的缓存前缀。
- 与「当前作品」元数据同级别 —— 都是无条件的会话上下文，注入方式应当一致。

只在 `status == active` 时注入。缺失或 stale 时不注入，由 `chapter_reading_boundary.md` 引导降级为直读近期章节 + 角色卡 + 伏笔。

完整快照仍可通过 `Read /novel/current_state` 获取（用于 AI 需要核对原文时）；fragment 中说明 system prompt 已含当前状态，不要重复 Read。

### snapshot 路径挂在 novel 单例下

snapshot 是 per-novel 的单一当前值，不是集合。路径定为 **`/novel/current_state`**，作为 novel 单例的一个字段，而不是单开 `/snapshots/` 根集合 —— 后者会让 AI 误以为可以列举、可以按 id 取，而实际上它只需要「当前那一份」。

历史版本留在 `novel_state_snapshot` 表里供排查用，v1 不给 AI 读取路径。

## 4. 模型设计

### 4.1 Chapters 新增字段

```
Chapters 新增：
  brief     // text, default ''      — 写后总结，chronicler 写
  tension   // integer, nullable     — 紧张度 1-10，chronicler 估算
  emotion   // text, string list     — 情绪标签（2-4字），chronicler 提取
  events    // text, json map list   — 章内事件序列，chronicler 提取
```

tension 和 emotion 分别记录章节紧张度和情绪。加入章节列表返回，AI 通过 `Read /chapters` 即可看到每章的紧张度和情绪。

events 复用 `JsonMapListConverter`。**不进章节列表返回** —— 它是重字段，列表里逐章带上会把 listing 撑爆；只在单章详情 `/chapters/{id}` 和字段路径 `/chapters/{id}/events` 返回。

### 4.2 新表 novel_state_snapshot

```
novel_state_snapshot
- id
- source_chapter_id    // 提取到哪章为止
- content              // Markdown 快照正文
- status               // active / superseded / stale
- created_at
- created_by           // chronicler / user
```

规则：

- 同一时间只有一条 active。
- 新 active 创建时，旧 active 变 superseded。
- stale 表示"之后有旧章节被修改过，内容可能不准"。

### 4.3 snapshot 内容格式

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
- 最近 5 章紧张度：{如 6,7,9,4,5}（来自 Chapters.tension）
- 距上次大高潮：{N} 章（第 {N} 章，紧张度 {X}）

## 写作手法账本（最近 5 章）
- 第 {N} 章：钩子={类型}；主导情绪={...}（来自最近 brief + Chapters.emotion）
```

「近期张力轨迹」从 `Chapters.tension` 查询，不是 chronicler 主观编写。「写作手法账本」从最近几章的 brief（实际钩子类型）和 `Chapters.emotion` 编译。

### 4.4 brief 内容格式

chronicler 发布后写入 `Chapters.brief`：

```markdown
## 本章摘要
{100-200 字}

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

outline 记计划，brief 记实际。对比能看出写偏了没有。

### 4.5 events 内容格式

chronicler 发布后写入 `Chapters.events`：

```json
[
  {
    "title": "事件标题",
    "summary": "一句话说清经过",
    "state_change": "该事件之后主线状态的变化结论"
  }
]
```

规则：

- 按章内时序排列，一章通常 3-8 条。
- 只记推动剧情或改变状态的事件；纯氛围描写、过场对话不记。
- `state_change` 写「变成了什么」而不是「发生了什么」，与 `summary` 区分开。没有实质状态变化的事件不必强行编造，留空字符串。

## 5. UI

两处：左侧栏的全书状态面板，和章节编辑器里的单章写后产物。都是只读 —— 用户要改就通过 AI 聊天说，与 snapshot 修正同一模式。

### 5.1 当前进展面板（左侧栏）

左侧栏「系统」分组新增「当前进展」入口，展示最新 active snapshot：

- snapshot Markdown 正文（只读）；snapshot 为 stale 时顶部挂提示条
- 情绪张力曲线
- 没有 snapshot 时给引导空态，不显示空白面板

**情绪张力曲线**

- **X 轴**：章节号
- **Y 轴**：紧张度 1-10（来自 `Chapters.tension`）
- **emotion 标签**：每章的情绪标签以 chip 展示在曲线节点下方（来自 `Chapters.emotion`）

数据来自 `Chapters.tension` 和 `Chapters.emotion`，不需要额外查询 snapshot 表。旧章节 tension/emotion 为 null 时曲线只画有数据的部分。

### 5.2 章节编辑器展示 events

章节编辑器展示 chronicler 的单章写后产物，让用户能直接核对 AI 提取得对不对：

- **顶部徽章行**：在已有的章节号 + 状态徽章之后，追加 tension 徽章和 emotion chip，沿用同款 pill 样式
- **本章事件卡片**：outline 卡片下方的只读折叠卡片，复用 outline 卡片的视觉（`surfaceContainerHigh` + `borderSubtle` + 折叠动画）
- 每条事件渲染为 `**标题**：经过`，`state_change` 非空时在下方缩进一行「状态变化：…」

**降级**：`events` 为空或 null 时整个卡片不渲染，不占位、不显示空态文案 —— 大量旧章节没有 events，留空卡片会让编辑器显得到处是坑。tension / emotion 为 null 时对应徽章同样不渲染。

## 6. snapshot 更新规则

### 用户规则优先

与 review 闭环同一模式：chronicler 发布后默认自动提取事实、写 brief、创建 snapshot。若用户规则禁止、限制或条件化这些行为，按规则决定；用户本次明确要求跳过时不执行，不视为阻塞，也不再次确认。已有 `useChronicler` 发布勾选开关，用户规则在其之上提供持久化控制。

### 正常推进

chronicler 处理第 N 章，N > 当前 active snapshot 的 source_chapter_id：

1. 创建新 snapshot（source_chapter_id = N，status = active）
2. 旧 active 变 superseded

### 修改旧章节

chronicler 处理第 N 章，N ≤ 当前 active snapshot 的 source_chapter_id：

1. 不创建新 snapshot
2. 当前 active 标记为 stale

### 用户修正

用户通过 AI 聊天修正 snapshot：

1. 创建新 snapshot（created_by = user，status = active）
2. 旧 active 变 superseded

### stale 恢复

orchestrator 读到 stale snapshot → 降级，直接读近期章节 + 角色卡 + 伏笔。下次正常推进（N > 水位）时自动恢复，新 snapshot 覆盖 stale。

### 汇总

| 场景 | 行为 |
|------|------|
| chronicler 处理第 N 章，N > 水位 | 新 active，旧 superseded |
| chronicler 处理第 N 章，N ≤ 水位 | 不创建，当前 active 标 stale |
| 用户修正 snapshot | 新 active（created_by=user），旧 superseded |
| orchestrator 读到 stale | 降级直读，下次推进自动恢复 |

## 7. 改动清单

### 7.1 Schema

**`lib/shared/database/novel_content_database.dart`**

- `Chapters` 表新增 `brief`（text, default ''）、`tension`（integer, nullable）、`emotion`（text, string list, nullable）、`events`（text, json map list, nullable）
- 新增 `NovelStateSnapshots` 表
- `chapters` VIEW 的 SELECT 列同步补上新增字段
- schema 尚未发布，按 AGENTS.md「未发布版本的 migration 合并」并进现有 V13 块，`schemaVersion` 保持 13；开发库用 `ALTER TABLE ... ADD COLUMN` 手动升级并查询验证

### 7.2 DAO

**NEW: `lib/shared/database/novel_content_daos/novel_state_snapshot_dao.dart`**

- `createSnapshot(...)`：事务内 supersede 旧 active，插入新 active
- `getLatestActive()` / `watchLatestActive()`：读取（订阅）最新 active snapshot
- `getById(...)`：读取历史 snapshot
- `markStale(...)`：标记当前 active 为 stale

**`lib/shared/database/novel_content_daos/chapter_dao.dart`**

- 单章查询列增加 brief、tension、emotion、events
- 章节树查询（列表）只增加 tension、emotion；events 是重字段，不进列表

**`lib/shared/services/novel_content.dart`**

- 加 snapshot 读写包装，不让 tool 层直接摸 DAO

### 7.3 AI 工具路径

**`lib/shared/services/ai/tools_support.dart`**

- pathSchema 的 novel 单例说明补 `/novel/current_state`
- `/chapters/{id}/brief`、`/chapters/{id}/events` 是自然字段路径，与 outline 同级

**`lib/shared/services/ai/tools_read.dart`**

- `Read /novel/current_state`：返回最新 active snapshot；无快照返回 not_found + hint；stale 时返回内容并带 `stale: true`
- 章节详情增加 brief、tension、emotion、events；章节列表 entries 增加 tension、emotion

**`lib/shared/services/ai/tools_write.dart`**

- `Write /novel/current_state`：payload `{value, source_chapter_id}`。**水位判断在代码里做**，不交给 prompt —— `source_chapter_id` 的章号大于当前 active 的章号则创建新 snapshot，否则标记 stale，直接实现 §6 汇总表
- `Write /chapters/{id}/brief`、`/tension`、`/emotion`、`/events`：自然字段写入
- **放宽已发布章节的写入拦截**：现有逻辑只允许已发布章节写 outline，而 chronicler 恰恰在发布后运行，需把上述四个 chronicler 字段一并放行

### 7.4 Prompt

**`assets/prompts/agent/chronicler.md`**

- 章节摘要写入 `/chapters/{id}/brief`，不再写 `/chapters/{id}/outline`
- 提取范围新增：章内事件（写入 Chapters.events）、紧张度估算（Chapters.tension）、情绪标签（Chapters.emotion）
- 工作流程追加：写 `/novel/current_state`，带 `source_chapter_id`
- 旧章节的 stale 处理由工具层水位判断自动完成，prompt 不需要区分

**`lib/shared/services/ai/prompts/use_cases/chat_prompt_use_case.dart`**

- `ChatPanelPromptInput` 增加 `storyState`
- `system()` 的 tail block 序列插入「当前故事状态」段，位置在用户自定义规则之后、当前环境之前，与 `userRules` 同构；值为空时不插

**`lib/shared/services/ai/chat_turn_runner.dart`**

- 构建 `ChatPanelPromptInput` 时读取 active snapshot 传入（仿照旁边 `novel_onboarding` 的读法）

**`assets/prompts/fragments/chapter_reading_boundary.md`**

- 说明 system prompt 已含「当前故事状态」，不要重复 Read；需要核对原文时才读 `/novel/current_state`
- 有当前状态时，不再为同类信息零散读取角色卡和伏笔列表
- 缺失或 stale 时降级为原有读取方式

### 7.5 Skill

**`skills/official/章节规划/SKILL.md`**

- 章节大纲结构补充「断章钩子」部分：类型（危机/谜题/情感/反转/抉择）+ 方向

### 7.6 UI

**`lib/shared/models/novel_workspace.dart`**

- `NovelWorkspaceSection` 新增 `story_progress`

**`lib/desktop/widgets/sidebar/rail.dart`**

- 「系统」分组新增「当前进展」入口

新增枚举值会打断所有 exhaustive switch，需同步补全 `feature_id.dart`、`app_localization.dart`、`sidebar/sections.dart`、`sidebar.dart`、`novel_editor.dart`、`novel_workspace_panel.dart`、`chat_prompt_builder.dart` 等约 15 处分支。移动端 `novel_chat_page.dart` 只补分支保证编译，不加入口（本方案的当前进展面板是桌面端功能）。

**NEW: `lib/desktop/widgets/workspace/story_progress_panel.dart`**

- 展示最新 active snapshot 的 Markdown 正文（只读）；stale 时顶部挂提示条
- 情绪张力曲线：折线图（tension）+ 每章 emotion chip
- 数据来源：`NovelStateSnapshotDao.watchLatestActive()` + `ChapterDao` 查询 tension/emotion
- 无 snapshot 时给引导空态，不显示空白面板

**`lib/desktop/widgets/workspace/chapter_editor.dart`**

- 顶部徽章行追加 tension / emotion
- outline 卡片下方新增只读「本章事件」折叠卡片；events 为空不渲染

### 7.7 不改的部分

- `plot_architect.md`、`pacing_expert.md`：Council 专属，不改
- `council_round.md`：不改
- `orchestrator.md`：创意预热已有「最俗版本」自问，不改
- `writer.md`：不改（通过 fragment 和委派说明获得约束）
- `review.md`：不改（现有三态裁决够用）

## 8. 迁移

- 旧数据不回填 snapshot，也不生成 brief
- 旧章节的 outline 保持现状（已发布的章节 outline 是摘要，无法恢复原始规划）
- 新表为空时不注入「当前故事状态」段，`Read /novel/current_state` 返回 not_found + hint，orchestrator 降级为旧读取方式
- `tension`、`emotion`、`events` 旧章节为 null，chronicler 后续处理新章节时逐步填充；UI 对 null 一律不渲染对应组件

## 9. 验收标准

| 类别 | 标准 | 验证方式 |
|------|------|----------|
| 功能 | chronicler 发布后 brief 写入 Chapters.brief，outline 不变 | 工具测试 |
| 功能 | chronicler 后新增 active snapshot，旧 active 变 superseded | DAO 单测 |
| 功能 | 修改旧章节后 snapshot 标 stale，不创建新 snapshot | DAO 单测 |
| 功能 | `Read /novel/current_state` 返回最新 active snapshot | 工具测试 |
| 功能 | `Write /novel/current_state` 按水位自动分流：新章创建 active，旧章标 stale | 工具测试 |
| 功能 | 章节列表返回包含 tension、emotion；events 不在列表中 | 工具测试 |
| 功能 | chronicler 提取的 events 写入 Chapters.events | 工具测试 |
| 功能 | `Read /chapters/{id}/events` 返回事件数组 | 工具测试 |
| 功能 | 已发布章节可写 brief / tension / emotion / events | 工具测试 |
| Prompt | active snapshot 存在时 system prompt 含「当前故事状态」段 | prompt 渲染测试 |
| Prompt | snapshot 缺失或 stale 时不注入该段 | prompt 渲染测试 |
| 兼容 | 没有 snapshot 的旧书降级为原有读取方式（orchestrator 直接读近期章节 + 角色卡 + 伏笔，和现状一样） | 手动测试 |
| Prompt | chronicler 不再写 outline | prompt 渲染测试 |
| UI | 左侧栏「系统-当前进展」展示 snapshot 和情绪张力曲线 | Widget 测试 |
| UI | 旧章节 tension/emotion 为 null 时曲线正常降级 | Widget 测试 |
| UI | 章节编辑器展示 events 卡片与 tension/emotion 徽章 | Widget 测试 |
| UI | events 为空时事件卡片不渲染 | Widget 测试 |

受影响目录的测试命令：

```bash
fvm flutter test test/shared/database
fvm flutter test test/shared/services/ai
```

## 10. 风险

| 风险 | 触发条件 | 影响 | 对策 |
|------|----------|------|------|
| snapshot 腐化 | chronicler 漏事实或写错事实 | 后续写作被错误状态带偏 | 保留历史；允许 stale 标记；水位校验暴露缺口 |
| 旧章节修改后状态不一致 | 改第 19 章但 snapshot 停在第 30 章 | snapshot 不准确 | stale 标记 + 降级直读 + 下次推进自动恢复 |
| 紧张度主观 | chronicler 估值不精确 | 张力轨迹不可靠 | 只作为粗信号，不作为硬业务判断 |
| 旧书无 snapshot | 旧书首次进入新流程 | 写作前无 latest snapshot | 降级旧读取方式，下一次 chronicler 自动建立 |
| 旧章节 outline 已是摘要 | 历史数据 outline 被 chronicler 覆盖过 | 无法恢复原始规划 | 不回填，新章节开始 outline 保持稳定 |
