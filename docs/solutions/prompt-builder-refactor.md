# Prompt / Prompt Builder 整理与重构方案

## 背景

当前 AI prompt 相关代码已经形成多套入口：

1. `lib/shared/services/ai/prompt_template.dart` 负责加载 `assets/prompts/**.md` 模板。
2. `lib/shared/services/ai/prompts.dart` 提供 task prompt 的静态入口。
3. `lib/shared/services/ai/prompt_builder.dart` 负责通用 chat system prompt 的分段组装。
4. `lib/shared/services/ai/chat_prompt_builder.dart` 负责桌面聊天面板的上下文、Agent persona、SubAgent、Skill 等二次拼装。
5. Monologue、Roleplay、Theater、Council 等 orchestrator 各自拼自己的 system prompt 和 task prompt。
6. 还有一批 prompt 直接写在 Dart 代码里，没有进入模板系统。

这导致同一类概念在多个文件里分散出现，后续维护时很难判断“改哪个 prompt 会影响哪个场景”。

## 现状总结

### 1. 模板加载层

`PromptTemplateService` 负责：

- 启动时加载 `_templatePaths` 中列出的模板。
- 使用 Mustache 渲染变量。
- 支持 `<inline-ref type="skill">skill-name</inline-ref>` 内联技能内容。
- 提供 `rawAsset` 和 `renderAsset` 两种读取方式。

模板大致分为三类：

| 类型 | 目录 | 用途 |
|---|---|---|
| Agent persona | `assets/prompts/agent/*` | 主 Agent、SubAgent、特殊模式角色设定 |
| Task prompt | `assets/prompts/task/*` | 一次性任务，比如章节改写、分块、council round |
| System prompt | `assets/prompts/system/*` | 独立系统角色，比如 council summarizer |

当前仓库里有少量模板文件存在但未进入 `_templatePaths`，需要确认是否遗留：

- `assets/prompts/task/monologue_round.md`

### 2. 通用 chat system prompt

入口是 `AiPrompts.buildChatSystemPrompt`，实际委托给 `prompt_builder.dart` 中的 `ChatPromptBuilder.build`。

它按固定顺序组装：

1. 工作指南
2. 长期记忆
3. 用户自定义规则
4. 当前环境
5. 行为指南
6. 当前模式
7. 工作区资源路径规则

这个入口服务于普通 chat、`AiChatService` fallback conversation，以及章节快捷操作等基础场景。

### 3. 桌面聊天面板专用 builder

`chat_prompt_builder.dart` 是桌面 chat panel 的二次包装层。

它负责：

- 加载当前章节、工作区、世界观、人物、素材等上下文。
- 在通用 system prompt 后追加当前 Agent persona。
- 注入可用 SubAgent 列表。
- 注入 Skill 摘要，并允许 persona prompt 内联 skill 内容。
- 构造 slash command 的 SubAgent prompt。
- 构造带引用的用户消息和 agent 读取提醒。

当前 `buildChatSystemPrompt` 参数里有 `allowedTools`，但方法体没有使用。需要确认是遗漏、历史参数，还是预留设计。

### 4. Task prompt 静态入口

`AiPrompts` 目前封装了：

- `buildChunkSegmentationPrompt`
- `buildShortcutPrompt`
- `buildWorkspaceActionPrompt`
- `buildCoverAnalysisPrompt`

这些入口基本只是给模板传变量，职责比较清晰。

### 5. 特殊模式 prompt

以下模式没有统一走 `chat_prompt_builder.dart`：

| 场景 | 主要入口 | 默认模板 |
|---|---|---|
| 角色内心独白 | `MonologueOrchestrator.monologuePrompt` | `assets/prompts/agent/monologue_narrator` |
| 角色扮演 | `RoleplayOrchestrator.roleplayPrompt` | `assets/prompts/agent/roleplay_master` |
| 小剧场 | `TheaterOrchestrator.theaterPrompt` | `assets/prompts/agent/theater_actor` |
| 多 Agent 讨论 | `AgentCouncilOrchestrator` | `assets/prompts/task/council_round`、`assets/prompts/task/council_summary` |

这些 orchestrator 大多各自追加上下文和 `pathSchema`，与通用 chat prompt 有重复但不完全一致。

