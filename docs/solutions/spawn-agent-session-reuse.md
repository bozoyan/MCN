# SpawnAgent Session Reuse 方案

> 状态：方案设计。
>
> 档位：**完整档**（涉及 AI tool 编排、底层 agent runtime 边界、既有子会话持久化与非确定性 SubAgent 输出）。
>
> 关联文档：[ADR: SpawnAgent reuses sessions only by explicit session id](../adr/0002-explicit-spawn-session-reuse.md)。

## 1. 背景 `[核心]`

### 现状

1. `SpawnAgent` 的 tool schema 定义在 `lib/shared/services/ai/tools_subagent.dart`，工具目录与 `AiToolManager` 注册在 `lib/shared/services/ai/tools.dart`。
2. `AiToolManager.registerAllTools()` 当前会注册 `SpawnAgent`，但 handler 是 `throw StateError('SpawnAgent must be intercepted by Agent')`。
3. 真正的 `SpawnAgent` 执行逻辑位于 `lib/shared/agent/agent.dart`：`Agent._dispatchTool()` 特判 `SpawnAgent`，`Agent._runSpawnAgent()` 查找 `SpawnableAgent`、解析子 agent 模型、创建子 `Agent.custom()`、执行任务。
4. `agent` package 内部没有独立的 SpawnAgent 业务调用点。实际调用链集中在 `lib/shared/services/ai/chat_turn_runner.dart`：构造 `SpawnableAgentRegistry`，把 `subAgents` / `spawnAgentRunRecorder` / `subAgentClientResolver` 传给 `Agent.custom()`。
5. 每次 SpawnAgent 完成都会创建一个新的子会话：`parentId = 顶层 chat session id`，`agentSlug = 子 agent slug`，`ai_chat_messages` 保存子 agent 的完整消息历史。

### 问题

问题一：**底层 Agent runtime 感知了产品层 SpawnAgent 语义。**

- 症状：`lib/shared/agent/agent.dart` 内有 `SpawnAgentRunRecord`、`SpawnableAgent`、`SpawnableAgentRegistry`、`SubAgentClientResolver`、`_runSpawnAgent()`。
- 根因：`SpawnAgent` 起初作为 agent loop 的特殊工具实现，被下沉到 runtime。
- 影响：继续支持 Spawn Session Reuse 时，很容易把 `session_id`、`parentId`、`agentSlug`、持久化校验继续塞进底层 agent，扩大边界污染。

问题二：**服务层声明工具，底层 runtime 执行业务工具，方向反了。**

- 症状：`AiToolManager` 注册 `SpawnAgent` 但要求 `Agent` 拦截。
- 根因：tool definition 与 tool execution 没有统一归属到服务层。
- 影响：工具能力扩展依赖修改底层 runtime，测试与维护成本上升。

问题三：**当前 SpawnAgent 只能新建 Spawn Session，不能显式续写旧会话。**

- 症状：同一个 Chat SubAgent 多次被委派时，历史上下文被拆成多个 `sub_session_*`。
- 根因：`SpawnAgent` schema 只有 `name/task`；执行逻辑没有加载既有子会话历史的入口。
- 影响：需要长期上下文的专业子 agent（如编年史者、内容核验）无法自然延续自己的工作记录。

### 约束

1. `lib/shared/agent` 是底层 agent runtime，不得新增或继续扩大 Spawn Session / SubAgent / chat persistence 语义。
2. Spawn Session Reuse 只支持**显式 `session_id`**；不做自动选择 latest session。
3. 复用时追加写回原 Spawn Session，不 fork 新子会话。
4. SubAgent prompt / model / tools 配置变化后，旧 Spawn Session 仍允许复用。
5. 不做数据库 schema migration；复用现有 `ai_chat_sessions.parentId`、`agentSlug`、`mode` 与 `ai_chat_messages`。
6. 不改变未传 `session_id` 时的既有行为：仍创建新的 isolated Spawn Session。

## 2. 目标 `[核心]`

### 目标

