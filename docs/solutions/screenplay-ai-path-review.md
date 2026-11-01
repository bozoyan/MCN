# 剧本 AI 工具、内置能力与跨作品路径审查

初审日期：2026-09-08。交付更新：2026-09-10，本轮实现基于代码提交 `b845e8a88`（refactor: flatten screenplay write path schema）。此前文档记录的交付提交为 `190457c43`。本文保留该日期的交付与复现记录，不代表当前代码状态或本次清理的验证结果；已移除功能的实施要求与失效文件引用不再列入本文。

当前结论：**此前剧本路径修复、正文原值、跨作品集隔离、Write／query 校验、剧本 schema 分层及 Glob／Grep／Replace 工具层均已完成。** 搜索沿用现有平级元素模型，`time_label` 不纳入文本搜索。最新提交已实现剧本资源平铺、目标类型过滤、hint、全局 `/_schema` 契约发现、伏笔共享及 active session 一次性重置。伏笔位置方案按用户本次确认更新为参与 working change、支持独立审阅与撤回。特殊模式已传递作品类型生成路径说明，本轮完成下节 SubAgent 入口适配与自动化回归。桌面／移动端手工验收待用户执行。

**2026-09-10 已实现，待用户验收：** orchestrator 负责传递具体任务要求，内置 SubAgent 精简为职责与执行约定，移除按作品类型禁用专家的逻辑，不新增默认创作 Skill。所有 SubAgent 都由运行时注入当前作品类型、当前作品工作路径与原作工作路径，覆盖内置、自定义、无工具、新建及续用调用。详见下文「SubAgent 任务驱动与作品上下文」。本轮完成产品代码、默认配置更新任务及回归测试；未手动修改用户数据库。

## 当前进度（2026-09-10）

| 项目 | 状态 | 当前结果与边界 |
| --- | --- | --- |
| 剧本返回路径与字段原值 | 已完成 | 季、集、节拍保留 ID 路径；元素有自身路径；字段路径保留末段；跨作品前缀不再改写正文 `text` |
| 跨作品季／集选择 | 已完成 | 目标场次、节拍 listing 不继承源作品当前集；缺少集、错误集与合法空集分别处理，提示指向目标作品 |
| Write／query 校验 | 已完成 | 未知字段、只读字段、类型、枚举、必填和互斥条件先校验；query 按资源层级校验；写入保留事务与失败回滚 |
| 剧本静态资源契约 | 已完成 | `screenplay` 为只读单例概览，季、集、节拍、场次为根级 collection，元素挂在场次下；Create／Write／query 和路径说明消费 `fieldSpecs`，已删除独立规则表 |
| `hidden` 向子树生效 | 已完成 | 根节点隐藏时整棵子树不输出常驻字段说明；路径发现与执行校验仍可用，搜索不得把 `hidden` 当权限 |
| `story_state` 与编年史者 | 已完成 | 快照已移除 `source_chapter_id`，覆盖章节或季／集／场次写在正文；chronicler 可处理小说和剧本 |
| 连续性与关系 skill | 已完成 | 合并为「故事连续性维护」，目录为 `story-continuity/`，含小说、剧本、关系三个 references；chronicler 先加载技能与对应附件 |
| 内置 SubAgent 类型限制 | 已移除 | writer／review／style_polish 在小说和剧本均可发现、新建及续用；启用状态、模式、会话归属与工具资源校验保留 |
| 搜索类型门禁 | 已完成 | Glob／Grep／Replace 遵守目标作品类型；人物等共享资料与剧本可读取文本均可搜索；仍拒绝目标类型不支持的资源 |
| 剧本 Glob／Grep／Replace | 工具层已完成 | 全季集遍历、文本原值、query 作用域、跨作品隔离与 Edit 权限均已接通；回归通过，双端手工验收待执行 |
| 创作向导旧 `/novel` 路径 | 已修复 | 主指令统一为 `profile`；当时内置技能测试 19 项全部通过 |
| 桌面／移动端搜索验收 | 接线已检查，手工验收待执行 | 两端共用工具层；多集搜索、单集过滤、替换预览／执行与撤回仍需在 UI 中验收 |
| `/_schema/{collection}` 与 `/_schema/groups/{group}` 按需契约入口 | 已实现，回归用例已提交 | 全局索引、单集合及分组契约由静态声明生成，包含 hidden 资源；接入只读校验、非法路径拒绝及错误 hint |
| 其他入口与提示词 | SubAgent 批次已完成 | 专家 prompt、委派要求、正文交付约定及 Spawn／斜杠命令／Council／headless 的作品上下文已接通；双端共用真实作品事实，Dreaming 类型传递仍另行交付 |
| 剧本资源平铺与类型过滤 | 已实现，回归用例已提交 | 小说根级路径保留；季、集、节拍、场次提到作品根，elements 留在场次下；不支持的 collection 不进入目录和常驻说明 |
| 伏笔共享 | 已实现，方案已同步 | foreshadowing 归 shared，新增铺垫／回收场次列并合入 v18；双端接入位置选择与跳转；四个位置字段的 AI Write 生成 working change，支持独立撤回 |
| active session 一次性重置 | 已实现，回归用例已提交 | initialization 注册一次性清空 active 指针任务；桌面移除最近会话兜底，空 active 绑定稳定新草稿；双端补缓存会话激活与过期回调保护，手工验收待执行 |

当前代码依据：[剧本 schema](../../lib/shared/services/ai/tools.dart)、[路径解析与校验](../../lib/shared/services/ai/tools_support.dart)、[剧本操作](../../lib/shared/services/ai/tools_screenplay.dart)、[跨作品响应](../../lib/shared/services/ai/tools_cross_work.dart)、[能力适用策略](../../lib/shared/services/ai/builtin_agent_tools.dart)、[连续性技能](../../assets/bundled_skills/story-continuity/SKILL.md)。

此前搜索交付完成工具、内置指南和正式回归，当时未修改正文模型、数据库结构或用户业务数据。以下 195／29／19 项为该轮历史结果，不覆盖最新路径切换、伏笔及会话改动。最终 8 组工具／prompt 回归 **195 项通过**，其中剧本测试 **29 项通过**，包含“扫描后元素消失”和“静态定义／当前作品绝对路径”等用例。覆盖全季集、原值回读、query 与跨作品边界、Replace 预览／执行／撤回、读取失败及 2,550 个字段的完整扫描与末尾目标写入。

附加技能测试发现的旧 `/novel` 路径已按后续要求修复：创作向导统一使用 `profile`，并补齐路径断言。修复前已复现主指令与附件的失败；修复后单独串行运行 `bundled_control_skills_test.dart`，**19 项全部通过**。

此前搜索交付的静态分析没有新增诊断；当时原有 `tools_support.dart` 两项 unused parameter warning 与 `tools_screenplay.dart` 两项 null-aware info 仍在。桌面与移动聊天均使用共享工具层，已检查接线；未运行双端 UI 手工验收或真实 LLM E2E。下文初审的 60 项通过与 7 项失败属于历史记录。

### 路径切换交付的验证依据

当前 `b845e8a88` 包含 schema 静态一致性与旧路径拒绝、伏笔位置变更与独立撤回、v17 → v18 迁移保留旧行、初始化只执行一次与失败重试、桌面会话绑定、移动伏笔列表和共享位置选择器等回归用例。本轮复跑了契约及剧本／伏笔工具测试，结果计入下节 252 项；未复跑该提交全部迁移和 UI 测试。开发库是否已手动补列仍未核实。

主要依据：[按需契约](../../lib/shared/services/ai/tools_schema.dart)、[伏笔 Write 与事务](../../lib/shared/services/ai/tools_write.dart)、[位置 apply 与回读](../../lib/shared/services/working_overlay.dart)、[共享位置选择器](../../lib/shared/widgets/foreshadowing/position_links.dart)、[初始化任务](../../lib/shared/services/initialization/chat_session_reset.dart)、[桌面会话绑定](../../lib/desktop/widgets/ai/chat/session_binding.dart)、[契约测试](../../test/shared/services/ai/tools_schema_test.dart)、[剧本及伏笔工具测试](../../test/shared/services/ai/tools_screenplay_test.dart)、[迁移测试](../../test/shared/database/screenplay_migration_test.dart)。

### 后续工作

1. 补齐最新提交的测试与静态分析运行记录，按下文验收清单核对覆盖范围；确认已有 v18 开发库的手动补列结果。
2. 完成双端手工验收：多集搜索、单集过滤、Replace 预览／执行／撤回，伏笔位置选择／跳转／独立撤回，以及重置后新对话、首发落库、重启恢复、历史会话切换与刷新布局稳定。
3. SubAgent 本批实现和自动化已完成，按下节清单进行最终用户验收。
4. Dreaming 的作品类型传递、其余共享技能的跨作品来源发现继续单独收尾。远程剧本审稿仍属于独立产品扩展。

真实 LLM E2E 尚未运行，需用户另行明确要求。自动化结果来自工具回归和技能加载测试，不代表 UI 或模型行为已验收。

## 已实现、待验收：SubAgent 任务驱动与作品上下文（2026-09-10）

用户已确认本节方向，并补充要求：所有 SubAgent 都要注入当前作品类型和原作工作路径。本节替代初审中「按入口扩展小说专家类型限制」「为专家增加小说／剧本两套创作规则」的建议。本轮已按确认方案完成实现；以下保留交付契约，运行结果见本节末尾。

### 职责、任务与技能

orchestrator 负责理解用户要求、选择执行者、交代目标和验收条件、整合实际结果。SubAgent 的默认 prompt 只保留专业职责、操作边界和回报要求。创作方法来自用户要求和本次选用的 Skill，不在每个专家里重复写一套固定配方。

现有 `SpawnAgentHandler` 新建子 Agent 时使用专家 prompt、用户规则、技能索引及工具上下文，通过 `process(task)` 传任务；它不自动继承主对话历史或主 Agent 已加载的 Skill 正文。续用时加载的是该子会话自己的历史。因此，精简 prompt 与补齐委派说明必须一起实施。

数据流保持现有结构：

```text
用户要求及本次选用的 Skill -> orchestrator -> SpawnAgent.task -> SubAgent -> 结果回报
当前作品记录 -> 统一作品上下文 -------------------------------> SubAgent
Council 议题 -------------------------------> 对应专家
```

斜杠命令和 Council 各有自己的任务来源，不要求先经过聊天 orchestrator；它们使用同一套精简专家职责和作品上下文。

### 精简所有内置 SubAgent

逐项检查 `assets/prompts/agent/` 下的 11 个内置 SubAgent。保留名称、slug、角色分工及用户自定义 prompt 的现有语义，不新增小说／剧本两套专家。

| 文件 | 保留内容与具体调整 |
| --- | --- |
| `writer.md` | 按任务创作；需要写入时使用指定资源；报告实际结果；缺少关键要求时返回阻塞原因。删除网文专精、章节专属流程、默认 POV、固定纯文本回报和大段写作片段引用 |
| `review.md` | 按本次验收条件核验；默认只读；问题附位置、证据和影响；返回通过／需修订／阻塞。删除默认十二维章节检查、手机阅读、断章及固定伏笔周期要求 |
| `style_polish.md` | 按任务润色，保持未授权修改的事实；交付形式由任务决定。删除固定风格配方和无条件「直接输出纯文本」要求 |
| `explorer.md` | 收集任务需要的资料，给出来源，区分事实与推断，如实报告缺失；压缩重复流程和固定长篇回报模板，内部资料不再只按小说章节表达 |
| `chronicler.md` | 现有 prompt 已简短，保留事实维护职责、范围边界和「故事连续性维护」操作指南；作品身份由统一上下文提供 |
| `plot_architect.md` | 保留结构、伏笔及后续影响的关注点；删除固定 `/outlines` 操作流程、章节范围要求、支线数量和高潮／伏笔周期配方，资源操作按任务与工具契约执行 |
| `character_analyst.md` | 保留动机、角色事实和一致性关注点；删除必须覆盖八个维度及机械 OOC 判定清单 |
| `world_builder.md` | 保留世界规则、一致性与设定代价的关注点；删除固定分层揭示比例、信息释放频率和章节专属措辞 |
| `pacing_expert.md` | 保留叙事推进、停滞及信息密度的关注点；删除每章字数、手机段落、300／500／1000 密度法和 80／20 断章配方 |
| `conflict_designer.md` | 保留利益、动机、对抗与后果的关注点；删除固定冲突阶段和每次冲突必须升级的配方 |
| `theme_guardian.md` | 保留主题与角色选择、情节结果的关联；删除固定主题数量、百分比进度和象征再现频率 |

六个 Council 专家不再各自重复发言字数和输出结构，继续由 `assets/prompts/task/council_round.md` 提供。专项 Skill 只在任务需要时使用，不为了符合专家模板而固定加载一组创作技能。

### orchestrator 交代任务，子 Agent 按同一标准执行

修改 `assets/prompts/agent/orchestrator.md` 和 `lib/shared/services/ai/tools_subagent.dart`：