### 6. 代码内散落 prompt

以下 prompt 仍直接写在 Dart 代码里：

- 会话标题生成。
- Monologue / Roleplay / Theater / Council 标题生成。
- `NameGeneratorService` 的 AI 起名 prompt。
- `MemoryExtractionService` 的记忆提取 prompt。
- `MemoryDreamingService` 的记忆整理 prompt。
- `FloatingChatService` 的全局浮窗 system prompt。
- `AiContextManager` 的旧消息摘要 prompt。

这些 prompt 不是一定都要迁到 assets，但至少需要被纳入清单，否则后续很容易漏改。

## 主要问题

### 问题 1：命名冲突

当前有两个 `ChatPromptBuilder`：

- `lib/shared/services/ai/prompt_builder.dart` 中的 `ChatPromptBuilder`
- `lib/shared/services/ai/chat_prompt_builder.dart` 中的 `ChatPromptBuilder`

前者是通用 chat system prompt builder，后者是桌面 chat panel prompt builder。名字相同但职责不同，阅读和搜索时容易误判。

### 问题 2：入口分散

新增 prompt 时可能有多个选择：

- 写到 `assets/prompts`。
- 加到 `AiPrompts`。
- 加到 `chat_prompt_builder.dart`。
- 写在 orchestrator 里。
- 直接写在 service 里。

目前没有一张稳定的归属规则。

### 问题 3：上下文拼装重复

`pathSchema`、当前小说/章节/工作区、角色信息等上下文在多个 orchestrator 中重复拼接。重复本身不一定是问题，但目前缺少统一的“上下文片段”概念，导致格式和覆盖范围不一致。

### 问题 4：模板资产与注册表可能漂移

新增 `renderAsset` 路径必须同步改 `_templatePaths`，但这个规则靠注释维护。仓库里已经出现未注册模板，说明资产和注册表可能漂移。

### 问题 5：硬编码 prompt 不可见

硬编码 prompt 分散在业务服务里，无法通过模板目录快速知道系统里有哪些 prompt。

## 重构目标

这次不做“轻整理”，目标是把 prompt 系统收敛成一个高内聚、低耦合的模块。业务层只表达“我要哪个场景的 prompt”，不直接拼长文本、不直接读模板、不直接拼通用片段。

目标状态：

1. 单一入口：所有 prompt 构建通过 `AiPromptService` 或明确的 use-case facade。
2. 单一注册表：所有模板、硬编码短 prompt、变量定义都进入 `PromptRegistry`。
3. 单一渲染器：只有 `PromptRenderer` 访问 `PromptTemplateService`。
4. 单一组装器：只有 `PromptComposer` 负责 section 顺序、分隔符、空值过滤。
5. fragment 可以存在，但只能是纯文本片段函数，不能读取模板、不能访问 provider、不能做业务查询。
6. 业务 orchestrator 不再直接拼 `pathSchema`、环境、记忆、用户规则、标题生成 system prompt。

## 核心立场

推荐方案：建立 `lib/shared/services/ai/prompts/` 模块，替换现在散落的 builder。保留 `AiPrompts` 作为临时兼容门面，但新代码不再直接依赖它。

不推荐继续在现有文件上局部修补。原因是当前重复不是单个函数重复，而是职责边界重复：模板加载、场景判断、上下文转换、片段拼接、业务 prompt 都互相穿透了。

## 目标架构

```
业务层 / Orchestrator / UI
  只调用具体用例：chatPanel.system(...), title.session(...), memory.extract(...)
        |
        v
AiPromptService
  聚合所有 prompt use-case facade，不暴露模板细节
        |
        v
Prompt Use Cases
  ChatPromptUseCase
  AgentPromptUseCase
  TaskPromptUseCase
  ModePromptUseCase
  MemoryPromptUseCase
  TitlePromptUseCase
  UtilityPromptUseCase
        |
        v
PromptComposer
  统一 section 顺序、分隔符、空片段过滤、优先级规则
        |
        +-------------------+
        |                   |
        v                   v
PromptFragments       PromptRenderer
  环境/记忆/规则/路径     只负责模板渲染
  persona/skill/index       |
        |                   v
        +------------> PromptRegistry
                       prompt id、模板路径、变量声明、owner、类型
                              |
                              v
                       PromptTemplateService
                       只加载和渲染 assets
```

