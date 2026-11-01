# Remote Assistant × WeChat Bridge

> 完整档。涉及跨模块改动、AI 非确定性输出。
> 相关 ADR：[0002](../adr/0002-remote-assistant-parallel-entry-point.md)、[0006](../adr/0006-remote-assistant-app-db-persistence.md)。
> ADR [0003](../adr/0003-async-run-task-completion-hook.md)、[0005](../adr/0005-task-comments-bidirectional-channel.md) 被本版方案取代（task comment 作为**双向通道**移除；comment 作为下行 artifact 经 `session_subscriptions` 的 task_comments 订阅者部分回归，接线另立方案），需补 superseded 标记。
> ADR [0004](../adr/0004-virtual-novelid-remote-assistant-sessions.md)（虚拟 novelId sentinel）被 ADR-0006（Assistant 对话持久化于 app DB 专属表）取代——sentinel 只解决 session 行落库，解决不了消息持久化（消息只存在于各 novel content DB），而 Assistant 对话历史必须跨重启保留。

## 1. 背景

### 现状

- reveric 是 Flutter 桌面写作应用，AI agent（Chat Orchestrator）在桌面 chat 入口处理用户指令，绑定 novel-scoped session。
- **Task Run** 以 task 为 seed 后台跑一轮 Orchestrator chat session（full agency、可观察可中断），入口 `TaskActions.runTask`（`lib/shared/providers/task_providers.dart#L132`），防重入靠 `isRequestInFlight`（`lib/shared/providers/task_providers.dart#L150`）。
- `runHeadlessSessionTurn`（`lib/shared/services/ai/headless_session_turn.dart#L211`）是非 UI 入口，Task Run 复用它，`askUserHandler` 传入 auto-cancel。
- Agent 内核（`lib/shared/agent/agent.dart`）已支持 turn 进行中注入：`steer()`（agent.dart:155）在每个 LLM round 前 drain（agent.dart:362），即 tool-call 边界注入 user message；面板侧还有 `takeQueuedAgentText` 队列接力（chat_turn_runner.dart:1780）。
- `AiToolManager`（`lib/shared/services/ai/tools.dart#L682`）构造时绑定单一 `NovelContentService`，工具无 per-call novelId 参数 → 跨小说操作需要 cross-novel 的中枢 agent 承接。`AskUser` 工具只在传入 `askUserCallback` 时注册（tools.dart:1043）。
- **Bridge 层已落地**：`WechatAdapter` / `wechat_api.dart`（iLink 协议封装，含 QR 登录、长轮询、chunking、typing）、`RemoteBridgeService`（生命周期、per-chatId 串行路由、`onInboundMessage` 扩展点）、桌面设置页 QR UI 与状态指示，均已合入（`lib/shared/services/remote/`、`lib/desktop/widgets/settings/remote_assistant_settings_section.dart`）。

### 问题

- 用户离开电脑时无法和 agent 沟通、无法启动/观察 Task Run。
- 长时间 Task Run（写一章可能数分钟）期间用户被绑在桌面前，无法远程观察进度或中途纠偏。
- bridge 入站消息目前只落日志（`onInboundMessage` 未接 AI），链路未闭环。

### 约束

- **WeChat 单会话**：一个用户与 bot 只有一条消息流，无 topic / 多会话。这条流必须同时承载闲聊、查询、跨小说管理、对运行中任务的指示 → **必须有一个稳定的多路分发中枢**。
- **WeChat iLink Bot 协议**：纯本地长轮询收消息 + HTTP 发消息，无 webhook；无 inline button；无消息编辑；只有 sendtyping 能触发"正在输入"；`context_token` 必须回传。
- **不引入 Node.js 依赖**：bridge 全部 Dart，运行在 reveric 桌面进程内（已实现）。
- **不破坏现有 Chat Orchestrator / Task Run 模型**：Remote Assistant 是平行 agent（ADR-0002）。
- **AiChatSessions.novelId 非空，且消息表只存在于各 novel content DB**：Remote Assistant 对话不塞进 novel-scoped 持久化，用 app DB 专属表 `assistant_sessions` / `assistant_messages`（ADR-0006）跨重启保留；不引入虚拟 novelId（ADR-0004 已废弃）。
- **跨平台权限**：WeChat bridge 仅桌面端启用，mobile 不接入。

## 2. 目标

### 目标

1. 用户在微信发消息，reveric 桌面进程内的 Remote Assistant agent 响应（同一持久 session）。
2. Remote Assistant 能列出小说、启动 Job（后台 headless session）、查询 Job 状态。不创建 Task。
3. Job 期间 Orchestrator 产出的 text block（进度自述、提问）由代码直接转发到微信，无 LLM 中继。
4. 用户在微信的消息由 Assistant 识别意图；属于对运行中/等待中 Job 的指示或回答时，注入该 Job（在跑 → steer 注入；idle → 作为 seed 开新 turn 续跑）。
5. Job 的 Orchestrator 需要用户输入时直接文字提问并自然结束 turn（不注入 AskUser 工具），用户回复经 Assistant 路由续跑。
6. bridge 登录态与 Assistant 对话历史跨 app 重启保留：重启免重扫 QR，微信继续同一 Assistant session。

### 非目标

1. V1 不支持 WeChat 之外的 channel（adapter 抽象已预留，`channel_adapter.dart`）。
2. V1 Remote Assistant 不直接读写 novel workspace（只通过 Job 间接）。
3. V1 不做敏感操作确认 + 速率限制（已知风险，见 §10）。
4. bridge 凭证不做加密存储（明文入 app DB，keychain 为后续方向，见 §10）。
5. 不支持消息编辑 / inline button / streaming preview。
6. app 重启会终止**进行中的 turn 执行**（内存 agent、steer 队列随之作废，非妥协）；run session 本身持久化，可经 `send_to_job` idle 路径续跑，订阅关系存 `session_subscriptions` 表，续跑后转发自动恢复。
7. V1 不做 Assistant 对话的桌面回看 UI（对话已持久化于 app DB 专属表，Assistant session 不在 `AiChatSessions`，桌面 chat 面板不直接可见）。后续方向是在 app home page 直接聊 Assistant（§5.2 未来扩展），届时自然获得回看与继续对话。

### 成功信号

| 信号 | 验证方式 |
|------|----------|
| 微信发"列出小说"收到列表 | 手动 |
| 微信发"开始写第3章"后 Assistant 启动 Job（不建 Task） | 手动 + `[RemoteBridge]` 日志 |
| Job 期间 Orchestrator 的进度 text block 出现在微信（带来源标签） | 手动 |
| Job 中途微信发"用张三这个名字"，下一个 tool-call 边界注入生效 | 手动 + `[RemoteBridge]` 日志 |
| Job 文字提问后停住；微信回复后同 session 续跑 | 手动 + session transcript |
| 桌面扫码后 bridge online | 已落地（手动回归） |
| app 重启后 bridge 自动恢复 online（免扫码） | 手动重启 + `[RemoteBridge]` 日志 |
| app 重启后微信继续对话，Assistant 保有此前上下文 | 手动 + session transcript |

## 3. User Stories

1. 作为作者，我希望在微信发"开始写第3章"，reveric 直接启动 Job（后台 headless session），以便我离开电脑也能让 agent 工作。Job 不是待办 Task。
2. 作为作者，我希望 Job 期间 agent 的进度自述自动转发到微信，以便我远程观察进展。
3. 作为作者，我希望在微信回复"用张三这个名字"，它能在 agent 下一个动作前生效，以便我中途纠正方向。
4. 作为作者，我希望 agent 拿不准时直接在微信问我、等我回复后继续，以便远程协作和桌面 chat 一样自然。
5. 作为作者，我希望在微信问"进度怎样"，Assistant 查 Job 状态总结回复，以便我不打断 agent 也能了解状态。

## 4. 解决方案

### 方案对比

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|------|------|------|------|------|
| A. Hub Assistant + run 直连管道 + session 订阅表 | cross-novel Assistant 独占微信会话做意图分发；run 的 text block 由代码按 `session_subscriptions` 订阅转发下行；用户指示经 `send_to_job` 走 agent 内核 `steer()`/新 turn 上行；提问 = turn 自然结束 | 无 LLM 中继、纠偏秒级生效、复用内核已有机制、订阅关系显式建模（可扩展第二类订阅者） | 每条用户消息一次 Assistant turn（单会话多路复用的必然代价）；一张新表 + migration | 推荐 |
| B. 微信直连 novel-scoped session | chatId 直接绑定 Orchestrator session | 最薄 | 微信单会话：长 turn 独占唯一通道，无法同时问进度/管理其他小说 | 放弃 |
| C. Task Comment 双向通道（前版方案） | TaskComments 表持久化中转，agent comment 触发 Assistant turn 决定转发，用户指示写 comment 等 agent pull | comment 可审计 | 转发是用 LLM 做确定性路由（违反 Rule 5，token 无界放大）；用户指示 pull-based，纠偏不保证及时 | 放弃（ADR-0003/0005 需 superseded） |
| D. 扩展 Chat Orchestrator 处理远程 | Orchestrator 加 channel adapter | 复用现有 agent | Orchestrator novel-scoped 与 cross-novel 路由不匹配 | 放弃 |

