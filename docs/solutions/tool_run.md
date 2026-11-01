# Reveric Structured Run 方案

## 1. 当前结论

`Run` 是 Reveric 内部命令入口。

当前输入固定为结构化 JSON：

```json
{
  "command": "agent-rules",
  "subcommand": "create",
  "options": {
    "name": "章节字数",
    "content": "章节正文目标字数为 4000-5000 字"
  }
}
```

字段含义：

- `command`：命令 namespace，例如 `help`、`image`、`agent-skills`、`agent-rules`、`tips`。
- `subcommand`：具体动作，例如 `cover`、`create`、`list`、`read`。
- `options`：动作参数对象。长文本、中文、换行、引号都直接放在 JSON 字段中。

## 2. 为什么使用结构化输入

`Run` 承载 `image`、`agent-skills`、`agent-rules`、`tips`。这些命令经常传大段 prompt、规则正文、建议描述。结构化输入可以让这些内容直接落在 JSON 字段里，调用方和 UI 都能稳定读取。

当前决策是：

- 保留一个顶层 `Run`，继续降低 tool catalog 复杂度。
- 用 `command/subcommand/options` 表达命令结构。

## 3. 当前命令

### help

```json
{"command":"help"}
{"command":"help","subcommand":"image"}
{"command":"help","subcommand":"agent-skills"}
{"command":"help","subcommand":"agent-rules"}
{"command":"help","subcommand":"tips"}
```

### image

```json
{"command":"image","subcommand":"cover","options":{"prompt":"...","image":"..."}}
{"command":"image","subcommand":"character-avatar","options":{"character":"c_123","prompt":"...","image":"..."}}
{"command":"image","subcommand":"character-photo","options":{"character":"c_123","prompt":"...","image":"..."}}
{"command":"image","subcommand":"item-photo","options":{"item":"item_123","prompt":"...","image":"..."}}
```

`image` 内部仍复用现有图片 handler：

| Run 子命令 | Handler |
| --- | --- |
| `image cover` | `_handleGenerateCover()` |
| `image character-avatar` | `_handleGenerateAvatar()` |
| `image character-photo` | `_handleGeneratePhoto()` |
| `image item-photo` | `_handleGeneratePhoto()` |

### agent-skills

```json
{"command":"agent-skills","subcommand":"list","options":{"scope":"novel","novel":"novel_id"}}
{"command":"agent-skills","subcommand":"create","options":{"name":"正文写作","prompt":"...","scope":"novel"}}
{"command":"agent-skills","subcommand":"update","options":{"id":"skill_id","prompt":"...","enabled":true}}
{"command":"agent-skills","subcommand":"delete","options":{"id":"skill_id"}}
```

### agent-rules

```json
{"command":"agent-rules","subcommand":"list"}
{"command":"agent-rules","subcommand":"read","options":{"name":"章节字数"}}
{"command":"agent-rules","subcommand":"create","options":{"name":"章节字数","content":"4000-5000 字","enabled":true}}
{"command":"agent-rules","subcommand":"update","options":{"name":"章节字数","content":"4500-5500 字"}}
{"command":"agent-rules","subcommand":"delete","options":{"name":"章节字数"}}
```

### tips

```json
{"command":"tips","subcommand":"create","options":{"name":"章节节奏","description":"每章结尾保留明确推进"}}
```

## 4. UI 与结果格式

执行结果仍保留可读 `command` label，例如：

```json
{
  "ok": true,
  "command": "agent-rules create",
  "exit_code": 0
}
```

这个 `result.command` 是 UI 展示用 label。Tool card 解析模型输入时读取结构化 arguments。

Tool card 解析模型输入时应读取：

- `arguments.command`
- `arguments.subcommand`
- `arguments.options`

如果落库后的历史 tool block 缺少 arguments，UI 可以从 `result.command` 做只读展示回退。

## 5. 权限与边界

`Run` 不能成为绕过权限的总后门。

必须保留这些约束：

- `AiSessionMode.canUseTool()` 仍限制顶层 `Run` 是否可用。
- 未来如果把写入类命令迁入 `Run`，必须继续复用 mutation / approval / working overlay 路径。
- callback-backed 命令在 callback 不存在时必须明确报错。
- 数据库写入仍遵守 DB 日志和错误处理规则。
