# 智能体管理

用于管理主智能体可委派的**自定义智能体**。每个智能体都有独立的名称、职责说明、system prompt、使用场景和启用状态。它们不是用户可直接调用的 AgentSkill，也不是小说世界观里的角色。

`subagents list` 只返回可编辑的自定义智能体。官方内置智能体不在此列表中，不能通过此命令修改、停用或删除；不要猜测或尝试使用它们的 id/slug。

必须先区分三类内容：

- **智能体**：可承担连续性审查、节奏审稿、世界观核验等任务的协作者，用 Run 的 `subagents` 命令管理。
- **AgentSkill / agent skill / AI 技能**：按任务加载的一套可复用流程，例如“章节节奏审稿”。这类内容用 `agent-skills` 管理，不要创建成智能体。
- **小说角色 / 世界观人物**：属于故事内容，例如“军师”“审稿官 NPC”“主角的谋士”。这类内容写入角色或世界观资料，禁止创建成智能体。

如果用户只说“新增一个 agent”，但上下文无法判断是智能体、可调用 AgentSkill，还是小说角色，先用 AskUser 问清楚。

## 创建、更新与删除

### 1. 先列出现有智能体

创建、更新、停用或删除前，先查看可编辑配置，避免重复职责或 slug 冲突：

```text
Run {"command":"subagents","subcommand":"list","options":{}}
```

返回的每项都带有 `id`；更新和删除必须使用该 `id`，不要按名称或 slug 猜测。

### 2. 判断创建还是更新

- 已有相同或高度相近职责的智能体：更新现有条目。
- 现有智能体职责相近但边界不同：先 AskUser 确认是合并、改名还是新建。
- 没有同类协作者：创建新的智能体。

不要把多个不相关职责塞进一个智能体。一个智能体只应负责一种清晰的协作角色。

### 3. 写好智能体字段

创建至少需要：

- `slug`：稳定、唯一的机器标识，使用小写英文、数字和下划线，例如 `continuity_auditor`。
- `name`：面向用户和主智能体展示的短名称，例如“连续性审查”。
- `description`：一句话说明何时应委派它。
- `prompt`：完整 system prompt，必须写明职责、先读哪些上下文、工作步骤、边界、输出格式和自检要求。

可选字段：

- `mode`：`chat` 或 `council`，默认 `chat`。只有用户明确要求作为 council 角色时使用 `council`。
- `enabled`：`true` 或 `false`，默认 `true`。

### 4. 创建

```text
Run {"command":"subagents","subcommand":"create","options":{"slug":"continuity_auditor","name":"连续性审查","description":"检查章节、设定和既有剧情之间的连续性问题。","prompt":"# 连续性审查\n\n先读取与任务相关的章节、设定、角色状态和用户规则。检查时间线、人物状态、地点移动、物品归属、信息边界和伏笔回收。输出确认的问题、需要核验的疑点及具体修正建议。不要改写正文，除非用户明确要求。","mode":"chat","enabled":"true"}}
```

### 5. 更新、启用与停用

更新前先 `list`，从结果中取目标 `id`。只传需要修改的字段，未传字段会保留原值。

```text
Run {"command":"subagents","subcommand":"update","options":{"id":"subagent_xxx","description":"审查章节、设定和大纲之间的连续性。","prompt":"# 连续性审查\n\n更新后的完整指令..."}}
```

停用：

```text
Run {"command":"subagents","subcommand":"update","options":{"id":"subagent_xxx","enabled":"false"}}
```

启用：

```text
Run {"command":"subagents","subcommand":"update","options":{"id":"subagent_xxx","enabled":"true"}}
```

修改使用场景：

```text
Run {"command":"subagents","subcommand":"update","options":{"id":"subagent_xxx","mode":"council"}}
```

### 6. 删除

删除会从当前配置中移除，仍应按用户可见的破坏性操作对待。用户只是暂时不想使用时，优先停用。

删除固定走确认门槛：

1. 先 `list`，以返回的 `id` 找到唯一目标。
2. 向用户说明将删除的名称和职责，并用 AskUser 要求明确确认。
3. 只有用户在这次确认后同意，才调用 `delete`，并传入 `confirm: true`。

不要把“清理”“不再使用”“换一个”“先移除看看”等模糊表述当作删除确认；这类情况改为停用或继续询问。

```text
Run {"command":"subagents","subcommand":"delete","options":{"id":"subagent_xxx","confirm":true}}
```

## Prompt 质量标准

一个好的智能体 prompt 应满足：

- 明确说明它负责什么、不负责什么。
- 指定开始前需要读取或核验的小说上下文。
- 给出可执行的步骤，不只写抽象角色标签。
- 说明输出应包含结论、依据、待核验项或可执行建议。
- 要求发现冲突时明确指出，不平均处理、不擅自覆盖用户规则。
- 不依赖当前聊天的隐含上下文；必要信息应要求先查询或询问。

不要把单次任务临时要求保存为智能体。可复用流程优先判断是否更适合作为 AgentSkill。

## 保存后回报

Run 成功后，简短说明创建、更新、启用、停用或删除了哪个智能体，以及它的职责。

Run 失败时，直接报告失败原因。不要声称已保存，也不要把配置只记在当前回复中。