### 决策

推荐方案：A。

选择理由：

1. 微信单会话约束决定必须有 cross-novel 中枢（否决 B）；中枢只做 judgment call（意图识别、按需总结），确定性动作（转发、注入、路由）全部代码化（否决 C）。
2. 「持续交互」不新造协议，全部映射到 session 原生形态：进度 = text block、提问 = turn 结束、回答 = 下一个 turn、纠偏 = `steer()` 注入。agent 内核对这四件事的支持都已存在。
3. 订阅关系用独立表 `session_subscriptions` 显式建模，不依赖 session metadata 做业务判断（AGENTS.md「Metadata 字段业务判断规则」）；已知两类订阅者（remote_chat 转发、task_comments 落 comment），表一次建好。run 的完整过程留在其 session transcript，桌面 chat 面板天然可回看。

### 核心原则

1. Remote Assistant 是平行 entry-point agent（ADR-0002），独占微信会话，负责且仅负责意图分发与 cross-novel 操作。
2. **LLM 只做 judgment call**：意图识别、状态总结。转发、注入、run 状态判断全部是代码（AGENTS.md Rule 5）。
3. Run 的下行分两条独立通道，**不经过 Assistant LLM，不消耗 token**：
   - **agent 主动通知（→ inbox）**：给 run agent（Orchestrator）注入 `Run {"command":"notify",...}` 子命令 + 配套 AgentSkill 指导何时通知。agent 在关键节点（里程碑 / 提问 / 完成）主动调用，写入通用 `assistant_inbox` 表。**inbox 只给 Assistant 上下文，不转发微信**——agent 自己决定什么值得记，从源头避免被动捕获每条 text block 的"太细"问题。Assistant 下一轮 turn 组装 context 时从 inbox 读取注入（借鉴 Codex `send_message`：通知但不触发 turn）。
   - **最小 observer（→ 微信）**：保留最小 `RunOutputForwarder`，只监听 `isRequestInFlight` 状态变化。turn 结束（true→false）→ 转发 finalText 到微信（带来源标签，一条 turn 一条消息）；崩溃/报错 → 转发错误文案到微信 + 写 inbox（agent 来不及 notify 时的兜底）。**不捕获进度 text block**。
4. Run 的 Orchestrator **不注入 AskUser 工具**：需要用户输入时调 `Run {"command":"notify","type":"question",...}` 或文字提问并结束 turn；续跑 = 同 session 新 headless turn。turn 结束就是 turn 结束，finalText 文字本身表达意图（提问 or 完成），用户自己判断。
5. `send_to_job` 按 run 状态二选一（纯代码判断 `isRequestInFlight`）：在跑 → `agent.steer()`；idle → seed 新 turn。
6. 同一 chatId 的所有 Assistant turn 串行（复用 `RemoteBridgeService._sessionLocks`）。**notify 工具与最小 observer 都不占 Assistant 串行锁**——双通道分离，用户消息不被 run 通知阻塞。
7. Session 的下行消费关系统一走 `session_subscriptions` 表；不在 session metadata 里塞业务判断字段（AGENTS.md「Metadata 字段业务判断规则」）。
8. **inbox 与微信转发职责分离**：inbox（agent 主动 notify 写入 + observer 崩溃兜底写入）只给 Assistant 上下文，**不触发微信转发**；微信转发只由最小 observer 在 turn 结束/崩溃时执行（一条 turn 一条消息，不捕获进度）。`assistant_inbox` 是通用收件箱（接受各种来源消息），**不混入 `assistant_messages`**——后者只存会传给 AI 的对话消息（user / assistant / compact_summary）。

### 关键假设

| 假设 | 如果不成立 | 应对 |
|------|------------|------|
| WeChat iLink Bot 协议稳定 | 协议变更/封号 | adapter 层已隔离，errcode -14 触发 `onSessionExpired` |
| 桌面进程运行时 bridge 才工作 | 桌面关闭则 bridge 断 | V1 接受，桌面必须常开 |
| `steer()` 注入的消息能进 run session transcript | steering 事件当前只落日志（chat_turn_runner.dart 中 `AgentSteeringApplied` 分支） | `send_to_job` 侧同步 `addUserMessage` + 落库（见 §5.4） |
| run 的 `isRequestInFlight` 状态可订阅 | provider 不暴露此状态 | 最小 observer 改为在 `runHeadlessSessionTurn` 返回时直接转发 finalText（同步路径，不依赖 provider 监听） |
| ChatTurnRunner 内核可在无 novel 上下文下运行 | 内核强依赖 novel（prompt 组装 / 工具构造 / runtime key） | PR-2 改为独立入口方案：新创建 `AssistantTurnRunner` / `AssistantToolDispatcher` / `AssistantCoordinator`，不复用 `ChatTurnRunner`，避免 novel-scoped 回归风险 |

## 5. 方案实施

### 5.1 架构

双通道分离：通道 A 处理用户消息（占 Assistant turn），通道 B 处理 run 下行（纯代码，不占 Assistant turn）。通道 B 内部再分两条独立子通道：agent 主动 notify（→ inbox 给 Assistant）与最小 observer（→ 微信给用户）。

```
┌──────────────────────────────────────────────────────────────────┐
│  通道 A：用户消息 → Assistant turn（per-chatId 串行）              │
│                                                                   │
│  微信唯一 chat                                                    │
│     │  RemoteBridgeService（长轮询、per-chatId 串行、chunking）    │
│     ▼                                                             │
│  Assistant（hub，assistant_sessions 持久化，cross-novel）          │
│     │  工具：list_novels / start_job / job_status / send_to_job   │
│     │        / create_novel / edit_novel / list_chapters          │
│     │        / share_chapter_review                               │
│     │                                                             │
│     ├─ 闲聊 / 查询 → 自己处理，text block 回微信                    │
│     ├─「写第3章」→ start_job → 共享 helper → 后台 Job              │
│     │              （novel-scoped Orchestrator session，不建 Task） │
│     └─ 与 Job 相关的用户消息 → send_to_job                         │
│                      │                                            │
│            ┌─────────┴──────────────┐                              │
│            │ run 在跑（isRequestInFlight）│→ runtime.agent.steer()  │
│            │                        │   下一个 LLM round 前注入     │
│            │ run idle               │→ runHeadlessSessionTurn      │
│            └────────────────────────┘   同 session 续跑            │
│                                                                   │
│  Assistant turn 组装 context 时从 assistant_inbox 表读取           │
│  最近消息注入（由通道 B 写入），获得 run 上下文                      │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  通道 B：run 下行（不占 Assistant turn）                           │
│                                                                   │
│  ┌─ B1：agent 主动 notify → inbox（给 Assistant 上下文）─────────┐│
│  │                                                                ││
│  │  run agent（Orchestrator）在关键节点主动调用                    ││
│  │  Run {"command":"notify","subcommand":"send",                  ││
│  │      "options":{"type":"progress|question|complete",           ││
│  │                 "text":"..."}}                                 ││
│  │     │  （配套 AgentSkill 指导何时通知：里程碑 / 提问 / 完成）    ││
│  │     ▼                                                          ││
│  │  inboxDao.append(assistantSessionId,                           ││
│  │    source=run_agent, sourceRef=runSessionId,                   ││
│  │    type, content)                                              ││
│  │     → 写入通用 assistant_inbox 表                              ││
│  │     → 不转发微信（inbox 只给 Assistant 下一轮 context）         ││
│  │     → agent 自己决定什么值得记，从源头避免"太细"                ││
│  └────────────────────────────────────────────────────────────────┘│
│                                                                   │
│  ┌─ B2：最小 observer → 微信（给用户通知）────────────────────────┐│
│  │                                                                ││
│  │  最小 RunOutputForwarder（纯代码无 LLM）                       ││
│  │  只监听 isRequestInFlight 状态变化，不捕获 text block           ││
│  │     │                                                          ││
│  │     ├─ turn 结束（isRequestInFlight true→false）               ││
│  │     │   → bridge.sendToUser(chatId,                            ││
│  │     │     带来源标签【run 标题】finalText) → 发微信              ││
│  │     │   → 一条 turn 一条消息，不写 inbox                        ││
│  │     │     （agent 应已通过 B1 notify 写了 inbox）               ││
│  │     │                                                          ││
│  │     └─ 崩溃/报错（turn aborted / exception）                   ││
│  │         → bridge.sendToUser(chatId, 错误文案) → 发微信          ││
│  │         → inboxDao.append(source=run_observer,                 ││
│  │              type=error, content=错误摘要) → 写 inbox           ││
│  │           （agent 来不及 notify 的兜底，Assistant 下一轮可见）   ││
│  └────────────────────────────────────────────────────────────────┘│
│                                                                   │
│  assistant_inbox 是通用收件箱（接受各种来源），                    │
│  assistant_messages 保持纯净（只存会传给 AI 的对话消息）            │
└──────────────────────────────────────────────────────────────────┘
```

