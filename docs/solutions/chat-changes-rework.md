# Chat Changes Rework — 默认接受 + 变更日志 + 轮次回退重发

> 综合本轮讨论的四个决策：默认接受 AI 改动、把"待确认卡"重做成"最近变更日志"、变更行去掉行数改用类型标签、新增"回退本轮变更并重发"。桌面 + 移动统一。

## 1. 背景 `[核心]`

### 现状

1. AI 对作品的改动通过 `WorkingOverlayService` **先真实写入正文**，再以 `working_change.status` 标记可逆状态：`active`(待决) / `committed`(已固化) / `rejected` / `conflicted`。编辑器里看到的始终是改后的文本，没有"应用前预览"。
2. 桌面 `PendingChangesSummaryCard` 挂在 composer 上方（`composer.dart:219`、`chat_side_panel.dart:79`），是"决策门"：逐条 + 全部 接受/拒绝，「查看变更」开 `PendingChangesDetailDialog`。移动端**没有**对应实现（仅设计稿 `designs/mobile/m_ai.jsx` 的 mock）。
3. 接受 = `commitWorkingChanges`(固化进 `ChangeCommits`/`ChangeCommitItems`)；拒绝 = `rejectWorkingChange`(`_revertActivePatch`，**带冲突检测**，撤不干净标 `conflicted` 并抛错)。
4. commit 后回滚走 `rollbackCommit({commitId, resourceId?})`：把字段**整体反写回 `oldText`** 再记一次手动 commit，**无冲突检测**，last-write-wins。
5. 设置项 `aiAgentAutoAcceptProvider` 已存在（默认 `false`）。开启时摘要卡只显示**失败**的改动(`_filterVisibleChanges`)。
6. `commitManualSave` 在用户手动保存时，会先把同 scope 内所有 active 的 AI patch 自动 commit —— "决策门"本就是漏的，勤保存用户事实上已在 soft auto-accept。
7. 摘要卡每行展示 `lineDelta` 算出的 `+X -Y` 行数；头部用 `</>` 图标 + 「N 个文件已更改」。
8. 会话有重试能力 `ChatSessionController.retry(assistantMessageId)`（复用前一条 user 消息文本重跑），但**没有**"回退本轮对作品的改动并把 prompt 放回输入框编辑重发"的能力。

### 问题

```text
问题 A：决策门与现实脱节
- 症状：改动已经在正文里了，却还要逐条点"接受"。
- 根因：working overlay 是"先写后固化"，accept 只是"固化"，不是"应用"。
- 影响：高频无谓摩擦；多步 agent 编辑时尤其痛。

问题 B：行数 diff 在散文里是误导信号
- 症状：整段改写显示 +1-1（像小改），新增整场戏显示 +1（像没动）。
- 根因：一行 diff ≠ 一个意义单位；正文段落是软换行长行。
- 影响：用户无法从摘要判断"AI 到底动了多少 / 动了什么性质"。

问题 C：代码隐喻错位
- 症状：</> 图标 + "文件" 字样，但 _buildSubtitle 又在翻"正文/简介/伏笔"。
- 影响：写作 app 里出现程序员心智，自相矛盾。

问题 D：无法"这轮重来"
- 症状：用户想"撤销 AI 本轮对作品的改动，改写 prompt 再发一次"，没有入口。
- 根因：缺少轮次维度的回退原语 + 重发动线。
- 影响：用户只能手动逐条回滚 + 手动重打字，或 fork 会话。
```

### 约束

- 不破坏既有数据：旧 `working_changes` / `change_commits` 必须继续可读、可回滚。
- 散文字段是整体文本替换，**无法做三方合并**——回退精度受此天花板限制（见已知妥协）。
- Drift 表变更必须遵循 `.agents/rules/db-migration.md`（schemaVersion + onUpgrade + 模型同步）；当前 `novel_content_database.dart` schemaVersion = 5。
- 跨平台共用逻辑进 `lib/shared`（见 `cross-platform-ui-in-shared` 记忆），桌面用 Dialog、移动用 Sheet 各包壳。
- 兜底逻辑禁止静默降级（`.agents/rules/error-handling.md`）：回退覆盖手改这种破坏性行为必须显式提示。

## 2. 目标 `[核心]`

### 目标