依赖方向固定为单向：

```
业务层 -> AiPromptService -> UseCase -> Composer -> Fragments/Renderer -> Registry/TemplateService
```

禁止反向依赖。`PromptTemplateService` 不知道业务模型；fragment 不知道 UI；orchestrator 不知道模板路径。

## 模块划分

### 1. `PromptRegistry`

职责：声明系统里有哪些 prompt。

建议文件：

- `lib/shared/services/ai/prompts/prompt_id.dart`
- `lib/shared/services/ai/prompts/prompt_definition.dart`
- `lib/shared/services/ai/prompts/prompt_registry.dart`

每个 prompt 定义至少包含：

| 字段 | 说明 |
|---|---|
| `id` | 稳定标识，例如 `chat.system.base`、`title.session` |
| `kind` | `system`、`agent`、`task`、`title`、`memory`、`utility` |
| `templatePath` | assets 路径；短 prompt 也可以没有 |
| `owner` | 归属模块，例如 `chat`、`memory`、`theater` |
| `variables` | 需要的变量名 |
| `customizable` | 是否允许用户覆盖 |
| `requiresPathSchema` | 是否需要工具路径规则 |

`PromptTemplateService._templatePaths` 应由 `PromptRegistry` 派生，不再手写第二份列表。这样模板资产和注册表不会漂移。

### 2. `PromptRenderer`

职责：唯一的模板渲染出口。

它只做：

- 根据 `PromptId` 找 `PromptDefinition`。
- 调 `PromptTemplateService.renderAsset`。
- 调 `PromptTemplateService.renderString`。
- 展开 inline skill ref。
- 缺变量时给出可定位错误或测试告警。

它不做：

- 不判断 chat / theater / memory 场景。
- 不拼 `pathSchema`。
- 不读数据库。
- 不知道 `AiSessionContext` 的业务语义。

### 3. `PromptFragments`

职责：可复用、稳定、无副作用的 prompt 片段。

可以保留 fragment，但必须遵守：

- 输入是 DTO 或原始值，输出是字符串或 `PromptSection`。
- 不访问 provider、database、rootBundle、template service。
- 不做场景调度。
- 不吞错误，不做静默 fallback。

建议 fragments：

| Fragment | 取代的重复 |
|---|---|
| `environment(context)` | 当前日期、小说名、章节 id/title |
| `userRules(rawRules)` | `AiPrompts.buildUserRulesBlock` 与 `PromptBuilder._buildUserRulesBlock` 重复 |
| `memory(memories)` | `MemoryService.buildMemoryPromptBlock` 的 prompt 出口 |
| `pathSchema()` | 多个 orchestrator 手写路径规则 |
| `workspace(context)` | 工作区类型、标题、内容 |
| `chapter(context)` | 章节大纲、正文、上一章、人物、世界观、素材 |
| `agentPersona(profile)` | 当前 Agent Persona |
| `subAgentIndex(subAgents)` | 可委派 SubAgent 列表 |
| `skillIndex(skills)` | Skill 摘要和使用说明 |
| `referenceReminder(refs)` | `<user-remind>` 引用读取提醒 |

### 4. `PromptComposer`

职责：统一 prompt section 的组装方式。

它处理：

- section 顺序。
- section 标题。
- 空 section 过滤。
- 分隔符。
- 是否追加路径规则。
- mode guide、behavior guide 等优先级。

建议保留类似 `PromptEnvelope` 的概念，但从 `prompt_builder.dart` 移到 composer 内部。业务层不要直接拼 `StringBuffer`。

### 5. Prompt Use Cases

职责：一个业务场景一个高内聚 use-case，只把业务输入映射成 fragments + template render，不直接拼底层通用规则。

建议文件结构：

```
lib/shared/services/ai/prompts/
  ai_prompt_service.dart
  prompt_id.dart
  prompt_definition.dart
  prompt_registry.dart
  prompt_renderer.dart
  prompt_composer.dart
  prompt_fragments.dart
  prompt_context.dart
  use_cases/
    chat_prompt_use_case.dart
    agent_prompt_use_case.dart
    task_prompt_use_case.dart
    mode_prompt_use_case.dart
    memory_prompt_use_case.dart
    title_prompt_use_case.dart
    utility_prompt_use_case.dart
```

