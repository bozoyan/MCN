# Chat 下一步建议（Next Action Recommendation）

> 档位：完整档（新增 AI 工具、跨 desktop / mobile / shared、含 AI 行为评测）。

## 1. 背景

### 现状

1. **空态只会填 prompt。** `lib/desktop/widgets/ai/chat/empty_state.dart` 的 `AssistantQuickAction` 只有一个 `prompt` 字段，点击即填入输入框并发送。`panel.dart:82 _buildOrchestratorQuickActions()` 硬编码 3 条固定文案（规划今天 / 梳理一致性 / 写下一章），与当前小说状态无关。
2. **对话过程中没有任何推荐。** 一轮回合结束后，composer 上方只有 queued message、notice、reference chip，没有「下一步可以做什么」的出口。
3. **五个 AI 模式互不引流。** `council` / `monologue` / `theater` / `roleplay` 只能从 desktop rail 或 mobile 模式切换条进入。反向 handoff 已经打通（`onDraftHandoffToWriteMode` → `AiChatHandoffDraft`），**正向从 chat 跳到其他模式的通道完全不存在**。
4. **封面工作台没有推荐入口。** desktop 走 rail / `novel_overview.dart` 的 `onOpenCoverStudio`；mobile 无独立页面，`novel_editor_page.dart:1072` 用一条 handoff prompt 让 chat 里的 AI 出图。两端都要用户自己想起来去点。
5. **已经有一整套推荐系统，但是死代码。** `lib/shared/models/feature_id.dart`（28 个 `FeatureId`）、`lib/shared/heuristic/feature_metadata.dart`、`lib/desktop/widgets/heuristic/discovery_banner.dart`、`scene_heuristic_banner.dart`、`assets/translations/*/heuristic.json`（含全部 feature 名称与描述）全部存在，**没有任何地方挂载**。`scene_heuristic_banner.dart` 文件头引用的 `lib/shared/heuristic/scene_registry.dart` 根本不存在。
6. **初始化引导已有门控。** `SetupPhaseGate.shouldShow()`（无 agent rules + `novel_onboarding=eligible` + chat 会话数 ≤ 3）决定是否注入 `{{#setup_phase}}` 段，由 `assets/bundled_skills/setup/SKILL.md`（创作向导）接管书名 / 分类 / 标签 / 简介与基础规则。**创作向导写完元数据后没有任何后续动作建议。**
7. **`FeatureUsages` 表已存在**（`app_database.dart:984`，主键 `featureId`），仅由 `triggerFeatureOnboardingIfNeeded()` 记录首次引导状态，key 带 `feature_onboarding.` 前缀，不记录建议点击。

### 可复用的工具基建（决定本方案形态）

`AskUser` 已经把「工具驱动的交互式 UI」完整跑通，`SuggestNextAction` 沿用同一条链路，不是新基建：

| 环节 | AskUser 现状 | 位置 |
|------|-------------|------|
| 目录声明 | `AiToolDefinition(name:'AskUser', group: askUser, subAgentConfigurable: false)` | `tools.dart:798` |
| 条件注册 | `if (askUserCallback != null) _registerDispatch('AskUser', ...)` | `tools.dart:1209` |
| Schema 下发 | `ToolDef(name:'AskUser', description:_askUserDescription, inputSchema:_askUserInputSchema)` | `tools.dart:1519` |
| 模式门控 | `if (!mode.canUseTool('AskUser')) return _modeDeniedResult(...)` | `tools.dart:1379` |
| 发块进消息流 | `sessionNotifier.addAskUserBlock(AiAskUserBlock(...))` | `chat_turn_runner.dart:470` |
| **抑制默认工具卡** | `if (block.toolName == 'AskUser') { ... }` 跳过 tool call block | `chat_message_view.dart:476` |
| 交互渲染 | `AskUserCard`（`label` / `description` / `recommended` 选项结构） | `shared/widgets/ai/tools/ask_user_card.dart` |

设置侧同样有现成落点：`AiAgentSettingsData`（`app_settings_aggregate_data.dart:393`）是版本化 JSON 聚合，加字段走 `fallback` 解码；`AiAgentsSettingsSection` 是双端共享的 AI 助手设置区。

### 问题

```text
问题 A：新用户不知道圆桌 / 小剧场存在
- 症状：用户在 chat 里反复问「这段该怎么写」，AI 只能在单线程对话里给一个视角；
        圆桌（多专家讨论）和小剧场（多角色演一遍）从未被打开。
- 根因：这两个功能只有 rail / 切换条入口，chat 内部零引流；空态 3 条推荐全是 chat 内动作。
- 影响：多模式产品被当成单一聊天框用，功能价值不可见。
```

```text
问题 B：一轮回合结束后是死胡同
- 症状：AI 回复完，输入框空着，用户自己想下一句说什么。
- 根因：没有 next action 承接位；AskUser 是阻塞式决策工具，语义上不是「推荐」。
- 影响：会话中断率高；写作流程「讨论 → 演绎 → 落笔 → 核对」断在每一步之间。
```

```text
问题 C：创作向导跑完就断了
- 症状：书名、分类、简介刚确认完，作品有了完整身份，但没有封面，也没人提。
- 根因：模型上下文里根本没有「有没有封面」这条事实，无从建议。
- 影响：书架上一排无封面作品；封面工作台（desktop 刚 rework 完）冷启动。
```

### 约束

- 不改 Drift schema，不记录建议点击；开关落在 `AiAgentSettingsData` 的 JSON 聚合里，两处都不动 `schemaVersion`。
- **工具描述必须保持契约级别**（`AGENTS.md` 第 10 条）：`description` 只写参数、边界、返回值；「什么时候该调用」写进 `orchestrator.md`。
- `AiSessionMode.canUseTool()` 限制非 chat 模式（`_specialModeTools` 只有 6 个只读工具），新工具天然只在 `chat` 可用。
- SubAgent 不得调用（同 `AskUser` 的 `subAgentConfigurable: false`），否则正文写手会在委派中途给用户推导航。
- desktop 与 mobile 的模式导航机制完全不同（`_EditorContentSelection` sealed class vs `pushReplacementMobileAiModePage`），封面能力两端也不对等（mobile 无 `CoverStudio` 页面）。
- 模型产出的 chip 文案是**运行时内容，不参与 i18n**；只有壳文案与空态文案走 locale key（`.agents/rules/i18n.md`）。
- Flutter 测试串行执行。

