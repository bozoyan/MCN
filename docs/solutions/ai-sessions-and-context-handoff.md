# AI 会话读取与新上下文接力

状态：待实施。本文记录已确认的产品方向，并给出接口、交互、实施和验收方案。

## 1. 目标与范围

作者需要在长对话后重新开始一段模型上下文，同时能按需回看之前的讨论。模型也需要独立于这个入口，发现和读取其他会话中的信息。

本方案提供两项能力：

1. `Run sessions`：发现、分页读取、搜索会话记录，获取单条消息中的指定内容。
2. 会话接力：用户选择来源会话，进入新的普通聊天。首轮只带来源引用和本次指令，历史由模型按需读取。

已确认的边界：

| 项目 | 决策 |
| --- | --- |
| Run 命令空间 | 使用 `sessions`，替换 `history` |
| 作品范围 | 默认当前作品，通过 `work_id` 选择其他作品 |
| 可读会话 | 普通聊天、子代理、议事厅、独白、剧场、角色扮演的已保存记录 |
| 自然语言引用历史 | 无需操作接力入口；模型根据本次要求发现并读取历史，在当前会话继续回答 |
| 新会话初始输入 | 来源引用和用户本次指令 |
| 历史注入 | 按需读取，不预先复制消息或生成摘要 |
| 当前会话入口 | 桌面新建按钮旁下拉；移动端新建菜单 |
| 当前会话入口文案 | “新对话”／“延续当前对话” |
| 历史会话入口 | 现有历史列表中的延续操作，来源取所选记录 |
| 内容过滤 | 用户发言、助手正文、工具记录、压缩摘要、内部提醒；支持工具名称和状态筛选 |
| 来源保留 | 沿用现有清理和删除规则，引用不延长保留期限 |
| 数据变更 | 不新增表、列、关系索引或数据库迁移 |

本轮不增加模型创建或切换会话的命令，不做跨作品会话选择器，不改变作品归属，不改已有 Fork 行为，不批量改造其他模式的转换流程。`sessions` 全部是只读操作。各 Agent 是否可以调用 Run，继续遵循现有工具权限。

## 2. 当前实现与缺口

- `lib/shared/services/ai/tools_run.dart` 已有 `history search/get`，通过 `source/current` 选择来源会话或当前执行会话，查询落在当前作品内容库。
- 会话索引位于主库的 `AiChatSessions`；消息位于对应作品内容库的 `AiChatMessages`。跨作品读取已有 `CrossWorkAccess` 和 `CrossWorkResolver` 可复用。
- `AiChatSessionDao.getByNovel()` 等现有 UI 查询会排除子会话。通用列表需要独立查询，不能直接复用这个过滤范围。
- `AiSessionPersistenceService.forkSession()` 会复制旧消息。桌面和移动端均有消息级 Fork 入口，这与本方案重开上下文的目标不同。
- `PendingChatHandoff`、临时会话标识、首次发送落库和来源标签已存在，可以复用。`AiHandoffContext` 的部分调用方会把完整文字记录放入 `summary`，新入口不使用这段内容组装。
- 工具调用及结果通常保存在 assistant 消息的 `AiToolCallBlock` 中。仅筛选 `type=tool_result` 会漏读；仅按 `role=user` 筛选，又会把 `system_remind` 算作用户发言。
- Run 的常驻描述只指向 help，现有聊天工具准则未说明何时检索旧对话。仅增加命令帮助不能保证模型主动发现能力；标题搜索也不足以定位用户只记得正文内容的对话。

本方案以现有代码、`CONTEXT.md` 和上述用户决策为准，不恢复旧 Agent 选择流程。

## 3. 方案取舍

| 方案 | 代价与效果 | 决策 |
| --- | --- | --- |
| 复制历史后继续 | 新会话仍承担旧上下文体积 | 沿用已有 Fork，不用于接力 |
| 自动摘要后继续 | 增加模型调用，并预先筛选信息 | 本轮不采用 |
| 来源引用加按需读取 | 新上下文较小，读取范围由本次任务决定 | 采用 |
| 为来源增加保留关系 | 需要关联查询和清理规则 | 不采用，来源不存在时明确返回错误 |

接力会建立新的聊天运行态和上下文管理器。标准系统提示词、当前作品规则、工具定义和必要的当前工作区定位仍正常加载；不继承来源会话的消息历史、压缩摘要、工具执行状态、运行队列或上下文管理器。

## 4. 用户交互

### 4.1 当前会话

桌面保留原新建按钮的一键操作，tooltip 使用“新对话”。旁边增加独立下拉触发区，菜单提供“新对话”和“延续当前对话”。下拉区可独立聚焦、通过键盘打开；主按钮点击不经过菜单。

移动端点击现有新建按钮，使用项目标准底部菜单，提供同名两项。触控区域至少 48px，不使用长按作为唯一入口。

“延续当前对话”的说明为：**开启新对话，需要时回看当前聊天。**

| 状态 | 行为 |
| --- | --- |
| 真实会话且有已保存消息 | 可以延续 |
| 空会话、临时会话或尚无已保存消息 | 隐藏延续选项，仍可新建 |
| 来源会话正在生成或变更历史 | 延续选项禁用，提示“请先停止生成”或等待历史操作完成 |
| 来源记录在点击前被删除 | 留在原页面，提示“来源对话已不可用” |