1. **默认接受**：AI 改动落地即生效，不再要求逐条确认（`aiAgentAutoAccept` 默认 `true`）。
2. **变更日志**：摘要卡转为"本会话最近 AI 改了哪些"，每条可一键回退；非"接受吗"的决策门。
3. **轮次回退重发**：用户消息上提供「回退到本轮对话发起前」，一键完成：回滚本轮对作品的改动 + 移除本轮 AI 回复 + 把原 prompt 放回输入框供编辑重发。
4. **诚实回退**：对某条/某轮回退时，若目标字段在 AI 改动后又被改过，UI 显式提示"回退会覆盖之后的改动"，不静默 last-write-wins。
5. **去行数**：变更行不再显示 `+X -Y` 行数，改为改动类型标签（新增/改写/扩写/删减）；头部如需分量感用字数增量。
6. 桌面与移动端行为一致，日志/回退核心逻辑在 `lib/shared`。

### 非目标

1. 不做散文字段的三方合并/逐句 merge。
2. 不改 `change_history_panel`（全量历史）的定位；本方案只管"本会话最近 + 本轮"。
3. 不实现图 2 的 Regenerate（同 prompt 重生成）——作为日后快捷特例，本期不做。
4. 不改 AI 编辑的工具协议/写入路径本身。

### 成功信号

| 信号 | 验证方式 |
|------|----------|
| 默认配置下 AI 改完无需点接受，正文即生效 | 手动检查 + 单测 `aiAgentAutoAccept` 默认值 |
| 变更日志列出本会话改动并能逐条回退 | 集成测试：发起一轮→日志出现→回退→正文复原 |
| 轮次回退后正文复原、AI 回复消失、prompt 回到输入框 | 集成测试 `rollbackTurn` + 控制器动线 |
| 字段在 AI 改后被手改，回退时出现覆盖提示 | 单测：构造冲突态，断言提示分支 |
| 变更行无行数、显示类型标签 | Widget 测试 |

## 3. User Stories `[按需]`

1. 作为作者，我希望 AI 改完直接生效、并能在日志里看到改了哪些，以便不被"逐条接受"打断心流。
2. 作为作者，我希望「回退到本轮对话发起前」一键撤销这轮 AI 对稿子的改动并让我改写 prompt 重发，以便快速试不同指令。
3. 作为作者，当我已经手动润色过 AI 改过的段落、又去回退那次 AI 改动时，我希望被告知"会覆盖我后来的改动"，以便不在不知情下丢失手改。
4. 作为维护者，我希望轮次回退是一个 `lib/shared` 原语，桌面/移动共用，以便两端行为不分叉。

## 4. 解决方案 `[核心]`

本方案含两个独立决策点，分别比较。

### 决策一：默认接受 + 摘要卡定位

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|------|------|------|------|------|
| A 保持决策门 | 维持 `aiAgentAutoAccept=false`，逐条接受 | 接受前有冲突检测(`reject`) | 高频摩擦；门本就漏(`commitManualSave`) | 放弃 |
| B 默认接受 + 卡转日志 | 默认 `true`，摘要卡→"最近变更日志 + 逐条回退" | 零摩擦；符合"先写后固化"现实；复用现有 commit/rollback | 回退精度低于 reject（见决策三补偿） | **推荐** |
| C 默认接受 + 无任何展示 | 改完即固化，只能去全量 history | 最简 | "改了哪些"无落脚；不可发现 | 放弃 |

**推荐 B**：`auto-accept` 设施已存在、`commitManualSave` 已证明门是软的；卡片从"接受吗"改成"AI 改了这些 + 一键回退"，把唯一比它强的"冲突保护"用决策三在 UI 层补回。

### 决策二：变更行的信息粒度

| 方案 | 做法 | 结论 |
|------|------|------|
| A `+X -Y` 行数 | 现状，`lineDelta` | 放弃：散文里 line≠意义单位，误导 |
| B 改动类型标签 | 新增/改写/扩写/删减 | **推荐**：作者真正关心的维度 |
| C 字数增量 | `+N字` | 头部可选保留作总量；净字数会藏改写，不能替代类型 |

**推荐 B（行内）+ C（头部可选）**：per-row 去 `+X -Y`，只留 `图标 + 标题/字段 + 类型标签`；精确 diff 留给 detail dialog。顺带删除 `lineDelta` 在摘要层的依赖（净减法）。