### 5.2 数据模型

```
SessionSubscriptions (NEW table, app DB)
- id: text (pk)
- session_id: text (AiChatSessions.id；同在 app DB，因软删除语义用字符串引用、不设外键)
- subscriber_type: text (remote_chat | task_comments)   -- enum snake_case（enum-naming.md）
- target_id: text
    remote_chat   → chatId（如 wxid）
    task_comments → taskId
- channel_type: text (nullable；仅 remote_chat 用，如 'wechat')
- created_at: integer (ms timestamp，db-timestamps.md)
- unique: (session_id, subscriber_type, target_id)
  （复合唯一索引已覆盖 session_id 最左前缀查询，不单建 (session_id) 索引）
```

订阅者类型（已知两类业务场景，表一次建好）：

- **remote_chat**（V1 接线）：run/assistant session 的 text block 转发到 IM chat。远程启动 run 时写入订阅行；转发目的地由此确定。持久化 → session 跨重启续跑后转发自动恢复。
- **task_comments**（本方案只建表注册类型，接线另立方案）：session 的进度输出落 `task_comments`，供桌面 task 面板持久观察。属 ADR-0005 中「comment 作为可观察 artifact」的部分回归——但只作下行 artifact，不作双向通道。

其他模型决策：

- 表放 **app DB**：run session 行同在 app DB 的 `AiChatSessions`（前版文档误写为「session 行在各 novel content DB」——per-novel 的是**消息表** `AiChatMessages`）。
- 生命周期：随 session 删除级联清理（app 层，session 为软删除、不设 SQL cascade）；`send_to_job` 遇订阅指向已删除 target 时删行。
- 明确**不用 session metadata 承载 `remoteChatId`**（AGENTS.md「Metadata 字段业务判断规则」——metadata 不做业务判断；现存 `metadata: {taskId}` 反查用法为存量，保留）。

Remote Assistant 对话持久化（NEW tables, app DB，ADR-0006）：

```
AssistantSessions
- id: text (pk)
- chat_id: text
- channel_type: text（如 'wechat'）
- provider / model: text (nullable，语义同 AiChatSessions)
- created_at / updated_at: integer (ms timestamp，db-timestamps.md)
- unique: (channel_type, chat_id)   -- V1 一个 chat 一条持久 session

AssistantMessages
- id: text (pk)
- session_id: text (AssistantSessions.id)
- role: text (user | assistant | compact_summary)
    user / assistant: 对话消息（会传给 AI 调用的消息）
    compact_summary: context 压缩摘要随普通消息落表，压缩状态天然跨重启，见 §5.4
- content: text（消息/blocks 序列化格式与 AiChatMessages 对齐，复用同一序列化助手，单测锁格式防漂移）
- created_at: integer (ms timestamp)
- index: (session_id, created_at)（命名遵循 db-index-naming.md）

AssistantInbox (NEW table, app DB)   -- 通用收件箱，独立于 assistant_messages，不混入对话消息
- id: text (pk)
- assistant_session_id: text (AssistantSessions.id；字符串引用，不设外键)
- source: text (run_agent | run_observer | ...)   -- 消息来源，enum snake_case（enum-naming.md）
- source_ref: text (nullable；来源引用，run_agent/run_observer → run_session_id)
- message_type: text (progress | question | complete | error | ...)   -- enum snake_case
- content: text（消息内容；agent notify 时是 agent 写的摘要，observer 崩溃时是错误摘要）
- created_at: integer (ms timestamp，db-timestamps.md)
- index: (assistant_session_id, created_at)（命名遵循 db-index-naming.md）
```

- **为什么不复用 `AiChatSessions` + 独立消息表**：session 行进 `AiChatSessions` 必须给 `novelId` 塞 sentinel，又回到 ADR-0004 的消费点审计；Assistant session 的查询维度是 (channel_type, chat_id)，与 novel-scoped 查询无交集，复用无收益。专属表让现有 chat 持久化面完全不感知本特性。
- **为什么不用隐藏 workspace novel**：能做到全链路零特判，但一行「伪小说」+ content DB 文件会泄漏进所有 novel 列表面（书架、`list_novels`、存储统计/清理、删除路径），需长期靠过滤防守；建模不干净，弃（对比见 ADR-0006）。
- **表名不带 remote 前缀（未来扩展预留）**：后续计划在 app home page 直接与 Assistant 聊天——同一存储再接一个本地 entry point，`channel_type = 'local'` + 固定 chat_id，unique (channel_type, chat_id) 天然支持；差异只在下行出口（home page UI 而非 bridge）。V1 不实现，仅保证表结构够用。
- `session_subscriptions.session_id` 只引用 run session（`AiChatSessions`）；Assistant session 自己的下行走流程 2 出口，不需要订阅行。
- **Assistant ↔ run 关联靠 chatId，不建新表**：`assistant_sessions.chat_id == session_subscriptions.target_id`（remote_chat）。查「某 chat 启动了哪些 run」= `session_subscriptions WHERE subscriber_type=remote_chat AND target_id=chatId`；一行订阅同时承担「转发目的地 + 归属关联」。`send_to_job` / `job_status` 以此做归属校验，防跨 chat 越权。
- chatId → session 映射：查 `assistant_sessions`（unique (channel_type, chat_id)），`AssistantCoordinator` 内存缓存；重启后查回，历史从 `assistant_messages` 读回内存 session 状态。
- steer 队列：agent 内核自有（`_steeringQueue`），生命周期 = 当次 turn 执行，不持久化。

Bridge 凭证持久化（NEW，复用 `AppStates` KV 表，无 migration）：

- `remote_bridge.wechat.credentials` → JSON {token, baseUrl, accountId, userId}。QR 登录成功时写入；errcode -14 时删除。
- `remote_bridge.wechat.context_tokens` → JSON map（chatId → context_token）。每条入站消息更新后落库——发消息必须回传 context_token，持久化后重启即可主动下发（run 转发），无需等用户先发一条。
- 明文存储，妥协见 §10。DB 写 try-catch + `[DB]` 日志（error-handling.md）。

### 5.3 关键业务流程

#### 流程 1：登录与凭证恢复（QR 已落地；持久化 NEW）

`RemoteBridgeService.startLogin()` → adapter 长轮询 QR 状态 → 桌面显示二维码 → 确认后凭证存内存 + **落库**（AppStates，见 §5.2）→ `start()` 开启消费循环。失败路径已实现（errcode -14 → `onSessionExpired` → bridge 停止并提示），持久化后增补：-14 时**同步删除库中凭证与 context_tokens**。

app 启动（bridge 开关开启时）：读库中凭证 → 有则 `adapter.restoreCredentials(...)` + `start()` 直接恢复消费循环，免扫码；首次轮询即 -14 → 走上述过期路径 → 设置页提示重扫。无库中凭证 → 停在未登录态等用户扫码。

context_token：每条入站消息刷新内存 map 并落库；重启后从库恢复。若恢复的 token 已失效（发送失败），删该 chatId 的 token、记 `[RemoteBridge]` 日志，等该 chat 下一条入站消息刷新。

#### 流程 2：微信消息 → Assistant turn

```
1. RemoteBridgeService 消费循环收到 InboundMessage，per-chatId 串行进入 onInboundMessage
2. AssistantCoordinator：chatId → session（查 assistant_sessions，无则创建；
   历史从 assistant_messages 读回内存 session 状态）
3. notifyProcessingStart(chatId)（typing）
4. 调 `runner.run(userText)`：独立 `AssistantTurnRunner`（自建 Agent、事件循环、持久化走 `AssistantSessionDao`），
    差异在 prompt 上下文（无 novel）、工具集（`AssistantToolDispatcher`，无 AskUser）、
    持久化目标（app DB 专属表，seed 先落库、完成块 upsert）
5. turn 结束后取 `outcome.finalText`，逐块 sendToUser（adapter 自动 chunking）
6. notifyProcessingEnd(chatId)
```

