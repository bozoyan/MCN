# Agent 上下文压缩修复（触发指标 / 切点 / 落库定位 / 可观测性）

> 档位：完整档。跨 `lib/shared/agent/` 与 `lib/shared/services/ai/`，含 AI 非确定性输出（摘要），无 DB migration。

## 1. 背景

### 现状

- Chat Panel 的 orchestrator agent 使用 `SmartAgentContextManager`（`lib/shared/agent/agent_context_manager.dart`）做 token 感知压缩：`buildMessages()` 内用 `字符数 ÷ 3` 估算 token，超过 `tokenLimit`（`chat_turn_runner.dart:1276` 写死 100000）时，以「最后一个 assistant 消息」为切点，把之前的消息交给 LLM summarizer 压成摘要，摘要以 `compact_summary` 类型 user 消息前置注入。
- 压缩摘要通过两条路径写回 UI / DB：
  - 回合结束后 `onAgentContextSettled` → `_syncPersistedContextState`（`lib/desktop/widgets/ai/chat/message_mapping.dart`），按 role+type+文本内容匹配定位插入。
  - 回合中增量落库 `upsertCompletedMessages` → `_buildPersistedMessages`（`session_persistence.dart:499`），按 **agent 消息 id** 匹配定位插入，找不到就 append 到末尾。
- 下次构建 agent 历史时，`_messagesSinceLatestCompact`（`chat_turn_runner.dart:206`）从最后一条 `compact_summary` 开始截取。
- SpawnAgent 子代理、Council/Theater/Monologue 使用 `SimpleAgentContextManager`，无任何压缩。
- 另有一套字符截断式的 `AiContextManager`（`context_manager.dart`），服务 `AiChatService`/`AiChapterService` 的单次生成路径，与 agent 压缩无关但命名易混淆。

### 问题

```text
问题 A（P0）：压缩几乎永远不触发
- 症状：长会话最终以供应商 400 / 上下文溢出报错收场，从未见过压缩发生。
- 根因 1：_charCount 只累加 m.content（agent_context_manager.dart:253）。tool result
  消息构造时 content 为空串、完整 JSON 在 ToolResultBlock 里（agent.dart:866-880）；
  ThinkingBlock 文本、ToolCallBlock arguments 同样在 blocks 里。工具重度会话中体积
  最大的部分对估算贡献为 0。
- 根因 2：÷3 chars/token 对中文低估 2–4 倍（中文 ≈ 1–1.5 字符/token）。
- 影响：tokenLimit 守门形同虚设；真实窗口先打爆。

问题 B（P0）：摘要落库定位依赖 id 对齐，错位时重载会裁光历史
- 症状（潜伏）：回合中触发压缩后增量落库，摘要被 append 到消息列表末尾；
  下次加载会话 _messagesSinceLatestCompact 从末尾的摘要截取 → 历史只剩一条摘要。
- 根因：_buildPersistedMessages 用 contextSnapshot.messages 的 id 匹配 UI 消息，
  但两者属于不同命名空间（agent 内部 id 形如 asst_chat_panel_${runId}_N，UI id 来自
  _nextMessageId()）。切点取「最后一个 assistant」时 retained 全是 agent 生成 id，
  insertIndex 必为 -1。
- 影响：数据丢失级 bug，目前被问题 A 掩盖；修好 A 就会暴露。

问题 C（P1）：切点与摘要质量
- C1 切点在最后一个 assistant，回合中触发时当前用户指令也被压进摘要，模型带着
  模糊摘要继续执行精确任务。
- C2 summarizer 输入只拼 m.content 且每条截 500 字符（chat_turn_runner.dart:1295）：
  tool_result 消息 content 为空 → 摘要模型看到成片空白行；提示词要求保留的
  file/novel references 恰恰在被丢掉的 tool result 里。
- C3 滚动摘要丢失：第二次压缩时旧 _summary 不在 overflow 内（它只在 buildMessages
  返回时前置），新摘要直接覆盖旧摘要 → 更早的历史被整体遗忘。
- C4 提示词要求摘要 <2000 字符，但 summaryMaxChars=16000，约束不一致。

问题 D（P2）：工程性缺陷
- D1 压缩在 buildMessages 内同步执行，阻塞请求路径，无事件/UI 提示，用户只见卡顿。
- D2 失败被 catch (_) 吞掉（agent_context_manager.dart:219）：违反 Rule 12；失败后
  消息仍超限，之后每一轮都重复付一次失败的 summarizer 调用（延迟和供应商调用费用）。
- D3 tokenLimit 写死 100000，与模型上下文窗口无关；system prompt（章节内容、
  memories、skills）在 context manager 之外拼接（agent.dart:256-270），不占预算。
- D4 SpawnAgent 子代理长任务（多轮工具调用）无压缩保护。

问题 E（P2）：AiContextManager 的「会话压缩」服务于不存在的场景，唯一生效的逻辑在帮倒忙
- 症状：记忆提取/dreaming 只基于会话开头一小段；已有记忆去重列表失效（重复记忆）。
- 根因：AiContextManager 只被 AiChatService.chatCompletion 使用，而其全部 7 个调用方
  （起名、4 个编排器的标题生成、memory_extraction、memory_dreaming）均为
  「system + 1 条 user」单发调用——12 条保留与拼接式摘要永不生效、compactContext
  无人传参；唯一生效的是 messageCharLimit=1600 逐条截断（context_manager.dart:96-100），
  把 memory_extraction_service 拼好的完整对话 + 已有记忆列表静默砍到前 1600 字符。
- 影响：记忆抽取覆盖率与去重实际失效；标题生成同样被截（取前 1600 字符起标题，基本无害）。

问题 F（P3）：死代码与外围
- F1 AiChapterService / runShortcut 在门面（chat.dart:282）暴露但全仓库零调用方：
  快捷指令已迁移为 DB 可配置的 AiShortcutActionDefinition + AiChatShortcutDraft
  注入聊天面板 agent 路径（novel_editor.dart:2431）。旧路径写死 3 值枚举、单发
  chatCompletion、无工具/流式/结果落地机制，属被淘汰的上一代实现。
- F2 遗留 enum AiShortcutAction 与 Drift 生成的数据类 AiShortcutAction 同名，易混淆；
  枚举唯一使用者即 F1 死代码。
- F3 SmartAgentContextManager._truncate 与 AiContextManager._truncate 按 UTF-16
  code unit 硬切，可能劈开代理对（emoji）产出非法字符串。
```