## 2. 目标

### 目标

1. 新增 `SuggestNextAction` 工具：模型可在一轮收尾挂 ≤3 条建议，类型覆盖「下一句提示词」与「跳到圆桌 / 小剧场 / 封面工作台」。
2. **模型没挂建议就什么都不显示。** 不做本地兜底、不补模板建议、建议条不占高度。
3. chat 空会话时（尚无任何模型调用，无从产生建议）由本地固定目录产出引导卡片，其中含「去圆桌讨论剧情」与「去小剧场演一遍」两个跨模式入口。
4. 把「当前作品尚无封面」作为一行事实注入 chat 上下文，让模型自己挑时机建议封面；客户端负责判定图像模型是否已配置。
5. 模型建议的目标经客户端白名单裁决；不可达的静默丢弃并记日志，不回传模型。
6. 用户可在 `AiAgentsSettingsSection` 一键关闭建议功能，双端生效，跨会话持久。
7. 复活 `FeatureId` / `featureMetadata` / `heuristic.json` 死代码作为白名单与展示目录的真相源。

### 非目标

1. **不做本地兜底建议。** 模型不调、工具被关、建议全被丢弃时，建议条就是空的，这是明确接受的行为。
2. 不把建议合并进 `AskUser`（理由见 4.1）。
3. 不做完整 handoff 上下文迁移；跳转只带模型给的一行 seed（见第 10 节妥协 1）。
4. 不做单条建议的永久关闭。建议随下一轮自然消失，只保留全局开关。
5. 不挂载 `DiscoveryBanner` / `SceneHeuristicBanner`（首页与编辑器顶部横幅，另一个投放位）。
6. 不改 `setup/SKILL.md`。封面靠上下文事实 + 模型判断，不塞进创作向导职责。
7. 不做 monologue / roleplay 引流（白名单预留，第一版不放开）。

### 成功信号

| 信号 | 验证方式 |
|------|----------|
| 模型调用后 chip 条渲染，默认工具卡被抑制 | widget 测试 |
| **模型未调用 → 建议条不渲染，不占高度** | widget 测试（核心负例） |
| 空会话卡片含 council + theater | 空态目录单测 |
| `imageModelReady=false` 时封面建议被丢弃 | 工具单测 |
| 无封面且元数据齐备时，上下文含「封面：尚未设置」 | prompt 单测 |
| 有封面时该行不注入 | prompt 单测（负例） |
| `onOpenFeature == null` → `ToolDef` 列表不含该工具 | 工具单测 |
| `defaultSubAgentToolNames()` 不含该工具 | 单测 |
| 设置里关闭后，工具不下发且空态卡片不出现 | 单测 + 手动 |
| 点击 council 建议后 desktop 进圆桌且议题框预填 | widget 测试 + 手动 |

## 3. User Stories

1. 作为新用户，我希望第一次打开 AI 面板就看到「和多位专家讨论剧情」和「不知道怎么写？先演一遍」，以便知道圆桌和小剧场存在。
2. 作为作者，我希望聊完一轮后 AI 告诉我「这段分歧适合去圆桌」而不是模板套话，以便建议真的贴合刚才聊的内容。
3. 作为作者，我希望**没什么可建议的时候界面就是干净的**，以便建议出现时它是有意义的信号而不是常驻装饰。
4. 作为刚跑完创作向导的作者，我希望 AI 在合适的时候提醒我做封面，以便作品在书架上有完整身份。
5. 作为没配图像模型的用户，我希望不被推荐封面工作台，以便不点进去撞一堵墙。
6. 作为老用户，我希望在设置里一次关掉建议功能。
7. 作为维护者，我希望模型给的建议落地前先过白名单，以便幻觉出的功能名不会变成点了会崩的按钮。

## 4. 解决方案

### 4.1 方案对比

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|------|------|------|------|------|
| A：回复正文追加结构块 | prompt 要求回复末尾输出 `<next-actions>`，客户端解析剥离 | 无需新工具 | 与「输出纪律」冲突；stream 中途渲染出半截标签，需增量剥离；格式易漂移 | 放弃 |
| B：额外一次小模型调用 | 回合结束后用低档模型生成建议 | 与主回复解耦 | 每轮 +1 次调用；有延迟，建议「后知后觉」闪出；未配置 provider 时静默失效 | 放弃 |
| C：纯本地规则引擎 | 纯函数按结构信号选建议 | 零 token、可单测 | 文案是模板不贴合；「在聊剧情」只能用「连续 N 轮无写入」代理，误判率不可控；且必然产出建议，与「没建议不强求」冲突 | 放弃（仅空态保留固定目录） |
| D：升级 `AskUser` 支持建议 | 给 `AskUser` 加 `blocking:false` 或 `kind:suggest` | 少一个工具、少一份 schema；选项结构与卡片现成 | **生命周期不兼容**（详见下） | 放弃 |
| **E：独立 `SuggestNextAction` 工具** | 模型主导挂建议，客户端白名单裁决；无建议不显示 | 阻塞语义无歧义；复用 AskUser 已验证链路与选项 UI；可被用户关闭 | token 不再零增量；调用时机不确定，需 prompt 约束 + 评测 | **推荐** |

**为什么不升级 `AskUser`（方案 D）**：两者生命周期相反，不是 schema 能调和的。

- `_askUser`（`chat_turn_runner.dart:453`）**无条件**建 `Completer`、注册进 `pendingAskUserRequests[callId]`、然后 `await`。整个 turn 挂在那里等人。
- 状态机 `AiAskUserStatus {pending, answered, cancelled, error}` 就是照「等一个人类」设计的。
- 建议必须在 turn **结束之后**出现，绝不能挂起 turn，且「用户没点」是正常终态而非 `cancelled`。