Use case 归属：

| Use case | 负责场景 |
|---|---|
| `ChatPromptUseCase` | 普通 chat system、chat panel system、引用提醒 |
| `AgentPromptUseCase` | 主 Agent persona、SubAgent prompt、slash command |
| `TaskPromptUseCase` | shortcut、workspace action、chunk segmentation、cover analysis |
| `ModePromptUseCase` | monologue、roleplay、theater、council |
| `MemoryPromptUseCase` | memory extraction、memory dreaming、memory prompt block |
| `TitlePromptUseCase` | session/monologue/roleplay/theater/council 标题生成 |
| `UtilityPromptUseCase` | floating chat、context summary、name generator |

## 新的业务调用方式

业务层目标调用方式：

```dart
final prompt = ref.read(aiPromptServiceProvider).chatPanel.system(input);
```

```dart
final prompt = ref.read(aiPromptServiceProvider).mode.roleplay(input);
```

```dart
final messages = ref.read(aiPromptServiceProvider).memory.extraction(input);
```

`input` 是 use-case 专属 DTO。DTO 负责隔离业务模型，避免 prompt 模块到处 import UI / DB 细节。

示例 DTO：

- `ChatPanelPromptInput`
- `SubAgentPromptInput`
- `RoleplayPromptInput`
- `MemoryExtractionPromptInput`
- `TitlePromptInput`

## 去重规则

### 规则 1：业务层不直接调用模板服务

禁止在 orchestrator / service / provider 里直接调用：

- `PromptTemplateService.instance.renderAsset`
- `PromptTemplateService.instance.rawAsset`
- `PromptTemplateService.renderString`

例外：prompt 模块内部。

### 规则 2：业务层不直接拼通用片段

禁止在业务层手写：

- `## 工作区资源路径规则`
- `路径模式用于 Read/Write/Edit/Remove 等工具`
- `<user_rule>`
- `<environment_context>`
- `## 记忆`
- `## Skills`
- `## 当前 Agent Persona`

这些全部归 `PromptFragments` 或 `PromptComposer`。

### 规则 3：一个 prompt 只有一个 owner

每个 prompt id 必须有唯一 owner。比如：

- `mode.roleplay.system` 属于 `ModePromptUseCase`
- `title.roleplay` 属于 `TitlePromptUseCase`
- `memory.extraction.system` 属于 `MemoryPromptUseCase`

其他模块只能调用 owner 暴露的方法，不能绕过 owner 直接 render。

### 规则 4：模板路径不出现在业务层

`assets/prompts/...` 字符串只允许出现在：

- `prompt_registry.dart`
- 迁移期兼容代码
- 测试

### 规则 5：短 prompt 也要注册

标题生成这类很短的 prompt 可以不迁 assets，但必须注册为 `PromptDefinition.inline`。这样清单完整，后续再决定是否资产化。

## 资产目录建议

把 assets 目录按用途重排，而不是只靠 `agent/task/system` 三类：

```
assets/prompts/
  agents/
    primary/
    subagents/
    modes/
  tasks/
    chapter/
    workspace/
    embedding/
    image/
    council/
  memory/
  title/
  utility/
```

迁移期可以保留旧路径，`PromptRegistry` 先指向旧路径。等 use-case 接好后再移动文件，避免一次性改动过大。

## 迁移方案

### Phase 1：搭建新 prompt 模块，不动业务行为

新增：

1. `prompt_id.dart`
2. `prompt_definition.dart`
3. `prompt_registry.dart`
4. `prompt_renderer.dart`
5. `prompt_fragments.dart`
6. `prompt_composer.dart`
7. `ai_prompt_service.dart`

把现有 `_templatePaths` 全部迁入 `PromptRegistry`，`PromptTemplateService.loadAll()` 从 registry 读取路径。

验收标准：

- 所有旧模板仍能加载。
- `PromptTemplateService` 不再维护手写 `_templatePaths`。
- 未注册模板有测试暴露。

### Phase 2：替换通用 chat prompt