### 约束

- 不能破坏既有会话数据：DB 中**永久保留全部原始消息**，压缩只影响发给模型的内容，不删任何行；`compact_summary` 记录 append-only（每次压缩新增一条，旧记录留存），`_messagesSinceLatestCompact` 取最后一条的截取语义不变（`lastIndexWhere` 天然兼容多条）。
- `AgentContextManager` 抽象被 fork / snapshot / 持久化多处依赖，接口改动要最小。
- 不引入新运行时依赖；不做 DB schema 变更。
- Flutter 测试串行执行（AGENTS.md）。

## 2. 目标

### 目标

1. 压缩触发指标以**上一轮真实 usage**（`AiUsage.inputTokens`，已含 cached tokens）为准，字符估算仅作兜底，且兜底估算覆盖全部 blocks 并对 CJK 计权。
2. 压缩触发线由「模型上下文窗口 − 输出下限 − 漂移余量」动态推导（≈90% 窗口利用率），不再写死；窗口数据来自 `models_catalog.dart` 的 `limit`，未知模型有保守默认值；输出空间由逐请求 max_tokens 钳制保证。
3. 切点优先落在 turn 边界（user text 消息），当前用户指令永不丢失；tool_call/tool_result 配对在 retained 内始终完整。
4. 摘要输入包含 tool result 文本与工具调用轨迹；滚动压缩合并旧摘要而不是覆盖。
5. 摘要落库定位不再依赖 agent/UI id 对齐；匹配失败时**跳过插入并告警**，绝不 append 到末尾。
6. 压缩过程对用户可见（状态提示）、对开发者可观测（日志 + 事件）；失败大声报错并退避，不重复空转。
7. SpawnAgent 子代理获得同等压缩保护。
8. `chatCompletion` 单发路径不再静默截断调用方输入（修记忆提取被砍到 1600 字符）；`AiChapterService`/`runShortcut`/遗留枚举等死代码清除。

### 非目标

1. 不把 `AiChatService` 的 7 个单发调用迁移为 `Agent`（轻量单发是 `.agents/rules/ai-calling.md` 明确允许的用途，且该规则禁止未经确认迁移）。
2. 不给 Council/Theater/Monologue 接入压缩（有界编排，见已知妥协）。
3. 不做 summarizer 模型降档配置。
4. 不恢复/重建 `runShortcut` 式的独立 shortcut 执行通道——现行 agent 路径（自定义 prompt + 引用注入 + 工具落地）全面优于旧路径，迁移方向只能是删除旧路径。

### 成功信号

| 信号 | 验证方式 |
|------|----------|
| 工具重度会话在真实 input tokens 逼近预算时触发压缩，而不是 400 报错 | 单测（模拟 usage）+ 手动长会话观察日志 |
| 压缩后重载会话，历史 = 摘要 + retained，无「只剩一条摘要」 | 单测 + 手动：压缩后重启应用加载会话 |
| retained 首条永远是 user text 或配对完整的 assistant | 单测穷举切点场景 |
| summarizer 失败时有 error 日志 + UI 不卡死 + 本 turn 不再重试 | 单测（summarizer 抛错）|
| 压缩期间聊天面板显示「正在压缩上下文…」 | 手动检查 |
| compact_summary 渲染为可折叠 CompactionCard（默认收起，含 token 前后对比），不再以普通气泡展示原文 | 手动检查 + widget 测试 |
| 记忆提取的 userPrompt（>1600 字符）原样送达 provider，无 `[已截断]` | 单测（fake client 断言收到的消息） |
| `runShortcut`/`AiChapterService`/遗留枚举删除后全仓库编译通过 | `flutter analyze` + 现有测试回归 |

## 3. User Stories

1. 作为作者，我希望超长创作会话自动压缩而不是突然报错，以便不中断创作流。
2. 作为作者，我希望压缩后 AI 仍记得我当前正在下达的指令原文，以便任务不跑偏。
3. 作为作者，我希望压缩时看到明确状态提示，以便不误以为应用卡死。
4. 作为维护者，我希望压缩触发/切点/失败都有日志（tokens before/after、切点位置、失败原因），以便排查「AI 忘事」类反馈。
5. 作为维护者，我希望压缩失败走退避而不是每轮重试，以便故障时不放大成本。

## 4. 解决方案

### 方案对比

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|------|------|------|------|------|
| A 原地修补 | 保留 buildMessages 内隐式压缩，只修估算器和落库匹配 | 改动最小 | 压缩仍同步阻塞且不可观测；估算修得再准也不如真实 usage；D1/D2 无解 | 放弃 |
| B usage 驱动 + 显式压缩步骤 | 触发指标改用上一轮真实 `inputTokens`；压缩从 buildMessages 移出，由 Agent 循环显式调用并发事件；切点改 turn 边界；落库改内容匹配 | 触发精确（usage 已含 system prompt 与 blocks，无需估算）；可观测；切点/落库一并理顺 | 接口小幅扩展（新增压缩查询/执行方法 + 2 个事件） | **推荐** |
| C 每轮无 LLM 裁剪（滑窗丢弃旧消息，不做摘要） | 超限时直接丢最旧消息 | 零额外 LLM 成本、无阻塞 | 长篇创作强依赖早期设定与决策，硬丢弃质量损失不可接受；且现有 compact_summary 持久化模型已按摘要设计 | 放弃 |