合并意味着让模型用一个布尔值决定**这一轮要不要阻塞**。往建议方向判错，turn 挂死在一排用户以为可以无视的 chip 上；往提问方向判错，模型拿不到答案就往下走。这个失败在 schema 里看不出来，只在运行时炸。

**该复用的复用**：选项结构（`label` / `description` / `recommended`）与 `AskUserCard` 的选项渲染抽出共用 —— 共享模型与 UI，不共享工具名。

### 4.2 决策

推荐 **方案 E：独立 `SuggestNextAction` 工具，模型主导，无兜底**。

选择理由：

1. **tool call 是带外的。** 不经过正文 stream，不违反 `orchestrator.md` 的「输出纪律」；`AskUser` 已证明这条链路可用，包括抑制默认工具卡改渲染交互 UI。
2. **模型解决了本地规则解不了的判断。** 「这轮是在聊剧情还是在改设定」「这段分歧值不值得开圆桌」「刚写完这章下一句该问什么」——这些依赖对话内容，客户端只能拿代理信号硬猜。
3. **没有建议就不显示，是特性不是缺陷。** 常驻的模板建议是噪音；只有当模型确实判断出下一步有价值时才出现，chip 条本身才成为有效信号。这同时砍掉了整个兜底层、`turnsSinceLastWrite` 计数、以及一批模板 i18n key。
4. **封面靠事实而非规则。** 客户端只负责把「尚无封面」这条事实喂进上下文（一行、条件注入），由模型挑时机 —— 比客户端在某个任意轮次弹出封面建议合理得多。
5. **裁决成本极低。** 目标是 3 值枚举白名单，`tools_enum_validation.dart` 的模式直接复用。

拒绝方案：见 4.1 表格与 D 的专门说明。

### 4.3 核心原则

1. **模型提议，客户端裁决。** 模型只能从白名单枚举选目标；可达性（功能是否存在、图像模型是否配置、宿主是否提供导航）一律客户端判定。
2. **没有建议就不显示。** 不补兜底、不占高度、不留占位。
3. **返回值最小化。** 工具在回合收尾被调用，模型不会对返回值做任何反应；`{"ok": true}` 即可。丢弃项记日志，不回传模型（详见 5.1）。
4. **建议照常进模型上下文。** tool_use / tool_result 与其他工具一视同仁地保留；只有裁决后的 `AiSuggestNextActionBlock` 不进上下文（它是 UI 投影，内容与 tool_use 重复）。

   > **修订（原则反转）**：初版是「成对剥离，避免为无人阅读的文本长期付费」。实现后发现剥离只在**从消息重建历史**时生效 —— 活着的 agent 实例被 `runtime.agent` 缓存复用，其 ContextManager 里原样留着 tool_use / tool_result。结果是同一会话重启前后模型对「自己挂过什么建议」的记忆不一致，且重建路径下模型会重复挂同一组建议。代价（每次约 300–400 字符的 args）换模型不重复建议，划算。
5. **工具描述只写契约。** 调用时机写进 `orchestrator.md` 场景指引。
6. **非阻塞。** handler 必须同步返回，**不能**照抄 `AskUser` 的 Completer —— 否则整个 turn 卡死。
7. **目录只有一份。** 目标一律用 `FeatureId`，展示名复用 `featureMetadata` + `heuristic.json`。

### 4.4 关键假设

| 假设 | 如果不成立 | 应对 |
|------|------------|------|
| 模型被 prompt 指引后会在合适时机调用 | 从不调用 → 建议条长期为空；每轮都调 → 打扰 | 评测（§7）量化调用率与恰当率；「从不调用」是可接受降级，不是 bug |
| 3 值白名单（council / theater / cover_studio）够用 | 模型想推 monologue / roleplay | schema 枚举拦截 + 裁决器二次校验；需要时扩枚举 |
| 「尚无封面」一行事实足以让模型在合适时机建议封面 | 模型忽略它，或每轮都推 | 评测场景覆盖；`orchestrator.md` 写明「一轮最多一次、被拒后不重复」 |
| 工具定义稳定 → 可被 provider prompt cache 覆盖 | 无缓存，每请求全额计费 | 定义位于请求前部且内容固定；成本上界见 §8 |
| council 的 `topicController` / theater 的 `sceneController` 可外部预填 | 控制器是私有 hook | 二者均为 `useTextEditingController()`，加入参即可 |
| ~~tool_use / tool_result 可成对剥离~~ | 已废弃：剥离只在重建历史时生效，与活着的 agent 上下文不一致 | 改为不剥离（见 4.3 原则 4 修订） |

## 5. 方案实施

### 5.1 工具契约

```text
SuggestNextAction
  group: AiToolGroup.suggestion (新增)
  agentConfigurable: true
  subAgentConfigurable: false          // 同 AskUser
  条件注册: suggestNextActionCallback != null && 用户未在设置里关闭
  模式门控: canUseTool() → 仅 chat
```

入参 schema：

```json
{
  "type": "object",
  "properties": {
    "suggestions": {
      "type": "array",
      "maxItems": 3,
      "items": {
        "type": "object",
        "properties": {
          "kind":    { "enum": ["prompt", "feature"] },
          "label":   { "type": "string" },
          "prompt":  { "type": "string" },
          "feature": { "enum": ["ai_council", "ai_theater", "ai_cover_studio"] },
          "seed":    { "type": "string" }
        },
        "required": ["kind", "label"]
      }
    }
  },
  "required": ["suggestions"]
}
```

- `kind=prompt` → `prompt` 必填，点击后填入 composer（**不自动发送**，用户可改）。
- `kind=feature` → `feature` 必填，`seed` 可选（预填圆桌议题 / 小剧场场景）。

**返回值：`{"ok": true}`。**

这是个刻意的最小化决定。工具在回合收尾被调用，模型拿到结果后就结束这一轮，不会对 `accepted` / `dropped` 做任何反应；把裁决详情塞回去，等于让一段永远无人阅读的文本常驻 history 并每轮收费。因此：

- 非法项（枚举外的 `feature`、缺 `prompt`、超过 3 条）**丢弃并写 warn 日志**，不回传模型。
- 环境约束不靠事后告知，靠**事前给事实**：没配图像模型时 `ai_cover_studio` 不进 schema 枚举；没封面时上下文里才有「封面：尚未设置」那行。模型在被约束的选项集里选，而不是选错了再被纠正。
- 全部被丢弃时同样返回 `{"ok": true}`，建议条为空 —— 符合「没有建议就不显示」。