1. 将 `SpawnAgent` 的业务执行从 `lib/shared/agent/agent.dart` 迁出到 `lib/shared/services/ai`。
2. 底层 `Agent` 只通过 `AgentToolDispatcher.executeTool()` 调用工具，不再特判 `SpawnAgent`。
3. `SpawnAgent` 新增显式 `session_id` 参数；不传时保持新建子会话。
4. 传入合法 `session_id` 时，加载该 Spawn Session 的历史消息，继续运行同一个 Chat SubAgent，并保存回同一个 session。
5. 传入非法 `session_id` 时 fail loud，返回明确工具错误，不降级新建。
6. 保持现有 SpawnAgent 工具卡片、子会话落库、模型 metadata 展示行为。

### 非目标

1. 不实现自动复用最近的 Spawn Session。
2. 不实现 Spawn Session fork。
3. 不新增 SubAgent session 管理 UI。
4. 不校验旧 session 的 prompt hash / model hash / allowed tools hash。
5. 不重构 council / theater / roleplay / monologue 的 agent loop。
6. 不重命名 `ai_chat_sessions` 表或 `AiChatSession` 模型。

### 成功信号

| 信号 | 验证方式 |
|------|----------|
| `lib/shared/agent/agent.dart` 不再包含 `SpawnAgent` / `SpawnableAgent` / `SpawnAgentRunRecord` | `rg "SpawnAgent|SpawnableAgent|SpawnAgentRunRecord" lib/shared/agent` |
| `SpawnAgent` 由 services 层 dispatcher / handler 执行 | 单测 + 文件检查 |
| 不传 `session_id` 时仍创建新 `sub_session_*` | service 单测 |
| 传合法 `session_id` 时写回同一 session id | service 单测 |
| 非法 `session_id` 不新建子会话 | service 单测 |
| prompt/model/tools 变化后仍能复用 | service 单测 |

## 3. User Stories `[按需]`

1. 作为作者，我希望编年史者等子 agent 能继续自己的上一次工作会话，以便长期核验不从零开始。
2. 作为作者，我希望只有明确指定旧 Spawn Session 时才复用，以免一次临时委派污染长期上下文。
3. 作为维护者，我希望底层 Agent 不知道业务工具，以便后续新增产品工具时不修改 runtime。
4. 作为排查者，我希望工具结果明确返回 `sub_session_id`，能定位本次委派写到了哪个子会话。
5. 作为维护者，我希望非法复用请求 fail loud，以便发现 parent/agent 不匹配等状态错误。

## 4. 解决方案 `[核心]`

### 方案对比

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|------|------|------|------|------|
| A. 继续在 `Agent._runSpawnAgent()` 加 `session_id` | 最小改动，在底层 Agent 加 loader/recorder 复用逻辑 | 短期最快 | 把 `session_id`、持久化校验、Spawn Session 语义塞进底层 runtime，边界继续恶化 | 放弃 |
| B. 在 `AiToolManager` 内直接实现 SpawnAgent | `AiToolManager.registerAllTools()` 给 SpawnAgent 注册真实 handler | 工具定义与执行归到 services 层 | `AiToolManager` 已经很大；handler 需要当前 chat session、provider resolver、persistence、subagent 列表，构造参数会膨胀 | 放弃 |
| C. 新增 services 层 `SpawnAgentHandler` + dispatcher wrapper | `ChatTurnRunner` 创建包装 `AgentToolDispatcher`，只拦截 SpawnAgent，其余委托 `AiToolManager` | 底层 Agent 变纯；SpawnAgent 业务归 services 层；不继续膨胀 `AiToolManager`；后续可单测 handler | 需要先迁移现有 SpawnAgent 行为，再加复用 | 推荐 |

### 决策

推荐方案：**C. 新增 services 层 `SpawnAgentHandler` + dispatcher wrapper**。

选择理由：

1. `SpawnAgent` 是 chat orchestrator 的产品层能力，不是 agent runtime 的通用能力。
2. dispatcher wrapper 是最小边界修复：`Agent` 仍只认识 `AgentToolDispatcher`，不认识业务工具。
3. `SpawnAgentHandler` 可以集中管理子 agent 选择、模型解析、历史恢复、落库和工具结果，不污染 `AiToolManager` 的通用资源工具职责。
4. 复用逻辑需要 `parentSessionId`、`AiSessionPersistenceService`、`NovelContentDatabase`、`SubAgent` 配置，这些天然都在 `ChatTurnRunner` / services 层。

