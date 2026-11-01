# AI Chat Streaming CPU 优化方案

> 状态更新：2026-07-02。本文档已按 `development` 分支（HEAD `e31e74b6`）实际代码核对，
> 区分「已落地 / 未做 / 待做」。早期版本里把若干 wip 分支的改动当作已完成，已纠正。

## 实施现状（按代码核对，非文档自述）

| 项 | 状态 | 证据 |
|----|------|------|
| Phase 6 编辑区 repaint 边界 | ✅ 已做 | `editor_focus_lines_layer.dart:178` `RepaintBoundary` + `isComplex:true` + `willChange:false` |
| Phase 7 断开 onEditingStateChanged 闭包环 | ✅ 已做 | `panel.dart:318` `onEditingStateChangedRef = useRef(...)`；effect keys `[runtimeState.isEditing]` / `const []`（commit `e1776640`） |
| #2 流式 jumpTo no-op guard | ✅ 已做 | `auto_scroll_hook.dart:141` streaming 分支：`pos.pixels < pos.maxScrollExtent - 0.5` 才 `jumpToBottom()`（本方案新增，原 doc 无） |
| memoize `groupMessagesForUi` | ⏳ 待测 | 已写 `panel.dart:277` `useMemoized(() => groupMessagesForUi(messages), [messages])`，但**未测试、未提交**，暂当未做 |
| Phase 1 tool partial 节流 | ❌ 未做 | throttle 文件只存在于 dangling wip commit `7aa5286a`，**未合入 development**；client 仍每 fragment `parseStreamingJson` |
| Phase 2 `upsertToolCallBlock` no-op dedupe | ❌ 未做 | `ai_providers.dart:537` 每次调用都 `state = state.copyWith(messages: newList)` |
| Phase 3-②③④ Consumer 下沉 / 稳定 key / SVG 隔离 | ❌ 未做 | — |
| Phase 4 partial JSON parser 优化 | ❌ 未做 | — |
| Phase 5 `aiModeProcessingTrackerProvider` 下沉 bridge | ❌ 未做 | `novel_editor.dart:3561` 仍在页面根 `ref.watch` |
| Phase 8 状态栏全文计算按文本身份缓存 | ❌ 未做 | `_ChapterStatusMetrics` 仍 `StatelessWidget`、`_StatusBarAutoFormatButton` 仍 `ConsumerWidget`，无缓存 |

**结论：用户实际只采用了 Phase 6 / 7，加上 #2。** memoize 与 Phase 1–5、8 待做。

## 背景

2026-07-02 的 macOS Debug 现场 profile 显示，Reveric 在 AI Chat 右侧面板展示「执行过程」并持续接收工具调用 stream 时，Activity Monitor 中主进程 CPU 稳定在 110%–120% 左右。用户观察到高 CPU 与 chat panel 的定时 / streaming 更新相关，要求先 profile 再优化。

本方案基于以下已采集证据，而不是基于截图或猜测：

- Dart CPU samples: `/tmp/reveric-highcpu2.cpu-samples.json`
- Native sample: `/tmp/reveric-highcpu2.native-sample.txt`
- 进程状态: `/tmp/reveric-highcpu2.ps.txt`
- Flutter build timeline: `/tmp/reveric-highcpu2-builds.timeline.json`
- 后续复现与采样流程记录在 `.agents/skills/profile/SKILL.md`

## 现状链路

OpenAI-compatible 工具调用 stream 的关键链路：

```text
OpenAiClient.chatStream
  -> 每个 tool_call delta 追加 arguments fragment
  -> parseStreamingJson(toolCall.args.toString())
  -> yield ToolCallDelta(isPartial: true)
  -> Agent / ChatTurnRunner 转发 partial tool event
  -> AiChatSessionNotifier.upsertToolCallBlock()
  -> state = state.copyWith(messages: newMessages)
  -> AiChatPanel watch messages
  -> groupMessagesForUi(messages)
  -> AiToolActivityGroup / ToolStepRow / RevericIcon / SvgPicture rebuild
```

text / thinking delta 链路（**当前主瓶颈**，见下）：

```text
AgentTextDelta / AgentThinkingDelta（每个 token）
  -> ChatTurnRunner 调 sessionNotifier.appendTextDelta / appendThinkingDelta
  -> List.from(blocks) + List.from(messages) + state = state.copyWith(messages)
  -> panel watch messages（identity 每 token 变）
  -> rebuild（即使有 memoize 也每 token miss，因 messages 每 token 换 identity）
```