工具 `description`（契约级，不含调用时机）：

```text
向用户挂载最多 3 条可点击的下一步建议，展示在输入框上方，用户可点可忽略。
本工具立即返回，不等待用户操作，不阻塞当前回合。

参数：
- suggestions：建议数组，最多 3 条。
  - kind：prompt 表示点击后把 prompt 填入输入框；feature 表示点击后跳转到指定功能。
  - label：按钮文案，一行内说清用户点了会发生什么。
  - prompt：kind=prompt 时必填。
  - feature：kind=feature 时必填，取值见 schema 枚举。
  - seed：kind=feature 时可选，作为目标功能输入框的预填文本。
```

### 5.2 orchestrator.md 场景指引（调用时机）

在「场景指引」下新增一节（与既有 `## 咨询与讨论`、`## 正文写作` 同级）：

```markdown
## 下一步建议

一轮工作收尾、且用户下一步存在多个合理走向时，用 SuggestNextAction 挂建议。
没有值得推荐的下一步时不要调用——空着比凑数好。

- 讨论出现实质分歧、需要多个视角权衡时，建议去圆桌，并把分歧写进 seed。
- 用户反复讨论同一场戏但迟迟没有落笔时，建议去小剧场先演一遍，并把场景写进 seed。
- 刚完成正文写入时，建议下一步的具体提示词（本章要核对什么、下一章从哪起笔），
  不要给「继续写吧」这类无信息量的建议。
- 当前作品显示尚未设置封面、且书名与简介已确认时，可以建议去封面工作台，一次为限。
- 多步任务执行途中不要挂建议；一轮最多一次；用户已明确拒绝过的方向不要重复。
- 建议是可选出口，不是提问。需要用户决策才能继续时用 AskUser，不要用本工具替代。
```

### 5.3 模型设计

```text
ChatNextAction                    // 统一展示模型（模型产出与空态目录共用）
- id: String
- feature: FeatureId?             // 跳转类指向的功能；提示词类为 null
- label: String                   // 模型给的运行时文案，或空态 locale key 求值结果
- subtitle: String?
- target: ChatNextActionTarget

ChatNextActionTarget (sealed)
├─ PromptActionTarget   { prompt: String }
└─ FeatureActionTarget  { feature: FeatureId, seedText: String? }

ChatNextActionEnvironment         // 裁决与空态共用的环境事实（很小）
- imageModelReady: bool
- coverStudioAvailable: bool
- suggestionsEnabled: bool
- hasCover / metadataReady / setupDone    // 仅空态与上下文事实注入使用
```

新增消息块（与 `AiAskUserBlock` 平行）：

```text
AiSuggestNextActionBlock
- id / callId
- suggestions: List<Map>          // 已裁决结果，用于会话恢复时重放
```

**没有** `turnsSinceLastWrite` / `wroteInLastTurn` —— 兜底层取消后这些信号无人使用，连带消除了「切会话时计数漂移」这个风险。

**没有**单条 dismissal 持久化 —— 建议随下一轮自然消失，只保留全局开关。

读取端是 `latestSuggestNextActionBlock`（`lib/shared/heuristic/chat_next_action.dart`），desktop / mobile 共用一份。扫描边界是**最后一条 user 消息**，不是最后一条 assistant 消息：一次 agent 回合会按 round 拆成多条 assistant 消息（挂建议的工具轮一条、收尾正文又一条），只看末条会漏掉挂在前一 round 的建议 —— 而模型调完工具再说一句收尾话恰恰是最常见的形态。停在 user 消息处，「下一轮自然消失」的语义同时也就保住了。

点击 `FeatureActionTarget` 直接执行功能跳转，不写入使用统计。`FeatureUsages` 仅用于首次引导状态。

### 5.4 空态固定目录

空会话时尚无任何模型调用，建议只能来自客户端。这是唯一保留的本地逻辑，且是**固定目录 + 简单可用性过滤**，不是规则引擎：

| 顺序 | id | 展示条件 | 目标 |
|------|-----|----------|------|
| 1 | `plan_today` | 总是 | 提示词：规划今天的工作（沿用 `ai.agent_quick_orchestrator_plan_today*`） |
| 2 | `goto_council` | 总是 | `FeatureActionTarget(ai_council)` |
| 3 | `goto_theater` | 总是 | `FeatureActionTarget(ai_theater)` |
| 4 | `goto_cover_studio` | `!hasCover && metadataReady && setupDone && imageModelReady && coverStudioAvailable` | `FeatureActionTarget(ai_cover_studio)` |

`suggestionsEnabled == false` 时整个空态推荐区不渲染，只留欢迎语。

### 5.5 关键业务流程

**流程 1：模型主导（happy path）**

```text
1. 模型在回合收尾调用 SuggestNextAction(suggestions:[...])
2. _handleSuggestNextAction:
   a. 逐条校验 kind / 必填字段 / feature 枚举 → 非法项 drop + warn 日志
   b. feature 类查环境：ai_cover_studio 且 !imageModelReady → drop
      （正常情况下不会发生：不满足时该值不进 schema 枚举）
   c. 超过 3 条 → 截断
   d. addSuggestNextActionBlock(裁决后结果)     // 同步，不 await
   e. return {"ok": true}
3. chat_message_view 抑制该工具的默认 tool call 卡（同 AskUser 476 行处理）
4. panel 取会话末尾 AiSuggestNextActionBlock，渲染 NextActionBar
5. 用户点击
   ├─ PromptActionTarget  → 填入 composer（不自动发送）
   └─ FeatureActionTarget → onOpenFeature(feature, seedText)
```

**流程 2：无建议（明确接受的路径）**

```text
模型未调用 / 工具未注册 / 用户关闭 / 全部被丢弃
  → 会话末尾无有效 AiSuggestNextActionBlock
  → NextActionBar 返回 SizedBox.shrink()，不占高度，不留占位
```