- `SpawnAgent.task` 继续使用现有字符串参数，字段说明要求写清目标与资源位置、必要背景、本次临时要求、允许修改的范围、选定的技能名称、验收条件和交付形式；不增加工具参数。
- 持久化用户规则继续由运行时注入，不在 task 中全文重复。主对话中的临时要求、已经作出的取舍和验收条件必须带给子 Agent，不能假设它看过主对话。
- 本次选用的 Skill 传准确名称，子 Agent 在自己的上下文中加载；已经有完整指令时不重复加载。用户明确指定的技能不可用时说明问题，不静默换成另一套写法。
- 写手与核验使用同一套任务要求和技能。核验不自行增加默认网文评分标准；确有证据的事实或资源格式问题仍需指出。
- 剧本分支的「排场、写场与正文修改由你完成」改为遵循通用委派规则。小说现有自动审查、剧本现有写后事实整理的触发条件保持原有语义，本批不增加剧本默认自动审查。

参数说明只写在 input schema 的对应字段中；工具 description 保留用途、选择执行者和结果处理规则，遵循 AGENTS.md 的契约说明与去重要求。

### 所有 SubAgent 统一注入作品上下文

这部分由运行时统一注入，不依赖 orchestrator 在 task 中手抄，也不依赖专家默认 prompt 是否包含占位符。适用于全部内置与用户自定义 SubAgent，包括无工具调用、新建和续用子会话、斜杠命令以及 Council 专家；桌面与移动端都要接通。

| 上下文项 | 真源与输出规则 |
| --- | --- |
| 当前作品类型 | 来自当前 `Novel.contentKind`，显式输出 `novel` 或 `screenplay`；不能使用作品性质字段 `type`，也不能因遗漏参数而默认成小说 |
| 当前作品工作路径 | 来自当前作品稳定 ID，输出 `/works/{当前作品ID}`，说明相对资源路径的解析起点；不使用数据库磁盘路径、标题或原作 ID |
| 原作工作路径 | 来自当前作品已有的 `Novel.sourceNovelId`，有关联时输出 `/works/{原作ID}`，没有关联时明确写「未关联原作」；不由专家名称、metadata 或本轮碰巧读取的其他作品推断 |

主聊天的 `_buildNovelMetadata` 已用 `sourceNovelId` 输出「原作工作路径」。本次把同一事实接到所有 SubAgent。原作路径只表示关联来源：读取原作不改变当前写入目标，也不授予写回原作的权限。原作可能是小说或剧本，类型以实际读取目标为准；未关联原作时，用户仍可在 task 中指定其他只读参考作品。

无当前作品的全局调用明确标为「未绑定作品」，不生成虚假的作品根或原作路径。已经绑定作品却缺失必要身份数据时修复或报出上下文错误，不用默认小说值掩盖接线缺失。原作已删除或不可访问时，保留关联事实，读取按既有工具错误处理，不自动换成另一作品。

具体落点如下，复用现有上下文模型与片段机制，不新增运行服务：

| 文件／入口 | 修改内容 |
| --- | --- |
| `lib/shared/models/ai_chat_models.dart` | 在 `AiSessionContext` 中增加可空 `sourceNovelId`，与已有 `workId`、`contentKind`、`workspacePath` 一起携带当前作品事实；构造与 `copyWith` 保持完整传递，并支持显式清空原作关联。仅增加内存上下文字段，不新增数据库列 |
| `lib/shared/services/ai/prompts/prompt_fragments.dart` | 增加统一的作品上下文片段，显式输出两种作品类型、当前根路径及原作根路径／未关联状态；同一 prompt 只输出一份，且不受 `hasTools` 控制 |
| `lib/shared/services/ai/prompts/use_cases/chat_prompt_use_case.dart` | 主聊天与专家调用使用统一片段；避免与原有元数据、environment 中的同名事实重复。保留其他作品元数据和环境信息 |
| `lib/shared/services/ai/chat_turn_runner.dart` | 在构造本轮 Agent 前由当前 `Novel` 补齐作品上下文；显式传入 `SpawnAgentHandler`。`runSlashCommand` 的 system prompt 同样追加统一片段，有无工具都生效；已有技能与任务加载流程继续使用 |
| `lib/shared/services/ai/spawn_agent_handler.dart` | 接收当前调用的作品上下文，在 `_buildSystemPrompt` 中独立于工具说明注入；自定义 prompt 原文保持不变，作品事实作为独立片段追加。新建和续用走同一逻辑 |
| `lib/shared/services/ai/headless_session_turn.dart` | 从已有 `Novel` 补传 `workId`、`contentKind`、`sourceNovelId` 和当前作品根；任务没有季集定位信息时通过 task 与资源查询定位，不冒用前台其他作品的选择 |
| `lib/shared/services/ai/agent_council_orchestrator.dart`、`prompts/use_cases/mode_prompt_use_case.dart` | Council 调用链显式传递同一份作品上下文，`councilSystem` 复用统一片段；参与者使用不同模型时仍绑定同一当前作品，不根据 provider 或 persona 推断来源 |
| 桌面／移动调用方 | 核对 `lib/desktop/widgets/ai/chat/agent_factory.dart`、`lib/mobile/pages/novel_chat_page.dart`、`lib/shared/services/ai/chat_session_controller.dart` 及桌面 `agent_council_panel.dart`、移动 `council_page.dart`；两端普通聊天、斜杠命令和 Council 均从当前作品记录传递同一事实 |

作品上下文是可变的会话事实，必须与本轮工具管理器的作品作用域一致。切换作品、解除原作关联或重建 Agent 后，不得沿用上一作品的来源路径；必要时走现有 Agent 失效／重建流程。续用历史只保留该子会话的消息，不允许用旧消息中的作品路径覆盖本轮上下文。正常读取跨作品资源时，当前根和原作关联均不随读取目标变化。

### 移除专家类型禁用，保留工具资源校验

删除 `builtin_agent_tools.dart` 的 `isSubAgentApplicable`；`chat_prompt_use_case.dart` 的专家索引取消作品类型过滤；`spawn_agent_handler.dart` 删除执行前的类型拒绝及可用名称列表中的同类过滤。继续保留原有启用状态、模式、会话归属和工具授权约束。

`contentKind` 仍用于工具资源能力和路径说明。`/chapters`、`/scenes` 的适用性、原作只读与跨作品写入拒绝、字段和引用有效性继续由工具执行。工具名称及 input schema 保持静态，作品事实只进入上下文，不按作品或原作改写 tool schema。

### 正文底线与用户 Skill

`prose_quality_baseline.md` 在主 Agent 中只保留正文与助手说明分离、遵守目标资源格式等交付约定。删除强制标点风格、破折号禁令、每章词句次数限制等创作规定；writer／review 不再重复引用该片段。

orchestrator 的「必须加载正文写作 Skill」改为按本次任务选用：用户指定时使用指定技能，否则根据任务匹配；没有匹配技能时按用户要求和已有作品执行。选定一种创作方法后，不自动叠加另一套同职责的方法。主 Agent 保留创作判断，但不能把自身默认写法当成高于用户要求和所选 Skill 的硬性标准，也不要求子 Agent 重新执行整套默认写作清单。

本批不新增默认创作 Skill，也不将删下来的创作配方搬到另一个必加载位置。现有「剧本工具使用规范」「故事连续性维护」继续负责工作区操作与事实维护。技能按名称加载和同名覆盖的规则保持不变：用户安装的同名技能优先，禁用同名技能也不恢复内置版本。现有机制只处理同名覆盖，不声称能自动解决不同技能之间的内容冲突。

### 默认描述与已有配置

修改 `subagent_seeds.dart` 中 writer 的默认 description，改为「按任务要求完成正文创作与写入，交付实际结果和未解决问题。」，删除「专精长篇网文」及「连续 4 章及以上」的委派门槛。关联的中英文展示文案一起核对。

已有 description 存于 agents 表，单改 seed 不会更新。沿用 `agent_migrations.dart` 与 `app_initialization.dart`，增加一次性任务 `default_global_agents_v16_writer_description`：仅匹配未删除、全局、category 为 subagent、slug 为 writer、未启用自定义 prompt，且 description 仍精确等于旧默认文案「专精长篇网文正文创作与写入。适合连续 4 章及以上的批量写作委派；内容审查由 orchestrator 负责。」的记录，更新 description 与更新时间。保留名称、启用状态、模型、排序和其他配置，不重置用户编辑过的描述，不重跑全量恢复默认值。任务失败按现有初始化机制重试，完成后不覆盖用户后续修改。

这是默认配置文案更新，不涉及数据库 schema version、聊天记录迁移或正文数据变更；用户自定义 prompt 不被覆盖。

### 验证与交付边界

本批实现、双端调用方与测试涉及多个文件。专家 prompt 精简、委派要求、作品上下文和类型禁用移除一起交付；不新增服务、后端 API、外部账号或依赖。Dreaming 类型传递单独处理，远程剧本审稿不纳入本批。

| 验证范围 | 必须覆盖的行为 |
| --- | --- |
| 类型禁用移除 | 小说／剧本均可发现、启动和续用 writer、review、style_polish；启用状态、模式、会话归属及工具授权仍正确 |
| 所有 SubAgent 的作品上下文 | 内置／自定义、有工具／无工具、新建／续用均收到真实当前类型与当前根；有关联时收到原作根，无关联时明确未关联。覆盖 Spawn、斜杠命令和 Council，以及小说／剧本的双向原作组合 |
| 上下文稳定性 | 切换作品、原作关联由有到无、多模型 Council、旧子会话续用均不泄漏旧来源；读取原作或其他作品不改变当前根、原作关联和写入权限。全局无作品时不伪造路径 |
| 任务与 Skill | 实际模型请求完整收到 task、用户规则及现有入口承诺提供的技能信息；选定技能名称与临时要求不丢失。同名覆盖、禁用与用户自定义 prompt 原文保持有效 |
| prompt 契约 | 11 个默认专家保留各自职责和必要边界，去掉旧小说配方；writer／review 不再注入旧正文底线和写作手艺。Council 继续由 round task 规定发言格式 |
| 工具权限 | 剧本调用小说专属资源仍按目标类型报错；原作 Read 可用时正确返回目标内容，原作不可访问时明确报错；对原作的写入及 Replace 预览仍被拒绝 |
| 默认描述更新 | 旧默认值被更新；自定义描述、自定义 prompt、禁用状态、模型及排序保持；初始化重复执行安全，成功后不重复覆盖 |

复用已有 fake client 捕获实际请求，验证注入与传递；prompt 契约测试只断言上述职责和冲突规则，不锁死整份文字。以下 19 组测试已补齐新场景并串行执行，252 项全部通过：

```sh
fvm flutter test --no-pub --concurrency=1 --timeout 60s \
  test/shared/services/ai/chat_prompt_builder_test.dart \
  test/shared/services/ai/prompt_tool_guidelines_test.dart \
  test/shared/services/ai/spawn_agent_handler_test.dart \
  test/shared/services/ai/headless_session_turn_test.dart \
  test/shared/services/ai/chat_turn_runner_characterization_test.dart \
  test/shared/services/ai/agent_council_orchestrator_test.dart \
  test/shared/services/ai/interaction_mode_prompt_context_test.dart \
  test/shared/services/ai/prompt_token_baseline_test.dart \
  test/shared/services/ai/tools_cross_work_test.dart \
  test/shared/providers/subagent_providers_test.dart \
  test/shared/services/initialization/agent_migrations_test.dart \
  test/shared/services/bundled_control_skills_test.dart \
  test/shared/providers/agent_council_providers_test.dart \
  test/shared/services/ai/interaction_mode_error_test.dart \
  test/shared/services/ai/chat_session_controller_rollback_test.dart \
  test/shared/services/ai/chat_session_controller_workspace_target_test.dart \
  test/shared/services/ai/tools_screenplay_test.dart \
  test/shared/services/ai/tools_schema_test.dart
git diff --check
```

桌面和移动端分别检查专家选择、默认提示词展示，以及有原作／无原作作品的聊天、斜杠命令和 Council 请求上下文。用户明确要求某项写作规则时，写手与核验均应收到同一要求。自动化只证明传递、格式和权限契约，不代表真实模型已稳定遵循；真实 LLM E2E 仍需用户另行明确要求。

最关键的前提是任务描述能完整传递临时要求，作品身份则由运行时独立保证。缺少任务关键条件时子 Agent 返回阻塞，不用长篇默认 prompt 猜补。发布后新建或重建 Agent 使用新模板；不清空历史聊天或 active 指针。代码回滚不自动恢复已更新的默认 description，保留新描述不影响旧版工具执行；用户后续修改的配置不因回滚被重置。

本批自动化已验证内置与自定义专家的任务传递、有无工具的作品身份、新建与续用、解除原作关联后的缓存重建、全局调用拒绝旧作品身份、多模型 Council、用户规则与技能加载、旧默认描述更新范围，以及会话和工具权限回归。桌面／移动端调用方已同步检查，未执行双端 UI 手工验收或真实 LLM E2E，也未手动读取或修改用户数据库。

32 个受影响 Dart 源文件与测试的定向静态分析无诊断；FVM 受限 codegen 成功，生成 diff 仅包含 Council provider 的源码 hash 更新，`git diff --check` 通过。代码生成保留仓库现有 SDK／analyzer 版本及生成器警告，不因此升级依赖。旧 writer 描述的更新只在应用下次执行初始化任务时生效；此处的数据库验证全部使用测试库。

## 已实现：剧本平铺、类型过滤与按需契约（2026-09-09）