相关文件：

- `lib/shared/agent/client/openai_client.dart`
- `lib/shared/agent/client/openai_responses_client.dart`
- `lib/shared/agent/client/anthropic_client.dart`
- `lib/shared/agent/client/_partial_json.dart`
- `lib/shared/providers/ai_providers.dart`
- `lib/shared/services/ai/chat_turn_runner.dart`
- `lib/desktop/widgets/ai/chat/panel.dart`
- `lib/shared/widgets/ai/chat/ui_message.dart`
- `lib/shared/widgets/ai/chat/auto_scroll_hook.dart`

## Profile 结论（历史证据，保留）

Dart CPU samples 中，Flutter framework 的 `updateChild` / `Element.update` / `performRebuild` 是主要 exclusive 热点，说明 CPU 很大一部分消耗在 widget 更新路径上。第一个 app frame 中，`parseStreamingJson` 和 `OpenAiClient.chatStream` 明显靠前，说明 rebuild 不是孤立 UI 问题，而是 stream 解析和状态写入在高频触发 UI 更新。

Build timeline 进一步印证了 rebuild fan-out：

| 指标 | 现场观察 |
|------|----------|
| 采样窗口 | 5 秒 |
| timeline events | 33166 |
| `SvgPicture` / `VectorGraphic` | 各 790 次 |
| `RevericIcon` | 388 次 |
| `AiToolStatusDot` | 64 次 |
| `_ToolStepRow` | 40 次 |
| `AiToolActivityGroup` | 25 次 |
| `NovelEditorPage` | 3 次，平均约 19ms |
| `LeftSidebar` | 3 次，平均约 9.8ms |
| `AiChatPanel` | 3 次，平均约 2.7ms |

### Root cause：`onEditingStateChanged` 闭包身份进入 useEffect keys（已由 Phase 7 修复）

`panel.dart` 两个 `useEffect` 曾把 `onEditingStateChanged` 回调的**闭包引用**放进 keys，而该回调在 `novel_editor.dart` 是内联闭包，`NovelEditorPage` 每次 rebuild 都产生新引用，闭合成环：

```text
页面 rebuild → 新闭包 → 两个 effect keys 变化
→ cleanup 写 isAgentEditing=false、新 effect 写 =true
→ ValueNotifier 通知 → NovelEditorPage 整页 rebuild → 新闭包 → …
```

- agent 运行 / AskUser 挂起时 `isEditing=true`，false→true 是真变化 → 环自持续（按帧率循环）。
- 空闲时 `isEditing=false`，false→false 不通知 → 环断开。精确匹配「只在 agent 运行期间 CPU 高」的现象。

放大器是每圈整页 rebuild 连带的无缓存全文计算（`countTextUnitStats` 7 个正则全文 pass、`formatChapterBody` 全文逐行 format 再 `==`），位于 `novel_workspace_panel.dart` 而非 chat panel。

Phase 7 用 `useRef` 解耦闭包身份后，该闭环已断开。**但放大器本身（Phase 8）未做**——只要还有别的路径触发整页 rebuild，它们仍会重跑。

### 当前真实瓶颈（Phase 6/7/#2 之后的复测）

复测采样（`/tmp/reveric-reprofile2.*`，CPU ~83.8%；`/tmp/reveric-postfix-hot.*`）显示热点已从 build/paint 转移：

| 信号 | 现值 |
|------|------|
| top exclusive | `_paintWithContext` / `paintChild`（reprofile2，paint-bound）→ postfix 已被 #2 压下 |
| first app frame | `toSql`(26) + logger `info`(11) + `parseStreamingJson`(10) + `upsertToolCallBlock`(6) + `appendThinkingDelta`(4) |
| 残留主因 | **每个 text/thinking token 写一次 `messages`**：`appendTextDelta`/`appendThinkingDelta` 每 token `List.from` + `state.copyWith`，panel 每 token rebuild |

> 测量 caveat：postfix native sample 主线程大量被 `ProfilerService::PrintJSON` / `dladdr` 占用，是采 `getCpuSamples` 时 profiler 自身开销，非 app 真实负载；可信的是 Dart first-app-frame 相对排序。

即：Phase 6/7/#2 已移除 paint 与闭环成本后，**per-token `messages` 写入**成为残余主因。这正是下一阶段目标。

## 当前效果