### 决策

推荐方案 B。

选择理由：

1. `AiUsage.inputTokens` 语义（`client.dart:53-57`）已统一为「含 cached tokens 的完整 prompt token 数」，即上一轮请求的真实上下文大小，天然包含 system prompt、thinking、tool 结果——问题 A 和 D3 的「system prompt 不占预算」一并消解。
2. assistant 消息的 usage 已随消息持久化并在会话恢复时回填（`session_persistence.dart:486-490`、`agent_message_mapping.dart:191`），重启后首轮同样拿得到真实基线。
3. 把压缩变成 Agent 循环里的显式步骤，事件、取消、失败退避都有自然挂点，符合 Rule 12。

拒绝方案：

- 方案 A：不解决同步阻塞与静默失败，等于保留两个已知 P2。
- 方案 C：与产品形态（长篇小说创作）冲突。

### 核心原则

1. **真实 usage 优先，估算只兜底**；估算宁可高估（触发早）不可低估（触发晚 = 报错）。
2. **retained 自洽**：任何切点下，retained 内 tool_result 必有配对 tool_call，首条不是孤儿 tool_result。
3. **落库永不猜位置**：内容匹配失败就跳过本次插入 + warning，等下一次 settled 同步，绝不 append 末尾。
4. **失败大声且有界**：summarizer 失败打 error 日志、发事件、本 turn 内退避，不静默重试。
5. 手术式改动：`AgentContextManager` 抽象、DB schema、`_messagesSinceLatestCompact` 语义不动。

### 关键假设

| 假设 | 如果不成立 | 应对 |
|------|------------|------|
| 各 provider 适配层都正确填充 `inputTokens` | 触发指标失真 | 兜底估算器仍在；日志记录 usage 缺失率，缺失时走估算 |
| UI 消息与 agent 消息可按 role+type+文本内容匹配（`_sameContextMessage` 现行逻辑已在用） | 摘要插入被跳过 | 跳过是安全侧（历史不丢），warning 日志暴露频率 |
| turn 边界（user text 消息）在预算内总能找到 | 单 turn 超大（超长工具循环） | intra-turn fallback 切点 + 指令原文 restate（见 5.3） |

## 5. 方案实施

### 5.1 模型设计

无新增持久化实体。运行时新增：

```text
CompactionOutcome（内存对象，agent_context_manager.dart）
- tokensBefore: int        触发时的评估值
- tokensAfterEstimate: int 压缩后 retained + summary 的估算值
- overflowCount: int       被压缩的消息数
- cutKind: turnBoundary / intraTurn / skipped
```

`SmartAgentContextManager` 构造参数语义变更：`tokenLimit` 改名 `compactThreshold`（= 触发压缩的输入 token 线，由调用方按「模型窗口 − 输出下限 − 漂移余量」推导，见 5.4 chat_turn_runner），另接收 `contextTokens` / `outputFloor` 供 Agent 做逐请求 max_tokens 钳制；新增内部状态 `_roundIndexAtLastCompaction`、`_suppressedThisTurn`（失败退避）、`_lastCompactionOutcome`（最近一次压缩的 tokensBefore/After，随 `snapshot()` 输出，供落库写进 compact_summary 消息 metadata → CompactionCard 展示）。

### 5.3 关键业务流程

**触发与压缩（Agent 循环内，每轮 LLM 调用前）：**

```text
1. Agent 检查 ctxMgr is SmartAgentContextManager 且 shouldCompact()：
   a. 取最近一条带 usage 的 assistant 消息；若其轮次 > _roundIndexAtLastCompaction，
      currentTokens = usage.inputTokens + estimate(该 assistant 之后新增的消息)
   b. 否则（无 usage / 刚压缩过）currentTokens = estimate(全部消息) + systemPromptEstimate
      （systemPromptEstimate 由 Agent 在调用时传入：estimate(systemPrompt + memoryBlock)）
   c. 触发条件：currentTokens > compactThreshold（= 窗口 − outputFloor − 4000，
      见 5.4 chat_turn_runner），且未处于失败退避
2. 触发 → yield AgentCompactionStart(tokensBefore)
3. ctxMgr.compact(summarizer)：
   a. 选切点：从尾部向前累积估算 token，在候选边界（user text 消息，含 steering/
      loop-hint）中选择「retained 估算 ≤ 0.35 × compactThreshold」的最老一个
   b. 无候选（单 turn 超大）→ fallback：最后一个 assistant 边界，向前调整直到
      retained 内所有 tool_result 都有配对 tool_call；并记录「需要 restate」
   c. overflow 为空（切点=0）→ 返回 skipped，不调 summarizer
   d. summarizer 输入 = [旧 _summary（如有）] + renderForSummary(overflow)
      （滚动合并，提示词要求「合并既有摘要与新内容」）
   e. 成功：_summary = safeTruncate(结果, summaryMaxChars=8000)；
      _inner.setMessages(retained)；若需要 restate，在 retained 头部插入
      「[用户当前指令原文] …」user 消息（safeTruncate 4000）；
      记录 _roundIndexAtLastCompaction
4. yield AgentCompactionEnd(ok, tokensBefore, tokensAfterEstimate)
5. 压缩期间/之后检查 _cancelled → AgentCancelled（上下文保持一致：compact 是
   原子内存操作，summarizer await 完成前不改 _inner）
失败路径：
3'. summarizer 抛错 → 保留原消息，_suppressedThisTurn = true（onStart 时复位），
    _log.error + yield AgentCompactionEnd(ok=false, reason)；本轮照常发送
    （可能被供应商拒绝，但错误可见且不静默空转）
```

**落库定位（persistence / settled 同步共用）：**

```text
1. 由共享 matcher（内容匹配：role + type + 文本相等，即现 message_mapping.dart
   _sameContextMessage 逻辑）把 snapshot.messages 解析为 UI 消息 id 集合
2. 插入位置 = 第一条命中 retained 的 UI 消息之前
3. 无命中 → 不插入摘要、保留原消息列表 + warning 日志（含 sessionId、retained 首条
   角色/类型），等待回合结束 settled 同步重试
```