### 决策三：轮次回退按钮形态（图 1 vs 图 2）

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|------|------|------|------|------|
| 图 1 用户消息上的 `↩ 回退到本轮对话发起前` | 锚在发起该轮的 user 消息 | 作用域清晰("这条往后")；可编辑重发；对正文操作诚实 | 需轮次回退原语 | **推荐** |
| 图 2 AI 回复上的 `↻ Regenerate` | 同 prompt 重生成 | 模式通用、用户熟悉 | 不带改 prompt；把"正文被回滚"藏在刷新图标后，破坏性不可见 | 放弃(本期) |

**推荐图 1**：需求是"回滚本轮变更 + **重新发送消息**"=可编辑重发，正是图 1 的检查点回退语义；且与"回退要 legible"原则一致。图 2 是不同意图（同 prompt 重来），作为日后快捷方式。

### 核心原则

1. **先写后固化不变**：仍是 overlay 写入→commit；本方案改的是"何时固化(默认自动)"与"如何展示/回退"。
2. **回退要 legible**：任何把正文倒回的操作都要有明确文案；覆盖手改必须显式提示。
3. **轮次回退是 shared 原语**：`rollbackTurn` 进 `WorkingOverlayService`，两端共用。
4. **摘要层给类型+总量，明细层给精确 diff**：行数不在任何摘要层出现。

### 关键假设

| 假设 | 如果不成立 | 应对 |
|------|------------|------|
| 默认接受下，一轮的改动在轮末被 commit，不会跨轮 active 合并 | `stageTextChange` 的 `_getActiveWorkingChange` 会把跨轮同资源 active patch 合并，丢失轮边界 | 轮末由 turn runner 主动 commit 本轮改动并打 `sourceTurnId`；active 合并仅发生在同轮内 |
| 通过 `working_changes.sourceTurnId` 能覆盖 active + committed 两态回退 | committed 行不保留或不可 join commit items | 已确认 `ChangeCommitItems.workingChangeId` 可 join；committed 的 working_change 行保留 |
| turn id 是一次工具执行上下文，而不是会话/工具管理器状态 | 把 `sourceTurnId` 保存到 `AiToolManager` / runtime / Agent 会产生 stale 值或跨轮泄漏 | 新增 `ToolExecutionContext`，由 `Agent.process` 随本轮工具调用显式传递，tool manager 只消费不持久保存 |
| 用户能接受散文回退是"字段级整体倒回" | 用户期望逐句 merge | 写进已知妥协 + 覆盖提示 |

## 5. 方案实施

### 5.1 模型设计 `[按需]`

给 `WorkingChanges` 增加轮次标记，作为"本轮变更"的唯一锚点：

```text
working_changes  (+1 列)
- sourceTurnId: text nullable   // 触发该改动的 user 消息 id（= 轮次 id）
  · AI 改动落地时由 ToolExecutionContext 写入当前轮的 user message id
  · 旧数据为 null：回退按轮不可用，退化为按条回退（兼容）
  · active 同资源合并时保留首条的 sourceTurnId（与 sourceSessionId 行为一致）
```

新增工具执行上下文，作为本轮 `Agent.process` 的只读参数：

```text
ToolExecutionContext
- sourceSessionId: string?   // 当前 chat session id，用于本会话变更列表
- sourceTurnId: string?      // 当前 user message id，用于轮次回退
```

设计约束：

- `sourceTurnId` 不能写进 `AiChatRuntime` / `Agent` / `AiToolManager` 的长期字段。
- `AiToolManager` 只能从本次 `executeTool` 收到的 `ToolExecutionContext` 读取 turn id，并把它传给 `WorkingOverlayService`。
- 无上下文的工具调用保持兼容：`sourceTurnId = null`，按轮回退不可用，按条回退仍可用。
- 子 Agent 的工具调用默认继承父轮次上下文；子 Agent 产生的改动属于触发它的父 user turn，便于一次回退撤销整轮工作。

回退某轮的解析路径（无需给 commit 加列）：

```text
sourceTurnId = T
 → working_changes where sourceTurnId = T
     ├─ status active     → rejectWorkingChange（带冲突检测）
     └─ status committed  → 经 ChangeCommitItems.workingChangeId 找到 commit item，
                            反向应用（reverse-apply），但先做冲突探测（见 5.3）
```

### 5.2 关键业务流程 `[核心]`

**A. 默认接受（轮末自动固化）**