> 诚实声明：没有一组同场景、同口径的 before/after 定量对比。下列是两次不同时点、不同复现强度的采样，只能说明「热点类型已转移」与「CPU 量级下降」，不构成精确降幅。

### 现象（用户实测）

用户反馈：#2（流式 jumpTo no-op guard）落地后，「优化了很多」，剩余现象是「每次 rebuild 瞬间的 CPU 很高」。这与 profile 推断一致——高频 paint 已消除，残余的是单次 rebuild 的瞬时成本。

memoize `groupMessagesForUi` 虽已写在工作树，但用户尚未测试，效果未知，暂不计入。

### 数据

| 窗口 | 时间 | 已含改动 | CPU | Dart tag / sampleCount | 主热点（first app frame） |
|------|------|----------|-----|------------------------|--------------------------|
| baseline `reprofile2` | 18:37 | Phase 6/7 | **140.7%** | 1203 / 2263 | paint-bound：`_paintWithContext` 77 excl / `paintChild` 76 excl |
| 复测 `postfix-hot` | 22:40 | Phase 6/7 + #2（memoize 当时在工作树但未测试，是否生效不明） | **~83.8%** | 199 / 425 | state/parse：`toSql` 26、`parseStreamingJson` 10、`upsertToolCallBlock` 6、`appendThinkingDelta` 4 |

观察：

1. **热点类型转移**：从 paint-bound（`_paintWithContext`/`paintChild` 主导）转到 state 写入 + parse（`toSql`/`parseStreamingJson`/`appendThinkingDelta`）。这正是 #2 的预期效果——paint fan-out 被压下后，暴露出上游 per-token `messages` 写入。
2. **CPU 量级下降**：140.7% → ~83.8%。但两个 caveat 削弱这个数字的可信度：
   - `postfix-hot` native sample 主线程大量被 profiler 自身占用（`ProfilerService::PrintJSON`/`dladdr`），83.8% 含采样开销，真实负载更低。
   - 两次复现场景强度、消息量不同，且 postfix sampleCount 仅 425（baseline 2263），统计噪声大；memoize 是否计入也不明。
3. **无法做精确降幅结论**：缺同场景同口径复测。要量化，需在同一复现场景下，分别采 #2 前、后各一次 hot window。

### 为何仍是「每次 rebuild 瞬间高」

#2 砍掉了「已贴底时无意义的 jumpTo 重绘」，但**不减 rebuild 次数**：

- 每个 text/thinking token 仍让 `messages` 换 identity → panel 每 token 一次 rebuild。
- memoize（若生效）只在 `messages` 不变时省，流式期 `messages` 每 token 变 → 必 miss → 流式期不省。
- 单次 rebuild 里 `appendThinkingDelta`/`appendTextDelta` 的 `List.from` + `state.copyWith`、`groupMessagesForUi` 重算、尾部气泡重绘，构成「瞬时 CPU 高」。

即 #2 解决了「持续的 paint 烧 CPU」，未解决「per-token 触发的瞬时 rebuild」。后者是 P0 的目标。

## 目标

1. 在同一「执行过程」+ 文本流式场景下，Debug build CPU 进一步下降；从 per-token rebuild 降到 per-message rebuild。
2. `parseStreamingJson` 不再出现在 hot window 主要 app frame（依赖 Phase 1，未做）。
3. text/thinking 流式期间 `messages` 不再每 token 变化。
4. `NovelEditorPage` / `LeftSidebar` 不因 chat stream 高频 rebuild（Phase 5 未做，仍是隐患）。
5. 工具调用执行语义不变：final tool call 只执行一次，使用完整 final arguments；partial event 只服务 UI 展示。

### 非目标

1. 不重设计 chat panel 视觉样式。
2. 不替换全局 icon / SVG 系统。
3. 不改数据库结构、历史会话持久化格式或公开 event model。
4. 不一次性解决所有启动和编辑器性能问题。
5. 不引入新的运行时依赖或后台 isolate 作为第一版方案。
6. 不新增用户可见功能。
7. 不改变公开事件模型。

## 核心原则

1. final tool call 是唯一执行依据，partial tool call 只用于 UI 展示。
2. partial 更新必须节流、去重，且只在 UI 可见信息变化时写 session state。
3. 不用截图判断性能问题；每次优化后用同一 profile 流程复测。
4. 先减少事件数量，再优化单次 build 成本。
5. 不为性能引入静默兜底；解析失败必须保持当前错误可见策略。
6. 不新增产品能力。