失败路径：turn 抛错 → `AssistantTurnOutcome.error` → 发送兜底文案（i18n），日志 `[RemoteBridge]`。

#### 流程 3：Assistant 启动 Job

```
1. Assistant 识别写作意图 → start_job(novelId, seed)（不建 Task）
2. 共享 helper 前置校验（novel 内容库可用、模型可用、isRequestInFlight 防重入）
   ── alreadyRunning 返回给 Assistant 的文案必须与 started 区分，避免误报"已启动"
3. 写入订阅行：session_subscriptions(session_id=jobId, subscriber_type=remote_chat,
   target_id=chatId, channel_type=wechat)  ── 同时是 Assistant↔Job 的归属关联
4. RunOutputForwarder 按订阅行对该 sessionId 注册 text block 监听
5. Assistant 回复"已启动"（自己的 text block 走流程 2 的出口）
```

Job 不是 Task。Assistant 没有 `create_task` 工具；待办只在桌面任务面板创建。实现上 Job 仍是 headless `AiChatSession`（`startHeadlessRun`），对外只称 Job。

#### 流程 4：Run 下行 — agent 主动 notify + 最小 observer 兜底

```
B1：agent 主动 notify → inbox（给 Assistant 上下文）
1. Orchestrator 在关键节点（里程碑 / 提问 / 完成）主动调用
   Run {"command":"notify","subcommand":"send",
       "options":{"type":"progress|question|complete","text":"..."}}
   （配套 AgentSkill 指导何时通知；agent 自己决定什么值得记）
2. notify 工具实现：inboxDao.append(assistantSessionId,
     source=run_agent, sourceRef=runSessionId, type, content)
   → 写入通用 assistant_inbox 表
   → 不转发微信（inbox 只给 Assistant 下一轮 context）
3. Assistant 下一轮 turn 组装 context 时从 inbox 读取最近消息注入
   （借鉴 Codex send_message：通知但不触发 turn）

B2：最小 observer → 微信（给用户通知）
1. 最小 RunOutputForwarder 只监听 isRequestInFlight 状态变化，不捕获 text block
2. turn 结束（isRequestInFlight true→false）
   → bridge.sendToUser(chatId, 带来源标签【<run 标题>】finalText) → 发微信
   → 一条 turn 一条消息，不写 inbox（agent 应已通过 B1 notify 写了 inbox）
3. 崩溃/报错（turn aborted / exception）
   → bridge.sendToUser(chatId, 错误文案) → 发微信
   → inboxDao.append(source=run_observer, type=error, content=错误摘要) → 写 inbox
   （agent 来不及 notify 的兜底，Assistant 下一轮可见）

turn 结束不区分"提问"与"完成"——finalText 文字本身表达意图，用户自己判断
```

Orchestrator 侧配合（prompt + AgentSkill，不是新机制）：Run seed 模板注明「你在被远程观察，关键节点调 `Run {"command":"notify",...}` 通知 Assistant；需要用户输入时调 notify(type=question) 或文字提问并结束本轮（不使用 AskUser 工具，未注入）」。配套 AgentSkill 定义指导何时通知。

回环不存在：run 下行不经过 Assistant LLM，Assistant 自己的输出只在流程 2 出口发送。Assistant 对 run 的感知来自通道 B1 写入 `assistant_inbox` 表的消息（下一轮 turn 组装 context 时注入），或主动调 job_status 工具查询。

#### 流程 5：Run 上行 — 用户中途指示 / 回答提问

```
1. 用户微信发"用张三这个名字"（run 在跑）或回答 run 的提问（run idle）
2. 流程 2 触发 Assistant turn，Assistant 结合 job_status 判断这是给 run 的
3. Assistant 调 send_to_job(runSessionId, text)（前置校验 runSessionId 在该 chatId 的订阅行内）：
   a. isRequestInFlight == true → runtime.agent.steer(userMessage)
      同时 addUserMessage 进 run session 状态 + 落库（transcript 完整性）
      → 下一个 LLM round 前注入，agent 看到并调整
   b. isRequestInFlight == false → prepareHeadlessSessionSeed + runHeadlessSessionTurn
      同 session 续跑，历史（含它自己的提问）完整在场
4. Assistant 回复"已转达"/不回复（prompt 决定，避免每条都双响）
```

失败路径：Assistant 误判归属（该给 run 的当成闲聊）→ 用户可见可纠正，V1 接受；runSessionId 无效或不属于该 chatId → 工具返回错误，Assistant 如实告知。

### 5.4 改动清单

#### `lib/shared/database/app_database.dart`
- ✅ `SessionSubscriptions` 表 + schemaVersion 11 已随 PR-1 落地。
- ✅ `AssistantSessions` / `AssistantMessages` 表定义（字段见 §5.2），`schemaVersion` 12 + `onUpgrade` 建表 + 索引（db-migration.md）已落地。
- 🔲 `AssistantInbox` 表定义（字段见 §5.2），`schemaVersion` 13 + `onUpgrade` 建表 + 索引（PR-4，待落地）。**通用收件箱**——不混入 `assistant_messages`（后者只存会传给 AI 的对话消息 user / assistant / compact_summary）；接受 agent notify 与 observer 崩溃兜底等各种来源消息。

#### NEW: `lib/shared/database/daos/session_subscriptions_dao.dart`（✅ 已随 PR-1 落地）
- `add({sessionId, subscriberType, targetId, channelType})` → 写入（unique 冲突即幂等）。
- `listBySession(sessionId)` → forwarder 恢复/注册用。
- `deleteBySession(sessionId)` / `deleteByTarget(subscriberType, targetId)` → 级联清理。

#### NEW: `lib/shared/database/daos/assistant_session_dao.dart`（✅ 已落地）
- `getOrCreateByChat(channelType, chatId)`、`loadMessages(sessionId)`、`upsertMessages(...)`、`touch(sessionId)`。
- 消息序列化独立实现（`_buildMessageCompanions` / `_decodeMessage` / `_buildPersistedMessages`），不依赖 novel-scoped 路径；格式对齐 `AiMessage` ↔ `AssistantMessages` 列。
- `loadMessages` 按 `createdAt ASC` 读取；`upsertMessages` 增量 upsert（非全量 sync），调用方负责过滤 streaming/system 消息。

#### NEW: `lib/shared/services/ai/assistant/`（独立入口，不复用 ChatTurnRunner）

Assistant 功能不走 `ChatTurnRunner` 可选化路径，而是**独立新建**以下类，全部放在 `lib/shared/services/ai/assistant/` 目录：

- **`tool_dispatcher.dart`** — `AssistantToolDispatcher`：轻量 `AgentToolDispatcher` 实现，不依赖 `AiToolManager` / `NovelContentService`。承载跨小说工具：`list_novels`、`start_job`、`job_status`、`send_to_job`、`create_novel`、`edit_novel`、`list_chapters`、`share_chapter_review`。无 Task 工具。工具回调由调用方通过 constructor 注入，dispatcher 自身无业务依赖。
- **`turn_runner.dart`** — `AssistantTurnRunner`：独立 turn runner，自建 Agent（`Agent.custom`）、事件循环、text 累积、消息持久化。与 `ChatTurnRunner` 完全独立：
  - 持久化走 `AssistantSessionDao`（app DB）而非 novel content DB
  - 工具走 `AssistantToolDispatcher`
  - 上下文管理器：`SmartAgentContextManager`（token limit = 200k），无 summarizer
  - hooks：`UsageHook` 记录本地 Token 用量
  - 无 UI 状态（不依赖 `aiChatSessionProvider` / `aiChatRuntimeProvider`）
- **`coordinator.dart`** — `AssistantCoordinator`：bridge → turn runner 的端到端编排。注册 `RemoteBridgeService.onInboundMessage` handler，按 chatId 串行执行 turn，失败兜底发送友好错误消息。负责 get-or-create session、resolve 全局默认 provider/model、构造 `AssistantToolDispatcher`（当前工具回调均为 stub，返回未实现错误）、驱动 `AssistantTurnRunner`、回发结果到微信。

设计决策：不 optionalize `ChatTurnRunner` 的 novel 依赖。两者共享 Agent 内核（`agent.dart` / `agent_context_manager.dart` / `agent_hook.dart`）但分别独立构造 provider client + agent config + 持久化路径，避免 novel-scoped 回归风险。