### 核心原则

1. **Agent runtime 不知道 SpawnAgent。** `Agent._dispatchTool()` 不允许出现业务工具名分支。
2. **显式复用。** 只有 `session_id` 非空时才加载旧 Spawn Session。
3. **校验失败即失败。** 复用请求不合法时返回工具错误，不自动新建 session。
4. **复用不冻结配置。** 子 agent 运行使用当前 prompt / model / tools 配置。
5. **消息转换复用现有路径。** 持久化消息恢复继续用 `convertAiMessageToAgentMessagesForModel()`；落库继续用 `prepareSpawnAgentRunMessagesForPersistence()`。

### 关键假设

| 假设 | 如果不成立 | 应对 |
|------|------------|------|
| `SpawnAgent` 生产调用只来自 chat orchestrator 路径 | 其它入口依赖 Agent 内置特判 | 搜索并迁移对应入口到 dispatcher wrapper |
| 子会话历史可以完整恢复成 AgentMessage | 历史工具结果恢复缺失导致模型上下文不完整 | 先补复用恢复单测，沿用现有 tool_result 合并逻辑 |
| `parentId + agentSlug` 足以判定 Spawn Session 兼容 | 同一 slug 多配置版本混用造成语义混乱 | V1 接受；后续加 metadata hash |
| 保存完整消息覆盖原 session 可接受 | 并发复用同一 session 导致后写覆盖 | V1 保持 Agent 工具循环串行；如出现并发入口，增加 session 级运行锁 |

## 5. 方案实施

### 5.1 模型设计 `[按需]`

不新增数据库模型。新增 services 层运行时模型：

```text
SpawnAgentRequest
- name: String
- task: String
- sessionId: String?

SpawnAgentRunPersistenceTarget
- sessionId: String
- isReuse: bool

SpawnAgentResult
- ok: bool
- output: String
- persistedSessionId: String?
- providerId: String?
- model: String?
- errorCode: String?
- error: String?
```

说明：

- `sessionId` 使用 tool schema 字段 `session_id`，Dart 内部可映射为 `sessionId`。
- `persistedSessionId` 是本次工具结果应返回给模型和 UI 的 `sub_session_id`。
- `initialMessages` 只来自目标 Spawn Session，不包含顶层 chat session 历史。

### 5.2 关系 `[按需]`

```text
Top-level Chat Session
  |
  | 1:N parentId
  v
Spawn Session ---- N:1 ---- Chat SubAgent(agentSlug)
  |
  | 1:N sessionId
  v
AI Chat Message
```

删除/归档策略沿用现有会话策略。本方案不新增级联删除规则。

### 5.3 关键业务流程 `[核心]`

#### 新建 Spawn Session

```text
1. Orchestrator 调用 SpawnAgent(name, task)。
2. ChatAgentToolDispatcher 拦截 SpawnAgent。
3. SpawnAgentHandler 解析 name/task，找到 enabled Chat SubAgent。
4. Handler 根据当前 SubAgent 配置解析 provider/model 和 allowed tools。
5. Handler 创建子 Agent，initialMessages 为空。
6. 子 Agent 执行 task。
7. Handler 创建 sub_session_*，parentId = 顶层 session id，agentSlug = SubAgent slug。
8. Handler 保存子 Agent 消息历史。
9. Handler 返回 { ok, output, sub_session_id }。
```

#### 复用 Spawn Session

```text
1. Orchestrator 调用 SpawnAgent(name, task, session_id)。
2. Handler 读取 session_id 对应会话。
3. Handler 校验：
   - session 存在
   - session.parentId == 当前顶层 session id
   - session.agentSlug == 当前 SubAgent slug
   - session.mode == chat
4. Handler 加载该 session 的消息，转换为 AgentMessage。
5. Handler 创建子 Agent，initialMessages = 旧 Spawn Session 历史。
6. 子 Agent 执行新的 task。
7. Handler 将完整新历史保存回同一个 session_id。
8. Handler 返回 { ok, output, sub_session_id: session_id }。
```