点击延续后直接进入新会话草稿，不弹确认框、不自动发送、不触发模型调用。保持当前选中的模型及推理设置，将未发送文字和已附加引用带到草稿中，聚焦输入框。

### 4.2 历史会话

桌面会话切换浮层、侧边栏聊天列表和移动端聊天历史弹层提供同一延续动作。动作以点击的历史项为来源，菜单展示该项标题，不能误用正在查看的会话 ID。

本轮沿用这些列表已有的作品和会话展示范围，不把所有子代理记录塞入普通聊天列表。所有类型的读取能力由 `sessions list/read/search/get` 提供。

### 4.3 新会话草稿

输入框上方显示来源标签，格式为“延续自：{title}”，可移除。点击来源标签可查看来源会话，复用现有会话导航。

- 移除标签后恢复普通新对话草稿，保留输入文字和其他引用。
- 草稿未发送就退出时，不创建会话或复制任何历史数据。
- 有输入时，使用用户输入作为本次指令；仅带来源标签发送时，使用共用提示词“继续来源对话中的任务。”，不生成摘要。
- 首次发送时复用 `ChatSessionController` 的会话落库流程，创建新的顶层 `chat` 会话，`parentId` 为空，采用普通聊天的 Chat Orchestrator。
- 新会话标题沿用正常新对话的标题生成流程。来源标题只用于引用展示，不用作身份或查询条件。
- 来源与新会话之后各自保存消息。重启后，新会话从首条持久化消息恢复来源标签。

当前入口和历史入口产生相同的草稿数据，由桌面、移动端各自外壳承接。来源验证或创建失败时保留输入和来源引用，使用现有错误反馈，不自动退化为空白对话。

## 5. Run sessions 契约

### 5.1 命令与帮助

沿用 Run 的静态结构：`command`、`subcommand`、`options`。不修改 `_runDescription` 或 `_runInputSchema` 的 description；具体命令说明写入帮助响应。

```json
{"command":"help","subcommand":"sessions"}
{"command":"sessions","subcommand":"list","options":{}}
{"command":"sessions","subcommand":"read","options":{"session_id":"ai_session_123"}}
```

`Run sessions` 未提供子命令或子命令为 `--help` 时返回帮助。帮助列出本文的参数、默认值、分类和续读方式。命令菜单中的说明使用：`sessions  List, read, and search saved AI conversations.`

执行路由、帮助和专用工具卡片映射统一移除 `history`，不保留别名、专门的改名提示或旧命令展示分支。调用旧名称按普通未知命令处理。已有持久化消息不做迁移。

### 5.2 作品和会话寻址

所有子命令的 `work_id` 均为可选字段，省略时使用工具宿主的当前作品。没有当前作品且没有显式 `work_id` 时返回 `work_required`；不猜最近打开的作品。

`read/search/get` 的会话选择规则统一为：

1. 提供 `session_id` 时，读取该会话。
2. 未提供时按 `scope` 解析；`source` 为默认值，保留现有子代理来源会话语义，`current` 表示当前执行会话。
3. `session_id` 已提供时忽略 `scope` 的选择作用。非法枚举仍报错，避免拼写错误被吞掉。
4. 先从主库校验会话存在、未软删除且属于目标 `work_id`，再读取该作品内容库。作品与会话不匹配返回 `session_not_found`，不自动切换作品。

`list` 不依赖当前会话存在。跨作品读取必须显式带目标 `work_id`；结果始终携带真实作品 ID 和会话 ID。来源引用中保存这两个 ID，模型不需要从标题猜测身份。

`search` 额外支持 `scope=work`，在目标作品全部有效会话的消息正文及所选内容中搜索，不要求提前知道 session ID，也不依赖 active session。此时禁止同时传 `session_id`，避免把单会话与作品范围混为一谈；read/get 不接受 work scope。未显式选择 work scope 时，仍使用上述 source/current 默认行为。

接力来源与运行时 `sourceSessionId` 是不同概念。接力后的 B 仍以 B 作为自身运行来源；B 派生的子代理默认来源也是 B。回查接力来源 A 时，模型必须显式传 A 的 `work_id/session_id`，不能把 AiClient 的 `sourceSessionId` 改成 A。

### 5.3 参数

| 子命令 | 参数 | 默认值与含义 |
| --- | --- | --- |
| `list` | `work_id` | 当前作品 |
| `list` | `query` | 可选，标题的字面子串匹配 |
| `list` | `mode` | 可选，现有 `AiSessionMode` 的持久化值 |
| `list` | `parent_id` | 可选，指定父会话的直接子会话；未传时包含顶层和子会话 |
| `list` | `limit`、`cursor` | 默认 20，范围 1 至 100；按最近更新时间分页 |
| `read/search/get` | `work_id`、`session_id`、`scope` | 见会话寻址规则 |
| `search` | `scope=work` | 搜索目标作品内的所有有效会话；不能与 session_id 同传 |
| `read/search/get` | `kinds` | 默认 `["user","assistant"]`；非空数组，取值见下节 |
| `read/search/get` | `tool_name` | 可选，工具注册名的精确匹配，如 `Read`、`Run` |
| `read/search/get` | `tool_status` | 可选，工具状态的精确匹配 |
| `read/search` | `order` | `asc/desc`；read 默认 asc，search 默认 desc |
| `read/search` | `limit`、`cursor` | 默认 20 条匹配消息，范围 1 至 100 |
| `search` | `query` | 必填、非空，匹配筛选后内容的字面子串，不解释为 SQL 或正则 |
| `get` | `id` | 必填，真实消息 ID；必须属于选定会话 |
| `get` | `block_id` | 可选，进一步选择该消息中的真实内容块 |
| `get` | `cursor` | 可选，续读该消息被截断的内容 |
| `read/search/get` | `max_chars` | 文本载荷上限，默认 12000，范围 1000 至 20000 |