```text
1. ChatSessionController 先 addUserMessage，得到 user message id
2. ChatTurnRunner.runTurn 构造 ToolExecutionContext(sourceTurnId = user message id)
3. Agent.process(text, toolExecutionContext: context)
4. Agent 执行工具时把 context 传给 AgentToolDispatcher.executeTool(...)
5. AiToolManager 的 Write/Edit/Create/Remove 等写入工具把 context.sourceTurnId 传给 WorkingOverlayService
6. 轮结束（runTurn 完成）→ 若 aiAgentAutoAccept：commitWorkingChanges(本轮 active ai changes)
7. 变更日志（原摘要卡）展示本会话最近 N 条已固化/未决改动 + 逐条回退入口
```

**B. 轮次回退并重发（图 1，happy path）**

```text
1. 用户在某条 user 消息上点 ↩「回退到本轮对话发起前」
2. 解析该轮：rollbackTurn(turnId = 该 user 消息 id)
   - 逐条：active→reject；committed→reverse-apply
3. 控制器截断会话：移除该 user 消息之后（含本轮 assistant 回复）的消息
4. 把原 prompt 文本放回 composer（draft），聚焦输入框
5. 用户编辑后发送 → 正常 send 新一轮
```

**C. 回退遇到"改后又被改过"（冲突，关键失败路径）**

```text
1. reverse-apply 前读取字段 currentText
2. 若 currentText != 该改动的 newText（说明 AI 改后又被改过）：
   - 不静默覆盖
   - 弹确认："此处在 AI 改动后又被修改，回退会覆盖之后的改动，是否继续？"
   - 用户确认 → 覆盖并记一次手动 commit；取消 → 跳过该条，回退其余
3. active 态走 rejectWorkingChange 原有冲突检测：撤不干净标 conflicted 并提示
```

### 5.4 改动清单 `[核心]`

#### `lib/shared/database/novel_content_database.dart`
- `WorkingChanges`：新增 `TextColumn get sourceTurnId => text().nullable()();`
- `schemaVersion` 5 → 6；`onUpgrade` 增加 `from 5 to 6` 分支 `ALTER TABLE working_changes ADD COLUMN source_turn_id TEXT;`
- 跑 Flutter 代码生成（`flutter pub run build_runner build`）刷新 `.drift.dart` / 模型 `WorkingChange` / `WorkingChangesCompanion`。

#### `lib/shared/services/working_overlay.dart`
- `stageTextChange(...)` / `stageCreateChange(...)`：新增可选参 `String? sourceTurnId`；写入与合并逻辑参照 `sourceSessionId`（合并保留 `prior.sourceTurnId ?? sourceTurnId`）。
- 新增原语 `Future<TurnRollbackResult> rollbackTurn({required String turnId, bool overwriteNewerEdits = false})`：
  - 查 `working_changes where sourceTurnId = turnId`；
  - active → `rejectWorkingChange`；committed → 经 `ChangeCommitItems.workingChangeId` 反向应用；
  - reverse-apply 前做冲突探测（`currentText == change.newText` 才安全）；不安全且 `overwriteNewerEdits=false` → 收集进 `result.conflicted`，跳过；
  - 反向改动统一 `commitManualSave(message: 'history.commit_message.rollback_turn')`。
- 新增返回类型 `TurnRollbackResult { rolledBack: int, conflicted: List<ConflictedField>, skipped: int }`。

#### `lib/shared/agent/agent_tool_dispatcher.dart`
- 新增 `ToolExecutionContext`：
  - `String? sourceSessionId`
  - `String? sourceTurnId`
- `AgentToolDispatcher.executeTool(...)` 新增可选参数 `ToolExecutionContext? context`。
- fake / test dispatcher 默认忽略 context，保持旧测试可最小迁移。

#### `lib/shared/agent/agent.dart`
- `Agent.process(...)` 新增可选参数 `ToolExecutionContext? toolExecutionContext`。
- Agent 内部执行工具时，将 `toolExecutionContext` 传给 `_toolManager.executeTool(...)`。
- `fork` / spawn 子 Agent 共享同一轮次上下文；不要在 Agent 实例上保存 turn id。