#### 复用失败

```text
1. Orchestrator 调用 SpawnAgent(name, task, session_id)。
2. Handler 校验失败。
3. Handler 返回 { ok: false, error, error_code }。
4. 不创建新 sub_session_*。
5. 不修改任何既有消息。
```

### 5.4 改动清单 `[核心]`

#### `lib/shared/agent/agent.dart`

- 删除 `SpawnAgentRunRecord`、`SpawnAgentRunRecorder`、`SubAgentClientResolver`。
- 删除 `SpawnableAgent`、`SpawnableAgentRegistry`。
- 删除 `_runSpawnAgent()` 与 `_runForkAgent()` 工具特判。
- `_dispatchTool()` 只调用 `_toolManager.executeTool(...)`。
- 保留 `ForkConfig` 与 `Agent.fork()` 作为底层 runtime 能力，但不作为工具名特判。
- 删除仅服务 SpawnAgent 的 `traceHooksForSpawn` import。

#### `lib/shared/services/ai/spawn_agent_handler.dart`（新增）

- `SpawnAgentHandler.run()`：执行 SpawnAgent tool。
- `_parseRequest()`：解析 `name/task/session_id`。
- `_resolveSubAgent()`：按 name 查找 enabled SubAgent。
- `_resolveSubAgentClient()`：按当前 SubAgent provider/model 解析 client，失败时回退父模型。
- `_loadReusableSession()`：校验并加载显式 session_id。
- `_runSubAgent()`：创建并运行子 `Agent.custom()`。
- `_persistRun()`：新建或覆盖保存 Spawn Session。

#### `lib/shared/services/ai/chat_agent_tool_dispatcher.dart`（新增）

- 实现 `AgentToolDispatcher`。
- `executeTool()` 中只拦截 `SpawnAgent`，其余工具委托给 inner dispatcher。
- `allToolNames()` / `allToolDefs()` / `toolDefsForNames()` 委托 inner，保持 LLM 可见工具列表不变。

#### `lib/shared/services/ai/chat_turn_runner.dart`

- 删除 `_toSpawnableAgents()` 与 `SpawnableAgentRegistry` 构造。
- 创建 `SpawnAgentHandler`，注入：
  - `availableSubAgents`
  - 当前 `ProviderClient` / `AgentConfig`
  - `AiToolManager`
  - `parentSessionId`
  - `AiSessionPersistenceService`
  - `NovelContentDatabase`
  - 当前顶层 session provider/model
  - pricing / trace hooks
- 主 orchestrator `Agent.custom()` 的 `toolManager` 改为 `ChatAgentToolDispatcher(inner: tm, spawnAgentHandler: handler)`。
- 不再向 `Agent.custom()` 传 `subAgents`、`spawnAgentRunRecorder`、`subAgentClientResolver`。

#### `lib/shared/services/ai/tools.dart`

- `SpawnAgent` 注册真实可执行 handler 的前提改为：如果 `AiToolManager` 单独执行到 SpawnAgent，返回明确错误 `SpawnAgent is only available through chat orchestrator dispatcher`，不再要求 Agent 拦截。
- 保持 `buildToolDefs()` 暴露 `SpawnAgent`。

#### `lib/shared/services/ai/tools_subagent.dart`

- 迁移完成后新增 optional `session_id` 字段。
- description 明确：
  - 不传 `session_id` 新建 isolated Spawn Session。
  - 传 `session_id` 只复用该 Spawn Session 自己的历史。
  - `session_id` 必须属于当前主会话下同一 SubAgent。

#### `lib/shared/services/ai/agent_message_mapping.dart`

- 保持 `prepareSpawnAgentRunMessagesForPersistence()`。
- 如测试发现复用恢复缺口，补充转换测试，不新增并行转换逻辑。

#### `CONTEXT.md`

- 已新增 `Spawn Session` 与 `Spawn Session Reuse` 领域词。