整数越界、空过滤数组、未知分类或状态返回 `invalid_argument`，不静默改为其他条件。`mode` 接受 `chat/council/monologue/theater/roleplay`。子代理使用 `mode=chat`，通过 `parent_id` 区分。

指定工具名称或状态而没有 `kinds` 时，默认改为 `["tool"]`。若同时显式给出不包含 `tool` 的 `kinds`，返回参数冲突。工具条件只约束 tool 部分，不影响同时选择的 user/assistant 部分。

旧 `role`、`include-tool-results` 参数由 `kinds` 替代，不增加两套过滤语义。新帮助只展示 `sessions` 契约。

### 5.4 内容分类

`kinds` 是读取结果的语义分类，不新增数据库枚举，也不把数据库中的 role 改成 tool。

| kind | 内容 | 归一化规则 |
| --- | --- | --- |
| `user` | 用户发言 | user 角色中的普通消息，排除内部提醒、压缩摘要和独立工具结果 |
| `assistant` | 助手正文 | assistant 的正文和文本块，不包含思考或工具块 |
| `tool` | 工具调用与结果 | `AiToolCallBlock` 及存量独立 `tool_result` 记录 |
| `summary` | 历史压缩摘要 | `compact_summary`，不根据 role 猜测 |
| `system` | 内部提醒 | `system_remind` 及实际仍存在的 system 消息 |

多分类取并集；`tool_name/tool_status` 与 tool 分类中的内容取交集。分类先判断明确的消息类型，再判断角色和块，确保一条压缩摘要不会同时被当作用户发言。

文本块与 `content` 是同一正文的两种表示时，只返回一份：有非空文本块时按块顺序输出，否则使用 `content`。用户消息中的来源引用要保留可读的作品和会话标识，不能在提取正文时丢掉回查入口。

工具记录返回工具名、调用 ID、状态、参数、结果和错误信息；参数、结果及错误格式化到该工具部分的文本载荷中，参与文本长度上限和搜索。不返回模型思考签名、加密推理字段或纯 UI 辅助 metadata。

对存量独立 `tool_result` 使用现有持久化解码约定。缺少工具名或状态时返回空值，不编造；无法确定名称的记录不能命中 `tool_name` 筛选。不为读取而修改、补写或重新合并旧消息。

图片和附件保留已保存的文字说明及可用引用，不读取二进制或文件内容。AskUser、下一步建议块输出已保存的可读内容，分别归入助手内容；用户实际提交的回答仍按其已保存消息归类。

`search` 在归一化并筛选后的文本中匹配；选择工具记录时，查询能够命中参数和结果。不能只对 `AiChatMessages.content` 做 LIKE，否则会漏掉块内内容。

作品范围搜索同样遵循上述分类。`list.query` 仍只匹配标题，不承担正文检索；标题未命中不能被解释为不存在相关历史。

### 5.5 返回值与分页

保留 Run 的 `ok/output/exit_code/duration_ms` 包装。`output` 只提供简短数量说明，正文放在 `data`，避免同一份历史在字符串和结构化字段中重复返回。

`list` 的每项包含 `id/work_id/title/mode/parent_id/created_at/updated_at`。标题展示最多 200 字符，标记是否截断；ID 不截断。

`read/search/get` 使用相同的消息结果：

```json
{
  "ok": true,
  "output": "Returned 1 message.",
  "exit_code": 0,
  "duration_ms": 8,
  "data": {
    "work_id": "work_1",
    "session_id": "session_1",
    "items": [
      {
        "id": "message_1",
        "role": "assistant",
        "type": "text",
        "sequence": 12,
        "created_at": "2026-09-21T08:00:00Z",
        "parts": [
          {
            "id": "block_1",
            "part_index": 0,
            "kind": "tool",
            "tool_name": "Read",
            "call_id": "call_1",
            "tool_status": "success",
            "text": "{\"arguments\":{\"path\":\"/chapters/ch_1\"},\"result\":{\"ok\":true}}",
            "text_offset": 0,
            "truncated": false
          }
        ]
      }
    ],
    "has_more": false,
    "next_cursor": null
  }
}
```

消息 `id` 和内容块 `id` 均使用已保存的真实身份。只有消息正文、没有块的部分不伪造块 ID，使用稳定的 `part_index` 定位。`part_index` 在整条消息完成归一化、尚未过滤时按顺序分配，不因筛选不同重新编号；一条消息内部始终保留原内容顺序。工具调用的 `call_id` 继续保留，不能拿来替换消息 ID。