用 `ChatPromptUseCase` 取代：

- `prompt_builder.dart` 中的 `PromptBuilder`
- `prompt_builder.dart` 中的 `ChatPromptBuilder`
- `chat_prompt_builder.dart` 中的 `buildChatSystemPrompt`

保留旧类作为 deprecated wrapper，内部委托新 use case。业务调用逐步改到 `AiPromptService.chatPanel.system`。

验收标准：

- `class ChatPromptBuilder` 不再作为真实实现存在。
- 通用 chat prompt 输出保持等价。
- `allowedTools` 要么进入 prompt 能力说明，要么从接口删除。

### Phase 3：迁移 Agent / SubAgent / Skill 场景

用 `AgentPromptUseCase` 取代：

- 当前 Agent Persona 拼接。
- SubAgent 列表拼接。
- Skill 摘要拼接。
- slash command 的 SubAgent prompt。

验收标准：

- persona、subagent、skill 的 prompt section 只在一个 use case 内定义顺序。
- Skill inline ref 只通过 `PromptRenderer` 展开。
- chat panel 只负责收集输入，不负责拼 prompt。

### Phase 4：迁移特殊模式

用 `ModePromptUseCase` 取代各 orchestrator 里的 prompt 拼接：

- `MonologueOrchestrator.monologuePrompt`
- `RoleplayOrchestrator.roleplayPrompt`
- `TheaterOrchestrator.theaterPrompt`
- `AgentCouncilOrchestrator` 的 context/path 拼接

orchestrator 只保留编排职责：创建 session、调用 Agent、处理流事件、保存结果。

验收标准：

- orchestrator 中不再出现 `renderAsset`。
- orchestrator 中不再出现 `pathSchema` 文案拼接。
- 特殊模式的 system prompt 构造都走 `AiPromptService.mode.*`。

### Phase 5：迁移 task / utility / memory / title

用对应 use case 取代：

- `AiPrompts.buildShortcutPrompt`
- `AiPrompts.buildWorkspaceActionPrompt`
- `AiPrompts.buildCoverAnalysisPrompt`
- `AiPrompts.buildChunkSegmentationPrompt`
- `MemoryExtractionService` prompt
- `MemoryDreamingService` prompt
- `NameGeneratorService` prompt
- `FloatingChatService` prompt
- 所有标题生成 prompt
- `AiContextManager` 摘要 prompt

验收标准：

- `rg "PromptTemplateService\\.instance|PromptTemplateService\\.renderString" lib/shared lib/desktop` 只命中 prompt 模块和兼容 wrapper。
- `rg "AiMessage\\.system" lib/shared lib/desktop` 命中的 system content 来自 prompt service 或业务传入，不再内联长 prompt。
- 所有长 prompt 都在 assets 或 registry inline 定义中。

### Phase 6：删除兼容层

完成调用方迁移后删除或收敛：

- `lib/shared/services/ai/prompts.dart` 中的旧静态入口，或保留为很薄的 public facade。
- `lib/shared/services/ai/prompt_builder.dart`
- `lib/shared/services/ai/chat_prompt_builder.dart` 中除 context helper 外的 prompt 组装逻辑。

如果 `chat_prompt_builder.dart` 仍保留，应改名为 `ChatPanelPromptContextBuilder`，只负责把 UI/数据库数据整理成 DTO，不负责生成 prompt 文本。

## 推荐文件变更顺序

第一批：新模块骨架和注册表。

1. `lib/shared/services/ai/prompts/prompt_id.dart`
2. `lib/shared/services/ai/prompts/prompt_definition.dart`
3. `lib/shared/services/ai/prompts/prompt_registry.dart`
4. `lib/shared/services/ai/prompts/prompt_renderer.dart`
5. `lib/shared/services/ai/prompts/prompt_fragments.dart`
6. `lib/shared/services/ai/prompts/prompt_composer.dart`
7. `lib/shared/services/ai/prompts/ai_prompt_service.dart`
8. `lib/shared/services/ai/prompt_template.dart`

第二批：chat 和 agent prompt。