### 5.4 改动清单

#### NEW: `lib/shared/agent/token_estimator.dart`

- `estimateAgentMessagesTokens(List<AgentMessage>)` / `estimateTextTokens(String)`：遍历 content + 全部 blocks（TextBlock/ThinkingBlock 文本、ToolCallBlock 的 `jsonEncode(arguments)`、ToolResultBlock 递归、ImageBlock 计固定 1600）；计权 `tokens = cjkChars + 非CJK字符 ÷ 4`（CJK 判定：U+2E80–U+9FFF、U+F900–U+FAFF、U+FF00–U+FFEF），刻意偏高估。
- `safeTruncate(String, int maxChars, {String suffix})`：UTF-16 代理对安全截断，供两个 context manager 复用（修 F3）。

#### `lib/shared/agent/agent_context_manager.dart`

- `SmartAgentContextManager`：
  - `buildMessages()` 退化为纯函数：只做 `_prependSummary`，不再触发压缩（修 D1）。
  - 新增 `bool shouldCompact({required int systemPromptTokens})`：按 5.3 步骤 1 实现（修 A、D3）。
  - 新增 `Future<CompactionOutcome> compact()`：切点选择（turn 边界优先 + intra-turn fallback + 配对校验 + restate）、滚动摘要合并、`safeTruncate`；**不再 catch (_)**，异常向上抛由 Agent 处理（修 C1/C3/D2/F3 相关部分）。
  - `tokenLimit` → `compactThreshold`（另接收 `contextTokens` / `outputFloor`，见 5.1），`summaryMaxChars` 默认 16000 → 8000（与提示词对齐，修 C4）；`fromSnapshot` 同步改名。
  - 新增退避状态 `_suppressedThisTurn` 与 `resetTurnState()`（Agent 在 `process` 开始时调用）。
- `SimpleAgentContextManager` 不动。

#### `lib/shared/agent/agent_event.dart`

- 新增 `AgentCompactionStart({int tokensBefore})`、`AgentCompactionEnd({bool ok, int tokensBefore, int tokensAfter, String? reason})`。

#### `lib/shared/agent/agent.dart`

- `process()`：新增可选参数 `String? userMessageId`，用户任务消息 id 优先取该值（`chat_turn_runner.runTurn` 已持有同名 UI id），使 turn 边界消息天然跨命名空间对齐（辅助修 B）。
- 循环内、每轮 `_buildMessages()` 之前：按 5.3 执行 shouldCompact/compact，发压缩事件，处理取消与失败（error 日志 + `AgentCompactionEnd(ok:false)`）。
- 逐请求 max_tokens 钳制：每轮 `chatStream` 前，`options.maxTokens = clamp(contextTokens − currentTokensEstimate − margin, outputFloor, config.maxTokens)`（context manager 提供 currentTokens 与窗口参数）；被钳低于配置值时打 debug 日志。保证 input + max_tokens 恒不超窗，压缩触发线才能贴近窗口上沿。
- `process` 开头调用 `smart.resetTurnState()`。

#### NEW: `lib/shared/services/ai/context_message_matcher.dart`

- 从 `message_mapping.dart` 提取 `sameContextMessage` / `resolveUiContextMessageIds` 为共享纯函数（修 B；Rule 5：保留内容匹配这套更稳的实现，废弃 id 匹配）。

#### `lib/shared/services/ai/session_persistence.dart`

- `_buildPersistedMessages`：`retainedIds` 改为经 `context_message_matcher` 解析出的 **UI 消息 id**；`insertIndex < 0` 时不再 `persisted.add(summaryMessage)`，改为跳过插入 + `_log.warning`（修 B 的数据丢失路径）。
- compact 记录改 **append-only**：`_compactSummaryMessageId` 从固定 `ctx_summary_$sessionId` 改为含压缩序号的唯一 id（`ctx_summary_${sessionId}_${compactionCount}`）；移除「插入前过滤掉所有既有 compact_summary」的逻辑——历史 compact 记录是普通持久化消息，永久留存，只有本次新摘要按边界插入。每次压缩后 DB 里的 compact 记录逐条累积，旧摘要原文可随时回看（`run history` 也可检索到）。

#### `lib/desktop/widgets/ai/chat/message_mapping.dart`

- 改为调用共享 matcher，删除本地重复实现；`insertIndex < 0` 分支同样改为跳过 + warning（当前是 append 末尾，同一隐患）。
- 与 persistence 同步 append-only 语义：`_syncPersistedContextState` 不再按固定 id 查找/替换既有摘要，只在**发生了新压缩**（snapshot 的 compactionCount 大于已同步值）时插入新记录，历史 compact 消息不动。

#### `lib/shared/models/models_catalog.dart`（已完成）

- `ModelCatalogEntry` 新增 `limit: ModelCatalogLimit(context, output)`；按家族沿袭值填充全部条目（GPT-5 系 400k/128k、Claude 系 200k/64k、Gemini 系 1M/64k…），未知模型（Mimo）留 null。
- 新增 `lookupCatalogLimit(modelId)`：与 `lookupCatalogReasoningEfforts` 同一套前缀回退匹配。
- 长度限制与 reasoningEfforts 都从本地模型目录读取，不保留远程配置覆盖入口。

#### `lib/shared/services/ai/chat_turn_runner.dart`