本节采用最新决定，替代上一轮新增 `/novel` 的方案。核心实现及回归用例已随 `190457c43` 提交；以下保留契约和完整验收要求，不表示全部验收已执行。伏笔位置的审阅／撤回方案已按用户本次确认与最新实现同步。

### 唯一路径契约

| 切换前的剧本路径 | 当前作品内路径 |
| --- | --- |
| `/screenplay/seasons/...` | `/seasons/...` |
| `/screenplay/episodes/...` | `/episodes/...` |
| `/screenplay/beats/...` | `/beats/...` |
| `/screenplay/scenes/...` | `/scenes/...` |
| `/screenplay/scenes/{scene_id}/elements/...` | `/scenes/{scene_id}/elements/...` |

小说专属资源保留 `/chapters`、`/volumes`、`/outlines`，不新增 `/novel` 目录；`/foreshadowing` 路径保留并提升为共享资源。小说节拍仍为 `/outlines/{title}/beats/{index}`，剧本节拍为 `/beats/{beat_id}`，两者不合并。共享资料仍使用 `/profile`、`/story_state`、`/characters`、`/locations`、`/lore`、`/relations`、`/canvas` 等作品根路径。

`/screenplay` 保留为只读剧本概览，返回格式及统计数据，不再挂载季、集等子资源。跨作品绝对调用变为 `/works/{work_id}/scenes/...`，当前作品相对调用为 `scenes/...`。`/` 是全局根，作品根仍为 `/works/{work_id}`。

对外工具、响应与错误提示、内部审阅记录的路径生成和匹配、UI 调用、内置 prompt／skill 与测试统一使用平铺路径。旧 `/screenplay/{collection}/...` 直接失效，不增加别名、转换层或双路径匹配。元数据一律使用 `/profile/...`。

**已清理 `/novel` 历史别名**：`_canonicalizeLegacyWorkSegments` 已删除，不再将 `/novel/current_state/...` 映射为 `/story_state/...`，也不再将其余 `/novel/...` 映射为 `/profile/...`。此项是移除现有别名；新增 `/novel` 命名空间的方案已取消，不保留任何 `/novel` 工具路径。当前状态直接使用 `/story_state`，元数据直接使用 `/profile`。

不迁移历史会话、历史审阅记录、已保存自定义技能中的旧路径，也不以保留旧记录可用性为理由维持内部旧路径。历史内容保留原样；新会话使用更新后的内置契约，自定义内容中写死的旧路径需由用户自行修改。

### 按目标作品类型显示和校验

在 collection 的静态声明中记录 `group`，取值为 shared、novel、screenplay；shared 适用于两种作品，其余组适用于同名作品类型。作品根目录、常驻路径说明、搜索遍历和执行校验由这份分组推导适用范围，不分别维护多份名单，也不在运行时修改声明本身。

| 目标作品类型 | 显示的 collection |
| --- | --- |
| 小说 | 共享集合（含 foreshadowing）+ chapters、volumes、outlines |
| 剧本 | 共享集合（含 foreshadowing）+ screenplay 概览、seasons、episodes、beats、scenes |

隐藏的是不支持的 collection 及其子树：它们不出现在目标作品根、该类型常驻路径／字段说明或根级搜索候选中。调用方显式访问不支持的集合仍返回 `content_kind_mismatch` 和可执行 hint，不能伪装成空集合。按目标 work 的类型判断，不能用当前聊天所在作品的类型判断跨作品路径。

保留现有 `hidden` 的独立含义：它仅控制常驻字段说明的篇幅，不表示 collection 不可访问。支持但 hidden 的 canvas、relations 等仍可发现和执行，按需契约也必须能查到；搜索继续遵守各资源自身的可搜索能力。Read 等工具定义与 input schema 保持静态，不按内容类型裁剪 JSON Schema。

### hint 与按需契约入口

`/_schema` 是全局只读契约入口，复用 Read；全局根增加该挂载，作品根只列业务集合。三个入口如下：

| Read 路径 | 返回内容 |
| --- | --- |
| `/_schema` | 全部 collection 的轻量索引；每项包含 `collection`、`group`、一句用途 `description` 和契约查询 `path` |
| `/_schema/{collection}` | 指定 collection 的完整契约，包含它的全部子资源 |
| `/_schema/groups/{group}` | 指定 group 下所有 collection 的完整契约，由单集合契约聚合生成 |

`group` 固定为 shared、novel、screenplay，每个 collection 只归属一组。分组查询仅返回本组，共享资源通过 shared 查询，不在 novel／screenplay 组内重复输出。分组成员为：

- shared：profile、story_state、lore、materials、characters、locations、skills、items、factions、creatures、relations、canvas、foreshadowing。
- novel：chapters、volumes、outlines。
- screenplay：screenplay、seasons、episodes、beats、scenes。

例如，`Read /_schema` 的 entries 包含以下条目（此处仅示例四项，实际索引返回全部集合）：

```json
[
  {"collection": "chapters", "group": "novel", "description": "小说章节与正文", "path": "/_schema/chapters"},
  {"collection": "scenes", "group": "screenplay", "description": "剧本场次与正文元素", "path": "/_schema/scenes"},
  {"collection": "characters", "group": "shared", "description": "角色资料", "path": "/_schema/characters"},
  {"collection": "foreshadowing", "group": "shared", "description": "伏笔的铺垫、回收与所在位置", "path": "/_schema/foreshadowing"}
]
```

`Read /_schema/scenes` 包含 elements 契约，不新增独立 elements collection。`Read /_schema/screenplay` 仅查剧本概览；`Read /_schema/groups/screenplay` 才查询整组剧本资源，两者不可混同。groups 是契约查询保留路由段，不是业务 collection；不会将 novel 或 shared 解释成单集合别名。

所有契约入口及索引均不受当前作品类型限制；在剧本中也能从索引的 `group: novel` 发现小说集合，或直接读取 `/_schema/groups/novel`。按类型隐藏仅作用于业务目录和当前类型说明，不隐藏全局契约；查询契约不改变业务读写权限。

契约说明来自与执行校验相同的静态资源声明，包含路径模板、适用类型、读写能力、字段、必填与类型、枚举、query、互斥关系和子资源。返回模板与约束，不填入真实作品 ID、当前季集或用户数据；同版本同入口结果不随作品或会话变化。现有 hidden 不能让按需契约缺失。单例概览与所有层级的子资源都必须输出自身契约，不能只复用当前省略 hidden 的常驻字段渲染结果。

类型不匹配的 hint 指向目标作品根和 `/_schema/groups/{目标类型}`；字段、query 或路径层级错误指向 `/_schema/{collection}`，子资源错误仍指向所属 collection 的契约；有效路径下 ID／标题不存在时保留 listing 发现提示。未知 collection 引导查目标作品根和 `/_schema`。错误说明只包含模型完成下一步调用所需的信息。

`/_schema` 在全局路由中处理，不打开作品内容库。对该入口的写入、未知 collection／group、缺少 group 的 `/_schema/groups`、额外层级或不支持的 query 明确报错；未知名称的 hint 指向 `Read /_schema`。拒绝 `/works/{id}/_schema/...`；跨作品 hint 增加 work 前缀时必须保持 `/_schema/...` 原样。既定 Create／Write／Edit／Replace／Remove 只能写当前作品的边界不变。

### 已确认：伏笔共享与位置关联

伏笔主体的 title、setup、payoff、status 保持通用语义，`foreshadowing` 归入 shared。沿用每条伏笔一个主要铺垫位置、一个主要回收位置；本次不新增多次出现记录表或泛化的资源引用体系。

| 位置 | 章节字段（保留） | 场次字段（新增，可空） |
| --- | --- | --- |
| 铺垫 | `setup_chapter_id` | `setup_scene_id` |
| 回收 | `payoff_chapter_id` | `payoff_scene_id` |

- 同一位置的 chapter／scene 两个字段互斥，允许都为空。小说只能关联本作品章节，剧本只能关联本作品场次；新设关联必须验证目标存在且未删除，章节目标不能是卷。
- 四个位置关联字段（setup_chapter_id、payoff_chapter_id、setup_scene_id、payoff_scene_id）的 AI Write 与 title、setup、payoff、status 一样生成 working change，参与字段审阅、提交和撤回。每个位置字段保留独立变更，可单独撤回；AI Create 的初始关联和双端选择器继续通过业务服务写入。
- 位置更新统一走 `novel_content.dart` 的服务入口：事务内读取当前记录，合并本次传入的位置字段，先校验完整位置状态的互斥、作品类型及新设目标，再通过一次 UPDATE 写入相关列。未提供的字段保持原值，显式 null 清空对应关联；校验失败时不写入。双端选择器、AI Create 及 AI Write 的 overlay apply 复用该服务校验。
- AI Write 同时包含正文／状态和位置字段时，在同一个内容库事务中构建各字段的变更请求，并统一交给 `stageTextChangesAtomically`。位置字段记录旧／新关联 ID，清空在变更记录中用空字符串表示，apply 时还原为 null 并调用位置更新服务。任一步失败回滚本次全部写入及变更记录。正文／状态的独立撤回不改位置；位置字段的独立撤回恢复对应旧关联，并遵守引用校验。
- 场次的季、集及编号从场次关系推导，不在伏笔中重复保存；场次换集或重新排序后仍通过 ID 指向同一场。选择位置不自动改变伏笔状态，设置状态也不强制要求关联位置。
- `/_schema/foreshadowing` 和 `/_schema/groups/shared` 静态列出四个位置字段、类型条件、互斥及清空规则。双类型共享同一份 tool schema，不按当前类型裁剪字段。位置字段通过 Create／Write 设置，Edit／Replace 仅处理已声明可编辑的文本字段，不替换 ID。
- 双端展示“铺垫位置／回收位置”：小说选择章节，剧本按季、集查找场次；支持清空和跳转。没有可选目标时允许只编辑伏笔文本。已关联目标后来删除时，保留伏笔和引用信息，显示目标不可用并允许用户重新选择或清空，不能误跳转或自动删除伏笔。
- working overlay 保留章节位置并补齐场次位置的字段 apply 和当前值读取，四个位置字段都进入现有审阅／撤回链路，不再从字段撤回入口排除位置记录。历史记录不批量迁移；撤回仍受当前资源与引用有效性约束。

具体修改覆盖以下位置，超过 8 个文件：

| 范围 | 修改落点 |
| --- | --- |
| 数据与服务 | `novel_content_database.dart` 的 Foreshadowings 增加两列，`novel_content_database_migrations.dart` 的 `migrateToV18` 同步补列，schemaVersion 保持 18；`novel_content.dart` 的创建和位置更新统一校验并持久化；Drift 生成模型随字段更新 |
| 工具与审阅 | `tools.dart`、`tools_screenplay.dart` 调整分组／类型门禁；`tools_create.dart`、`tools_read.dart`、`tools_write.dart` 接通四个位置字段的创建、批量 stage 和回读；`working_overlay.dart` 支持章节／场次位置 apply、当前值读取和字段撤回；`tool_resource_resolver.dart` 补位置字段标签；双类型搜索均可发现伏笔文本 |
| 桌面 | `widgets/workspace/foreshadowing_editor.dart`、`widgets/workspace/novel_workspace_panel.dart`、`widgets/sidebar/rail.dart`、`pages/novel_editor.dart` 接入剧本伏笔入口、位置选择及场次跳转 |
| 移动 | `models/screenplay_workspace_state.dart`、`mobile/features/screenplay/` 的导航与 shared_content、`mobile/pages/foreshadowing_editor_page.dart` 接入伏笔列表／编辑页和场次选择，复用现有伏笔 UI |
| 说明与验证 | 更新关联文案的 en／zh-CN 翻译、内置连续性指南和字段契约；补 service、工具、审阅与双端回归；现有 canvas demo 的章节关联验证继续成立 |

用户已确认：v1.2.1 发布的 schemaVersion 为 17；v18（`558ae2819`）仅在 development／dev-next，未推远端、未打 tag。新增 `setup_scene_id`、`payoff_scene_id` 两列直接合入 `migrateToV18`，schemaVersion 保持 18。已是 v18 的开发库需通过 SQLite skill 手动补列并查询验证；本次未读取开发库，执行状态待核实。保留已有伏笔文本、状态和章节关联，新场次列初始为 null；不新增 v19，也不增加运行时幂等补列、fallback 或兼容层。此处按 AGENTS.md 的未发布版本规则执行。

生成源修改后通过项目 FVM SDK 运行 codegen，检查生成 diff，并以 v17 结构验证升级到 v18 后已有行保留、两列可空且通过 Typed DAO 正常读取；开发库手动补列后另行查询确认版本仍为 18。

### 已核实的调整范围

本次超过 8 个文件，应作为一批完整契约切换交付；解析、调用方、内置说明和 active 重置一起进入版本。