`scope=work` 的结果以 `data.scope="work"`、`data.session_id=null` 表达范围，每条消息额外携带 `session_id/session_title/session_mode`。模型据此对命中的会话发起 read/get，并向用户用标题和日期说明来源。标题仍按 200 字符限制，不以标题匹配代替真实 ID。

分页规则：

1. `list` 按 `updated_at DESC, id DESC`；单会话消息按 `sequence, created_at, id` 排序，方向取 `order`。作品范围搜索按 `created_at, id` 排序，默认倒序，不能跨会话比较 sequence。
2. DAO 每批读取最多 200 条候选消息，归一化和过滤后填充结果，直到满足 `limit/max_chars` 或扫描结束。不能先取 limit 条再过滤，也不一次加载整段会话。
3. `limit` 统计返回的不同消息数。一条消息可包含多个匹配部分；工具条件不会把不匹配的工具块带回来。
4. `max_chars` 约束返回的所有 `parts.text`，按 Unicode 码点计数，不能切断字符。超长部分返回片段、`text_offset` 和 `truncated=true`，cursor 记录下一段位置。
5. cursor 是无状态的编码值，包含操作、作品、会话、过滤条件、排序和续读位置。下一次沿用原请求并传入 cursor；`limit/max_chars` 可以调整，其他条件改变则报 `cursor_invalid`。不新增服务端游标表或缓存。
6. 同一消息跨页继续时保留原 ID；`part_index/text_offset` 表达续读位置。`search` 对完整部分判定是否命中，再分页返回该部分，避免关键词位于截断处导致漏读。
7. 读取当前已保存的历史，不创建快照。cursor 指向的消息或块已消失时返回 `cursor_invalid`，从首轮重读；跨请求期间发生其他历史编辑时，不承诺快照一致性。
8. 无匹配返回成功、空 items、`has_more=false`。只有后面仍有匹配内容或未返回完的片段时，才提供 `next_cursor`。

工具状态采用已有值：`pending/rejected/cancelled/running/success/error`。过滤不改变这些状态，不把历史工具记录重新提交给执行器。

### 5.6 常见调用

```json
{"command":"sessions","subcommand":"list","options":{"work_id":"work_2","mode":"chat","query":"人物动机"}}
{"command":"sessions","subcommand":"search","options":{"scope":"work","query":"反派动机","kinds":["user","assistant"]}}
{"command":"sessions","subcommand":"read","options":{"session_id":"session_1","kinds":["user"],"order":"desc","limit":10}}
{"command":"sessions","subcommand":"search","options":{"session_id":"session_1","query":"承诺","kinds":["user","assistant"]}}
{"command":"sessions","subcommand":"read","options":{"session_id":"session_1","kinds":["tool"],"tool_name":"Read"}}
{"command":"sessions","subcommand":"read","options":{"session_id":"session_1","tool_status":"error"}}
{"command":"sessions","subcommand":"get","options":{"session_id":"session_1","id":"message_1","kinds":["tool"],"block_id":"block_1"}}
{"command":"sessions","subcommand":"read","options":{"scope":"current","kinds":["summary"]}}
```

第一行列出其他作品的会话；其后的请求默认当前作品。跨作品读取消息时同样传 `work_id`。`read/get` 不需要当前已存在一个真实聊天，只要显式提供有效作品与会话即可。

### 5.7 错误

| 错误码 | 条件与处理 |
| --- | --- |
| `invalid_argument` | 参数格式、枚举、范围或组合无效，说明具体字段 |
| `work_required` | 无当前作品且未指定作品 |
| `work_not_found` | 作品不存在或已删除 |
| `work_unavailable` | 对应内容库缺失或无法读取，不自动新建空数据库 |
| `session_required` | 未显式指定会话，运行上下文也无法解析会话 |
| `session_not_found` | 会话不存在、被删除或不属于目标作品 |
| `message_not_found` | 消息不存在或不属于选定会话 |
| `block_not_found` | 指定块不属于该消息 |
| `cursor_invalid` | 游标格式、查询条件或目标位置不再有效 |
| `sessions_unavailable` | 工具宿主未接入会话读取能力 |

源记录过期或被删除时返回对应错误。保留 B 已有的输入和回答，不恢复 A、不延长清理期限，也不偷偷创建摘要副本。

## 6. 接力引用与发送流程

来源引用使用现有消息内引用机制，携带 `work_id/session_id/title/mode`，随 B 的首条消息保存。它是模型输入与 UI 展示信息，不成为数据库关联、业务路由或清理判断依据。

共用提示词示意如下，动态值必须通过现有 XML 转义函数处理：

```xml
<user-remind type="session" path="ai-session:session_1" work-id="work_1" label="人物动机讨论" mode="chat">
This conversation continues work from the referenced session with fresh context.
When earlier details are needed, use Run sessions with work_id="work_1" and session_id="session_1".
Read only the history relevant to the current request.
</user-remind>
```

这段提示词共用一份，不做 i18n。来源标题只作标签，不能承担指令或寻址。普通聊天首轮标准提示词继续由现有 prompt builder 生成。