#### `lib/shared/services/ai/chat_turn_runner.dart`
- `runTurn(..., userMessageId)` 构造 `ToolExecutionContext(sourceSessionId: 当前 session id, sourceTurnId: userMessageId)`，调用 `agent.process(text, toolExecutionContext: context)`。
- retry 复用原 user message id；headless seed 使用 seed user message id。
- 不在 `ChatTurnRunner` / `AiChatRuntime` / `Agent` / `AiToolManager` 上持久保存 `sourceTurnId`。
- `runTurn` 结束：若 `aiAgentAutoAccept`，commit 本轮 active ai changes（保证轮末固化、不跨轮 active 合并）。

#### `lib/shared/services/ai/tools.dart`
- `AiToolManager.executeTool(...)` 接收 `ToolExecutionContext? context`。
- `_stageTextChange(...)` / `_stageCreateChange(...)` 从 `context?.sourceTurnId` 取轮次 id，并传给 `WorkingOverlayService`。
- 删除/避免 `AiToolManager.sourceTurnId` 这类长期可变字段；工具管理器只消费本次调用上下文。

#### `lib/shared/services/ai/chat_session_controller.dart`
- 新增 `Future<void> rollbackTurnAndPrepareResend(String userMessageId)`：
  1. `workingOverlay.rollbackTurn(turnId: userMessageId)`（含冲突确认回调）；
  2. 截断会话至该 user 消息之前（复用/参照 fork 的截断逻辑）；
  3. 经现有 draft 机制（`AiChatDraftMessage`）把原 prompt 放回 composer。

#### `lib/shared/providers/settings_providers.dart`
- **彻底移除** `aiAgentAutoAccept` 设置：删除 `AppSettings` 字段、持久化 key、`setAiAgentAutoAccept`、设置区开关行。auto-accept 强制常开，`aiAgentAutoAcceptProvider` 直接返回 `true`。
- 不保留向后兼容：旧用户曾显式关闭的偏好**不需要尊重**（auto-accept 是新的固定行为，回退能力由变更日志 + 轮次回退兜底）。

#### `lib/desktop/widgets/ai/diff/pending_changes_summary_card.dart`（重做为变更日志）
- 头部：移除 `</>` 与「N 个文件已更改」，改 `RevericIcons` 文档/历史图标 + 「最近改动 · N 处」；移除头部 `+X -Y`（如需总量改 `+N字`）。
- 行：移除 per-row `+${added}/-${removed}`；新增改动类型标签（`changeType` → 新增/改写/扩写/删减，create 已可判别，其余按 old/new 是否非空推导）。
- 行尾操作：由"接受/拒绝"改为单一「回退」（调 `rollbackTurn` 的按条变体或 per-change reject/rollback）；移除底部"全部接受/全部丢弃"，保留"全部回退"（可选）。
- 删除 `_resolveChanges` 中对摘要层 `lineDelta` 的使用（detail 仍用）。

#### `lib/desktop/widgets/ai/chat/composer.dart` / `chat_side_panel.dart`
- 挂载条件由 `pendingAiChanges.isNotEmpty` 改为"本会话有最近改动"；默认折叠（auto-accept 下不抢输入区）。

#### NEW: `lib/shared/widgets/ai/diff/recent_changes_log.dart`
- 抽出两端共用的"最近变更日志"展示 + 回退逻辑（resolve 标题、类型标签、回退调用、冲突提示）。桌面包 Dialog/inline，移动包 Sheet（对齐 `cross-platform-ui-in-shared`）。

#### `lib/shared/widgets/ai/chat/chat_message_view.dart`（MessageActionBar，两端共用）
- user 消息 action bar 新增 `↩` 按钮（图 1），`tooltip = 回退到本轮对话发起前`，回调 `rollbackTurnAndPrepareResend(message.id)`；仅当该轮存在 AI 改动或可截断时显示。

#### `lib/mobile/pages/novel_chat_page.dart` + `designs/mobile/m_ai.jsx`
- 移动端接入 `recent_changes_log`：默认单行 bar（`✦ AI 改了 N 处 [查看]`），「查看」开全屏 review sheet；逐条回退在 sheet 内大目标操作。
- 同步设计稿 `PendingChangesCard` → 日志形态、去行数。

#### i18n 三件套（`.agents/rules/i18n.md`）
- `locale_keys.dart` + `assets/translations/{en,zh-CN}/{workspace,ai,common}.json` 新增：
  - `aiRollbackTurnTooltip` = 「回退到本轮对话发起前」/ "Revert to before this turn"
  - `aiRollbackConflictHint` = 「此处在 AI 改动后又被修改，回退会覆盖之后的改动」/ "This was edited after the AI change; reverting will overwrite later edits"
  - `workspaceRecentChanges` = 「最近改动」/ "Recent changes"
  - 改动类型：`commonChangeCreate/Rewrite/Expand/Trim` = 新增/改写/扩写/删减
  - 移除不再使用的 `workspaceFilesChanged`（若无他处引用）。