#### `lib/shared/providers/remote_bridge_providers.dart`（✅ 已落地）
- `remoteBridgeServiceProvider`：单例管理 `RemoteBridgeService` 生命周期。
- `assistantCoordinatorProvider`：单例管理 `AssistantCoordinator`，用闭包封装 `ref.read` 构造 `AiClient` + `listNovels` 回调，不耦合 Riverpod。
- 文件命名遵循「目录即命名空间」规则（AGENTS.md）：文件不加目录名前缀（如 `coordinator.dart` 而非 `assistant_coordinator.dart`）。

#### `lib/shared/services/remote/wechat_adapter.dart` / `wechat_api.dart`
- `WechatCredentials` 增加 JSON 序列化；adapter 增加 `restoreCredentials(...)`（免扫码直入已登录态）与 context_token 变更回调（供落库）。

#### `lib/shared/services/remote/remote_bridge_service.dart`
- 登录成功落库、app 启动时恢复凭证并自动 `start()`、-14 清库；context_token 更新落库（AppStates keys 见 §5.2）。

#### `lib/shared/services/remote/run_output_forwarder.dart` → 简化为最小 observer
- 只监听 `isRequestInFlight` 状态变化，**不捕获 text block**（进度由 agent 主动 notify 处理，见下）。
- turn 结束（isRequestInFlight true→false）→ `bridge.sendToUser`（带来源标签 finalText）→ 发微信。一条 turn 一条消息，不写 inbox。
- 崩溃/报错 → `bridge.sendToUser`（错误文案）→ 发微信 + `inboxDao.append`（source=run_observer, type=error）→ 写 inbox（agent 来不及 notify 的兜底）。
- 纯代码，无 LLM 参与（符合 Rule 5）。

#### NEW: Run `notify` 子命令（注入 run agent / Orchestrator）
- 在 `tools_run.dart` 的 Run 工具新增 `notify` 命令：`Run {"command":"notify","subcommand":"send","options":{"type":"progress|question|complete","text":"..."}}`。
- Orchestrator 已有 Run 工具（via `AiToolManager`），新增 `notify` 命令的 handler 由回调注入（`AiToolManager` 构造时传入 `notifyCallback`，远程 run 启动时挂载、桌面 run 不挂载）。
- handler 实现：`inboxDao.append(assistantSessionId, source=run_agent, sourceRef=runSessionId, type, content)` → 写 `assistant_inbox`。**不转发微信**（inbox 只给 Assistant 上下文）。
- 配套 AgentSkill 定义（`.agents/skills/` 或 agent-skills Run 子命令管理）：指导 agent 何时通知（里程碑 / 提问 / 完成），避免过度通知。

#### NEW: `lib/shared/database/daos/inbox_dao.dart`（PR-4，待落地）
- `assistant_inbox` 表的 DAO（表定义见 §5.2）。
- `append({assistantSessionId, source, sourceRef, messageType, content})` → 追加消息行。
- `loadRecent(assistantSessionId, {limit})` → Assistant turn 组装 context 时读取最近 inbox 消息注入。
- `deleteByAssistantSession(assistantSessionId)` / `deleteBySourceRef(sourceRef)` → 级联清理。
- 与 `AssistantSessionDao` 独立——`assistant_messages` 表保持纯净（只存对话消息），inbox 消息不混入。

#### `lib/shared/providers/task_providers.dart`
- 抽出共享 helper `startHeadlessRun(...)`（建 session + 校验 novel/model + keepAlive + 跑 headless turn），供桌面 `runTask` 与远程 `start_job` 共用。`runTask` 保持现有 task↔session 关联（`runSessionId` + `metadata:{taskId}`）；远程 `start_job` 直接调 helper，不建 Task。
- 远程 `start_job` 启动后写 `session_subscriptions` 订阅行（remote_chat→chatId，兼作 Assistant↔run 归属关联）。
- Run seed 模板补充远程自述/提问指示（仅 prompt 文本）。

#### Prompt 文件（✅ 已落地，2026-07-08 重命名为 assistant-centric）
- `assets/prompts/agent/assistant.md`：Assistant system prompt（从 `remote_assistant.md` 重命名，去掉「远程/微信」身份强调）。
- `lib/shared/services/ai/prompts/use_cases/assistant_prompt_use_case.dart`：prompt 渲染 use case（从 `remote_assistant_prompt_use_case.dart` 重命名）。
- `lib/shared/services/ai/prompts/prompt_id.dart`：`PromptId.agentAssistant`（从 `agentRemoteAssistant` 重命名）。
- notify + inbox 落地后需补充：prompt 告知 Assistant 上下文注入中包含 inbox 消息（来自 `assistant_inbox` 表，source=run_agent 是 agent 主动通知，source=run_observer 是崩溃兜底），据此了解 run 进展；用户问及 run 时可结合这些消息回复，也可调 `job_status` 查更多细节。

#### i18n
- turn 失败兜底文案等新增用户可见文案；bridge 相关文案已随 PR-5 落地（`assets/translations/{en,zh-CN}/remote.json`）。

### 5.5 Task Graph

```
PR-A WeChat adapter + iLink 协议封装 ✅
  └─ PR-B RemoteBridgeService + QR 登录 UI + 设置页 ✅
       ├─ PR-C bridge 登录态持久化（凭证 + context_token 落库/恢复，可与 PR-2+ 并行）✅
       │
PR-1 SessionSubscriptions 表 + DAO + migration ✅
PR-2 Assistant 持久化表（v12）+ DAO + prompt + 工具集 + 独立 turn runner + coordinator 接线 ✅
  └─ PR-3 微信 ↔ Assistant 闭环（end-to-end 消息往返，依赖 PR-B；coordinator 已落地，待 bridge 消费循环接入）
       └─ PR-4 Run 下行：start_job（共享 helper，不建 Task）+ 订阅行写入 + Run notify 子命令（agent 主动写 assistant_inbox）+ 最小 observer（turn 结束/崩溃转发微信）+ assistant_inbox 表 + AskUser 不注入 + seed 模板 + AgentSkill（依赖 PR-1）
            └─ PR-5 Run 上行：send_to_job(runSessionId，steer / 续跑) + job_status（recent_output 增强）+ 归属校验
                 └─ PR-6 全链路测试 + 评测（依赖 PR-C：重启恢复链路）
```

| 任务 | 内容 | 依赖 | 状态 | 验证 |
|------|------|------|------|------|
| PR-A | WeChat adapter + 协议封装（`wechat_adapter.dart` / `wechat_api.dart` / `channel_adapter.dart`） | 无 | ✅ 已合入 | 单测已随 PR 落地 |
| PR-B | RemoteBridgeService + QR UI + 设置页 | PR-A | ✅ 已合入 | `test/shared/services/remote/remote_bridge_service_test.dart` |
| PR-C | 凭证 + context_token 持久化（AppStates KV）、启动恢复、-14 清库 | PR-B | ✅ 已落地 | 手动重启免扫码 + `flutter test test/shared/services/remote/` |
| PR-1 | SessionSubscriptions 表 + DAO + migration | 无 | ✅ 已合入（schemaVersion 11；未单建 `(session_id)` 索引，复合唯一索引最左前缀已覆盖，见 §5.2） | `flutter test test/shared/database/` |
| PR-2 | `assistant_sessions/messages` 表 + DAO + v12 migration（ADR-0006）+ 独立 Assistant 入口（`AssistantTurnRunner` + `AssistantToolDispatcher` + `AssistantCoordinator`）+ prompt | 无 | ✅ 已落地（独立入口方案，非 ChatTurnRunner 可选化；工具回调当前为 stub） | `flutter test test/shared/database/` + `flutter test test/shared/services/ai/`（串行） |
| PR-3 | onInboundMessage → Assistant turn → text block 回微信（end-to-end 闭环） | PR-B, PR-2 | 待开始 | 手动：微信闲聊/列小说 |
| PR-4 | start_job（共享 helper，不建 Task）+ 写订阅行 + **Run notify 子命令**（agent 主动写 `assistant_inbox`）+ **最小 observer**（简化 forwarder：turn 结束/崩溃转发微信）+ `InboxDao` + v13 migration + AskUser 不注入 + seed 模板 + AgentSkill | PR-1, PR-3 | 待开始 | 手动 + `flutter test test/shared/services/remote/` + `flutter test test/shared/database/` |
| PR-5 | send_to_job(runSessionId) + job_status（recent_output 从 1-2 条增强为 5-10 条）+ 归属校验（target_id==chatId）+ steer 落库 + 重启后续跑转发恢复 | PR-4 | 待开始 | 手动中途纠偏 + 集成测试 |
| PR-6 | 全链路测试 + 评测（含重启恢复：免扫码 + Assistant 历史 + 续跑转发 + inbox 上下文可见性） | PR-5, PR-C | 待开始 | 见 §7 |