- 构造 `SmartAgentContextManager` 时按模型动态推导触发线，替换写死的 100000（修 D3）。
  原则：**不为最大输出全额预留窗口，只保障最低输出空间**——`maxTokens=65536` 是上限而非典型值，全额预留等于常态性放弃 1/3 窗口、压缩提前 70k 触发：
  ```text
  limit            = lookupCatalogLimit(session.model)
  contextTokens    = limit?.context ?? 131072                                    // 保守默认
  outputFloor      = min(16000, limit?.output ?? 16000)                          // 单轮输出的最低保障
  compactThreshold = max(20000, contextTokens − outputFloor − 4000)              // 4000 为估算漂移余量
  ```
  代入：Claude 200k → 触发 ≈ 180k（~90% 窗口利用）；DeepSeek chat 128k/输出 8k → 触发 ≈ 116k；Gemini 1M → 触发 ≈ 1.03M。
- 输出空间的正确性由 agent.dart 的**逐请求 max_tokens 钳制**保证（见其改动条目）：上下文尚小时配置的 `maxTokens` 完整可用；上下文增长到挤占输出空间后，单请求 max_tokens 被钳到剩余窗口（始终 ≥ outputFloor）；钳到 outputFloor 仍不够，即达到 compactThreshold，触发压缩。三段行为连续，任何时刻请求都不会因 input + max_tokens 超窗而被拒。
- summarizer 重写（修 C2/C3）：
  - 输入渲染改用新 helper `renderForSummary`：user/assistant 取文本（每条 ≤1000 字符），ToolCallBlock 渲染为 `→ ToolName(args ≤200 字符)`，tool_result 提取 ToolResultBlock 文本 ≤800 字符；总输入 ≤60k 字符，超出从最旧处丢弃并加 `[更早 N 条消息已省略]` 标记。
  - system prompt 不再内联硬编码，改为 `assets/prompts/system/context_compaction.md`。注入时机：应用启动时 `PromptTemplateService.loadAll()` 已预载全部 prompt 资产，`getOrCreateChatAgent` 构建 summarizer 闭包时经 `rawAsset()` 同步取字符串、捕获进闭包——它是**独立 summarizer 一次性 Agent 的 system prompt**，不进入 chat agent 自身的 system prompt，压缩发生时无任何运行时加载动作。

#### NEW: `assets/prompts/system/context_compaction.md`

- 替换现有内联英文 prompt（"You are a conversation summarizer…"），中文、结构化、域定制，遵循 `council_summarizer.md` 的既有风格。必须包含：
  - **角色定位**：说明输出将**替代**被压缩消息，成为 Agent 后续轮次唯一可见的早期记录（让模型理解丢失即永久）。
  - **保真原则**：只记录对话中明确出现的信息，不推断补全；用户的明确指令与禁忌尽量原文引用；不确定的标「待确认」——摘要幻觉会以既定事实身份进入后续所有轮次，比信息丢失更危险。
  - **滚动合并**：输入含既有摘要时合并为单一摘要，冲突以新内容为准（修 C3 的 prompt 侧）。
  - **删减优先级**（空间不足时从后往前舍弃）：用户明确指令/禁忌 > 已确认创作决策（情节、人设、文风）> 章节/文件修改状态 > 待办 > 过程性讨论与被否定方案（可整段省略）。
  - **结构化输出格式**：`## 当前任务` / `## 创作决策与约束` / `## 内容状态`（哪章改了什么、完成与否）/ `## 待办` / `## 用户偏好与禁忌`。
  - **输出约束**：语言与对话主要语言一致；4000 字符以内（`summaryMaxChars=8000` 留余量）；直接输出、无前言。
- `runTurn` 事件循环：处理 `AgentCompactionStart/End` → 置/清 session 的 `isCompactingContext` 标记 + info/error 日志（tokens before/after、cutKind、耗时）。
- `agent.process(text, userMessageId: userMessageId, ...)` 传入 UI id。

#### `lib/shared/providers/ai_providers.dart`

- `AiChatSessionState` 新增瞬态字段 `bool isCompactingContext`（不持久化）；notifier 加 `setCompactingContext(bool)`。

#### NEW: `lib/shared/widgets/ai/chat/compaction_card.dart`

- 独立压缩 UI，遵循 `thinking_card.dart` 的可折叠范式（默认收起）。压缩不是工具调用（无 `ToolCallBlock`/callId），不走 `tools/` 卡片管线，由**消息类型驱动**渲染。
- 收起态：压缩图标 + `context.t(LocaleKeys.aiContextCompacted)` + token 前后对比（如 `180k → 60k`，读消息 metadata 的 `tokens_before`/`tokens_after`，缺失时只显示标题——兼容旧数据）。图标走 `RevericIcon`（`.agents/rules/icons.md`）：优先复用 `RevericIcons` 已有项，缺失则从 phosphor 库复制注册（候选 `arrows-in-simple` / `archive`）。
- 展开态：摘要全文（Markdown 渲染，与消息正文一致）。

#### `lib/shared/widgets/ai/chat/chat_message_view.dart`

- `message.type == compact_summary` 分支改为渲染 `CompactionCard`，替换普通 user 气泡。
- `isCompactingContext == true` 时在打字指示器旁显示 `context.t(LocaleKeys.aiCompactingContext)` 文本（修 D1 的用户感知；进行中不出卡片——瞬态且消息尚不存在）。

#### `session_persistence.dart` + `message_mapping.dart`（compact_summary metadata）

- 构造 compact_summary 消息时，从 `AgentContextSnapshot` 带出的最近压缩数据写入 `metadata: {tokens_before, tokens_after}`，供 CompactionCard 展示。

#### i18n 三件套

- `lib/shared/localization/locale_keys.dart`：新增 `aiCompactingContext`、`aiContextCompacted`。
- `assets/translations/en/ai.json`：`"compacting_context": "Compacting context…"`、`"context_compacted": "Context compacted"`。
- `assets/translations/zh-CN/ai.json`：`"compacting_context": "正在压缩上下文…"`、`"context_compacted": "上下文已压缩"`。

#### `lib/shared/services/ai/spawn_agent_handler.dart`