`cancelled` / `failed` 的回合同样不渲染建议条。

**流程 3：空会话**

```text
无消息 → 空态固定目录（5.4）→ AssistantEmptyState 卡片
```

**流程 4：封面事实注入**

```text
ChatPromptUseCase._buildNovelMetadata(novel):
  现有：标题 / 作者名 / type / 分类 / 标签
  新增（仅当 novel.coverPath == null 且 metadataReady）：
    - 封面：尚未设置
  有封面时不注入该行（避免每轮都提醒模型有个封面）
```

**流程 5：跳转（desktop）**

```text
onOpenFeature(FeatureId.ai_council, seedText)
  → contentSelection.value = _EditorAgentCouncilSelection(initialTopic: seedText)
  → _buildAgentModeArea → AgentCouncilPanel(initialTopic:)
  → topicController 初值 = initialTopic
```

**流程 6：跳转（mobile）**

```text
council / theater → pushReplacementMobileAiModePage(mode, seedText)
ai_cover_studio   → 复用 novel_editor_page.dart:1072 的 cover handoff prompt
```

### 5.6 改动清单

#### NEW: `lib/shared/services/ai/tools_suggest_next_action.dart`

```dart
// 职责: SuggestNextAction 工具实现 — 校验模型建议、裁决可达性并挂载到会话
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/models/ai_message_block.dart
//   lib/shared/heuristic/chat_next_action.dart
//   lib/shared/services/ai/chat_turn_runner.dart
```

- `part of 'tools.dart';`，`mixin _AiToolManagerSuggestNextActionMixin on _AiToolManagerBase`。
- `_suggestNextActionInputSchema`（`feature` 枚举按环境动态裁剪）/ `_suggestNextActionDescription`（契约级）。
- `_handleSuggestNextAction()`：校验 → 裁决 → 调 callback → `return {'ok': true}`。**同步返回，不建 Completer。**

#### `lib/shared/services/ai/tools.dart`

- `enum AiToolGroup` 新增 `suggestion`（第 747–762 行）。
- `aiToolCatalog` 新增 `AiToolDefinition(name:'SuggestNextAction', group: AiToolGroup.suggestion, subAgentConfigurable: false)`。
- 新增字段 `void Function(List<Map<String,dynamic>>)? suggestNextActionCallback;`（返回 void —— 不需要回传条数）。
- `_registerDispatch` 与 `ToolDef` 均照 `AskUser` / `skillLoader` 的条件模式，`callback == null` 时既不注册也不下发。
- mixin 挂到 `AiToolManager` 的 `with` 列表。

#### `lib/shared/models/ai_message_block.dart`

- 新增 `AiSuggestNextActionBlock`（`@JsonSerializable`，字段 `id` / `callId` / `suggestions`），在 `fromJson` 分发处（第 29 行附近）注册 type。需跑 `make codegen`。

#### `lib/shared/services/ai/chat_turn_runner.dart`

- 注入 `toolManager.suggestNextActionCallback`：调 `sessionNotifier.addSuggestNextActionBlock(...)`。与 `_askUser`（第 453 行）平行，但**不建 Completer、不 await**。

#### `lib/shared/services/ai/agent_message_mapping.dart` / `ai_chat_service.dart`

- `case AiSuggestNextActionBlock():` → skip。它是裁决后的 UI 投影，内容与 tool_use 的 `arguments` 重复，进上下文等于同一份建议发两遍。
- `SuggestNextAction` 的 tool_use / tool_result **不做特殊处理**，与其他工具走同一条转换路径（见 4.3 原则 4 修订）。单测固化「成对保留、无孤儿」。

#### `lib/shared/services/ai/prompts/use_cases/chat_prompt_use_case.dart`

- `_buildNovelMetadata()`（第 251 行）：`novel.coverPath == null` 且书名非占位、简介非空时追加 `- 封面：尚未设置`；否则不注入。

#### `assets/prompts/agent/orchestrator.md`

- 「场景指引」下新增 `## 下一步建议`（见 5.2）。

#### NEW: `lib/shared/heuristic/chat_next_action.dart`

```dart
// 职责: Chat 下一步建议的数据模型、白名单裁决与空态固定目录
// 关联文件:
//   lib/shared/models/feature_id.dart
//   lib/shared/heuristic/feature_metadata.dart
//   lib/shared/services/ai/tools_suggest_next_action.dart
//   lib/shared/widgets/ai/chat/next_action_bar.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/heuristic.json
//   assets/translations/zh-CN/heuristic.json
```

- `ChatNextAction` / `ChatNextActionTarget` / `ChatNextActionEnvironment`。
- `ChatNextActionArbiter.judge(raw, env)`：白名单 + 可达性裁决，工具层与 UI 层共用同一份逻辑。
- `emptyStateActions(env)`：5.4 固定目录。纯函数、无 IO、无 Flutter 依赖。

#### NEW: `lib/shared/widgets/ai/chat/next_action_bar.dart`

```dart
// 职责: 下一步建议条 — 有建议时渲染 chip 行，无建议时不占空间
// 关联文件:
//   lib/shared/heuristic/chat_next_action.dart
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/heuristic.json
//   assets/translations/zh-CN/heuristic.json
```

- `actions.isEmpty` → `SizedBox.shrink()`（第一行就返回，验收硬要求）。
- 横向可滚动 chip；跳转类用 `featureMetadata` 图标，提示词类用 `lightbulb_outline`。
- **无 `⋯` 菜单** —— 关闭入口在设置里。

#### MOVE: `lib/desktop/widgets/ai/chat/empty_state.dart` → `lib/shared/widgets/ai/chat/assistant_empty_state.dart`

- 双端复用（mobile 当前只有一行 `mobileChatEmptyConversation`）。
- `AssistantQuickAction` 改为持有 `ChatNextAction`，删除裸 `prompt` 字段。

#### `lib/shared/widgets/ai/tools/ask_user_card.dart`

- 抽出选项 chip 渲染（`label` / `description` / `recommended`）为可复用子组件，供 `NextActionBar` 使用。行为不变，纯提取。

#### `lib/shared/widgets/ai/chat/chat_message_view.dart`