| 范围 | 文件与具体调整 |
| --- | --- |
| 静态声明与解析 | `lib/shared/services/ai/tools.dart`、`tools_support.dart`：将季、集、节拍、场次提升为独立 collection，elements 仍为 scenes 子资源；保留 fieldSpecs 校验能力，适配当前只为 singleton 分支解析嵌套资源的逻辑，更新静态类型适用规则、路径模板、目录和字段说明 |
| 剧本操作与审阅路径 | `tools_screenplay.dart`：按平铺 collection 分发，移除以 screenplay 为首段的固定下标假设，统一返回 path、引用与审阅 resourcePath；`working_overlay.dart` 及 `screenplay_edit_orchestrator.dart` 验证新路径合并、scope、提交和撤回 |
| 搜索与跨作品 | `tools_resource_search_support.dart`、`tools_glob.dart`、`tools_grep.dart`、`tools_replace.dart`、`tools_cross_work.dart`：平铺后仍按全季集遍历，保留 query 与目标作品隔离；错误中的平铺业务路径正确加 work 前缀，schema 路径不加前缀、正文不改写 |
| 按需契约和 hint | `tools_read.dart`、`tools_cross_work.dart`、`tools_support.dart`：全局 Read 分发 collection 索引、单集合契约和 groups 聚合契约；索引携带 group，聚合复用单集合渲染；类型、字段、query、路径错误添加对应查询引导 |
| UI 引用及标签 | `lib/shared/models/novel_workspace.dart`、`lib/shared/widgets/ai/tools/tool_resource_resolver.dart`：更新双端共享的路径引用、资源识别和工具卡片标签；`lib/desktop/pages/novel_editor.dart` 的元数据审阅路径 `/novel/description` 改为 `/profile/description` |
| 内置说明与上下文 | `assets/bundled_skills/screenplay-tool-guide.md`、`story-continuity/SKILL.md`、`assets/prompts/agent/orchestrator.md`、`lib/shared/services/ai/prompts/prompt_fragments.dart`：使用平铺路径与 schema 发现规则；当前已以工具使用规范取代旧剧本写作指南，创作方法由用户要求与匹配的 Skill 决定 |
| 伏笔共享 | 按上一节同时完成数据列、类型与引用校验、工具／审阅、双端入口和位置选择；不能只修改 group |
| 初始化与会话绑定 | 新增 `lib/shared/services/initialization/chat_session_reset.dart`，在 `app_initialization.dart` 注册一次性任务；调整 `session_persistence.dart` 的空 active 选择，核对桌面与移动聊天入口 |
| 回归 | 工具、跨作品、working overlay、screenplay orchestrator、workspace 路径、工具卡片、bundled skills 与 prompt 测试同步更新；残留检查针对业务路径，不能把源码 import、目录名或 contentKind 的 screenplay 当作旧工具路径改名 |

数据流：静态 collection 契约 → 类型适用判断 → 目录／常驻说明／搜索与执行；同一静态契约 → 全局 schema 查询；执行错误 → hint → schema 或真实资源 listing。UI 保存与 AI 编辑生成同一套审阅路径。

### active session：随切换一次性清空

用户已指定落点为 `lib/shared/services/initialization`，选择“随新路径切换一次性重置”。清理对象是用户作品内容库 `novel_states` 中 `active_chat_session` 的指针，不是现在手动清本机数据库，也不是删除聊天或消息。

1. 注册任务 ID `flat_resource_paths_active_session_reset_v1`，复用现有 `AppInitializationTask` 与 `app_initialization.` 完成标记。覆盖主库可见、具有内容库路径的小说和剧本，避免任一类型会话保留旧剧本路径或旧契约上下文。
2. 按现有 `outline_migrations.dart` 的方式解析内容库路径、检查文件存在并在 finally 关闭连接。没有内容库路径的作品跳过；声明了路径但文件缺失或打开／写入失败时记录日志并抛错，不能创建空库或标记任务完成。
3. 直接复用 `novelStateDao.setActiveChatSessionId(null)` 清空 active。`getActiveChatSessionId()` 和对应 watch 对“状态行不存在”与“data 为 null”均返回 null，现有 `deleteSession` 也通过该接口清空 active；本任务没有保留状态行或审计其时间戳的需求，不要求 UPDATE。不存在该行时重复调用仍安全。不删除 session、message、审阅记录或其他作品状态，不新增 schema version，也不新增 DAO 清空接口。`clearActiveChatSessionIn(ids)` 保留原有按 ID 清理语义，供存储清理使用，不为初始化移除其过滤条件。
4. 所有目标库成功后才由 runner 写完成标记；中途失败时下次启动重试，已清空的指针可重复执行。任务在聊天入口可用前完成；成功之后的再次启动必须跳过，不清掉用户新选中的会话。
5. `effectiveAiChatSessionId` 已移除 active 为 null 时回退最近会话的逻辑，同时删除不再需要的 sessions 参数和调用方传参。桌面绑定保留完整 AsyncValue，以 `secondaryReady` 和 `hasValue` 区分“尚未读取”和“已读到空值”，按下一节门控双端会话入口。已确认无 active 时使用稳定的新会话临时信号，首轮发送才创建真实会话；已有有效 active、新会话临时信号及 handoff 映射保持各自行为。
6. 移动端 `MobileNovelChatPage` 未指定 `existingSessionId` 时已生成新会话信号；已检查作品入口和 assistant hub 都可走该分支。验证重置后双端默认打开新对话，显式选择历史记录仍可打开。保留桌面编辑器和 session_switcher 中“用户删除当前会话后选剩余会话”的两处 `pickPreferredAiChatSession` 调用；读取持久化 active 的 `getPreferredSession()` 也保留。

#### 加载窗口的具体处理

桌面 `novel_editor.dart` 已接入 `useResolvedChatSession`，保留 `AsyncValue<String?>`，以 `(novelId, databasePath)` 为作用域解析会话。以下为加载、刷新与错误处理的验收要求：

| 输入状态 | 绑定与 UI 行为 |
| --- | --- |
| 本地有明确选择（initialSessionId、用户选中的真实 ID、新建／handoff 临时信号） | 优先使用本地选择，持久化读取晚到时不得覆盖；仍需满足内容库已准备好的条件 |
| 无本地选择，`!secondaryReady` 或尚无数据且仍在加载 | 会话未确定；首次进入在聊天区域原有尺寸内显示加载占位，不挂载可发送的 AiChatPanel，不发起恢复或创建动作 |
| 无本地选择，`secondaryReady && persistedActiveAsync.hasValue`，值为真实 ID | 绑定该 ID，按 ID 查询会话，不依赖它是否出现在会话列表首屏；消息未就绪时走该会话的加载态，不切到空草稿 |
| 无本地选择，`secondaryReady && persistedActiveAsync.hasValue`，值为 null | 确认没有 active；为当前作品作用域生成并复用一个 `__new__...` 信号，绑定现有草稿流程；首轮发送时由 `materializeAiChatNewSession` 创建真实 ID 并落库 |
| 读取失败且没有可用数据 | 保持未确定状态，在原区域提供重试；不得当作“没有 active”创建新对话 |

具体落点为 `novel_editor.dart` 的会话解析、`novel_editor_ai_area.dart` 的侧栏分支和展开聊天分支，两处共用同一就绪判定。已经显示内容时，后台刷新使用同作品的已解析绑定及缓存值，保留消息、草稿、选择和滚动位置，不卸载面板或切成整页 loading。切换作品时清掉旧作用域的临时信号及缓存，不能把上一作品的 hasValue／active 复用过来。

“已确认空 active”必须传显式新会话信号，而不是含糊的 null：`AiChatPanel` 当前在 `targetId == null` 时还会独立调用 `getPreferredSession()` 查询持久化 active。通过已解析 ID／临时信号进入面板，避免编辑器刚判断完为空、面板又重复恢复的双重决策。其他使用 null 自动恢复的调用方另按实际用途检查，不能全局把 null 恢复分支删掉。

初始恢复和异步切换回调都绑定当次作品／目标／请求代次；用户改选、开始新草稿或组件销毁后，过期结果不得再更新本地选择、激活旧会话或触发 `onSessionRestored`。命中已加载的会话只能跳过消息重读，不能跳过用户选择所需的 active 持久化。已有绑定的刷新失败记录日志并保留内容，不转成新会话。

#### active 准确性与回退来源：代码审查结果

本次证据来自当前代码和 Git 历史，未读取用户数据库、未运行 UI 复现。active 是 `novel_states.active_chat_session` 中的持久化指针，与页面本地 `activeAiSessionId` 是两个状态。

正常链路已接通：共享 `chat_session_controller.dart` 首次发送会调用 `createActiveSession`，顶层 chat 创建后写 active；桌面／移动端未缓存的历史会话打开时调用 `activateSession`；删除当前会话时清空 active。`novel_providers.dart` 的正常页面调用传入内容库并订阅 DAO，查询具体 session 时还会校验作品归属和 deletedAt。首轮发送前的新草稿不持久化 active，因此关闭未发送草稿后重新进入仍可恢复此前会话；本次一次性重置后则直到首次发送前都没有持久化 active。

以下为实施前的审查依据。`190457c43` 已补双端缓存命中激活、顶层 chat 校验、桌面会话绑定门控与过期回调保护；尚未进行本次 UI 复验。后台创建写 active 的既有语义保持不变：

- **缓存命中可能漏激活**：桌面 `panel.dart` 的 `sessionState.sessionId == targetId && sessionState.isLoaded`，以及移动端 `novel_chat_page.dart` 的 `isLoaded` 分支，都在 `activateSession` 之前返回。若该会话仍驻留内存，界面可以打开它而数据库 active 仍指向另一会话。实施时将“用户选择后激活”与“是否重读消息”分开；双端覆盖 A → B → 已缓存 A，再重新进入恢复 A。
- **后台创建也会写 active**：`headless_session_turn.dart:startHeadlessRun` 调用 `createActiveSession(mode: chat)`，任务运行和远程入口都会走这里。所以当前 active 还可能是最近创建的后台聊天，不能将它解释为纯粹的“最后前台选择”。本轮记录这一现有语义，不擅自改变后台创建是否激活的产品行为；最近 updatedAt 回退同样无法解决这个问题。
- **激活入口校验不一致**：`createActiveSession` 排除带 parentId 的子会话，`activateSession` 只校验 mode，没有同样排除 parentId；持久化 active 的读取也仅返回字符串。不能以非 null 就断言是可恢复的顶层 chat。实施时统一持久化激活的顶层 chat 边界，按 ID 校验真实会话；失效指针与数据库读取失败分别处理，不以最近会话代替校验。
- **恢复回调存在覆盖风险**：面板的 null 恢复分支在异步读取后调用 `onSessionRestored`，该分支没有和指定 ID 分支等价的目标过期检查，父页面直接写本地选择。新增门控避免编辑器进入此分支，并检查仍使用该分支的调用方；这是代码路径风险，尚无本轮运行时复现结论。

回退的演变可以定位到四次提交：

| 提交 | 实际改动 |
| --- | --- |
| `a811e76a7`（2026-04-27，refactor: active session） | 引入 `pickPreferredAiChatSession`，当时只返回 status 为 active 的会话；没有 active 就返回 null，并非“选最近” |
| `b7cd277ce0`（2026-05-08，opt: chat sessions filter） | active 改存 novel_states；该 helper 改为过滤 chat 后选最近 updatedAt，服务的 `getPreferredSession` 则改为读真正的持久化 active；桌面已有 helper 调用仍保留 |
| `c35274a6b`（2026-05-24，refactor: chat agent v3 to prepare background） | 把已有的“本地 ID，否则 helper”提取到 `effectiveAiChatSessionId`，增加临时信号映射，并不是首次引入最近会话选择 |
| `1890ae7cc`（2026-05-25，fix: bind temporary chat sessions before send） | 桌面开始订阅持久化 active 并优先于 helper；新增 provider 的注释明确写着应恢复 active，而非回退最近更新的会话，但最终兜底仍保留 |

由 diff 可确认：最近会话回退是在 active 存储方式改变后沿用的默认选择策略，之后已有显式 active 优先的修正。未找到提交说明证明它用于修复 active 丢失或数据库读取不可靠，不把推测当作原始动机。当前需求明确要求空 active 开新对话，因此去掉入口的最近会话兜底，并补读取状态与激活准确性；删除当前会话后选择剩余会话的独立 helper 用法仍保留。

### 验证与交付