#### `docs/adr/0002-explicit-spawn-session-reuse.md`

- 记录“只支持显式 session id 复用”的决策。

### 5.5 Task Graph `[按需]`

| 任务 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| PR-1 边界迁移 | 新增 dispatcher wrapper 与 SpawnAgentHandler；迁出现有 SpawnAgent 行为；删除 Agent 内置 SpawnAgent | 无 | 现有 SpawnAgent 行为测试通过 |
| PR-2 显式复用 | 给 handler 加 `session_id` 解析、校验、加载、写回 | PR-1 | 新增复用单测 |
| PR-3 schema 暴露 | 更新 `tools_subagent.dart` schema/description 与 prompt 使用说明 | PR-2 | tool schema 测试 |
| PR-4 清理与文档 | 清理旧类型、更新相关注释/solution/ADR | PR-1/2/3 | `rg` 检查 |

### 5.6 Migration `[按需]`

无 Drift schema migration。

旧数据兼容策略：

1. 既有 `sub_session_*` 已有 `parentId` 与 `agentSlug`，可直接作为可复用 Spawn Session。
2. 旧 Spawn Session 没有 prompt/model/tool snapshot，V1 不校验配置版本。
3. 旧消息按现有 `loadSessionMessages()` + `convertAiMessageToAgentMessagesForModel()` 恢复。
4. 不做一次性补数据脚本。

### 5.7 上线后验证 `[按需]`

| 指标 / 日志 / 数据 | 目的 | 异常信号 | 观察周期 |
|-------------------|------|----------|----------|
| SpawnAgent result 中 `sub_session_id` | 确认新建/复用目标正确 | 复用请求返回新 id | 开发期 + 首轮手动验证 |
| 复用校验失败日志 | 排查 parent/agent 不匹配 | 同一用户频繁失败 | 首周 |
| SpawnAgent handler 错误率 | 发现迁移后工具不可用 | `ok:false` 比例明显上升 | 首周 |
| 子会话消息数量增长 | 发现重复覆盖或未追加 | 复用后消息数量不增长 | 开发期 |

## 6. 验收标准 `[核心]`

| 类别 | 标准 | 验证方式 |
|------|------|----------|
| 边界 | `lib/shared/agent` 不再出现 SpawnAgent 业务类型与特判 | `rg "SpawnAgent|SpawnableAgent|SpawnAgentRunRecord|SubAgentClientResolver" lib/shared/agent` |
| 兼容 | 不传 `session_id` 时行为与现状一致：新建子会话并返回 `sub_session_id` | `flutter test test/shared/services/ai` |
| 功能 | 传合法 `session_id` 时加载旧消息，并写回同一 session | service 单测 |
| 错误处理 | 不存在 / parent 不匹配 / agentSlug 不匹配 / mode 不匹配均返回工具错误，不新建 session | service 单测 |
| 配置变化 | SubAgent prompt/model/tools 改变后，仍可复用旧 session | service 单测 |
| Tool schema | `SpawnAgent` schema 暴露 optional `session_id`，required 仍只有 `name/task` | `flutter test test/shared/services/ai/tools_design_test.dart` |
| 落库 | 复用写回继续合并 tool_result，不产生孤立 running tool block | `flutter test test/shared/services/ai/spawn_agent_message_persistence_test.dart` |

## 7. 评测 `[按需]`

### 评测对象

- 被测能力：Orchestrator 是否在明确需要延续子 agent 上下文时传入已有 `sub_session_id`。
- 不测内容：自动选择最新 session；子 agent 输出质量本身。
- 输入来源：固定 prompt 场景 + 已存在的子会话 id。
- 输出判定：deterministic tool call 检查为主，人工抽查为辅。

### 评测场景

| 场景 | 输入 | 期望 | 判定方式 |
|------|------|------|----------|
| 新建委派 | “请让编年史者检查这一章事实” | SpawnAgent 不带 `session_id` | deterministic |
| 明确继续 | “继续用刚才的编年史者子会话检查下一章，session 是 sub_session_1” | SpawnAgent 带 `session_id: sub_session_1` | deterministic |
| 错误 session | 提供属于其它 parent 的 session id | 工具返回错误，orchestrator 不声称已完成 | deterministic |
| 配置变化 | 改 SubAgent prompt 后复用旧 session | 工具可执行并写回同 session | deterministic |