- 第 476 行同款：`if (block.toolName == 'SuggestNextAction')` 跳过默认 tool call block。
- `AiSuggestNextActionBlock` 本身不在消息流内渲染（由 panel 提升到 composer 上方统一渲染）。

#### 全局开关

| 文件 | 改动 |
|------|------|
| `lib/shared/models/app_settings_aggregate_data.dart` | `AiAgentSettingsData` 新增 `nextActionSuggestions: bool`，`defaults` 为 `true`；`fromJson` 走 `fallback`，旧记录自动得 `true`。**无 migration** |
| `lib/shared/providers/settings_providers.dart` | `AppSettings` 加同名字段；`setAiAgentNextActionSuggestions()` 照 `setAiAgentIdentity`（第 2221 行）写法 + `_persistPartial(aiAgentSettings:)`；新增派生 `aiAgentNextActionSuggestionsProvider` |
| `lib/shared/widgets/settings/ai_agents_settings_section.dart` | 在头像行之后加 `SettingsRowDivider` + `SettingsRow(labelKey: settingsAiAgentNextActionSuggestions, descriptionKey: ...Description, child: Switch(...))` |

#### 其余接线

| 文件 | 改动 |
|------|------|
| `lib/desktop/widgets/ai/chat/panel.dart` | 删 `_buildOrchestratorQuickActions()`（82–118 行）；新增 `onOpenFeature`（null 时不注册工具、过滤空态跳转项）；新增 hook 取会话末尾 `AiSuggestNextActionBlock`；composer 上方插 `NextActionBar` |
| `lib/desktop/widgets/ai/chat/expanded_chat_area.dart` | 透传 `onOpenFeature` |
| `lib/desktop/pages/novel_editor_ai_area.dart` | `_buildAiArea()` 新增并透传 `onOpenFeature` |
| `lib/desktop/pages/novel_editor.dart` | 实现 `openFeatureFromChat()`，映射三种 `_EditorContentSelection`；未知 `FeatureId` 记 warn |
| `lib/desktop/pages/novel_editor_content_selection.dart` | `_EditorAgentCouncilSelection` 加 `initialTopic`；`_EditorTheaterSelection` 加 `initialScene` |
| `lib/desktop/pages/novel_editor_agent_mode_area.dart` | 解构并透传新字段 |
| `lib/desktop/widgets/ai/council/agent_council_panel.dart` | 新增 `initialTopic`；`topicController` 用它初始化 |
| `lib/desktop/widgets/ai/theater/theater_panel.dart` | 新增 `initialScene`；`sceneController` 同上 |
| `lib/mobile/pages/novel_chat_page.dart` | 空态换 `AssistantEmptyState`；插 `NextActionBar`；实现 `onOpenFeature` |
| `lib/mobile/widgets/mobile_ai_mode.dart` | `pushReplacementMobileAiModePage()` 加 `seedText`，转交目标页 |

#### i18n 三件套

模型产出的 `label` / `seed` 是运行时内容，不进翻译文件。兜底层取消后，需要的 key 很少：

| key | zh-CN | 用途 |
|-----|-------|------|
| `heuristic.next_action.title` | 下一步 | 建议条标题 |
| `heuristic.next_action.goto_council` | 和多位专家讨论剧情 | 空态卡片 |
| `heuristic.next_action.goto_council_sub` | 换几个视角看看这段该往哪走。 | 空态卡片 |
| `heuristic.next_action.goto_theater` | 不知道怎么写？先演一遍 | 空态卡片 |
| `heuristic.next_action.goto_theater_sub` | 让角色把这场戏演出来，再决定怎么落笔。 | 空态卡片 |
| `heuristic.next_action.goto_cover` | 给作品做一张封面 | 空态卡片 |
| `heuristic.next_action.goto_cover_sub` | 书名和简介都齐了，配张封面上书架。 | 空态卡片 |
| `settings.ai_agent_next_action_suggestions` | 下一步建议 | 设置项 |
| `settings.ai_agent_next_action_suggestions_description` | 让 AI 在回合结束时推荐下一步动作。 | 设置项 |

复用既有 key：`heuristic.feature.ai_council` / `ai_theater` / `ai_cover_studio` 及其 `_desc`；`ai.agent_quick_orchestrator_plan_today*`（空态第 1 条继续用）。

删除：`ai.agent_quick_orchestrator_continuity*` 与 `ai.agent_quick_orchestrator_start_next_chapter*` 两组（共 6 个 key），空态收敛到 4 条后不再使用；同步移除 `locale_keys.dart` 常量。

### 5.7 Task Graph

```text
PR-1 模型 + 裁决器 + 空态目录（纯 Dart）
  ├─ PR-2 SuggestNextAction 工具 + 消息块 + 上下文剥离 + codegen
  │    └─ PR-3 orchestrator.md 场景指引 + 封面事实注入 + 评测
  ├─ PR-4 共享 UI（NextActionBar / 空态迁移 / AskUserCard 选项提取）+ i18n
  │    ├─ PR-5 desktop 接线
  │    └─ PR-6 mobile 接线
  └─ PR-7 设置开关（AiAgentSettingsData + settings section）
```

| 任务 | 内容 | 依赖 | 验证 |
|------|------|------|------|
| PR-1 | `chat_next_action.dart`（模型 + 裁决器 + 空态目录） | 无 | `fvm flutter test test/shared/heuristic/` |
| PR-2 | 工具、`AiToolGroup.suggestion`、消息块、成对剥离、`make codegen` | PR-1 | `fvm flutter test test/shared/services/ai/` |
| PR-3 | `orchestrator.md` + `_buildNovelMetadata` 封面事实 + §7 评测 | PR-2 | prompt 单测 + 评测脚本 |
| PR-4 | `NextActionBar`、空态迁移、`AskUserCard` 选项提取、i18n | PR-1 | `fvm flutter test test/shared/widgets/ai/` |
| PR-5 | desktop panel / editor / council / theater 接线 | PR-2, PR-4 | `fvm flutter test test/desktop/widgets/ai/chat/` |
| PR-6 | mobile chat page + seedText 传递 | PR-4 | `fvm flutter test test/mobile/` |
| PR-7 | `AiAgentSettingsData` 字段 + settings section 开关 | PR-4 | `fvm flutter test test/shared/providers/` |