## 待做（按优先级）

### P0：用户明确想做的两件事

#### P0-①：memoize `groupMessagesForUi`

已写在工作树（`panel.dart:277` `useMemoized(() => groupMessagesForUi(messages), [messages])`），未测试、未提交。

效果边界（必须说清）：只在 `messages` identity 不变时省——即非 token 来源的 rebuild（runtimeState / sessionState / onboarding / composer 高度等）。**流式期 `messages` 每 token 换 identity，memoize 每 token miss，流式期不省**。所以它单独不能解决 per-token rebuild，必须配合 P0-② 才有意义：解耦后 `messages` 在流式期不变，memoize 才会命中。

即：P0-① 和 P0-② 互为前提——单独做任一个，流式期都不省；合在一起才有收益。

#### P0-②：thinking/text 独立渲染（解耦 — 完成才写 messages）

当前 `appendTextDelta` / `appendThinkingDelta`（`ai_providers.dart:462/490`）每个 token 都 `state = state.copyWith(messages: ...)`，是 per-token rebuild 的直接来源。`ChatTurnRunner` 已有 `AgentTextComplete` 携带完整最终文本（`chat_turn_runner.dart:1626`），天然是 flush 边界。

设计：

- `AgentTextDelta` / `AgentThinkingDelta` → 写进**流式 buffer**（轻量 `ValueNotifier` 或挂在 `AiChatRuntime` 上的小 state），**不碰 `messages`**。
- `AgentTextComplete` / 消息结束 → 把完整文本一次性写进 `messages`（一次落库级写入）。
- panel 的 `messages` watch 在纯文本流式期**完全不触发**；只有尾部气泡 widget watch buffer，局部 rebuild。
- 配合 P0-①：`messages` 不再每 token 变，memoize 命中。

两个范围（择一先做）：

- **范围 1（推荐）**：只解耦 text/thinking。tool call / askUser 仍走 `messages`（tool 依赖 Phase 1 节流，askUser 低频）。
- **范围 2**：连 tool call / askUser 搬进 buffer。最彻底，但 askUser 必须即时可见可交互，风险大。

风险点：

1. **崩溃恢复不回归**：per-token 写 `state` 本就不落库（落库只在 `persistCompletedMessagesFromAgentEvent` 消息边界），解耦不丢已有恢复能力——已确认。
2. **尾部渲染契约变了**：尾部 UIMessage 当前从 `messages` 来；解耦后尾部气泡要从 buffer 合成，需动 `chat_message_view` 渲染入口，是本次最易回归处。
3. thinking 默认折叠，渲染最简单——若想先做最小子步，可只解耦 thinking。

### P1：Phase 1 tool partial 节流（未做）

`parseStreamingJson` 仍每 fragment 在 client 调用（postfix first-app-frame 10 samples）。wip commit `7aa5286a` 曾实现 `tool_call_partial_throttle.dart`（500ms 节流 + final-only 准确解析 + 去重），但未合入 development。需要重新接入 `openai_client.dart` / `openai_responses_client.dart` / `anthropic_client.dart`，并补回 `tool_call_partial_throttle_test.dart`。

### P1：Phase 2 `upsertToolCallBlock` no-op dedupe（未做）

`ai_providers.dart:537` 每次调用都写 state。应先比较 UI 可见字段（`toolCallId` / `toolName` / `status` / `arguments` / `result` / `error` / `targetPath` / diff 字段），等价则 return。用 cheap compare / stable hash，不用深扫大 map；终态（success/failed/cancelled）不能被吞。

### P2：Phase 5 `aiModeProcessingTrackerProvider` 下沉 bridge（未做）

`novel_editor.dart:3561` 仍在页面根 `ref.watch(aiModeProcessingTrackerProvider)`。Phase 7 断环后它不再是高频推手，但仍是「chat 运行状态 → 整页 rebuild」的边界隐患。下沉到不可见 bridge widget，`PopScope.canPop` 继续用 `isModeRunning`。

### P2：Phase 8 状态栏全文计算缓存（未做）

`_ChapterStatusMetrics`（`StatelessWidget`）、`_StatusBarAutoFormatButton`（`ConsumerWidget`）无缓存，整页 rebuild 时重跑 `countTextUnitStats`（7 正则全文 pass）、`formatChapterBody`（全文逐行 format 再 `==`）。改 StatefulWidget 缓存 `(text → 结果)`，builder 内先 `identical` 再 `==` 命中即复用。Phase 7 断环后它不再是主因，但仍是任何整页 rebuild 的放大器。