### 5.5 Task Graph `[按需]`

先以 mockup 确认交互，再落地。代码相关步骤一律在 mockup 确认后进行。

```text
PR-1 Mockup 交互确认（先做）
  └─ PR-2 去开关 + 硬编码默认接受
       └─ PR-3 DB migration: working_changes.sourceTurnId (v5→6)
            └─ PR-4 ToolExecutionContext + Overlay 原语 rollbackTurn
                 ├─ PR-5 turn runner 传执行上下文 + 轮末 auto-commit
                 │    └─ PR-6 控制器 rollbackTurnAndPrepareResend（回退+截断+draft重发）
                 │         └─ PR-8 图1 回退按钮接入 MessageActionBar（两端）
                 └─ PR-7 变更日志 UI: shared recent_changes_log + 桌面/移动接入（去行数/类型标签）
  PR-9 i18n + 测试（随对应 UI/逻辑 PR 收尾）
```

| 任务 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| PR-1 | 改 `designs/desktop/ChatPanel.jsx` + `designs/mobile/m_ai.jsx`：待确认卡→最近变更日志（去决策门/去行数/加类型标签）；user 消息加图1 `↩ 回退到本轮对话发起前`；移动端折叠 bar + 全屏 review sheet | 无 | 浏览 mockup 确认交互，签字后继续 |
| PR-2 | **彻底移除** auto-accept 设置（删 `AppSettings` 字段/key/setter + `ai_agents_settings_section.dart` 开关行）；`aiAgentAutoAcceptProvider` 固定返回 true。不保留旧偏好兼容 | PR-1 | 设置页无开关；全局读到 true；现有 reader（card/`chat/state.dart`）行为正确 |
| PR-3 | `WorkingChanges` 加 `sourceTurnId` 列；schemaVersion 5→6 + onUpgrade；跑 Flutter codegen | PR-2 | 迁移单测；旧库升级不丢数据 |
| PR-4 | 新增 `ToolExecutionContext` 并沿 `Agent.process` → `AgentToolDispatcher.executeTool` → `AiToolManager` 传递；`stageTextChange`/`stageCreateChange` 加 `sourceTurnId` 参；新增 `rollbackTurn` + `TurnRollbackResult` | PR-3 | 单测：工具上下文不落全局状态；`working_overlay` active/committed/create/冲突三态 |
| PR-5 | `chat_turn_runner.runTurn` 为每轮构造 `ToolExecutionContext`；`runTurn` 末若 auto-accept 则 commit 本轮 active ai changes | PR-4 | 集成：Write/Create 改动都有正确 turnId 且轮末固化；retry/headless 带正确 turnId |
| PR-6 | `chat_session_controller.rollbackTurnAndPrepareResend`：回退轮次 + 截断会话至该 user 消息前 + draft 放回 prompt | PR-4（标记需 PR-5） | 集成：正文复原 + AI 回复消失 + prompt 回输入框 |
| PR-7 | NEW `lib/shared/widgets/ai/diff/recent_changes_log.dart`；重做 `pending_changes_summary_card`（去行数/类型标签/逐条回退/默认折叠）；桌面 `composer.dart`+`chat_side_panel.dart` 与移动 `novel_chat_page.dart` 接入 | PR-4, PR-2 | Widget 测试：无行数、类型标签、回退；两端一致 |
| PR-8 | `chat_message_view.dart` MessageActionBar：user 消息加图1 `↩`，回调 PR-6；仅本轮有改动/可截断时显示 | PR-6 | 集成：点 ↩ 走完整动线 |
| PR-9 | i18n 三件套（5.4 列出的 key）+ 各触及目录测试（Rule 14 串行） | PR-7, PR-8 | `flutter test` 对应目录通过 |

### 5.6 Migration `[按需]`

```text
novel_content_database: from version 5 to 6
1. ALTER TABLE working_changes ADD COLUMN source_turn_id TEXT;   // nullable，默认 NULL
2. 无需 backfill：旧 working_change 的 sourceTurnId = NULL
3. 回滚兼容：sourceTurnId=NULL 的轮次回退不可用，UI 对旧消息隐藏 ↩，退化为按条回退
```