### 5.8 Migration

**无 schema 变更。**

- `FeatureUsages` 保留首次引导状态；建议跳转不新增统计记录。
- 开关落在 `AiAgentSettingsData` 的 JSON 聚合（`app_settings_aggregate_data.dart:393`，`appSettingsKey = 'ai_agent_settings'`）；`fromJson` 已有 `fallback` 机制，旧记录缺该字段时取默认 `true`。`currentVersion` 保持 1。
- 历史会话不含 `AiSuggestNextActionBlock` → 恢复后建议条为空，行为正确。

## 6. 验收标准

| 类别 | 标准 | 验证方式 |
|------|------|----------|
| 功能 | 模型调用后 chip 条渲染，默认 tool call 卡被抑制 | widget 测试 |
| 功能 | **模型未调用 / 全部被丢弃 → `NextActionBar` 返回 `SizedBox.shrink()`，不占高度** | widget 测试 |
| 功能 | 空会话卡片含 `goto_council` + `goto_theater`，顺序稳定 | 空态目录单测 |
| 功能 | 点击 council 建议后 desktop 进圆桌且议题框预填 seed | widget 测试 + 手动 |
| 契约 | 返回值恒为 `{"ok": true}`，不含 accepted / dropped | 工具单测 |
| 契约 | `feature` 传枚举外值 → 该条丢弃 + warn 日志，其余照常挂 | 工具单测 |
| 契约 | `kind=prompt` 缺 `prompt` → 该条丢弃 | 工具单测 |
| 契约 | 传 5 条 → 最多挂 3 条 | 工具单测 |
| 契约 | handler 同步返回，不 await 用户操作 | 单测断言无 Completer |
| 上下文 | `SuggestNextAction` 的 tool_use / tool_result **成对保留**进上下文，无孤儿；`AiSuggestNextActionBlock` 不重复进 | `agent_message_mapping` 单测 |
| 上下文 | 无封面且元数据齐备 → metadata 段含「封面：尚未设置」；有封面则无该行 | prompt 单测（正负例） |
| 门控 | `onOpenFeature == null` → `ToolDef` 列表不含该工具 | 工具单测 |
| 门控 | 设置关闭 → 工具不下发，空态推荐区不渲染 | 单测 + 手动 |
| 门控 | `defaultSubAgentToolNames()` 不含该工具 | 单测 |
| 门控 | `AiSessionMode.council.canUseTool('SuggestNextAction') == false` | 单测 |
| 错误处理 | `imageModelReady=false` → 封面既不进 schema 枚举，也不进空态卡片 | 工具单测 + 目录单测 |
| 兼容 | 旧 `ai_agent_settings` 记录缺开关字段时解码为 `true` | 单测 |
| 兼容 | 不含新块的历史会话恢复后建议条为空，不崩 | widget 测试 |
| 可维护性 | 新增一个可推荐功能 = 枚举加一项 + 裁决表加一条 + 单测加一条 | 代码审查 |

测试命令（串行，走 FVM）：

```bash
fvm flutter test test/shared/heuristic/
fvm flutter test test/shared/services/ai/
fvm flutter test test/shared/widgets/ai/
fvm flutter test test/shared/providers/
fvm flutter test test/desktop/widgets/ai/chat/
fvm flutter test test/mobile/
fvm flutter analyze
```

Widget 测试按 `.agents/rules/i18n.md` 初始化 EasyLocalization + `MergingAssetLoader`；同一文件内第二个 `testWidgets` 重包 `EasyLocalization` 会拿到空子树，需在同一个 test 内连续 pump。

UI 完成后必须实际运行 desktop app 目视确认「有建议」与「无建议」两种形态（`fvm flutter run -d macos`）；analyze 与单测覆盖不到视觉缺陷，尤其是无建议时的残留间距。

## 7. 评测

「何时调用、建议是否恰当」是非确定性的，必须评测。裁决器与空态目录是确定性的，单测覆盖即可。

### 评测对象

- **被测能力**：`SuggestNextAction` 的调用时机与建议恰当性。
- **不测内容**：裁决器、空态目录、剥离逻辑（确定性）；建议文案的措辞美感。
- **输入来源**：12–16 个固定会话场景，复用 `test/shared/services/ai/` 既有 headless turn 跑法。
- **输出判定**：是否调用、参数合法性、目标是否命中期望集合为 deterministic；建议内容是否「有信息量」为 manual 抽查。

### 评测场景

| 场景 | 输入 | 期望 | 判定方式 |
|------|------|------|----------|
| 刚写完一章 | 写入正文后收尾 | 调用；含 `kind=prompt` 且 prompt 提及本章具体内容 | deterministic + manual |
| 讨论方向有实质分歧 | 3 轮纯讨论，出现两个互斥走向 | 调用；含 `feature=ai_council`，seed 写出分歧 | deterministic + manual |
| 同一场戏反复讨论未落笔 | 4 轮围绕同一章无写入 | 调用；含 `feature=ai_theater` | deterministic |
| 创作向导刚写完简介 | 上下文含「封面：尚未设置」 | 调用；含 `feature=ai_cover_studio` | deterministic |
| 已有封面 | 上下文无该行 | **不建议封面** | deterministic（负例） |
| 多步任务中途 | TodoWrite 后第 2 步执行中 | **不调用** | deterministic（负例） |
| 简单事实问答 | 用户问「主角叫什么」 | **不调用** | deterministic（负例） |
| 用户已拒绝圆桌 | 上一轮建议圆桌被忽略并明确说不用 | 不再建议 `ai_council` | manual |
| 换低档模型 | 上述场景用 haiku 档 | 调用率下降；**建议条为空是可接受结果** | 只观察 |

### 自动化与人工边界

- **自动化阻断项**：负例场景（多步任务中途、简单问答、已有封面）不得调用；参数合法性；枚举命中。
- **人工抽查**：建议文案是否有信息量、seed 是否真的复述了分歧 —— 每次 prompt 改动抽查 8 例。
- **只观察不阻断**：调用率绝对值。不同模型差异大；建议条为空是设计上接受的状态，不构成上线阻塞。