### P3：Phase 3-②③④（未做）

panel 内会随 streaming 高频变化但不影响当前 build 分支的 watch 下沉到局部 `Consumer`；工具 activity group 用稳定 key；仅在复测仍显示 SVG/icon build 成本高时做 repaint 隔离。

### P3：Phase 4 partial JSON parser（未做）

`_partial_json.dart` regex trimming 改线性扫描减少 `RegExp_ExecuteMatch`；明显不完整片段走轻量 partial close。test-first，不能破坏 Anthropic / Responses 的 tolerant partial 行为。

## 测试计划

### 单元测试

- `test/agent/client/partial_json_test.dart`（Phase 1/4）
- `test/agent/client/tool_call_partial_throttle_test.dart`（Phase 1，需补回）
- `test/agent/client/openai_client_test.dart` / `openai_responses_client_test.dart` / `anthropic_client_test.dart`
- `test/shared/providers/ai_providers_test.dart`（Phase 2 dedupe + P0-② 解耦后 final 文本完整）
- `test/shared/widgets/ai/chat/auto_scroll_hook_test.dart`（已含 #2 的 streaming-follow 测试）
- `test/shared/widgets/ai/chat/ui_message_grouping_test.dart`（memoize 不改分组规则，已过；若改 `groupMessagesForUi` 入参契约需扩展）

P0-② 解耦必须覆盖：长文本拆成大量 token delta 时 `messages` 写入次数 = 1（完成时）；final 文本完整；崩溃 / 取消时 buffer 不丢展示。

### 性能复测

用 `.agents/skills/profile/SKILL.md` 流程：复现 CPU 高窗口 → 8s `getCpuSamples` + native sample → 5s build timeline → 与 baseline 对比 first app frame 和 widget build count。

注意：采 `getCpuSamples` 时 profiler 自身会占主线程（`ProfilerService::PrintJSON` / `dladdr`），native sample 会偏高；以 Dart first-app-frame 相对排序为主要判据，绝对 CPU 数值供参考。

## 风险与妥协

| 风险 | 影响 | 应对 |
|------|------|------|
| P0 解耦后尾部气泡从 buffer 合成 | 渲染入口变更，最易回归 | 先只解耦 thinking（折叠态最简单）验证，再推 text |
| P0 取消 / 崩溃时 buffer 未 flush | 尾部文本丢展示 | 取消路径显式 flush buffer |
| partial 节流后工具 arguments 不再逐字刷新 | UI live 感略弱 | 500ms 周期更新，名称 / running 立即显示 |
| provider 间 stream 格式不同 | final / partial 语义不一致 | 每个 client 单独测试，final event 作统一执行边界 |
| deep equality 消耗 CPU | Phase 2 dedupe 抵消收益 | cheap compare / stable hash |
| Debug ≠ Release | CPU 数字不代表用户机器 | 用相对下降和热点变化作主标准 |

## 回滚策略

- #2：独立可回滚（auto_scroll guard）。
- P0-① memoize：独立可回滚，但单独回滚后非-token rebuild 会恢复冗余分组。
- P0-② 解耦：若尾部渲染回归，回退到 per-token 写 `messages`，保留 buffer 仅作调试。
- P0 解耦：若尾部渲染回归，回退到 per-token 写 `messages`，保留 buffer 仅作调试。
- Phase 1/2：独立保留或回滚。

本方案不要求 DB migration，不改变历史数据格式，也不改变公开 event model。

## 验收清单

- [x] Phase 6 编辑区 repaint 边界
- [x] Phase 7 onEditingStateChanged 闭包环断开
- [x] #2 流式 jumpTo no-op guard
- [ ] P0-① memoize `groupMessagesForUi`（已写未测，待测试后确认）
- [ ] P0-② thinking/text 独立渲染（完成才写 messages）
- [ ] Phase 1 tool partial 节流 / 去重
- [ ] Phase 2 `upsertToolCallBlock` no-op dedupe
- [ ] Phase 5 `aiModeProcessingTrackerProvider` 下沉 bridge
- [ ] Phase 8 状态栏全文计算缓存
- [ ] Phase 3-②③④ / Phase 4
- [ ] 同一复现场景 CPU 明显下降（per-token → per-message rebuild）
- [ ] profile artifacts 与复测 artifacts 可追溯