**PR-2 实施决策**：Assistant 功能不复用 `ChatTurnRunner`，而是独立创建以下类：
- `AssistantToolDispatcher`（`lib/shared/services/ai/assistant/tool_dispatcher.dart`）：轻量工具调度器，不依赖 `AiToolManager` / `NovelContentService`，工具回调由调用方注入。
- `AssistantTurnRunner`（`lib/shared/services/ai/assistant/turn_runner.dart`）：独立 turn runner，自建 Agent、事件循环、消息持久化（走 `AssistantSessionDao`）。
- `AssistantCoordinator`（`lib/shared/services/ai/assistant/coordinator.dart`）：bridge → turn runner 编排，注册 inbound handler、session 管理、provider/model 解析、工具 stub 构造。

方向改变原因：避免 `ChatTurnRunner` 可选化带来的 novel-scoped 回归风险；两者共享 Agent 内核但构造路径与持久化目标独立。文件命名遵循 AGENTS.md「目录即命名空间」规则（目录名承担命名空间职责，文件名不加前缀，如 `coordinator.dart` 而非 `assistant_coordinator.dart`）。

### 5.6 Migration

```text
v10 → v11（PR-1，✅ 已落地）:
1. CREATE TABLE session_subscriptions (
     id TEXT PRIMARY KEY,
     session_id TEXT NOT NULL,
     subscriber_type TEXT NOT NULL,
     target_id TEXT NOT NULL,
     channel_type TEXT,
     created_at INTEGER NOT NULL,
     UNIQUE (session_id, subscriber_type, target_id))
2. 无旧数据迁移（新表）；未单建 (session_id) 索引（复合唯一索引最左前缀已覆盖）

v11 → v12（PR-2）:
1. CREATE TABLE assistant_sessions / assistant_messages（字段见 §5.2）
2. 无旧数据迁移（新表）
3. 回滚：drop table（V1 接受丢 Assistant 历史）

v12 → v13（PR-4）:
1. CREATE TABLE assistant_inbox（字段见 §5.2）
2. 无旧数据迁移（新表）
3. 回滚：drop table（V1 接受丢 inbox 历史）

bridge 凭证走 AppStates KV，无 schema 变更。
```

遵循 db-migration.md：schemaVersion + onUpgrade + Dart 模型类三者同步；索引命名遵循 db-index-naming.md。

### 5.7 上线后验证

| 指标 / 日志 / 数据 | 目的 | 异常信号 | 观察周期 |
|-------------------|------|----------|----------|
| `[RemoteBridge]` 日志 | bridge 健康 | 断线/重连频繁 | 上线 1 周 |
| `[TaskRun]` 日志 | run 启动成功率 | failed 比例高 | 上线 1 周 |
| 转发节流丢弃/合并计数 | 下行风暴 | 高频合并说明 Orchestrator 自述过密，调 prompt | 上线 1 周 |
| 微信消息发送失败率 | adapter 健康 | >5% | 上线 1 周 |
| Assistant turn 次数/token | hub 成本 | 显著高于用户消息数（说明有非用户触发的 turn，属 bug） | 上线 1 周 |

## 6. 验收标准

| 类别 | 标准 | 验证方式 |
|------|------|----------|
| 功能 | 微信发"列出小说"收到列表 | 手动 |
| 功能 | 微信发"开始写X"启动 run（不建 task） | 手动 + `[TaskRun]` 日志 |
| 功能 | run 进度 text block 转发微信（带标签、无 streaming 碎片） | 手动 |
| 功能 | run 在跑时发指示，下一个 tool-call 边界注入生效，且指示出现在 run transcript | 手动 + 桌面回看 session |
| 功能 | run 提问后 idle；微信回复后同 session 续跑 | 手动 + session transcript |
| 错误处理 | bridge 断线不崩溃桌面主进程 | 已有单测 + 手动 |
| 错误处理 | Assistant turn 抛错发兜底文案，不卡死 chatId 队列 | 手动 + 日志 |
| 兼容 | 桌面发起的 Task Run 行为不变（无订阅行 → 不转发） | `flutter test test/shared/providers/` |
| 功能 | app 重启后经 send_to_job 续跑，订阅行恢复转发 | 手动 + 集成测试 |
| 兼容 | AskUser 工具在桌面 chat 面板行为不变 | `flutter test test/shared/services/ai/` |
| 功能 | app 重启后免扫码恢复 bridge；凭证失效（-14）清库并提示重扫 | 手动重启 + `[RemoteBridge]` 日志 |
| 功能 | app 重启后微信继续对话，Assistant 历史完整（`assistant_messages` 读回） | 手动 + 查表 |
| 功能 | Assistant 长会话超限触发 compaction，`compact_summary` 落表、重启读回后继续对话正常 | 集成测试（压低 tokenLimit 触发） |
| 兼容 | 桌面 novel-scoped chat 持久化与 session 列表行为不变（Assistant 不进 `AiChatSessions`） | `flutter test test/shared/services/ai/` + 手动 |
| 性能 | bridge idle 不占明显 CPU（<1%） | Activity Monitor |
| 可维护性 | 新增 IM channel 只需实现 `BaseChannelAdapter` | code review |

测试命令（按 AGENTS.md Rule 14，串行执行）：
- `flutter test test/shared/database/`
- `flutter test test/shared/services/remote/`
- `flutter test test/shared/services/ai/`
- `flutter test test/shared/providers/`

## 7. 评测

非确定性环节只剩 Assistant 的意图分发（下行转发已代码化，不需要评测）。

### 评测对象

- 被测能力：意图识别（闲聊 / 查询 / 启动 run / 给 run 的指示或回答 / 可选 task 创建）、run 归属判断、总结质量。
- 不测内容：协议层、转发层、注入层（确定性，单测覆盖）。

### 评测场景

| 场景 | 输入 | 期望 | 判定 |
|------|------|------|------|
| 闲聊 | "你好" | 直接回复，不调 send_to_job | manual |
| 启动写作 | "开始写第3章" | start_job（不建 Task），回执区分 started/alreadyRunning | manual + 日志 |
| 查进度 | "进度怎样"（Job 在跑） | 调 job_status 总结，不打断 Job | manual |
| 中途指示 | "用张三这个名字"（Job 在跑） | send_to_job → steer | manual + transcript |
| 回答提问 | Job 刚提问结束，用户回复 | send_to_job → 同 session 续跑 | manual + transcript |
| 归属歧义 | Job 在跑时问"今天天气" | 不误转给 Job | manual |

### 自动化与人工边界

- 自动化：steer 注入 → 下一 round 生效、idle 续跑历史完整性、转发节流与标签（集成测试）。
- 人工：意图识别准确率、总结文案质量。
- 仅观察不阻断：Assistant token 消耗分布。

## 8. Token 成本

| 维度 | 估计 | 说明 |
|------|------|------|
| 单次 Assistant turn | 输入 ~2k / 输出 ~300 | system prompt + session history + 用户消息 |
| 触发次数 | 仅每条用户微信消息 1 次 | **上界 = 用户打字速度，天然有界**；run 下行转发 0 token |
| Run 侧增量 | ≈0 | 无新工具；仅 seed 模板多几句自述/提问指示 |
| 上下文增长 | 超 tokenLimit（200k）触发 LLM compaction | 复用 chat panel 的 SmartAgentContextManager + summarizer；单次 compaction ≈ 一次摘要调用（输入截断后的历史 / 输出 <2k 字符） |
| 模型档位 | Assistant 用 sonnet；Run 不变 | |

相比前版（comment 中继）：删去了「每条 agent comment 一次 Assistant turn」的无界放大项。

## 9. 风险