- 路径：平铺季／集／节拍／场次 listing 及各自支持的读写操作、elements 嵌套、字段原值和 query；旧 screenplay 子路径及 `/novel`、`/novel/title`、`/novel/description`、`/novel/current_state` 及其子路径明确失败，相对路径与带 work 前缀的旧路径同样被拒绝；小说章节、卷、大纲及其节拍、伏笔路径保持可用；profile、story_state 与 screenplay 概览仍正确。
- 类型与契约：双类型目录和常驻说明只包含支持的集合；显式错误类型被拒绝；schema 可跨类型查询且包含 hidden 契约；索引每项都有正确 group 和可读取的契约 path；group 聚合成员与索引一致，单集合内容与聚合中对应契约一致，shared 不混入专属组；scenes 包含 elements，screenplay 单集合与 screenplay 组分别返回概览契约和整组契约；未知名称、缺段、额外层级与写入被拒绝；同入口结果与工具定义不随当前作品变化；错误 hint 可以直接执行且 schema 不被加 work 前缀；全局查询不需要有效作品内容库。
- 搜索：从作品根和平铺集合执行 Glob／Grep／Replace；所有返回路径可 Read；跨作品只读、目标作品类型门禁、替换预览不写入、执行及撤回恢复原值；旧 screenplay 路径不能以搜索成功零命中蒙混通过。
- 审阅：AI 修改后接手动编辑，再次 AI 修改能按新路径合并；按新 scope 提交与撤回正确；元数据审阅使用 profile。不要为了测试旧记录继续增加兼容。
- 伏笔：索引中 group 为 shared，两个作品目录均可发现；小说章节和剧本场次关联可创建、更新、清空及回读，AI Write 的四个位置字段均生成独立 working change；同位置双引用、错误作品类型、不存在／已删除目标与卷 ID 均在写入前拒绝；混合正文与位置的 Write 后续失败时整批回滚；正文／状态独立审阅和撤回不改位置关联；位置字段可独立撤回至旧关联，清空与恢复均通过引用校验；场次换集后位置显示及跳转更新；目标删除后显示不可用；双端切换选择器和取消选择不丢文本；升级后旧章节引用保留、新场次列为 null。
- 初始化：小说／剧本多库、有 active、状态行不存在、data 为 null、无内容库路径、缺失文件、写入失败及重试；以 active 读取结果为 null 验证清空，不要求保留状态行；验证其他状态、历史会话和消息保留；完成标记只在全部成功后存在；成功后新 active 在下一次启动仍保留。
- 双端：首次升级进入新对话、首条消息落库并成为 active、重启恢复新 active、显式选择历史会话；桌面覆盖侧栏及展开聊天。延迟 active 读取分别返回 ID／null／错误，先返回 session 列表时不得先选最近会话；先返回 active 且 ID 不在列表首屏时仍按 ID 恢复；首次读取中不得自动发送或创建；刷新保留绑定和草稿；读取晚到不能覆盖用户显式选择；切换作品不沿用旧缓存；A → B → 已缓存 A 后持久化 active 应为 A；过期恢复回调不得回写旧选择。后台新建导致 active 改变的现有行为单独记录，不将其测试为“前台选择一直不变”。

以下为待核实运行结果的验收命令，须串行执行；初始化回归已放入列出的初始化测试目录：

```sh
fvm flutter test test/shared/services/ai/
fvm flutter test test/shared/services/working_overlay_test.dart test/shared/services/working_overlay_screenplay_test.dart test/shared/services/chapter_save_test.dart
fvm flutter test test/shared/services/app_initialization_test.dart test/shared/services/initialization/
fvm flutter test test/desktop/widgets/ai/tools/ --timeout 60s
fvm flutter analyze lib/shared/services/ai lib/shared/services/initialization lib/shared/services/app_initialization.dart
git diff --check
```

另对实际修改的共享／桌面／移动文件运行最窄静态分析及对应测试。上述是待执行清单，不代表通过；此前的 195／19 项测试结果不覆盖本次切换。不需要新增服务、外部账户或 API key，不运行真实 LLM E2E。

发布时路径切换、内置说明和会话重置必须一起进入版本。回滚代码不会恢复已清空的 active 指针，用户可从历史列表重新选择；新版本已生成的新路径记录也不会自动转回旧路径，不能将回滚描述成历史数据兼容。

<a id="screenplay-search"></a>

## 已交付：剧本 Glob／Grep／Replace 工具层

### 交付目标与范围

沿用三个现有工具及 `/works/{work_id}`，在 `tools_resource_search_support.dart` 增加剧本遍历分支，三者共用资源发现和文本读取。保持现有小说、共享资料、跨作品权限与返回计数的语义；不增加工具名、顶层参数、数据库字段或服务，也不改造正文模型及历史快照。

验收结果必须同时满足：Glob 返回的每个具体资源／字段路径都能 Read；Grep 能找到多季多集中的已知正文；Replace 的预览与执行使用相同可编辑目标，成功写入仍进入场次 working change。桌面和移动端共用这一工具层，两个入口都应能执行同样的调用。

### 可读取的文本路径

`_ResourceField.read` 表示字段出现在资源结果中，`readPath` 表示它能单独读取。本轮为集 `outline`、季／集标题、节拍标题／说明补齐 schema 标记与独立读取分支，搜索返回路径可直接回读。

已实现的字段能力如下：

| 资源字段 | 当前独立 Read | Glob／Grep 目标 | Replace |
| --- | --- | --- | --- |
| `seasons/{season_id}/title` | 已支持 | 支持 | 跳过；标题仍可通过 Write 修改 |
| `episodes/{episode_id}/title` | 已支持 | 支持 | 跳过；标题仍可通过 Write 修改 |
| `episodes/{episode_id}/outline` | 已支持 | 支持，读取大纲原文 | 跳过，只读 |
| `beats/{beat_id}/title`、`description` | 已支持 | 支持 | 跳过；仍可通过 Write 修改 |
| `scenes/{scene_id}/synopsis` | 已支持 | 支持 | 按现有 `edit: true` 支持 |
| `scenes/{scene_id}/elements/{element_id}/text` | 已支持 | 支持 action／parenthetical／dialogue／transition／subtitle／note 原文 | 按现有 `edit: true` 支持非 character 元素 |

表中路径均从作品根开始，如 `/scenes/{scene_id}/synopsis`；旧 `/screenplay/` 子路径已失效。遍历还返回真实的集合、资源、元素列表和已支持的 `cast` 路径；数组不当成正文字符串搜索。`time_label` 不新增独立字段路径，也不纳入本次文本搜索。编号、统计、外键、移动锚点、枚举，以及角色展示名与 extension 不进入本次文本搜索；角色资料继续走 `/characters`。不把整个资源 JSON 序列化后搜索，也不把展示名当成可替换正文。

沿用当前独立 character 与平级 dialogue／parenthetical，见 [元素模型](../../lib/shared/models/screenplay_element.dart)和[元素工具返回](../../lib/shared/services/ai/tools_screenplay.dart)。character 保存角色引用与 extension，其 text 为空；后续台词与括号提示按现有连续块规则归属角色。它们各自的 text 可直接读取，无须先合并模型才能搜索。

字段能力继续只写在原 schema 中：表中新增文本路径已标记 `readPath: true`，以 `read && readPath && type == string` 推导剧本可搜索文本，再以 `edit` 筛选 Replace。无需新建 `_screenplaySearchFields`／Replace 字段名单。character 元素是否具有正文由现有元素类型判断，其 `/text` 不进入遍历，显式搜索该路径也不计为可编辑正文；运行时数据不修改静态 tool schema。

`tools_screenplay.dart` 为新增字段返回对应原值；保留已有 synopsis／text 的同名键，新文本字段也使用同名键。`_readResourceString` 对匹配到的剧本字段取 `result[field]`，小说仍取 `result['value']`。字段 Read 不混入其他字段，不为搜索渲染场景标题或整集正文。

### 遍历范围与季集选择

搜索的范围来自 `path`／glob，不随编辑器当前季集变化。完整搜索在内部枚举真实季集，并向现有 listing Read 显式传入 ID；现有 Read 的当前选择规则保持原状。

| 搜索起点 | 遍历范围 |
| --- | --- |
| `/`，或只给 `**` 模式 | 当前目标作品所有可见资源；匹配剧本时覆盖全部季集，共享资料照常处理 |
| `/screenplay` | 只读概览，不展开季、集、节拍、场次或元素；全作品搜索从根开始 |
| `/seasons`、`episodes`、`beats`、`scenes` | 全作品对应集合；场次继续展开其元素，其他集合只展开自身资源与字段 |
| `/episodes?season_id=<id>` | 指定季内的集及集字段 |
| `/scenes?episode_id=<id>`、`beats?episode_id=<id>` | 指定集的对应资源；scenes 还可按既有 `beat_id`／`stage`／`search` 筛选 |
| `/scenes/{scene_id}` | 该场梗概、cast、元素列表与元素正文 |
| 其他单资源或单字段路径 | 只处理该资源的真实子路径；不隐式扩展到其他平级集合 |

例如只搜索某集正文，应传 `path: /scenes?episode_id=<id>`；`/episodes/{id}` 只包含集自身字段，不虚构 `/episodes/{id}/scenes` 路径。

具体遍历顺序：读取 seasons；逐季用 `season_id` 读 episodes；逐集用 `episode_id` 读 beats／scenes；逐场读 elements。内部利用父子关联找到资源，输出仍用 listing 的权威 `path`，不用标题重建，也不把季集关系拼进场次路径。只搜索场次时不读取无关集大纲，已知单场或单元素时直接定位。

query 与规范资源路径分开保存。query 只约束其所属 listing，并用该层 schema 校验，不带入后续字段路径或 glob 匹配；即使最后零命中，也不能忽略未知 query 或非法值。场次筛选缺少 `episode_id` 时，按全剧本逐集应用已给筛选，不回退当前集。显式错误 ID 必须报错，合法空季／空集正常返回零结果。

跨作品搜索先取得目标 lease 和类型，整次遍历只使用目标服务；源作品当前季集不参与。Glob 返回路径、Grep 展示路径只加一次目标前缀，正文中的行首 `/` 保持原样。`/works/*` 或多个目标作品仍拒绝；Replace 连同 dry run 继续拒绝其他作品路径。

### 共享实现与错误处理

```text
Glob / Grep / Replace
          |
          v
已有作品作用域检查 + 目标 content_kind 门禁
          |
          v
_collectResourcePaths
  现有小说／共享资源遍历 + 剧本季集遍历
          |
          +--> Glob：规范路径匹配与输出
          +--> Grep：schema 文本字段 -> 原值 -> 匹配与计数
          +--> Replace：同一文本集合 -> edit 权限 -> 预览／_applyEditToPath
```

1. `_readRawResource` 在类型门禁后接入 `handleScreenplayRead`；`_collectResourcePaths` 使用匹配到的子资源 schema，替换仅看顶层字段或 `id/title` 的假设。剧本概览不充当树 listing，也不按根 schema 的统计字段凭空生成 Read 不支持的路径。
2. `_looksLikeResourceFieldPath` 和 `_isReplaceTargetField` 使用 `ParsedPath._resource` 的最终字段契约；保留现有小说与大纲节拍逻辑。`hidden` 只影响常驻说明，不影响遍历。
3. 剧本 listing 读取失败立即返回带失败路径的结构化错误，不能吞成空数组。Grep／dry run 的文本读取失败也返回错误，不能跳过后声称完整扫描。Replace 实际执行时的读取或写入失败纳入既有 `failed` 分组。
4. Glob／Grep 沿用现有预算：路径收集 5000、Glob 输出 200、Grep 搜索文本 1000，以及既有匹配行上限；如触发则保留相应 `truncated` 指标。`scanned_paths` 记录规范路径访问数，`searched_files` 只计算实际读取并匹配的文本，去重后统计。
5. Replace 继续 `budget: null`，先完成路径发现再写入，不能套用 Grep 的 1000 字段上限。扫描失败时不开始写；实际应用按字段记录成功／失败，保留既有“部分成功”语义，不承诺整批事务回滚。
6. 每次元素替换都重新读取当前场次元素，再走现有 `_applyEditToPath`／`handleScreenplayEdit`。同场多个命中必须累积更新，不能把扫描时缓存的旧数组反复写回；元素 ID、类型、顺序、角色引用、extension 和 cast 均须保留。

只读文本在预览和执行中都进入既有 `skipped_fields.not_editable`，不进入匹配／替换计数。缺少 session 或存在跨会话 working change 冲突，仍由 Edit 返回对应错误并计入 `failed`。现有跨会话锁只保护整场 `elements`，`synopsis` 沿用独立字段权限；成功项继续保留来源会话、Replace 工具名和场次变更记录，支持现有撤回流程。

### 文件落点与交付顺序

| 文件 | 修改内容 |
| --- | --- |
| `lib/shared/services/ai/tools.dart` | 在原 `fieldSpecs` 中补表内文本字段的 `readPath`，保持写权限 |
| `lib/shared/services/ai/tools_screenplay.dart` | 补字段原值读取；复用现有季集解析、元素类型判断与 Edit 管线 |
| `lib/shared/services/ai/tools_resource_search_support.dart` | 剧本遍历、query 作用域、读取分发、字段识别、错误传播与去重 |
| `lib/shared/services/ai/tools_grep.dart` | 使用共享文本读取结果并传播读取错误，保留计数与输出格式 |
| `lib/shared/services/ai/tools_replace.dart` | 根据最终资源 schema 判断 edit 权限，读取失败纳入结果，沿用写入管线 |
| `lib/shared/services/ai/tools_glob.dart` | 补剧本路径示例；路径匹配与预算逻辑继续共用 |
| `assets/bundled_skills/screenplay-writing-guide.md` | 搜索交付后移除“暂不支持”，说明范围、可搜字段、可替换字段及实际调用 |
| `test/shared/services/ai/tools_screenplay_test.dart` | 把“剧本搜索未支持”断言换成实际能力验收，补原值、跨作品和权限用例 |
| `test/shared/services/ai/tools_replace_test.dart` | 补同场多元素更新、冲突、失败计数与撤回验证 |

搜索交付修改上述 9 个实现、指南和测试文件；随后修复 `assets/bundled_skills/setup/SKILL.md` 的旧路径，并补充 `test/shared/services/bundled_control_skills_test.dart` 的附件断言。另更新本文进度；未修改 `tools_support.dart`。不增加服务、外部依赖或账号，不需要网络调用或 migration。