## 8. Token 成本

| 维度 | 估计 | 说明 |
|------|------|------|
| 工具定义常驻 | 输入 ~220–300 tokens / 请求 | description + schema。位于请求前部且内容固定，**prompt cache 友好**；命中后边际成本接近零。用户关闭开关时为 0 |
| `orchestrator.md` 新增段 | 输入 ~130 tokens / 请求 | 常驻 system prompt，同在缓存区 |
| 封面事实 | 输入 ~10 tokens / 请求 | 一行，且**仅在没封面时**注入 |
| 工具调用 | 输出 ~100–180 tokens / 次 | 3 条建议 × ~40 + 调用开销 |
| tool result | 输入 ~10 tokens / 次 | 就是 `{"ok": true}` |
| 上下文增长 | **零累积** | 块与 tool_use / tool_result 对成对剥离，不进后续请求 |

净影响：

- 未命中缓存的首个请求约 +360 tokens 输入；后续主要成本是调用发生时的 ~110–190 tokens。
- 「没建议就不调用」直接压低了调用频次 —— 只在模型判断有价值时才付这笔钱。按每 4 轮调用一次估算，30 轮会话增量约 **1k–1.5k tokens**，不随会话长度放大。
- 降级：用户关开关 / 模型不调用时成本归零，功能不影响离线与本地开发。
- 可选优化（未进第一版，见妥协 2）：仅在特定条件下下发 schema，把常驻成本降到接近零。

## 9. 风险

| 风险 | 触发条件 | 影响 | 对策 |
|------|----------|------|------|
| 模型每轮都挂建议 | prompt 约束不够强 | 面板变吵，token 浪费 | `orchestrator.md` 写明「没有值得推荐的下一步时不要调用」「一轮最多一次」「任务中途不挂」；评测负例为阻断项 |
| 模型从不调用 | 换模型 / 用户关开关 | 建议条长期为空 | **这是设计上接受的行为**，不是待修复缺陷；空态引导仍在 |
| 孤儿 `tool_use` | 剥离时只删块或只删 result | API 直接报错，整轮失败 | 映射层按 `callId` 成对处理；单测构造「块被剥离但 tool_use 残留」的负例 |
| handler 误写成阻塞 | 照抄 `AskUser` 的 Completer | 整个 turn 卡死 | 核心原则 6 明确；验收项断言无 Completer |
| SubAgent 调用 | 忘记 `subAgentConfigurable: false` | 正文写手在委派中途推导航 | 目录声明 + `defaultSubAgentToolNames()` 单测固化 |
| 误用为提问 | 模型拿它替代 `AskUser` | 用户以为点了就决策了 | 描述写明「不阻塞、可忽略」；`orchestrator.md` 明确「需要决策用 AskUser」；评测抽查 |
| 模型编造功能名 | 幻觉 | 点了会崩 | schema 枚举 + 裁决器白名单双层拦截 |
| 封面被反复建议 | 模型忽略「一次为限」 | 打扰 | 有封面后事实行消失，自然收敛；评测覆盖 |
| 跳转丢上下文 | 点「去圆桌」后要重说一遍 | 体验断裂 | 模型给的 seed 已含分歧描述；完整 handoff 见妥协 1 |
| 空态迁移回归 | `empty_state.dart` 移到 shared 后导入断裂 | 编译失败 | 纯移动 + 改导入，`analyze` 可捕获；PR-4 独立提交 |
| 无建议时残留间距 | `NextActionBar` 外层还包着 Padding | 出现莫名空白 | `actions.isEmpty` 在**最外层**返回 `SizedBox.shrink()`；目视验证列为验收项 |
| mobile 封面能力不对等 | mobile 点封面建议 | 期望落空 | 走既有 cover handoff prompt；文案不承诺「工作台」 |
| 与 setup_phase 抢注意力 | 创作向导提问途中挂建议 | 引导被打断 | `orchestrator.md` 的「初始化设置」段优先级更高，且新段写明任务中途不挂 |

## 10. 已知妥协

```text
1. 妥协：跳转到 council / theater 只带模型给的一行 seed，不迁移会话上下文。
   - 原因：完整 handoff 需要给 council / theater panel 加 handoffDraft 入参、
           复用 AiHandoffContext 生成摘要，工作量接近本方案主体。
   - 影响：用户到了圆桌可能还要补背景，或让圆桌自己 Read 工作区。
   - 升级触发：跳转后首轮补充说明率高，或用户反馈「去了等于重开一局」。
   - 后续方向：复用 AiHandoffService.toMessageContent()，打通 chat → 特殊模式的正向 handoff。
```

```text
2. 妥协：工具 schema 常驻下发（开关打开时），不做按轮次的条件下发。
   - 原因：条件下发要把会话状态提前算到 ToolDef 构造时机，会把 UI 状态耦合进工具层。
   - 影响：开关打开时每个请求多约 220–300 输入 tokens（缓存友好，边际成本低）。
   - 升级触发：成本核算显示该项占比超预期。
   - 后续方向：按「上一轮是否写入正文」等粗粒度信号决定是否下发 schema。
```

```text
3. 妥协：monologue / roleplay 不进白名单。
   - 原因：诉求只点名圆桌、小剧场、封面；这两个模式缺少可靠的推荐时机判断。
   - 影响：继续只有 rail / 切换条入口。
   - 升级触发：产品明确要给它们引流。
   - 后续方向：枚举加值 + 裁决表加条即可，结构无需改。
```

```text
4. 妥协：DiscoveryBanner / SceneHeuristicBanner 继续是死代码。
   - 原因：本方案只做 chat 内建议；那两个是首页与编辑器顶部的另一个投放位，
           且 scene_heuristic_banner.dart 引用的 scene_registry.dart 根本不存在。
   - 影响：仓库里继续存在两个未挂载 widget 和一个悬空文件头引用。
   - 升级触发：确定要做首页功能发现时。
   - 后续方向：补 scene_registry 并挂载，或删掉这两个文件
           （heuristic.json 的 feature 文案本方案在用，不能一起删）。
```