| 风险 | 触发条件 | 影响 | 对策 |
|------|----------|------|------|
| WeChat 协议变更/封号 | iLink Bot 失效 | bridge 断 | adapter 已隔离；-14 → onSessionExpired |
| 下行转发风暴 | Orchestrator 自述过密 | 微信刷屏 | 代码节流合并（非 prompt 祈祷）+ prompt 调自述密度 |
| 多 run 输出交错 | 同 chat 多个 run 并行 | 用户混淆 | 来源标签【run 标题】；V1 也可限制单 chat 单活跃 run |
| 无身份验证 | 任何人加微信即可控制 | full workspace agency 暴露 | `BaseChannelAdapter.isAuthorized` 挂点已留；建议 V1 就加 wxid 白名单（§10） |
| 凭证明文落库 | 本地 app DB 被读取 | bot token 泄漏 = 微信侧可控制 agent | V1 接受（本地单用户桌面）；-14 即清库；后续 keychain（§10） |
| 恢复的 context_token 失效 | 重启间隔过久 | 恢复后首次主动下发失败 | 发送失败删 token + `[RemoteBridge]` 日志，等该 chat 下一条入站消息刷新 |
| steer 消息不进 transcript | 只调 agent.steer() 忘记落库 | 桌面回看缺用户指示 | send_to_job 实现强制同步 addUserMessage + 落库，集成测试覆盖 |
| 订阅行泄漏 | session/task 删除时未清理（跨库无 SQL cascade） | 表缓慢膨胀、转发指向死目标 | app 层删除路径调 deleteBySession；forwarder 遇死目标删行 |
| Assistant 误判归属 | 意图识别错误 | 指示没到 run / 闲聊被转发 | 用户可见可纠正；评测场景覆盖（§7） |
| 桌面关闭 | 用户关掉 reveric | bridge 断、run 终止 | V1 接受，桌面必须常开 |

## 10. 已知妥协

1. 妥协：WeChat 身份不设限（若 V1 不做白名单）
   - 影响：任何加微信的人可控制 agent。本版 Assistant 直连 full agency 入口，风险高于前版。
   - 升级触发：建议提前至 V1 收尾；`isAuthorized` 挂点已存在，成本仅一个配置项。

2. 妥协：凭证与 context_token 明文存 app DB
   - 影响：本机能读 app DB 即能取得 bot token。
   - 后续方向：迁移 keychain / flutter_secure_storage。

3. 妥协：Remote Assistant 暂不支持 Memory 机制
   - 影响：现有 Memories 机制（`MemoryService` 注入 system prompt 片段 + extraction/dreaming 沉淀）不接入 Assistant；跨会话的用户偏好/事实不会沉淀，context 压缩后细节只存在于 compact_summary 摘要里。
   - 升级触发：用户明显重复交代同样的偏好/背景。
   - 后续方向：复用 `memoryServiceProvider` 注入（chat_turn_runner.dart:1307 同款路径）+ 按需接 extraction。

4. 妥协：单 chat 多活跃 run 的体验未打磨
   - 影响：并行 run 输出交错，仅靠标签区分。
   - 升级触发：用户实际并行使用。
   - 后续方向：Assistant 侧「当前关注 run」概念，或限单活跃 run。

## Open Questions

1. ~~**assistant_messages 序列化细节与 ChatTurnRunner novel 可选化边界**（PR-2）~~ ✅ 已决定
   - 序列化：独立实现 `_buildMessageCompanions` / `_decodeMessage` / `_buildPersistedMessages`，不依赖 novel-scoped 路径。`content` 列存纯文本，`blocks` 列存 JSON 序列化 block 列表（`AiMessageBlockListConverter`）。
   - 入口：不走 `ChatTurnRunner` 可选化，独立新建 `AssistantTurnRunner` + `AssistantToolDispatcher` + `AssistantCoordinator`（见 §5.4）。

1b. **summarizer prompt 是否需要 hub 特化**（PR-2；tokenLimit 已定 200k）
   - 通用摘要 prompt 可能丢「哪条消息在讨论哪个 run」的归属上下文，压缩后 `send_to_job` 归属判断变差；倾向摘要指令中要求保留 task/run 引用。

1c. ~~**send_to_job / job_status 的 run 定位符**（PR-5）~~ ✅ 已决定（见「修订记录」2026-07-07）
   - 定位符直接用 run 的 `AiChatSession` id（runSessionId），不再经 taskId 解析。调用前用 `session_subscriptions WHERE subscriber_type=remote_chat AND target_id==chatId` 校验归属，防跨 chat 越权。run 与 Task 解耦后不存在 taskId↔session 的二义。

2. **Assistant 工具白名单完整清单**（PR-2）
   - `list_novels` / `start_job` / `job_status` / `send_to_job` / `create_novel` / `edit_novel` / `list_chapters` / `share_chapter_review` 确定。无 Task 工具。其余对齐 `tool_run.md` 逐条过。

3. **下行节流参数**（PR-3）
   - 合并窗口时长（倾向 3–5s）、单条上限（adapter chunking 已兜底 4000 字符）。

4. **长 tool call 期间 typing 策略**（PR-3）
   - 两个 text block 之间可能间隔数分钟。是否周期性 sendtyping（adapter 已支持 typing ticket）。倾向：run 在跑期间低频心跳 typing。

5. **job_status 的"最近消息摘要"取多少**（PR-5）
   - 倾向：最后 1–2 条 assistant 消息的 text block 原文，不做 LLM 摘要（Rule 5）。

6. **home page Assistant 聊天的形态**（未来扩展，另立方案）
   - 与微信 session 是否共用一条历史（默认按 (channel_type, chat_id) 分开，unique key 天然支持；共用则需 alias 机制）；下行出口从 bridge 换成 home page UI 的抽象方式。

7. **task_comments 订阅者的接线形态**（另立方案）
   - 订阅行怎么产生（run 启动时自动 + task 绑定？）、写 comment 的粒度（每 text block 一条 vs 节流合并）、`task_comments` 表 schema（可参考前版 git 记录中的设计）。
   - 本方案只保证 `session_subscriptions` 表结构对其够用（subscriber_type=task_comments, target_id=taskId）。

## 修订记录

> 正文只保留最新形态；本章节记录每次结构性决定的摘要与理由，供追溯。

### 2026-07-07 — Run 与 Task 解耦，Assistant↔Run 靠 chatId 关联

**决定**：远程写作意图不再自动创建 Task。**Run 成为独立原语**（一个后台 headless `AiChatSession`），**Task 降级为「显式意图才建」的可选 Assistant 工具**。

**要点**：

- **Run = session 原语**：Assistant 识别写作意图 → `start_job(novelId, seed)` 直接跑 headless turn，不建 Task。Task 只在用户明确要「记待办」时经 `create_task` 建立，可选地指向某个 run。二者解耦。
- **转发订阅与 Task 正交**：是否写 `session_subscriptions`（remote_chat→chatId）只取决于「该 run 要不要发回微信」，与建不建 Task 无关。既有桌面 `runTask`（本地、有 Task、无订阅）原样保留。
- **Assistant↔Run 关联走 chatId，不建新表**：`assistant_sessions.chat_id == session_subscriptions.target_id`。查「本会话启动了哪些 run」= `session_subscriptions WHERE subscriber_type=remote_chat AND target_id=chatId`。一行订阅同时承担「转发目的地 + 归属关系」。assistant 专属表（ADR-0006）保持不变，是关联不是合并。
- **Locator 改为 runSessionId**：`send_to_job` / `job_status` 直接用 run 的 `AiChatSession` id，调用前用 `target_id==chatId` 做归属校验（防跨 chat 越权）。原 Open Q 1c（taskId 二义）消解。
- **共享 helper**：从 `runTask` 抽出「建 session + 校验 novel/model + keepAlive + 跑 headless」为 `startHeadlessRun(...)`，桌面 `runTask` 与远程 `start_job` 共用。
- **来源标签**：run 下行前缀从【task 名】改为【run session title】。

**为什么**：转发链路本就是 session-based；重启恢复（转发重挂、idle 续跑、in-flight 判定）全部以 `session_id` 为 key，与 Task 无关。Task 在远程链路里只剩「桌面 task panel 露出」和「taskId 句柄」两项，均可由 run 的 chat session（chat panel 天然可回看）+ chatId 关联替代。去掉后概念更少、消掉一个 Open Question、复用已落地的 `session_subscriptions`（PR-1）。

**取舍（已接受）**：远程快速起的 run 默认不进桌面 task panel，只在对应小说的 chat 会话列表可见（run 是正常 `AiChatSession`，可定位、非孤儿）；想统一进 panel 就显式让 Assistant 建 Task。

**影响的 ADR**：ADR-0002 工具集与「task lifecycle through Run subcommands / delegated to Task Runs」表述更新为「Run 原语 + 可选 create_task」。ADR-0006 不变（assistant 专属表保留，靠 chatId 关联而非合并进 `AiChatSessions`）。

### 2026-07-08 — 命名回归以 Assistant 为核心

**决定**：代码与 prompt 命名从「Remote Assistant」回归为「Assistant」；Remote Bridge 只是使用 Assistant 的一种通道，未来 app 内直聊 Assistant 复用同一套。

**要点**：