本次已完整交付字段读取、遍历、Grep 和 Replace，移除搜索的 `unsupported_operation` 门禁并更新指南。本节记录当时的搜索交付；后续契约入口现采用前文 `/_schema/{collection}` 与 `/_schema/groups/{group}` 方案，已与剧本平铺一起实现。

### 验证与完成标准

- 多季多集 fixture 在当前选择为空、有效或不同的情况下得到同一全作品结果；指定 query、单场、单字段与 glob 时只命中指定范围，无重复路径。
- Glob 的每条具体资源／字段路径再 Read 成功；非空或同名标题、标题恰好为 `synopsis`／`text` 不影响 ID 寻址；新增文本字段返回原值。
- Grep 命中已知梗概、动作、台词、括号提示等文本元素和只读集大纲，覆盖三种输出模式、中文、换行与行首 `/`；角色展示名、extension 和 cast 不冒充正文。
- Replace 默认 dry run 不改数据或 working change；正式执行只改 synopsis 与非 character 元素的 text。只读大纲、标题和说明在两种模式中一致跳过。
- 同一场多元素、多场批量替换后，前面已改文本不丢失，元素 ID、顺序、角色引用与 extension 不变；失败项有准确计数和路径。检验缺少 session、跨会话冲突、元素在扫描后消失、正文格式校验失败与已有撤回流程。
- 不存在的季／集／场／元素、非法 query、内容类型不匹配和读取失败明确报错；合法空数据、真实无匹配、预算截断能区分。Replace 覆盖超过共享扫描预算的全部目标。
- 小说读剧本、剧本读剧本、剧本读小说和小说读小说均遵守目标类型；当前作品相对／绝对路径等价；外部 Replace dry run／执行均被拒绝。人物、小说章节、大纲节拍、画布回归保持通过。
- 固定工具定义在两种作品上下文一致；支持但 hidden 的集合仍可搜索其可读文本，详细字段说明不进入常驻 prompt。

以下为实际执行记录。联合测试时 8 组工具／prompt 回归 195 项通过，技能测试当时为 18 项通过、1 项失败；旧路径修复后单独复跑技能测试，19 项全部通过。修复后未重新联合执行全部 9 个测试文件，不能将两轮结果写成一次全套通过。静态分析仍有上文列出的 4 条既有诊断。

```sh
fvm flutter test --no-pub --concurrency=1 \
  test/shared/services/ai/tools_screenplay_test.dart \
  test/shared/services/ai/tools_glob_test.dart \
  test/shared/services/ai/tools_grep_test.dart \
  test/shared/services/ai/tools_replace_test.dart \
  test/shared/services/ai/tools_cross_work_test.dart \
  test/shared/services/ai/tools_outline_test.dart \
  test/shared/services/ai/tools_canvas_test.dart \
  test/shared/services/ai/chat_prompt_builder_test.dart \
  test/shared/services/bundled_control_skills_test.dart

fvm flutter test --no-pub --concurrency=1 \
  test/shared/services/bundled_control_skills_test.dart

fvm flutter analyze --no-pub lib/shared/services/ai/tools.dart \
  lib/shared/services/ai/tools_support.dart \
  lib/shared/services/ai/tools_screenplay.dart \
  lib/shared/services/ai/tools_resource_search_support.dart \
  lib/shared/services/ai/tools_glob.dart \
  lib/shared/services/ai/tools_grep.dart \
  lib/shared/services/ai/tools_replace.dart \
  test/shared/services/ai/tools_screenplay_test.dart \
  test/shared/services/ai/tools_replace_test.dart
```

桌面和移动端手工验收分别在剧本聊天中确认：多集搜索、单集过滤、Replace 预览无写入、执行后编辑器显示变更，以及撤回恢复原文。真实 LLM E2E 需用户另行明确要求；工具回归通过不能代替模型行为与 UI 验证。

回滚只涉及本次工具代码、指南及新增只读字段路径，保留先前的类型门禁与明确未支持错误。功能上线后新增路径可能被保存的技能引用，应按公开契约处理，不能随意删除；已经执行的正文替换使用现有 working change 撤回，不因回退代码自动恢复数据。

## 初审记录（2026-09-08，以下为历史快照）

初审基线为 `0f955d0d4`，重点检查 `65b2a9bf7`（跨作品读取）、`74b71eee2`（剧本桌面与移动端）及其调用链。当时发现错误路径、假空搜索、跨作品上下文串用和读取内容变形。下文的“当前”“尚未”“建议”均指初审时点，实施状态以本文开头为准。

保留统一的 Read / Glob / Grep / Create / Write / Edit / Replace / Remove，以及 `/works/{work_id}` 的方向继续适用。作品身份决定操作哪份数据，`content_kind` 决定支持哪些资源，能力契约决定每条路径能做什么。

初审未修改产品代码或业务数据。当时工作区还有剧本 UI 编辑，关键证据来自共享工具与 prompt 文件。

## 已经做对的部分值得保留

跨作品读取不是临时切换全局数据库。`tools_cross_work.dart` 使用按调用隔离的 Zone 保存目标 lease；Read、Glob、Grep 和 GraphSearch 可以借用目标作品的内容服务。写工具会先检查作品作用域，其他作品的绝对路径返回 `cross_work_write_denied`，当前作品的绝对路径则归一化后执行。已有测试也覆盖了作用域冲突、借用和释放。这套结构可以继续使用。

`content_kind` 已经是明确的作品字段，值为 `novel` / `screenplay`。它与原创、续作、同人、资料等作品性质不是同一个维度；后者不能用来决定正文路径。当前剧本领域的 kind / format 又是更内层的概念，目前是 `series` / `asian`，不应和作品内容类型混为一谈。

主聊天的适配有实质内容：

- `orchestrator.md` 会在剧本工作区切换写作手艺和阅读边界，要求加载「剧本写作指南」，直接写入场次。
- `ChatPromptUseCase` 不在剧本中触发小说初始化，且从主聊天的 subagent 索引隐藏 writer、review、style_polish、chronicler。
- `ChatTurnRunner` 的 bundled fallback 在剧本中跳过「创作向导」，在小说中跳过「剧本写作指南」。
- 剧本指南清楚区分集大纲、节拍和场次，使用结构化正文，要求角色与地点在目标作品重新建档。
- Read / Create / Write / Edit / Remove 的正常入口有内容类型门禁。正文变更进入场次级 working change，并有跨会话冲突保护。
- 跨剧本的多季选择已经单独处理：不会使用源工作区的当前季；多季目标要求提供 `season_id`。

这些设计说明方向正确。问题主要出在剧本作为新层级资源接入通用工具时，通用层仍沿用旧的名称文档和章节假设。

主要依据：[tools_cross_work.dart](../../lib/shared/services/ai/tools_cross_work.dart)、[tools_screenplay.dart](../../lib/shared/services/ai/tools_screenplay.dart)、[chat_prompt_use_case.dart](../../lib/shared/services/ai/prompts/use_cases/chat_prompt_use_case.dart)、[chat_turn_runner.dart](../../lib/shared/services/ai/chat_turn_runner.dart)。

## 先修会直接破坏调用链的路径问题

2026-09-09 状态：本节三项已修复，并已加入正式回归；以下保留原始原因与复现过程。

### 返回的权威路径并不可靠

`_collectionSchemas['screenplay']` 使用 `usesNamePath: true`，把季、集、节拍、场次和元素的字段放在同一个集合里。实际剧本却按 ID 寻址。剧本 handler 手工拆完整路径，所以部分 Read 可以成功，但通用响应层仍会把它当作标题文档处理。

有两种已复现的后果：

1. `_seasonJson`、`_episodeJson`、`_beatSummaryJson` 已返回正确的 ID 路径，随后 `_attachListingEntryPath` 又按 `title` 重建。季标题为“第一季标题”时，listing 返回 `/screenplay/seasons/第一季标题`，而不是 `/screenplay/seasons/{season_id}`。标题非空的集和节拍存在同样的代码路径；标题为空时不改写，因此容易在默认空标题数据下漏测。
2. Read `screenplay/scenes/{id}/synopsis` 返回 `{synopsis: ...}`，没有通用字段读取所用的 `value`。`_classifyReadResult` 把它判为普通资源，`_resourceDisplayPath` 删除末段，最终 `path` 丢失 `/synopsis`。单元素 `/text` 读取也落入同类逻辑。

系统提示同时要求“直接使用工具返回的权威 path”。模型完全遵循提示也会走错。这是优先级最高的问题之一。

最小修复是像现有 canvas 分支一样，为剧本提供明确的响应路径处理：保留 handler 已生成的 ID 路径，字段读取保留完整字段路径，元素条目补齐可复制的自身路径。后续应让通用层直接理解剧本的嵌套资源结构，不能长期依赖名称文档标志来代理 ID 层级。