```text
当前会话或历史项
  -> 读取并验证来源描述
  -> PendingChatHandoff（引用 + 草稿文字，不自动发送）
  -> 桌面 / 移动端新会话草稿
  -> ChatSessionController 首次发送
  -> 创建 B、保存首条消息、启动新的 Agent
  -> 模型按需调用 Run sessions
  -> 主库校验归属 -> 对应作品内容库 -> 筛选后的历史
```

入口只读来源会话描述及是否有已保存消息，不为了显示标签加载整段历史。B 仍通过既有首次发送机制生成 ID，重复点击或重复发送复用现有临时会话认领和发送 guard。

历史读取只覆盖已持久化内容。其他仍在运行的会话可以读取此前已保存的记录，不等待生成完成，也不读取其进程内流式状态。用户界面的延续动作按第 4 节限制正在运行的来源。

### 6.1 用户直接提起以前的对话

自然语言入口不要求来源标签，也不要求用户知道会话 ID。比如“按我们上次聊的反派动机继续写”，在当前会话内执行以下流程：

1. 当前上下文已足够时直接处理；需要找回或核对旧记录时进入 sessions 检索。
2. 已有明确来源 ID 时直接 read/search；不清楚参数时先调用 `Run help sessions`。
3. 不知道来源时，按线索使用 list 查标题或最近会话，或用 `search scope=work` 查正文。默认当前作品；用户明确提及其他作品时先解析真实作品 ID，再传 work_id。
4. 从结果获得真实 session ID，按需 read/get 上下文。查询用户要求时优先 user，查询执行过程时选择 tool 和对应工具过滤器；不要把全部记录灌回上下文。
5. 只有一个匹配来源且任务明确时继续回答；多个来源仍无法区分、结论冲突或记录不足时，说明找到的候选并只问必要的澄清问题。
6. 查询无结果或来源不可用时如实说明，不假装记得。只读取历史不会自动创建、切换会话，也不会重新执行旧工具操作。

在 `PromptFragments.toolUseGuidelines()` 中增加一份固定规则，经现有 `ChatPanelPromptUseCase.system()` 注入，确保用户没有点击延续入口时也能看到这项能力。拟用文案如下：

> 需补查以往对话时，使用 Run sessions，用法见 Run help sessions。按需读取相关内容；来源不明确时再询问，查不到时如实说明。

规则不依赖关键词字符串触发器，不增加客户端意图分类或额外模型调用。这里只提供能力提示与行为约束，完整参数仍由 help 承载。顶层 Run description 和 schema description 保持原样。

`assets/prompts/system/context_compaction.md` 中现存的 `Run(history search)` 指引也同步改为 sessions，并说明 source/current 范围，避免压缩后的会话继续推荐旧命令。这是提示词内容迁移，不复制旧会话摘要到接力目标。

## 7. 实现结构

采用已有 Run 命令 handler 接线方式，新增一个 sessions handler 和一个消息归一化模块，不增加通用查询 DSL、服务注册体系或新的存储层。

```text
Run 路由
  -> SessionsRunCommandHandler
       -> AppDatabase.aiChatSessionDao（身份、归属、会话列表）
       -> CrossWorkAccess.acquire(workId)
            -> NovelContentDatabase.aiChatMessageDao（分批候选消息）
       -> transcript 纯函数（分类、内容投影、搜索与片段）
  <- 统一 Run 结果

桌面 / 移动端延续动作
  -> 共用来源引用构造
  -> 既有 PendingChatHandoff 和 ChatSessionController
```

handler 构造注入 AppDatabase、当前作品和 CrossWorkAccess；当前执行会话与来源会话在每次调用时传入，不能捕获创建 handler 时的 session ID。子代理复用同一工具分发器时，以 `ToolExecutionContext` 为准。

跨作品数据库借用在 `finally` 释放。会话过滤和列表限制在主库查询中完成；消息块内容过滤在 Dart 侧完成，不引入 JSON SQL 查询、FTS 或派生表。已有列上的可用索引继续使用，本轮不为接力增加 schema 结构。

作品范围搜索只扫描选定作品的内容库，仍按 200 条候选消息分批。每批按出现的 session ID 从主库批量校验有效状态和作品归属，补充会话标题；排除主记录缺失、已删除或归属不符的消息。复用同一 transcript 过滤器和字符预算，不逐个加载全部会话历史，也不扩展为所有作品的全文扫描。

### 7.1 文件改动

本方案跨工具接线、DAO、两端 UI、本地化和测试，改动超过 8 个文件。新增生产文件限定为下面两个 sessions 模块，其他改动落在现有文件。

#### 新增 `lib/shared/services/ai/sessions/run_command_handler.dart`

- 实现 `SessionsRunCommandHandler`，集中处理四个子命令、参数校验、身份与归属校验、候选扫描、游标和结果预算。
- 参数与结果采用本文固定契约；缺少依赖返回明确错误。

#### 新增 `lib/shared/services/ai/sessions/transcript.dart`

- 实现从已保存消息到可读部分的纯函数，处理分类、工具块、存量独立工具结果及正文去重。
- 保留真实 ID 和源顺序，支持 Unicode 安全分段；不访问 UI、文件或网络。