### 自动化与人工评测边界

- 自动化覆盖 handler 校验、消息加载、写回目标、tool result payload。
- 人工抽查 orchestrator prompt 是否能在用户明确给出 session id 时使用 `session_id`。
- 不把模型是否“主动猜测应该复用”作为 V1 阻断标准，因为 V1 不支持自动复用。

## 8. Token 成本 `[按需]`

| 维度 | 估计 | 说明 |
|------|------|------|
| 单次复用输入 token | 增加旧 Spawn Session 历史长度 | 只加载目标子会话历史，不加载顶层 chat 历史 |
| 调用次数 | 不变 | 仍是一次 SpawnAgent 子 agent 调用 |
| 上下文增长 | 随该 Spawn Session 消息数增长 | 可被现有 AgentContextManager 压缩策略限制 |
| 模型档位 | 不变 | 使用当前 SubAgent 配置模型；未配置时继承父会话模型 |

成本控制：

1. 不自动复用，避免无意把长历史带入每次委派。
2. 复用只加载指定 Spawn Session，不复制顶层 chat transcript。
3. 如未来长子会话成本过高，再给 Spawn Session 引入 context snapshot / summary，不属于 V1。

## 9. 风险 `[核心]`

| 风险 | 触发条件 | 影响 | 对策 |
|------|----------|------|------|
| 迁移出 Agent 时破坏现有 SpawnAgent 行为 | dispatcher wrapper 未正确接管 SpawnAgent | Orchestrator 无法委派 SubAgent | PR-1 先只迁移不加复用，用现有行为测试锁定 |
| 非法 session 被复用 | 校验缺 parentId/agentSlug/mode | 子 agent 读到错误历史 | handler 集中校验，失败不降级 |
| 并发写同一 Spawn Session | 同一顶层会话同时发起两个复用请求 | 后写覆盖前写 | V1 保持 Agent 工具循环串行；如出现并发入口，增加 session 级运行锁 |
| 旧消息恢复不完整 | tool_result 合并或恢复路径有缺口 | 模型看到不完整工具上下文 | 复用单测覆盖 tool call + tool result 历史 |
| schema 先暴露后实现 | 模型传 `session_id` 但 runtime 不支持 | 用户看到错误行为 | 必须先完成 handler 复用测试，再改 `tools_subagent.dart` |
| prompt/model/tools 变化造成语义漂移 | 用户复用很旧的 Spawn Session | 子 agent 历史与当前身份不完全一致 | V1 明确接受；后续可加 metadata 提示或 hash 检查 |

## 10. 已知妥协 `[按需]`

1. 妥协：V1 不自动选择最近 Spawn Session。
   - 原因：自动复用隐藏上下文，容易污染委派结果。
   - 影响：用户或 orchestrator 必须显式知道 `sub_session_id`。
   - 升级触发：用户频繁要求“继续刚才那个子 agent”，且显式 id 成本过高。
   - 后续方向：在 tool result / UI 中提供可引用的最近 Spawn Session affordance，但仍让调用显式。

2. 妥协：V1 不校验 prompt/model/tools snapshot。
   - 原因：当前 schema 未存 snapshot；增加 hash 需要额外 metadata 设计。
   - 影响：旧 session 可能被新配置的 SubAgent 继续。
   - 升级触发：出现“同名 SubAgent 改配置后复用旧历史导致错误”的真实案例。
   - 后续方向：在 session metadata 存 `sub_agent_prompt_hash` / `tool_names_hash` / `model_ref`。

3. 妥协：复用写回采用完整消息同步。
   - 原因：现有 `saveMessages()` 与 tool_result 合并路径成熟。
   - 影响：并发复用时可能后写覆盖。
   - 升级触发：出现同一 Spawn Session 并发运行需求。
   - 后续方向：引入 session run lock 或 append-only completed messages 写入策略。