- 子代理 `Agent.custom` 传入 `SmartAgentContextManager`：compactThreshold 按子代理实际模型走同一套 `lookupCatalogLimit` 推导，summarizer 复用同一构建函数（以子代理自身 client 创建）；子代理无 UI，无需事件消费（事件已存在，仅日志）（修 D4）。

#### `lib/shared/services/ai/context_manager.dart` + `lib/shared/services/ai/ai_chat_service.dart`

- 删除 `AiContextManager` 的会话管理半边：`buildConversation` / `_retainRecentMessages` / `_truncateMessage` / `_buildSummary` / `AiManagedConversation`——对现有全部调用方唯一实际效果是把单发输入静默砍到 1600 字符（修 E）。
- `AiChatService._buildConversation` 改为：提取首条 system 消息作 system prompt（现有逻辑不变），其余消息**原样透传**，不再经过保留/截断/摘要。
- 保留 `compactContext`（章节/大纲/人设等引用材料的字符上限，服务 sessionContext 路径），其 `_truncate` 改用 `safeTruncate`（修 F3）。
- 文件头 `// 职责:` 更新为「单次生成的引用材料字符截断，**非** agent 会话压缩——agent 压缩见 lib/shared/agent/agent_context_manager.dart」。

#### DELETE: `lib/shared/services/ai/ai_chapter_service.dart`

- 全仓库零调用方的死代码（修 F1）；快捷指令现行路径为 `AiShortcutActionDefinition` → `AiChatShortcutDraft` → 聊天面板 agent。

#### `lib/shared/services/ai/chat.dart`

- 删除 `runShortcut` 转发、`_chapterService` / `_ensureChapterService`（修 F1）。

#### `lib/shared/models/ai_shortcut_action.dart`

- 删除遗留 `enum AiShortcutAction`（唯一使用者为被删的 `AiChapterService`；顺带消除与 Drift 数据类 `AiShortcutAction` 的同名冲突，修 F2）。`AiShortcutActionLocation` 与 `AiShortcutActionDefinition` 不动。

#### `lib/shared/services/ai/prompts/use_cases/task_prompt_use_case.dart`

- 删除 `shortcut()` 模板方法及 `TaskPromptAction` 中随之无引用的成员（删前 grep 确认无其他调用方；若仍有引用则保留并在 PR 说明）。

#### `lib/shared/services/ai/tools_run.dart` + `run_command_parser.dart`（PR-5：历史检索）

- Run 工具新增 `history` namespace（选 Run 子命令而非独立工具：使用频率低——仅压缩后需要；避免每请求常驻一份工具 schema；可发现性由 compact_summary 内的提示在恰好需要的时刻给出）：
  - `history search`，options `{query, role?, limit?}`：当前 session 消息 LIKE 检索，默认 top 20、按时间排序，每条截 500 字符并附消息 id/角色/序号；tool_result 消息默认排除（可选参数开启）。
  - `history get`，options `{id}`：按消息 id 取完整内容（补偿 search 的截断）。
  - `help` 文案、`run_command_parser.dart` 的 `needsSubcommand` 集合、tool card descriptor 同步登记。
- 范围硬限当前 session，不跨会话。语义检索（embedding）明确不做，LIKE 命中率不足时再升级（复用 `chapter_embedding_sync` 基建）。

#### DAO：`ai_chat_message_dao`（PR-5）

- 新增 `searchInSession(sessionId, query, {roles, limit})` 与按 id 单取：LIKE 过滤与 limit 在 SQL 层完成（遵循 `.agents/rules/db-query-aggregation.md`），不读全量行内存过滤。

- `context_compaction.md` 联动：角色定位补一句「被省略的细节，Agent 可通过 `Run(history search)` 从完整历史找回」——摘要从此只需当好索引，不必当档案。

> 所有被修改的 Dart 文件按仓库规则同步更新文件头 `// 关联文件:`。

### 5.5 Task Graph

```text
PR-1 核心压缩重构（token_estimator + SmartAgentContextManager + Agent 事件）
  ├─ PR-2 落库定位修复（context_message_matcher + session_persistence + message_mapping）
  └─ PR-3 接线（chat_turn_runner 预算/summarizer/事件消费 + UI 提示 + i18n + spawn_agent）
        ├─ PR-4 外围清理（AiContextManager 去截断收缩 + 死代码删除 + safeTruncate 复用）
        └─ PR-5 历史检索（Run history 子命令 + DAO 检索 + 压缩 prompt 联动）
```

| 任务 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| PR-1 | 估算器、shouldCompact/compact、事件、退避、`process(userMessageId)` | 无 | 新增 `test/shared/agent/` 单测 |
| PR-2 | 共享 matcher、两处插入定位改造 | PR-1（依赖切点语义） | persistence 单测：命中插入 / 未命中跳过 |
| PR-3 | 预算推导、summarizer 渲染、CompactionCard 与压缩状态 UI、i18n、子代理保护 | PR-1、PR-2 | characterization 测试 + CompactionCard widget 测试 + 手动长会话 |
| PR-4 | AiContextManager 收缩（去 1600 截断）、删 AiChapterService/runShortcut/遗留枚举/shortcut 模板、safeTruncate 复用 | PR-1 | 记忆提取输入完整性单测 + `flutter analyze` + 现有测试回归 |
| PR-5 | Run `history` 子命令（search/get）、DAO 检索、compact prompt 联动提示 | PR-3（需 context_compaction.md 已存在） | DAO 检索单测 + Run 路由单测 |

**发布门槛：PR-1 不得单独发版**——它让压缩真正开始触发，而问题 B 的数据丢失路径要 PR-2 才关闭。PR-1/PR-2 必须同批合入 release 分支。

### 5.7 上线后验证