#### `lib/shared/services/ai/tools_run.dart`

- 将 history 路由替换为 sessions，更新帮助、usage 和示例；旧名称使用通用未知命令处理，不新增特殊分支。
- `_runSessionsCommand` 只负责获得本次执行上下文、调用 handler 回调和封装结果；不继续堆积数据库查询。
- `source/current` 的解析由当前 `ToolExecutionContext` 驱动；list 和显式会话读取不要求 active session。

#### `lib/shared/services/ai/tools.dart`

- 增加 `AiSessionsCommandCallback` 及 manager 接线。回调接收 action/options 和本次 current/source session ID，避免把内部上下文塞进模型 options。
- 顶层 Run schema 与 description 保持静态，沿用现有工具注册和权限。

#### `lib/shared/services/ai/prompts/prompt_fragments.dart`

- `toolUseGuidelines()` 增加第 6.1 节的历史检索规则，使普通聊天也能主动发现 sessions。
- 使用现有 `ChatPanelPromptUseCase.system()` 注入链路；仅维护一份共用文本，不增加 locale key，也不在多个 Agent 模板复制同样规则。

#### `assets/prompts/system/context_compaction.md`

- 将旧 history 工具指引迁移为 sessions，明确单会话 source/current 查询，避免被误解为默认作品范围搜索。

#### `lib/shared/services/ai/ai_service_config.dart`、`chat.dart`

- 在配置、直接构造函数、`AiClient.fromConfig` 和 tool manager 创建处透传 sessions 回调，覆盖冷启动和已有配置路径。
- 不借此重构其他 AiClient 参数或迁移调用方式。

#### `lib/shared/services/ai/chat_turn_runner.dart`

- 两处 AiClient 创建链路都构造并注入 sessions handler，复用已取得的 AppDatabase 和 CrossWorkResolver。
- 普通聊天、子代理与 headless turn 共享这条接线。用测试验证子代理每次调用的 current/source 身份，避免绑定成父会话常量。

#### `lib/shared/database/daos/ai_chat_session_dao.dart`

- 新增面向工具的作品内列表查询，包含所有 mode 和 parent 层级，支持标题、mode、parent_id 过滤及稳定分页。
- 保持原 UI 列表语义；继续使用真实列校验 deletedAt 和 novelId。
- 为作品范围正文检索提供批量会话身份与描述查询，不复用排除子会话的 UI 列表。

#### `lib/shared/database/novel_content_daos/ai_chat_message_dao.dart`

- 新增稳定顺序的候选批次读取、单会话单消息校验查询、是否存在已保存消息的轻量查询。
- 作品范围 search 使用 created_at/id 顺序的候选读取，再由主库校验其会话归属。
- SQL 限制批量大小，块内容由 transcript 模块处理，不使用全量 `getBySession()` 作为分页实现。
- 需要刷新 DAO 生成文件时使用 FVM build_runner，检查生成 diff；不修改 schemaVersion。

#### `lib/shared/services/ai/handoff_service.dart`

- 增加只构造来源引用及 `PendingChatHandoff` 的函数，输入为已验证的会话描述和当前草稿。
- 不调用已有 `createTargetSession()` 提前落库，也不使用带 summary 的 `AiHandoffContext` 构造新入口的内容。
- 使用已存在的 XML 转义方法，来源描述携带真实作品和会话 ID。

#### `lib/shared/services/ai/chat_session_controller.dart`

- 复用 `_materializeSessionForSend()` 和 `_buildAgentTextWithHandoff()`；补齐只有来源标签发送时的共用继续指令。
- 新会话正常构建新的 Agent；失败保留可重试的草稿与来源引用，已创建 B 的重试继续使用 B，不重复建会话。
- 不把接力来源写进运行时 `sourceSessionId`，不调用 Fork 或复制源消息。

#### 桌面聊天文件

- `lib/desktop/widgets/ai/chat/header.dart`：主按钮和下拉入口、可用态、键盘和 tooltip。
- `lib/desktop/widgets/ai/chat/session_switcher.dart`、`session_list.dart`：历史项延续回调，来源取点击项。
- `lib/desktop/widgets/ai/chat/panel.dart`、`handoff.dart`：组装新草稿并复用临时会话激活机制。
- `lib/desktop/pages/novel_editor.dart`、`novel_editor_ai_area.dart`：在现有回调链上传递请求；页面只负责导航和组合，不放查询逻辑。

#### 移动端聊天文件

- `lib/mobile/widgets/mobile_ai_session_app_bar.dart`：在普通聊天宿主提供“新对话／延续当前对话”菜单；其他模式未传入延续能力时保持原行为。
- `lib/mobile/widgets/ai_session_history_sheet.dart`：增加可选的延续回调，避免改变其他模式已有的会话选择返回契约。
- `lib/mobile/pages/novel_chat_page.dart`：进入新草稿、传递来源与输入，复用首次发送落库，不调用源会话的停止或清空操作。

#### 共享展示与本地化