- 默认值：NULL。
- 失败处理：onUpgrade 失败按现有 DB 打开失败路径处理（不静默吞）。
- 是否可回滚：加列为加性变更，旧版本读取忽略新列即可。

## 6. 验收标准 `[核心]`

| 类别 | 标准 | 验证方式 |
|------|------|----------|
| 功能 | 默认配置 AI 改完即生效，无需接受 | 单测：`aiAgentAutoAccept` 默认 true；集成：改完正文已变且无待决门 |
| 功能 | 变更日志列出本会话改动，逐条回退后正文复原 | 集成测试 |
| 功能 | user 消息 ↩ 一键完成 回退正文 + 删本轮 AI 回复 + prompt 回输入框 | 集成测试 `rollbackTurnAndPrepareResend` |
| 功能 | 变更行无 `+X -Y`，显示类型标签 | Widget 测试 |
| 数据正确性 | Write/Edit/Create 等 AI 写入都记录 `source_turn_id`；同一轮子 Agent 改动继承父轮次 id | 单测 + 集成测试 |
| 架构边界 | `sourceTurnId` 不保存在 runtime/Agent/toolManager 长期状态，只通过 `ToolExecutionContext` 传递 | 代码检查 + 单测断言 |
| 错误处理 | 字段 AI 改后被手改，回退弹覆盖确认，取消则跳过该条、回退其余 | 单测构造冲突态 |
| 兼容 | 旧 `working_changes`(sourceTurnId=NULL) 仍可按条回退；旧消息不显示 ↩ | 集成测试 + 手动 |
| 兼容 | auto-accept 强制常开，旧用户关闭偏好不保留（已决策，无需尊重） | 代码检查：无设置项、provider 返回 true |
| 可维护性 | 日志/回退核心在 `lib/shared`，两端复用 | 代码检查 |

测试命令（按 Rule 14，串行）：
- `flutter test test/shared/services/working_overlay`（或对应目录）
- `flutter test test/shared/services/ai`
- `flutter test test/shared/widgets/ai`
- 触及 desktop/mobile widget 的对应目录测试。

## 7. 风险 `[核心]`

| 风险 | 触发条件 | 影响 | 对策 |
|------|----------|------|------|
| 跨轮 active 合并丢轮边界 | auto-accept 关 + 同资源连续两轮都 active | 轮次回退把两轮当一轮 | 轮末主动 commit（假设1）；关 auto-accept 时提示回退粒度可能变粗 |
| reverse-apply 覆盖手改 | AI 改后用户又手改同字段，再回退该轮 | 手改被覆盖（仍可从 history 再翻回） | 5.3 冲突探测 + 显式确认；默认不覆盖 |
| 截断会话误删 | 回退轮在会话中间，后续还有别的轮 | 误删后续对话 | 图 1 语义即"回到发起前"，明确删该消息往后；执行前确认文案点明范围 |
| 默认接受让用户措手不及 | 老用户习惯逐条接受 | 信任/控制感下降 | 变更日志常驻可见 + 一键回退兜底（auto-accept 固定常开，不提供关闭） |
| migration 失败 | 加列失败 | DB 打不开 | 加性变更风险低；沿用现有 DB 失败处理，不静默 |

## 8. 已知妥协 `[按需]`

```text
1. 妥协：散文回退是"字段级整体倒回"，非逐句 merge。
   - 原因：正文字段是整体文本，三方合并成本高、对小说语义无清晰边界。
   - 影响：回退 AI 改动时，该字段上的手改会被一并倒回（有覆盖提示 + history 可再翻回）。
   - 升级触发：用户频繁在 AI 改过的段落手改后回退、且抱怨丢改。
   - 后续方向：引入段落级/句级 diff 锚点做更细回退，或回退前自动 fork 一份手改快照。

2. 妥协：本期不做图 2 Regenerate（同 prompt 重生成）。
   - 原因：与图 1 是不同意图，本需求出口是可编辑重发。
   - 影响："同 prompt 换结果"仍需手动重发。
   - 升级触发：用户高频"原样重来"。
   - 后续方向：基于 rollbackTurn 加 AI 回复上的 ↻ 快捷（回退本轮 + 用原 prompt 自动重发）。
```