依据：[tools.dart](../../lib/shared/services/ai/tools.dart#L760)、[tools_support.dart](../../lib/shared/services/ai/tools_support.dart#L2041)、[tools_screenplay.dart](../../lib/shared/services/ai/tools_screenplay.dart#L1425)。

### 跨作品读取会改写正文中的行首斜杠

`_transformWorkValue` 递归遍历整个返回对象，遇到键名 `text` 就把每行开头的 `/` 替换成 `/works/{work_id}/`。这原本可以修饰 Grep 格式化输出中的路径，但剧本元素也使用 `text` 保存正文。

已复现：源元素为两行 `/灯光熄灭`、`/幕落`，跨作品 Read 后变成 `/works/target/灯光熄灭`、`/works/target/幕落`。本次没有改坏源数据库；改坏的是模型读到的内容。后续引用、对照和精确 Edit 都可能基于错误文本执行。

修复应限定改写对象：Read 的正文、字段原值和业务 JSON 不做递归字符串变换；只改写响应契约明确声明的路径字段。Grep 在组装结果时对命中的路径列加作品前缀，再生成展示文本。不要按键名 `text` 或字符串以 `/` 开头来推断它是不是地址。

依据：[tools_cross_work.dart](../../lib/shared/services/ai/tools_cross_work.dart#L689)。这也违反了项目 `tools_path.md` 的字段原值要求。

### 当前季隔离了，当前集没有隔离

`_resolveSeason` 会判断是否读取其他作品；`_readBeats` 和 `_readScenes` 却直接使用 `query['episode_id'] ?? currentEpisodeId`。

已复现：在剧本 A 当前集存在时，Read `/works/B/screenplay/scenes` 将 A 的集 ID 带入 B 的数据库，返回空 listing、`has_more: false`，而不是要求选择 B 的集。这并不意味着读取到了 A 的正文，却足以让模型误判 B 没有场次。复制内容库后存在相同 ID 时，还可能命中 B 中并非用户意图的集。

应统一当前季、当前集的默认作用域：只有目标 `work_id` 等于当前作品时，才允许使用当前工作区的冻结选择。读取其他作品的 scenes / beats 时必须显式提供 `episode_id`；缺少就返回 `episode_id_required`。显式 ID 还要先确认资源在目标作品中存在，区分“合法空集”和“集不存在”。

错误提示必须给目标作品内的修复路径。当前 `_resolveSeason` 的 hint 是相对的 `Read screenplay/seasons`，跨作品改写函数又没有覆盖 `screenplay` 根，照抄提示容易回到当前作品。可以返回一个明确的目标 `path` / `hint`，无需恢复整套 `_links`。

依据：[tools_screenplay.dart](../../lib/shared/services/ai/tools_screenplay.dart#L383)、[tools_screenplay.dart](../../lib/shared/services/ai/tools_screenplay.dart#L1173)、[tools_cross_work.dart](../../lib/shared/services/ai/tools_cross_work.dart#L765)。

## 通用搜索尚未接通剧本，而且与 Read 的门禁不同

2026-09-09 状态：搜索门禁、完整剧本遍历和 Glob／Grep／Replace 工具层均已完成。旧联合字段表已拆分，下文对此表和假空搜索的描述仅指初审代码；最新交付与验证结果见本文开头。

Read 的剧本分支直接调用 `handleScreenplayRead`。Glob / Grep 的 `_readRawResource` 则直接找 `_handlerForParsedPath`，后者的 handler 表没有 `screenplay`。

已复现：创建一个包含特定梗概的场次后，对 `path: screenplay` 执行 Grep，得到 `ok: true`、`No results found.`、`searched_files: 0`、`truncated: false`。这不是“搜索过但没找到”，而是没有搜索正文资源。跨作品只换了数据作用域，不能补上这个遍历缺口。

仅把 `_readRawResource` 改成能调剧本 Read 还不够：

- `Read screenplay` 返回统计概览，没有可供遍历的季、集、场次树。
- 通用 listing 遍历认为条目标识是 `id` 或 `title`，剧本返回 `season_id`、`episode_id`、`scene_id` 等。
- 当前字段表将多个层级的字段混在一起，不能据此给每个场次生成所有字段路径。
- `_readResourceString` 只接受 `value` 字符串，剧本当前的 synopsis / text 读取形状不同。
- `_looksLikeResourceFieldPath` 不足以表达哪些路径是可搜索文本叶子。

另一个已复现的问题是内容类型门禁被搜索绕过。纯内存库中保留一条章节，在 screenplay manager 上 Read chapters 被拒绝，Grep chapters 却能搜到章节正文。这里用残留章节构造的是隔离边界用例，**并非断言新建剧本默认带有章节，也不是发现了跨作品写入漏洞**。但它证明“Read 不可见的内容”仍可能被搜索返回。

Replace 复用同一遍历器，也不能可靠批量替换剧本文本。它最终调用 Edit 时仍有类型门禁，因此不能据此宣称已经绕过写入保护；问题在于扫描、dry run 和实际修改的能力不一致。

最小可独立交付的修复：先统一搜索入口门禁，并对暂未接通的剧本搜索返回明确的 `unsupported_operation`，禁止用成功空结果代替。完整修复则为剧本增加按季、集、场次遍历的支持，枚举到 synopsis、集大纲以及非 character 元素的 text；Grep 与 Replace 共用合法文本叶子定义，但 Replace 进一步检查可写权限，不能替换只读大纲。

依据：[tools_resource_search_support.dart](../../lib/shared/services/ai/tools_resource_search_support.dart#L62)、[tools.dart](../../lib/shared/services/ai/tools.dart#L2071)、[tools_replace.dart](../../lib/shared/services/ai/tools_replace.dart#L126)。

## 写入与 query 的契约仍然过于宽泛

2026-09-09 状态：本节问题已修复。最终规则已统一到分层 schema，`_screenplayCreateSpecs` 与后续短期使用的 Write 独立白名单均已删除，不再作为实现基础。

剧本 Create 已有按资源区分的 `_screenplayCreateSpecs`，能一次报告缺字段、互斥参数、非法枚举和未知字段。这部分比 Write 完整，应作为后续扩展的基础。

Write 的多个分支只挑自己认识的字段执行，没有统一检查未消费的字段。已复现：给场次传 `fields: {title: "不支持的标题"}`，返回 `ok: true`，没有 `ignored_fields`，也没有失败信息。工具通用说明却承诺被忽略的字段会出现在返回值里。

集大纲尤其容易踩中这个问题：单集 Read 会返回 `outline`，指南明确它只读，但 Write episodes 分支没有专门拒绝 `outline`，只更新标题、时长、编号和季等字段。代码路径表明，模型尝试写大纲可能收到成功响应，却没有完成目标。这里是静态调用链结论，未另加集大纲运行用例。

另外，`_screenplayWriteFields` 优先选 `fields`，通用 Write schema 却写着单字段 `value` 优先。正常只传一种不会触发，但同时出现时存在契约冲突。

Read query 也按整个 `screenplay` 集合的联合字段放行，具体 handler 只使用其中一部分。例如 seasons listing 接受 `search` 后没有应用筛选；episodes 不处理 `search`；scenes 才处理 search / beat_id / stage。错误条件被接受后，模型可能误以为拿到的是过滤后的结果。

建议按资源与操作声明四类内容：可读字段、可写字段、创建字段、listing query。校验必须在任何业务写入前完成。对剧本无效字段返回明确错误和该路径契约；只读字段返回 `read_only_field`，无匹配路径返回 `invalid_path`。若保留部分更新语义，则必须列出成功与忽略字段，且全被忽略时不能报无条件成功。

`episode_number` 目前实际可以通过 Write 更新，而指南笼统禁止提交“派生编号”。应明确区分可修改的集编号和只读的季号、场号；不能只靠“编号”这个中文类别推导权限。

依据：[tools_screenplay.dart](../../lib/shared/services/ai/tools_screenplay.dart#L684)、[tools_screenplay.dart](../../lib/shared/services/ai/tools_screenplay.dart#L1349)、[tools_write.dart](../../lib/shared/services/ai/tools_write.dart#L11)、[tools_read.dart](../../lib/shared/services/ai/tools_read.dart#L472)。

## 内置 skill：剧本指南基本可用，共享指南存在实质冲突

2026-09-09 状态：剧本指南已同步 Write／query 与当前搜索边界；原独立关系指南已合并进「故事连续性维护」的 `references/relations.md`，章节／场次证据规则已修正。表内其余技能建议仍作为后续事项。

| 内置能力 | 当前判断 | 应如何处理 |
| --- | --- | --- |
| 剧本写作指南 | 季、集、节拍、场次和元素的写作流程较完整，改编时要求重新建立当前作品实体也正确 | 保留；补 Write 权限、元素 text 精确路径、跨作品集选择、搜索能力边界及读取后的正文结构映射 |
| 创作向导及 original / sequel / fanfic / imitation 附件 | 明确是小说流程，包含章节字数、分卷和大纲轨道；默认剧本已隐藏 | 保持小说专用；不要把“章”机械替换成“场”来复用 |
| 关系图谱指南 | 仍要求每条关系必须有 chapter_id，漏掉 scene_id 和场次过滤 | 立即同步；这是剧本中仍可加载的共享能力 |
| 画布构图指南 | 人物、地点和普通便签可复用；引用资源类型仍是章节、伏笔等，没有 episode / scene | 明示能力边界；当前可做人物关系和自由便签，不能承诺场次引用或自动剧本时间线 |
| 图像生成工具指南 | 人物头像、照片、物品图片基于共享实体，没有明显章节正文依赖 | 保留共享；强调引用 ID 属于当前作品 |
| 创作工具管理及附件 | 管理工具可共享，但创建 skill / subagent 的例子主要是章节任务 | 增加内容类型与适用任务边界的写作指导，避免生成全局可见却只懂小说的能力 |

关系图谱的实际实现已经接受可选 `chapter_id` / `scene_id`，两者互斥，并支持 `/relations?scene_id=...`。指南“七个字段全部必填”“未写正文时填计划章节”的指令已过时。应按以下实际边界描述：已有章节证据填 chapter_id，已有场次证据填 scene_id，纯设定可以不填两者，但保留 proof。不存在的未来场次不能靠造 ID 挂证据。

同时区分“场次是关系证据”与“场次是图谱实体”。当前 `entityTypes` 和 `canvasNodeRefTypes` 没有 scene / episode；新增 `scene_id` 不等于 GraphSearch 和画布自动支持场次作为实体端点。后者涉及实体解析与 UI 导航，不能仅改 skill 宣称已支持。

还有一处容易被忽略：bundled 过滤只发生在 fallback。已经全局安装的同名「创作向导」或其他小说写作技能仍从 `executable` 列表进入剧本；不能把“默认隐藏了内置向导”理解成“安装的所有技能都按类型隔离了”。用户自定义能力不应仅因名称相同被重新分类或改写，类型未知时应在指令里说明适用边界，最终仍靠工具门禁保护数据。

对于跨作品能力，setup 主技能已修改作用域描述，但 sequel / fanfic / imitation 附件仍主要沿已有工作区资料展开，未完整讲清 `/works` 来源发现。后续可以补充“先定位用户指定原作，再读取必要证据”，不把新工具变成默认扫描其他作品的理由。

依据：旧 `screenplay-writing-guide.md` 已移除，现行操作说明见[剧本工具使用规范](../../assets/bundled_skills/screenplay-tool-guide.md)；其余依据为[关系指南现位置](../../assets/bundled_skills/story-continuity/references/relations.md)、[canvas-composition-guide.md](../../assets/bundled_skills/canvas-composition-guide.md#L47)、[setup/SKILL.md](../../assets/bundled_skills/setup/SKILL.md)、[entity_relations_service.dart](../../lib/shared/services/entity_relations_service.dart#L157)、[novel_content_database.dart](../../lib/shared/database/novel_content_database.dart#L167)。

## 初审记录：Agent 类型限制（已被任务驱动方案替代）

2026-09-10 决定：下文关于限制小说专家、按入口扩展限制、按作品类型增加两套专家创作规则的建议已撤销。当前代码仍有旧门禁；下一批按前文「SubAgent 任务驱动与作品上下文」精简职责、移除门禁，并向所有 SubAgent 注入当前类型、当前作品根与原作工作路径。以下保留初审原因，不作为实施要求。

2026-09-09 状态：主聊天索引、Spawn 和续用已共用适用策略，chronicler 已支持剧本；原建议“限制四个内置 agent”已调整为仅限制 writer／review／style_polish。特殊模式的路径说明已传入作品类型；通用正文底线、persona 内容及后台入口的缺口仍待处理。

主聊天隐藏四个小说 subagent 是合理的一期取舍：writer 专注网文章节，review 的检查维度包含章节、POV、断章和纯文本，style_polish 要求直接输出纯文本，chronicler 则写章节 brief / events / tension / emotion 及章节水位快照。它们不适合直接拿来处理结构化剧本。

但过滤目前位于 `ChatPromptUseCase` 的索引渲染；`ChatTurnRunner` 传给 `SpawnAgentHandler` 的仍是原始 availableSubAgents。后者按 enabled 和 name 找对象，没有同样的内容类型判定。历史对话中的名称或其他入口仍可能让模型调用到被索引隐藏的能力。该结论来自代码审查，未执行真实子模型。

建议使用同一份内置能力适用策略，同时服务于索引、实际 Spawn、续用子会话。对上述四个内置 agent，第一步继续限制为小说；请求不匹配时明确报错，不启动子模型。用户自定义 prompt 的行为另行保持，不按自定义名称猜类型。

主 orchestrator 还无条件注入 `fragment_prose_quality_baseline`，其中明确要求“每章每项最多一次”和“单章次数上限”。剧本分支换掉了 writing craft，却没有换掉这个计量单位。通用的正文纯净、标点、反套话原则可以保留；按章计数的规定应留在小说分支，剧本使用基于场景目的、可拍动作与人物声音的规则。

六个 Council persona 的核心分析能力有复用价值，但尚未统一适配：剧情、人物、冲突与主题可保留通用部分；pacing_expert 的每章字数、300/500/1000 密度法、80/20 断章和手机段落长度明显是网文规则，不能原样用于剧本。world_builder 的“首次出现章节”等也应随证据类型调整。

另有几条入口不应被主聊天通过的测试遮蔽：

- 此项已修复：`ModePromptUseCase` 的 council 和 `_appendPathSchema` 现调用 `pathSchemaBlock(kind: contentKind)`，Council / Theater / Roleplay / Monologue 调用方已传递类型；persona 内容适配仍待检查。
- `headless_session_turn.dart` 构造 `AiSessionContext` 时只传 databasePath 和 novelName，省略 contentKind。它虽然持有 Novel，仍可能以小说默认上下文处理剧本。
- Dreaming 的 ToolManager 没传 contentKind；调度器查询作品时也没有按内容类型排除剧本。后台入口存在类型丢失风险。
- `assistant.md` 是远程轻量助手，配套工具为 list_chapters / share_chapter_review 等章节能力。其剧本远程审稿能力尚未接通，不能因为主聊天支持剧本就宣称这一入口也支持。

这些是具体构造点与契约缺口。未做远程助手、后台任务或特殊模式的真实模型端到端验证，报告不把它们描述成已复现的用户故障。桌面和移动主聊天均已传递 contentKind / 当前季 / 当前集；上述共享层修复应同时覆盖两端。

依据：[spawn_agent_handler.dart](../../lib/shared/services/ai/spawn_agent_handler.dart#L440)、[chat_turn_runner.dart](../../lib/shared/services/ai/chat_turn_runner.dart#L1528)、[orchestrator.md](../../assets/prompts/agent/orchestrator.md)、[prose_quality_baseline.md](../../assets/prompts/fragments/prose_quality_baseline.md)、[mode_prompt_use_case.dart](../../lib/shared/services/ai/prompts/use_cases/mode_prompt_use_case.dart)、[headless_session_turn.dart](../../lib/shared/services/ai/headless_session_turn.dart#L261)。

## 初审判断：story_state 依赖章节（此限制已移除）

2026-09-09 状态：用户已选择移除 `source_chapter_id`，通过快照正文记录覆盖范围，小说与剧本共用 `story_state`；chronicler 与连续性 skill 已同步。本节“暂时限定为小说”和“剧本快照另做领域设计”的旧建议已撤销。自动判定场次重排后的状态新鲜度不属于当前实现。

`_sharedWorkCollections` 包含 story_state，剧本的字段字典因此仍展示 `source_chapter_id`。实际 `_writeStoryState` 要求这个字段，并确认它指向当前内容库的真实章节。

这意味着剧本 agent 看见“共享状态快照”后，不能用场次生成合法的新快照。characters 中的 `first_appear_chapter_id` 也有同样的章节专属语义。共享实体并不意味着实体的每个字段都适合所有内容类型。

建议当前先把 story_state 明确限定为小说，并在剧本字段说明和执行校验中排除章节专属字段。保留已有数据，不做自动清理，也不要为绕过约束创建虚假章节。

剧本若要支持完整写后连续性提取，应另做明确的领域设计：来源场次或集、跨季集的顺序、插场和重排后的新鲜度、删除证据后的状态失效。这涉及持久化与业务语义，不能在本次工具修整中偷偷加一个 metadata.source_scene_id，也不应把 scene_id 塞进 source_chapter_id。关系的 scene_id 可以继续使用，它已经有明确列和校验。

依据：[tools_screenplay.dart](../../lib/shared/services/ai/tools_screenplay.dart#L22)、[tools.dart](../../lib/shared/services/ai/tools.dart#L367)、[tools_write.dart](../../lib/shared/services/ai/tools_write.dart#L532)。

## 推荐的路径方案：统一作用域，分别声明资源能力

2026-09-09 状态：本节的剧本分层静态 schema 已完成，独立 Create spec 已迁入；搜索改用前文的具体实施方案。按需契约入口已随 `190457c43` 实现，采用前文 `/_schema/{collection}` 与 `/_schema/groups/{group}` 方案；下文初审建议不作为当前契约。

不建议增加 ReadNovel / ReadScreenplay / WriteScene 等两套平行 CRUD，也不建议把小说章节别名成剧本场次。这会扩大工具表，复制跨作品权限判断，并模糊正文字符串与元素数组的差别。

最新决定保留根级小说路径，平铺剧本子资源，配合类型过滤、hint、`/_schema/{collection}` 和 `/_schema/groups/{group}`；详见前文“剧本平铺、类型过滤与按需契约”。此前新增 `/novel` 的方向已取消，不保留旧剧本子路径兼容或历史路径迁移。

建议把现有链路整理成下面的单向流程，沿用 ToolManager、lease 和业务 Service，不另造服务框架：

```text
Read / Glob / Grep / Create / Write / Edit / Replace / Remove
                         |
                         v
            解析路径与作品作用域（单次一个 work_id）
                         |
                         v
       读取目标类型，检查操作权限和适用资源/字段
                         |
                         v
      静态资源契约 -> 对应读取/遍历/写入实现 -> 业务 Service
                         |
                         v
          响应封装（准确 path，正文值保持原样）

同一份静态资源契约 -> 当前工作区路径说明 / 按需契约 / 错误提示
```

静态资源契约需要表达的是路径结构与操作能力，而非再增加一套完整 JSON Schema 框架。扩展现有 `_CollectionSchema` / `_SubSchema` 和剧本 Create spec，逐项记录：

- 对应路径模板和 ID 字段；名称寻址仅用于真正的名称文档。
- 支持的 content_kind、允许操作、只读字段和可搜索文本叶子。
- Create / Write 各自允许的字段、必需项、枚举、类型和互斥约束。
- listing 可接受的 query、排序和父资源要求。
- handler 负责的子资源遍历方式。

剧本至少分出 season、episode、beat、scene、element 五类，而不是给它们共用所有字段。Read、错误契约、路径说明和搜索均消费这份声明。Create 已有的校验应迁入或复用，避免“新增一个统一表，旧手写表继续决定行为”。

修复搜索时不必顺带改掉所有既有 Read 返回键。现有小说字段使用 `value`，剧本 synopsis / text 使用同名键，先由对应资源的文本读取适配器提取原值，供 Grep / Replace 使用。契约必须明确每种形状；不要靠扫描所有字符串字段或序列化整个对象代替正文读取。元素 Read 中的 name 等展示字段也不能被原封不动送回 Write，指南应给出明确的可写字段投影。

作品身份仍从明确的 workId / contentKind 取值。`CrossWorkDescriptor` 里的内容类型当前来自 Novel.contentKind，再放进返回用的 Map；可以在内部 descriptor 上增加类型化属性，避免读目标时因缺失或非法类型退回当前作品类型。这无需新增数据库字段。目标类型不可判定时应报错，不能猜测。

### 跨类型读取需要一个按需、静态的契约入口

初审提出过按作品类型查询 `/schema/novel` 和 `/schema/screenplay`。该旧入口未实现；当前已实现前文确认的 `/_schema/{collection}` 与 `/_schema/groups/{group}`、平铺资源及类型过滤方案，不提供 `/schema` 别名。

仍需解决的问题是：当前 prompt 只讲当前类型路径，另一类型被过滤；Read `/works` 的 `content_kind` 和目标根的集合名称不足以说明字段、query 与子资源。全局按需契约提供这部分知识，跨类型读取无需加载会指示模型执行写作流程的完整 AgentSkill。契约从静态资源声明生成，查询不会改变当前作品的类型或写入权限。

### 模型实际应如何跨作品读

以“把小说 A 的第 3 章改编为当前剧本 B 的某一场”为例：

1. 当前工作区 B 始终是写入目标，不因读取 A 改变。
2. Read `/works`，按用户指定对象定位 A，保存返回的 work_id、content_kind 和 path。发现入口当前排除当前作品，这是合理的“其他作品”列表。
3. 不熟悉小说资源时 Read `/_schema/groups/novel`；只需章节契约时 Read `/_schema/chapters`；不知道有哪些集合时 Read `/_schema`，按条目的 group 发现。随后使用 `/works/A/chapters?chapter_num=3` 找到真实章节路径，再读取正文和相关设定；不遍历未请求的作品。
4. 区分原著事实、改编选择和 B 已确认的设定。不要把原著 agent rules 当成 B 的用户规则。
5. 在 B 的 characters / locations 中寻找或新建需要的实体。A 的角色 ID 不能作为 B 场次的 cast、character_id、location_id。
6. 用 B 的集、节拍和相邻场次确定写入位置，加载 B 的剧本写作流程，写入 B 的结构化元素。
7. 交付时能指出来源作品和原著章节，以及目标剧本场次。跨作品来源引用不要求扩展成跨库实体外键。

反方向“在小说中研究剧本 A 第二季第三集”也遵循同样顺序：目标 type 来自 A；显式选择 A 的 season 和 episode；Read A 的大纲、节拍、场次和元素；最后如需写作，仍写当前小说章节。

自然语言编号发现可在后续为各 listing 补充 `season_number` / `episode_number` / `scene_number` 等精确 query。当前并不支持这些 query，短期必须读取对应 listing 后选真实 ID。编号只服务定位，不能替代稳定路径 ID。

## 如何收敛实施范围

2026-09-10 决定：本节为历史交付划分。下一批采用前文「SubAgent 任务驱动与作品上下文」；不再扩展专家类型门禁，也不再增加小说／剧本两套 persona。Dreaming 独立收尾。涉及默认描述的一次性更新与回滚边界以新方案为准。

2026-09-09 状态：以下为原交付划分；“无需数据库 migration”不适用于前文新增伏笔场次字段。搜索工具层已完成，契约入口已采用前文 `/_schema/{collection}` 与 `/_schema/groups/{group}` 方案实现。第一项的路径、校验、schema、关系与主聊天 subagent 限制已完成，正文底线仍待改；`story_state` 已另行完成并包含 schema 变更，不能再将其列为未支持。下文“无需 migration”只适用于当时提出的工具修整，不覆盖后来已完成的快照字段移除。

完整建议涉及超过 8 个文件，主要横跨工具与路径共享层、prompt 组装、内置技能以及测试。不需要新增运行服务、第三方依赖、外部账号、后端 API 或数据库 migration。建议按三个可独立合并的交付处理。

主要修改落点：`tools.dart` / `tools_support.dart` 管声明、解析和结果路径；`tools_screenplay.dart` 管层级选择、路径校验和剧本操作；`tools_cross_work.dart` 管作用域及结果前缀；`tools_resource_search_support.dart` 管遍历与文本读取。能力适用策略由 `chat_prompt_use_case.dart`、`chat_turn_runner.dart`、`spawn_agent_handler.dart` 共用；创作行为落在对应 agent / fragment / bundled skill。现有四组测试加上搜索与 Spawn 的测试承担回归，无需为审查另建长期测试框架。

**第一项先让现有剧本入口可信。** 修复权威路径、字段路径与原值；隔离跨作品集默认值；统一搜索门禁，对未支持的剧本搜索明确报错；为 Write / query 补路径级校验；同步关系 skill、小说专属字段与 prose baseline；让四个小说内置 subagent 的索引和实际执行限制一致。新建 `/schema` 和全文搜索尚未完成，也不影响这一项成立。

**第二项补齐搜索和静态契约发现。** 扩展已有资源声明与遍历支持，连通剧本 Glob / Grep。Replace 只支持声明为可 Edit 的文本叶子，先 dry run，结构化角色块继续走元素工具。再把同源声明暴露为 `/schema`，当前 prompt 和跨作品引导都从这里取契约事实。此处为原交付划分；后续采用剧本平铺及 `/_schema/{collection}`、`/_schema/groups/{group}`，按前文新方案执行。

**第三项处理主聊天之外的入口。** 为 headless、Dreaming 和特殊模式显式传递作品上下文；复用当前已有的类型信息，避免默认成 novel。特殊 persona 加小说 / 剧本分支。若要支持远程审稿，应作为有独立验收的产品扩展，不随工具修整默认为已提供。

剧本 story_state、场次图谱实体、场次画布引用、独立剧本 writer / reviewer，以及可持久化的原著到改编实体映射，都不进入上述修整。这些新增能力有各自的领域语义，不能为了“看起来完全适配”顺带引入。第一期主 Agent 完成剧本写作的选择可以继续保留。

回滚以代码和 bundled prompt 为单位，不需要处理业务数据。新增 `/schema` 的公开路径上线后，应考虑已保存技能对它的引用，不能随意删除；关闭创作扩展也不应删除已创建的作品内容。任何后续状态快照或实体映射改动都需另按数据库规则评审。

这套方案最关键的前提是“一次工具调用只有一个明确目标作品，写入只允许当前作品”。若未来需要一次调用跨多个作品搜索或直接把外部资源写回源作品，应另设计作用域与权限契约，不要让 glob 中的 work_id 通配符悄悄突破当前边界。

## 初审验证与后续验收

以下命令与结果均为 2026-09-08 初审记录，本次文档更新未复跑。初审时已串行运行：

```sh
fvm flutter test --concurrency=1 \
  test/shared/services/ai/tools_screenplay_test.dart \
  test/shared/services/ai/tools_cross_work_test.dart \
  test/shared/services/ai/chat_prompt_builder_test.dart \
  test/shared/services/bundled_control_skills_test.dart
```

结果：**60 项通过**。这些测试证明已有功能的基线可用，不代表本文提出的边界已经通过。

另外，以现有 screenplay test 的纯内存 fixture 添加临时审查用例，串行运行：

```sh
fvm flutter test --concurrency=1 \
  test/shared/services/ai/tools_screenplay_audit_probe_test.dart \
  --plain-name AUDIT
```

结果：**7 项断言失败，全部对应预期正确行为与当前实现之间的差异**，没有产品修复后复测：

| 用例 | 预期正确行为 | 实际结果 |
| --- | --- | --- |
| 季 listing 保留 ID 路径 | `/screenplay/seasons/{真实 ID}` | 被非空 title 替换 |
| synopsis Read 的路径 | 保留 `/synopsis` | 末段消失 |
| 跨作品未指定集 | `episode_id_required` | 使用当前集 ID，返回空 listing |
| 跨作品元素原值 | 两行 `/灯光熄灭`、`/幕落` 原样返回 | 两行都多出 `/works/target/` |
| 剧本 Grep | 搜索已创建场次的特定梗概 | `searched_files: 0`，成功空结果 |
| 搜索类型门禁 | 和 Read 一样拒绝剧本库的 chapters 路径 | 搜到了构造的残留章节正文 |
| 场次 Write 不支持的 title | 明确失败或报告未生效字段 | `ok: true`，无提示 |

临时测试已从仓库移除。本机留有 `/tmp/reveric-screenplay-audit-probe-test.dart`、`/tmp/reveric-screenplay-audit-probes.log` 和 `/tmp/reveric-screenplay-audit-baseline.log`。源文件保留了原 fixture 的相对 import，如需在本机重跑，应复制回上述临时 test 路径；这些临时文件不是长期测试交付物。多内存数据库用例出现 Drift 的多实例提示，实际使用独立 executor；七项失败均为表中业务断言，不是初始化异常。

后续正式回归应把这些用例收进已有测试，并重点验证以下边界：

- 小说读小说、小说读剧本、剧本读小说、剧本读剧本四种组合；当前作品绝对路径与相对路径行为一致。
- 相同标题、标题恰好等于字段名、空标题、同名不同作品、删除的父资源和无效 ID。返回 path 再 Read 必须指向同一资源。
- 多季、多集以及当前季集存在 / 不存在；跨作品读取不继承当前选择，显式错误 ID 不冒充空数据。
- 元素 text、synopsis、cast 和 JSON 原值不被响应修饰污染；分页后的内容不因路径封装变化；整场数组不要因读取分页而被误当作完整正文覆盖写回。
- Grep 能找到已知台词和梗概；已知没有匹配、尚未支持和扫描截断三种结果可区分；Glob 返回的每个文本路径都能实际读取。
- Write 的无效字段、只读字段、互斥锚点和非法值在写入前拒绝；拒绝后内容、排序和 working change 均不变化。
- 跨作品所有写工具持续拒绝，当前作品写入继续允许；原著的角色、地点和关系证据 ID 不可直接作为目标作品引用。
- 固定 tool definitions 在两种作品上下文中保持一致；差异只在合法的上下文说明、能力索引与执行结果中。
- SubAgent 的旧类型限制用例按 2026-09-10 新方案更新：新建、续用和错误名称提示不按作品类型禁用专家；工具资源权限继续校验。
- 桌面和移动主聊天，以及所有 SubAgent 入口、headless 使用一致的 workId、contentKind、当前作品根与原作关联；当前作品和只读参考作品的作用域明确分开。

本次没有运行真实 LLM E2E、远程助手、UI 自动化或生产数据库读取。提示词是否能稳定完成长任务仍需在工具契约修复后，另按用户授权开展真实模型评估；本报告的确定性结论来自代码、现有测试和七个纯内存复现。