- `lib/shared/widgets/ai/chat/chat_message_parts.dart`、`chat_message_view.dart`：复用来源标签解析和显示，支持新文案；普通文本输出不能暴露整段控制标签。
- `lib/shared/services/ai/run_command_parser.dart`：新命令的参数流式到达状态。
- `lib/shared/widgets/ai/tools/tool_card_descriptor.dart`：sessions 标题、参数摘要及结果数量，删除 history 专用映射。
- `lib/shared/localization/locale_keys.dart`、`assets/translations/en/ai.json`、`assets/translations/zh-CN/ai.json`：新增或调整相应 namespace 的 key。

建议新增聊天专用 key，避免改动现有 `ai.new` 影响其他模式：

| key | zh-CN | en |
| --- | --- | --- |
| `ai.chat_new_conversation` | 新对话 | New conversation |
| `ai.chat_continue_current` | 延续当前对话 | Continue current conversation |
| `ai.chat_continue_hint` | 开启新对话，需要时回看当前聊天。 | Start a new conversation and refer back when needed. |
| `ai.chat_continued_from` | 延续自：{title} | Continued from: {title} |
| `ai.chat_source_unavailable` | 来源对话已不可用 | Source conversation is unavailable |

工具卡片增加 sessions 的 list/read/search/get 文案。生成中禁用提示复用已有本地化语义。提示词与 Run help 不做 i18n；用户界面文案按项目规则补齐三件套及 Dart 文件头关联。

## 8. 实施顺序

| 交付 | 内容 | 独立可用性 |
| --- | --- | --- |
| 第一批 | sessions 四个命令、单会话和作品范围搜索、分类过滤、分页、各宿主接线、常驻检索规则、帮助与工具卡片、相关测试 | 模型已经可以响应自然语言要求读取其他会话，尚无新 UI 也能使用 |
| 第二批 | 当前会话及历史项入口、首条消息引用、两端草稿与发送流程、本地化、相关测试 | 用户可以直接启动新上下文接力 |

每批包含自身的测试和文案，不把错误处理或验证留给后一批。已有 Fork 与其他模式转换保持原用途。

## 9. 验收与测试

### 9.1 确定性验收

| 类别 | 通过条件 |
| --- | --- |
| 命令发现 | help 只发布 sessions；history 使用普通未知命令处理，没有别名或专用卡片映射 |
| 无当前会话 | list 和显式 session_id 读取可以工作 |
| 作品边界 | 默认只查当前作品；显式 work_id 可跨作品；作品与会话不匹配时失败 |
| 类型范围 | 顶层聊天、子代理和每种特殊 mode 的已保存记录均可列出和读取 |
| 子代理语义 | scope=source/current 分别命中父来源与当前子会话；复用子会话不串 ID |
| 用户过滤 | user 不包含 system_remind、compact_summary 或工具结果 |
| 工具过滤 | assistant 块内工具和独立 tool_result 均能读取；名称、状态筛选正确 |
| 正文 | 文本块与 content 不重复；默认不返回思考、工具大结果或内部提醒 |
| 搜索 | 块内文本、工具参数、工具结果均可按分类匹配；特殊字符按字面处理 |
| 未知来源 | scope=work 能命中标题不含关键词的历史正文，返回真实会话 ID；排除已删除、无主记录和跨作品混入的消息 |
| 无 UI 入口 | 无来源标签的普通聊天提示词也含历史检索规则；工具帮助可发现完整调用方式 |
| 分页 | 同时间记录不漏不重；稀疏匹配不会被前一批无关消息挡住；超长块可完整续读 |
| 失效 | 来源被删除、库缺失、错误归属、无效游标均有明确错误，不创建替代记录 |
| 草稿 | 打开、关闭或取消延续草稿不新增 session/message；移除标签后仍保留输入 |
| 发送 | 首次发送只创建一个 B；A 消息与上下文不变；失败重试不重复建会话 |
| 上下文 | B 初始输入只增加来源引用和本次指令；标准作品上下文正常，A 的消息和摘要未复制 |
| 重启 | B 首条消息中的来源引用仍可展示，模型可以显式回查 A |
| 清理 | 不修改 StorageCleanupService，不新增保留判断 |

新增测试文件：

- `test/shared/services/ai/sessions/run_command_handler_test.dart`：多作品数据库、各模式、参数和分页。
- `test/shared/services/ai/sessions/transcript_test.dart`：分类、真实 ID、正文去重、工具块与长内容分段。
- `test/shared/services/ai/chat_session_controller_handoff_test.dart`：首次发送、失败重试、独立上下文。
- `test/desktop/widgets/ai/chat/session_continuation_test.dart`：一键新对话、下拉、历史项、草稿状态。
- `test/mobile/widgets/session_continuation_test.dart`：底部菜单、历史项、导航与草稿状态。

扩展现有 tools_run、run_command_parser、handoff_service、session_switcher、chat_message_view、run_subcommand_localization 和 session DAO 测试。`test/shared/services/ai/prompt_tool_guidelines_test.dart` 与 `chat_prompt_builder_test.dart` 覆盖无来源标签时的提示词注入，以及压缩指引迁移。过滤测试必须构造同一 assistant 消息中同时包含正文、思考、成功和失败工具的情况；不能只测试独立的 tool_result 行。

### 9.2 实施时执行的命令

以下是实施后的验证计划，本次写方案没有运行这些测试。Flutter 命令串行执行。