1. `lib/shared/services/ai/prompts/use_cases/chat_prompt_use_case.dart`
2. `lib/shared/services/ai/prompts/use_cases/agent_prompt_use_case.dart`
3. `lib/shared/services/ai/prompt_builder.dart`
4. `lib/shared/services/ai/chat_prompt_builder.dart`
5. `lib/desktop/widgets/ai/chat/runtime.dart`
6. `lib/desktop/widgets/ai/chat/agent_factory.dart`
7. `lib/desktop/widgets/ai/chat/context_loader.dart`

第三批：特殊模式。

1. `lib/shared/services/ai/prompts/use_cases/mode_prompt_use_case.dart`
2. `lib/shared/services/ai/monologue_orchestrator.dart`
3. `lib/shared/services/ai/roleplay_orchestrator.dart`
4. `lib/shared/services/ai/theater_orchestrator.dart`
5. `lib/shared/services/ai/agent_council_orchestrator.dart`

第四批：task、memory、utility、title。

1. `lib/shared/services/ai/prompts/use_cases/task_prompt_use_case.dart`
2. `lib/shared/services/ai/prompts/use_cases/memory_prompt_use_case.dart`
3. `lib/shared/services/ai/prompts/use_cases/title_prompt_use_case.dart`
4. `lib/shared/services/ai/prompts/use_cases/utility_prompt_use_case.dart`
5. `lib/shared/services/ai/memory_extraction_service.dart`
6. `lib/shared/services/ai/memory_dreaming_service.dart`
7. `lib/shared/services/name_generator_service.dart`
8. `lib/shared/services/floating_chat_service.dart`
9. `lib/shared/services/ai/context_manager.dart`

## 测试策略

### 1. Registry 完整性测试

- 每个 `assets/prompts/**/*.md` 必须存在于 `PromptRegistry`。
- 每个 registry template path 必须有对应 asset 文件。
- 每个 `PromptId` 唯一。
- 每个 prompt owner 非空。

### 2. 等价输出测试

迁移期间对关键 prompt 做 before/after snapshot：

- chat system prompt
- chat panel prompt with persona + skill + subagent
- slash subagent prompt
- roleplay system prompt
- monologue system prompt
- theater system prompt
- council round prompt
- memory extraction prompt

### 3. 约束测试

新增测试或 lint-like test：

- 业务目录不得直接调用 `PromptTemplateService.renderAsset/rawAsset/renderString`。
- 业务目录不得直接引用 `assets/prompts/` 字符串。
- 业务目录不得直接拼 `## 工作区资源路径规则`。

### 4. 行为测试

- chat panel 正常发送消息。
- Agent persona 生效。
- Skill inline ref 生效。
- slash command subagent prompt 正常。
- roleplay/monologue/theater/council 能正常构造 prompt。

## 风险与处理

| 风险 | 处理 |
|---|---|
| 一次性迁移范围过大 | 先搭新模块和 wrapper，再按 use case 替换 |
| prompt 文本变化影响模型行为 | 每个 use case 加 before/after snapshot，先追求等价 |
| DTO 过多导致样板代码 | 每个 use case 一个 input DTO，不做通用大 Map |
| Registry 变成上帝对象 | Registry 只存定义，不做渲染、不做业务判断 |
| Fragment 膨胀成新 builder | Fragment 禁止调模板和 provider，只允许纯函数 |
| 旧入口长期不删 | Phase 6 明确删除或降级为 thin facade |

## 最终验收标准

1. `PromptTemplateService` 只负责模板加载和渲染。
2. `PromptRegistry` 是唯一 prompt 清单。
3. `PromptComposer` 是唯一 section 组装器。
4. `PromptFragments` 是唯一通用片段出口。
5. `AiPromptService` 是业务层唯一 prompt 入口。
6. orchestrator 不直接读模板、不直接拼通用 prompt 片段。
7. `assets/prompts` 与 registry 不漂移。
8. `rg "class ChatPromptBuilder" lib` 不再命中真实实现。
9. `rg "assets/prompts/" lib` 只命中 prompt registry、迁移期 wrapper、测试。
10. `rg "PromptTemplateService" lib` 只命中 prompt 模块、初始化代码、迁移期 wrapper。

这个方案比温和整理改动更大，但边界更干净：prompt 作为一个独立子系统存在，业务层只提交输入，不参与模板路径、片段拼接和 section 顺序决策。