| 指标 / 日志 | 目的 | 异常信号 | 观察周期 |
|-------------|------|----------|----------|
| `compaction triggered tokensBefore=… cutKind=…` info 日志 | 确认触发时机合理 | 从不出现（长会话下）或每轮出现 | 2 周 |
| `compaction failed …` error 日志 | summarizer 稳定性 | 失败率 > 5% | 2 周 |
| `summary placement skipped (no match)` warning | matcher 命中率 | 高频出现（说明内容匹配失效） | 2 周 |
| usage 缺失走估算兜底的 debug 日志 | provider usage 覆盖度 | 某 provider 恒缺失 | 1 周 |
| 上下文溢出类 400 报错次数 | 最终效果 | 修复后仍出现 | 持续 |

## 6. 验收标准

| 类别 | 标准 | 验证方式 |
|------|------|----------|
| 功能 | 构造含 60k+ token 工具结果（全在 blocks）的历史，`shouldCompact` 返回 true；纯 content 同量级亦触发 | `test/shared/agent/agent_context_manager_test.dart` |
| 功能 | 触发后 retained 首条为 user text；或 fallback 时所有 tool_result 配对完整且含 restate 指令消息 | 同上，穷举切点场景 |
| 功能 | 二次压缩的 summarizer 输入包含首次摘要（滚动合并） | 单测断言 summarizer 收到的输入 |
| 功能 | 压缩期间 `AgentCompactionStart/End` 事件按序产出；UI 标记置位/清除 | agent 单测 + turn runner characterization 测试 |
| 功能 | 任意上下文大小下，请求的 input 估算 + max_tokens ≤ contextTokens；max_tokens 恒 ≥ outputFloor | agent 单测（穷举上下文大小区间） |
| 功能 | `run history search` 只返回当前 session 的匹配消息；`history get` 返回完整内容；未知 id 报错不崩 | DAO + Run 路由单测 |
| 功能 | compact_summary 消息渲染为 CompactionCard：默认收起、展开见全文；metadata 缺失（旧数据）不崩、只隐藏 token 对比 | widget 测试 |
| 功能 | 二次压缩后：原始消息一行不少、两条 compact 记录并存于 DB、agent 历史从最新一条截取、UI 按位置显示两张卡片 | persistence 单测 + 手动检查 |
| 兼容 | 旧会话中固定 id `ctx_summary_$sessionId` 的存量摘要行照常加载、渲染为卡片、可作为截取边界 | 现有数据手动验证 |
| 兼容 | 旧会话（无 usage 列 / 无 compact_summary）加载与发送行为不变 | `chat_turn_runner_characterization_test.dart` 回归 |
| 兼容 | `_messagesSinceLatestCompact` 行为不变（既有摘要边界会话恢复正常） | 现有测试回归 |
| 错误处理 | summarizer 抛错：消息不变、error 日志、`AgentCompactionEnd(ok:false)`、同 turn 不再尝试 | 单测（summarizer 抛异常） |
| 错误处理 | matcher 未命中：不插入摘要、不 append 末尾、warning 日志、消息列表原样 | persistence 单测 |
| 错误处理 | 压缩中取消：正常走 AgentCancelled，上下文不处于半压缩状态 | agent 单测 |
| 性能 | 估算器对 1000 条消息 < 10ms（纯遍历，无分配热点） | 单测粗测 |
| 可维护性 | `estimateTextTokens('你好世界')` ≥ 4，`safeTruncate` 不劈代理对 | `test/shared/agent/token_estimator_test.dart` |
| 功能 | `chatCompletion` 收到的 user 消息 >1600 字符时原样送达（无 `[已截断]`） | `test/shared/services/ai/` 单测（fake client 断言） |
| 兼容 | 起名 / 标题生成 / 记忆提取 7 个调用方编译通过、行为不变（除不再截断） | `flutter analyze` + 现有测试回归 |
| 可维护性 | `runShortcut`/`AiChapterService`/`enum AiShortcutAction`/`TaskPromptUseCase.shortcut` 全仓库无残留引用 | grep 检查（不含 docs/） |

测试命令（串行）：

```bash
flutter test test/shared/agent
flutter test test/shared/services/ai
```

## 7. 评测

### 评测对象

- 被测能力：压缩摘要是否保留「当前任务、已确认的创作决策、文件/章节引用、待办与约束」。
- 不测内容：摘要文笔；触发/切点逻辑（已由确定性单测覆盖）。
- 输入来源：3–5 个脚本化长会话（含大量 Read/Grep/Edit 工具轮次 + 中文创作讨论）。
- 输出判定：人工 checklist。

### 评测场景

| 场景 | 输入 | 期望 | 判定方式 |
|------|------|------|----------|
| 工具重度 turn 中触发 | 30+ 轮工具调用后超预算 | 摘要含被读写的章节/文件名；restate 保留指令原文 | manual |
| 跨 turn 触发 | 多个完整 turn 后超预算 | 摘要含各 turn 结论；retained 从最近 turn 的 user 消息起 | manual |
| 滚动二次压缩 | 首次压缩后继续超预算 | 首次摘要中的决策仍出现在合并摘要 | manual |
| 保真：无幻觉 | 含明确决策与开放问题的会话 | 摘要不含对话中未出现的事实；未定事项不被写成已决 | manual |
| 输出语言 | 全中文创作会话 | 摘要为中文、遵循结构化分节格式 | manual |

### 自动化与人工评测边界

- 自动化：触发条件、切点合法性、配对完整性、事件序列、落库位置——全部确定性单测。
- 人工：摘要语义质量抽查，仅作观察，不阻断合入。

## 8. Token 成本

| 维度 | 估计 | 说明 |
|------|------|------|
| 单次压缩调用 | 输入 ~5k–20k / 输出 ~1k–2k token | 输入为渲染后的 overflow（总 ≤60k 字符）+ 旧摘要 |
| 调用次数 | 每次上下文逼近预算触发一次；正常创作会话约每 15–40 turn 一次 | 失败退避保证每 turn 至多 1 次尝试 |
| 上下文增长 | 压缩后请求体回落到 ~0.35 × budget + 摘要 ≤8k 字符 | 由 keep 目标控制，不随会话无限增长 |
| 模型档位 | 沿用会话模型 | 降档为后续优化（见已知妥协） |
| 记忆提取输入恢复完整 | 单次提取输入从 ~1600 字符恢复到实际 prompt 长度（提取服务自身已限每条消息 800 字符，有内生上界） | 修 bug 的预期成本：此前提取只覆盖会话开头，属于错误省钱 |