- **Prompt 重命名**：`assets/prompts/agent/remote_assistant.md` → `assistant.md`；`PromptId.agentRemoteAssistant` → `agentAssistant`；`RemoteAssistantPromptUseCase` → `AssistantPromptUseCase`；`aiPromptService.remoteAssistant` → `aiPromptService.assistant`；prompt 内容去掉「远程/微信」身份强调，改为「创作助手 + 聊天通道」。
- **设置区重命名**：`remote_assistant_settings_section.dart` → `remote_bridge_settings_section.dart`；`RemoteAssistantSettingsSection` → `RemoteBridgeSettingsSection`。设置区是远程桥接（WeChat 登录/开关）的 UI，不是 Assistant 本身的设置——职责分离。
- **不变的**：`lib/shared/services/ai/assistant/` 目录、`AssistantCoordinator` / `AssistantTurnRunner` / `AssistantToolDispatcher` / `AssistantSessionDao` / `assistant_sessions` / `assistant_messages` 表名本就是 assistant-centric，无需改动；`RemoteBridgeService` / `RunOutputForwarder` 等 remote-bridge 层保持原名（它们就是 remote bridge 的实现）；ADR 历史记录不改（记录决策时点的认知）。

**为什么**：Assistant 是核心 agent，remote bridge 只是一个 entry point。表名不带 remote 前缀的决策（ADR-0006 已明确「未来扩展预留」）早就定下了，这次把 prompt / 类名 / 设置区对齐到同一视角，为后续 app home page 直聊 Assistant（`channel_type = 'local'`）扫清命名歧义。

### 2026-07-09 — agent 主动 notify + 最小 observer（取代 RunObserver）

**决定**：从 RunObserver 被动捕获每条 text block，改为 **agent 主动 notify**（写 inbox 给 Assistant）+ **最小 observer**（只转发 turn 结束/崩溃到微信）。新建通用 `assistant_inbox` 表取代 `assistant_run_events`。

**背景**：RunObserver 被动捕获每条 text block 太细——agent 产生的每段文字都变成事件，即使分级过滤（进度只写表不转发）仍是在"猜"什么值得记。正确做法是让 agent 自己决定什么值得通知：给 run agent 注入 `Run {"command":"notify",...}` 子命令，agent 在关键节点主动调用，写入 `assistant_inbox`。inbox 只给 Assistant 上下文，不转发微信（微信转发由最小 observer 在 turn 结束时做，一条 turn 一条消息）。

**要点**：

- **agent 主动 notify（→ inbox）**：给 run agent（Orchestrator）的 Run 工具新增 `notify` 命令，agent 在里程碑/提问/完成时主动调用，写 `assistant_inbox`（source=run_agent）。配套 AgentSkill 指导何时通知。**inbox 只给 Assistant 下一轮 context，不转发微信**。
- **最小 observer（→ 微信）**：`RunOutputForwarder` 简化为只监听 `isRequestInFlight`。turn 结束 → 转发 finalText 到微信（一条 turn 一条消息）；崩溃/报错 → 转发错误到微信 + 写 inbox（source=run_observer, type=error，agent 来不及 notify 的兜底）。**不捕获 text block**。
- **inbox 与微信转发职责分离**：inbox（agent notify + observer 崩溃兜底）只给 Assistant 上下文；微信转发只由 observer 在 turn 边界执行。两条子通道独立，互不干扰。
- **`assistant_inbox` 是通用收件箱**：接受各种来源消息（run_agent / run_observer / 未来扩展），不限于 run 事件。**不混入 `assistant_messages`**——后者只存会传给 AI 的对话消息（user / assistant / compact_summary）。
- **不检测"提问"**（不变）：turn 结束就是 turn 结束，finalText 文字本身表达意图。
- **不注入 AskUser 工具**（不变）：run 的 Orchestrator 不注册 AskUser。
- **双通道分离**（不变）：通道 A（用户 → Assistant turn）与通道 B（run 下行）独立，notify 工具与 observer 都不占 Assistant 串行锁。

**与上一版（RunObserver）的差异**：

| 维度 | RunObserver（上一版） | agent notify + 最小 observer（本版） |
|---|---|---|
| 进度捕获 | 被动监听 text block，分级处理 | agent 主动调 notify，自己决定什么值得记 |
| inbox / 事件表 | `assistant_run_events`（run 专用） | `assistant_inbox`（通用收件箱） |
| 微信转发 | observer 转发（进度不转发，turn 结束转发） | observer 只转发 turn 结束/崩溃（一条 turn 一条消息） |
| 上下文注入 | observer 写事件表 → Assistant 读 | agent notify 写 inbox → Assistant 读 |
| 复杂度 | observer 要理解 text block 边界 + 分级 | observer 只监听 isRequestInFlight；agent 用已有 Run 工具调 notify |

**为什么**：

1. **agent 自己最清楚什么值得通知**——被动捕获每条 text block 是在猜，不如让 agent 主动决定。从源头解决"太细"问题。
2. **inbox 通用化**——`assistant_inbox` 接受各种来源，不限于 run 事件，为未来扩展（其他 agent / 源）预留。
3. **observer 最小化**——只做 turn 边界转发 + 崩溃兜底，不碰 text block 内容，复杂度大降。
4. **职责分离清晰**——inbox 给 Assistant 上下文，微信给用户通知，两条路独立。

**Codex 机制对应关系**（更新）：

| Codex 概念 | 我们的对应 | 说明 |
|---|---|---|
| `spawn_agent` | `start_job` 工具 | Assistant 启动 run |
| `send_input` | `send_to_job` 工具 | 向运行中 run 注入（steer / idle 续跑） |
| `send_message`（trigger_turn=false） | agent 调 `Run notify` 写 `assistant_inbox` | 通知 Assistant，不触发 turn（agent 主动，非被动捕获） |
| `followup_task`（trigger_turn=true） | V1 不使用 | run 不触发 Assistant turn（只有用户消息触发） |
| 自动完成通知 | 最小 observer 转发 finalText | turn 结束自动通知用户（微信） |
| `maybe_start_completion_watcher` | observer 监听 `isRequestInFlight` | 监视 run 状态变化 |
| `AgentPath`（`/root/worker`） | `session_subscriptions`（run↔assistant 归属） | agent 层级标识 |

**取舍（已接受）**：

- agent 不 notify 进度时，Assistant 上下文里没有 run 进展——可接受（agent 应在关键节点 notify；用户也可主动问，Assistant 调 `job_status` 查）。
- 崩溃时 observer 写 inbox 是兜底，正常情况下 agent 自己 notify complete/error。
- `session_subscriptions.target_id` 仍为 chatId（不改为 `assistant_session_id`）——V1 WeChat 单 channel 下两个语义重合；留到 in-app 直聊落地时一起改。

**影响的组件**：

- `RunOutputForwarder` → 简化为最小 observer（只监听 isRequestInFlight，不捕获 text block）
- `tools_run.dart` → 新增 `notify` 命令（`Run {"command":"notify","subcommand":"send",...}`）
- `AiToolManager` → 构造时可选传入 `notifyCallback`（远程 run 挂载、桌面 run 不挂载）
- 新建 `assistant_inbox` 表 + `InboxDao`（v13 migration）
- `assistant.md` prompt → 告知 Assistant 上下文注入中包含 inbox 消息
- `job_status` 工具增强：`recent_output` 从 1-2 条改为 5-10 条（兜底查询）
- 配套 AgentSkill 定义 → 指导 agent 何时 notify

**影响的 ADR**：无新增 ADR；ADR-0002（平行 entry-point agent）与 ADR-0006（app DB 专属表）不变。

### 2026-08-14 — 对外原语从 Run 改名为 Job；Assistant 不再有 Task 工具

**决定**：Remote Assistant 面向模型与用户的后台写作原语改称 **Job**。工具为 `start_job` / `job_status` / `send_to_job`，定位符为 `job_id`。实现仍是 headless novel-scoped `AiChatSession`（`startHeadlessRun`、`RunOutputForwarder`、novel `Run` 命令均不改名）。

**Job ≠ Task**：

- **Task**：桌面待办（`todo` / `doing` / `closed`），由 **Task Run** 执行。
- **Job**：Remote Assistant 启动的后台写作。Assistant 没有 `create_task` / `Run` 命令工具，不能建待办。

**为什么**：Run 已用于 novel `Run` 命令，不再复用为后台写作原语的名称。Session 不能用，因为 Assistant 自己已有 `AssistantSession`。Job 与 Task 在口语里会撞「任务」，用 glossary、工具 schema（`job_id` 且拒绝 `task_id`）和 prompt（用户可见文案说「后台写作」，不说「任务」）切开。

**影响的 ADR**：ADR-0002 工具集与原语更新为 Job；不再写可选 `create_task`。