```bash
fvm flutter pub run build_runner build --build-filter="lib/shared/database/daos/ai_chat_session_dao.drift.dart" --build-filter="lib/shared/database/novel_content_daos/ai_chat_message_dao.drift.dart"
fvm flutter test --concurrency=1 test/shared/services/ai/sessions test/shared/services/ai/tools_run_test.dart test/shared/services/ai/run_command_parser_test.dart test/shared/services/ai/handoff_service_test.dart test/shared/services/ai/chat_session_controller_handoff_test.dart test/shared/database/ai_chat_session_dao_test.dart
fvm flutter test --concurrency=1 test/shared/services/ai/prompt_tool_guidelines_test.dart test/shared/services/ai/chat_prompt_builder_test.dart test/shared/services/ai/prompt_registry_test.dart
timeout 180s fvm flutter test --concurrency=1 test/desktop/widgets/ai/chat/session_continuation_test.dart test/desktop/widgets/ai/chat/session_switcher_test.dart test/desktop/widgets/ai/chat/handoff_activation_test.dart test/desktop/widgets/ai/tools/run_command_parser_test.dart
timeout 180s fvm flutter test --concurrency=1 test/mobile/widgets/session_continuation_test.dart test/shared/widgets/ai/chat/chat_message_view_test.dart test/shared/localization/run_subcommand_localization_test.dart
fvm flutter analyze lib/shared/services/ai lib/shared/database/daos/ai_chat_session_dao.dart lib/shared/database/novel_content_daos/ai_chat_message_dao.dart lib/shared/widgets/ai lib/desktop/widgets/ai/chat lib/mobile/widgets/mobile_ai_session_app_bar.dart lib/mobile/widgets/ai_session_history_sheet.dart lib/mobile/pages/novel_chat_page.dart
git diff --check
```

Widget 测试需要真实本地化资源时在 setUp 中执行 `rootBundle.clear()`；watch Drift stream 的用例在结尾拆树并 settle。只运行相关目录，挂起时按 testing 规则定位，不同时启动多个 Flutter 测试进程。

### 9.3 交互与模型行为检查

桌面检查主按钮一键创建、键盘菜单、历史项来源正确；移动端检查底部菜单、触控区域、返回导航、窄屏来源标签。两端都检查输入法未完成组合、已有草稿、生成中禁用、来源被删和发送失败重试。

工具与上下文注入可用 stub client 检查首轮请求，验证未复制 A 的历史。真实模型是否按需读取属于非确定性行为：人工检查“继续上次任务”“只找用户最后的要求”“查上次失败的工具调用”“跨作品回查”四类场景，观察是否选择了正确会话和过滤器，不强制固定调用次数。

这四类场景都要覆盖没有点击延续入口、没有来源标签的普通聊天。其中至少包含标题不含主题关键词、多个候选结论不同、历史已删除，以及当前上下文已经足够无需检索的对照。通过标准是模型知道何时检索、能发现真实来源并据此回答，不能用“提示词包含 sessions 字样”的单测替代行为验证。

不自动启动真实模型 E2E 评测。只有用户明确要求时才运行对应评测；未运行时报告为未运行，不能用工具单测替代模型行为验证。

## 10. 成本、风险与回滚

新增接力入口本身产生 0 次模型调用，首次发送不增加摘要调用。新上下文中来源引用的大小与历史长度无关，只有按需读取的结果进入后续上下文。每次读取的文本载荷默认最多 12000 个 Unicode 码点，上限 20000；这不是 token 数，实际 token 和模型继续读取的次数取决于内容与任务，不承诺固定费用。

普通聊天新增一段固定检索规则，不附带会话目录或历史正文；其大小不随历史数量增长。未知来源时可能增加 help、发现、补读几个工具步骤，只在任务需要历史时发生。

| 风险 | 处理及接受的限制 |
| --- | --- |
| 来源已过期或删除 | 明确提示不可读取，沿用既有清理规则 |
| 用户只说“继续”，来源任务不明确 | 模型读取相关历史，必要时追问；不在客户端猜任务或预生成摘要 |
| 消息被压缩、回退或改写 | 读取当前持久化结果，不能恢复已不存在的原文 |
| 超长工具结果 | 按字符预算分段，cursor 可续读；不是默默丢掉尾部 |
| 稀疏块内搜索较慢 | 限定单会话或单作品后分批扫描、限制结果体积；第一版不新增 FTS、全文索引或缓存体系 |
| source/current 与接力来源混淆 | 明确分离运行上下文和消息内来源引用，并覆盖子代理测试 |
| 旧 history 调用仍出现在历史上下文 | 按普通未知命令处理，模型通过当前提示词及 help 使用 sessions；不增加兼容分支 |
| 两端首轮落库或导航不同步 | 共用 ChatSessionController；测试真实会话 ID 的认领和失败重试 |

无需数据库迁移、后端 REST 改动、额外凭证或第三方服务。回滚代码即可停用新入口和命令，已经创建的 B 仍是普通会话，消息和来源引用原文可保留；旧版本可能无法执行 sessions 回查，不删除这些消息或改写为 Fork。

本次文档交付仅写入方案并维护词汇表。实现、代码生成、Flutter 测试和真实模型验证均未执行。