相比现状：现状压缩从不触发，token「成本」表现为整段请求报废（400）+ 用户重开会话；本方案新增每次压缩一笔摘要调用，换取长会话可持续。子代理接入压缩同理，且子代理历史通常更短，触发频率低。

### 缓存影响

- **压缩之间的轮次**：`buildMessages` 改为纯函数后，输出是「稳定前缀（summary + restate + retained，一次写入后不变）+ 逐轮追加」结构，自动前缀缓存正常累积命中；max_tokens 逐请求钳制是请求参数，不参与缓存键，无影响。触发线设在 ~90% 窗口不会显著抬高成本的原因也在此：高位轮次的输入绝大部分是 cache read（约全价 1/10），增量只有新消息。
- **压缩发生的下一轮**：消息段缓存必然失效一次——压缩本质是重写消息前缀（删旧消息、前插 summary）。system/tools 前缀段不变，支持分段缓存的 provider 仍命中。这是所有压缩方案的固有成本，每次压缩一次性支付。
- **summarizer 调用自身**：独立 system prompt + 一次性 overflow 渲染，与任何已有请求前缀不同，无缓存可言——全价 input 一次（~5k–20k token）。
- **接线时核实**：Anthropic 的 prompt cache 需要显式 `cache_control` 断点，OpenAI/DeepSeek/Gemini 为服务端自动前缀缓存。检查 provider 适配层是否已为 Anthropic 设置断点；若未设置属存量问题，单独处理，不阻塞本方案。

## 9. 风险

| 风险 | 触发条件 | 影响 | 对策 |
|------|----------|------|------|
| 某 provider `inputTokens` 填 0 / 缺失 | 使用该 provider 长会话 | 触发退化到估算路径 | 估算器偏高估兜底；debug 日志暴露缺失率 |
| 内容匹配（matcher）因文本清洗（`_stripHandoffTags` 等）不一致而未命中 | 含 handoff 标签的消息成为 retained 首条 | 摘要插入被跳过（安全侧），重载后压缩边界缺失 → 下轮重新压缩，多付一次摘要成本 | matcher 对比双方都先做同样 strip；warning 日志监控命中率 |
| turn 边界切点后 retained 仍超预算（单 turn 巨大） | 超长工具循环 | fallback intra-turn 切点 | 已设计 fallback + restate；单测覆盖 |
| 压缩后 usage 基线过期导致重复触发 | 压缩完成的下一轮 | 连续压缩空转 | `_roundIndexAtLastCompaction` 守卫：无新 usage 前只用估算当前（较小的）消息集 |
| catalog limit 家族沿袭值与实际不符（偏大） | 新模型窗口缩水或 catalog 数据过期 | 仍可能溢出 | 未匹配时默认保守（131072）；错误可从 400 日志定位后改 catalog |
| summarizer 与主循环共用 client 的取消语义冲突 | 压缩中用户点停止 | 压缩请求悬挂 | Agent 在 compact await 后检查 `_cancelled`；summarizer agent 独立实例，`client.cancel()` 会中断底层请求 |

## 10. 已知妥协

```text
1. 妥协：intra-turn fallback 压缩后，重载会话的历史范围与运行时 retained 不完全一致
   （重载按 compact_summary 边界截取，会重新包含被压缩的本 turn 早期轮次）。
   - 原因：DB 侧压缩边界以消息为粒度，UI 消息无法表达「turn 内部切点」。
   - 影响：重载后首轮请求略大（轻微冗余），无数据丢失。
   - 升级触发：日志显示 intra-turn cutKind 占比高且重载后频繁立即再压缩。
   - 后续方向：持久化 AgentContextSnapshot 并用 SmartAgentContextManager.fromSnapshot 恢复。

2. 妥协：Council/Theater/Monologue 暂不接入压缩，仍用 SimpleAgentContextManager。
   - 原因：均为有界编排（轮数固定），溢出概率低，改动收益比差。
   - 影响：极端长的编排仍可能溢出。
   - 升级触发：这些路径出现上下文溢出报错。
   - 后续方向：复用本方案的 Smart manager 构建函数。

3. 妥协：catalog 未收录的模型 context 默认 131072，小窗口本地模型会提前打爆；
   catalog 中后发模型的 limit 为家族沿袭值，可能与官方实际值有偏差。
   - 原因：模型限制来自静态本地目录。
   - 影响：本地小模型用户仍可能遇到溢出；沿袭值偏大时压缩触发偏晚。
   - 升级触发：用户反馈溢出，或供应商公布的模型限制发生变化。
   - 后续方向：核对供应商限制并更新本地目录。
     catalog 数值随官方文档持续修订。

4. 妥协：summarizer 沿用会话模型，不降档。
   - 原因：降档需要跨 provider 的「更便宜模型」解析规则，超出本方案范围。
   - 影响：压缩成本随会话模型档位走。
   - 后续方向：settings 增加摘要模型配置。

5. 妥协：上下文逼近触发线时，单轮 max_tokens 被钳制（最低至 outputFloor=16k），
   超长正文单轮生成可能被输出截断。
   - 原因：为换取 ~90% 窗口利用率，放弃「任何时刻都保障配置 maxTokens 全额输出」。
   - 影响：仅发生在触发线前的窄区间（Claude 200k 上约 134k–180k 区间逐步收窄）；
     被钳时有 debug 日志；下一次压缩后恢复全额。
   - 升级触发：日志显示长文生成频繁撞钳。
   - 后续方向：撞钳且本轮为长文任务时提前触发压缩，而非等 outputFloor 见底。
```
