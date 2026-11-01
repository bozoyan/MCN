# 后台任务查询、等待与取消

生成、FFmpeg、预览或导出返回 `run_id` 后，保留它并继续跟踪。需要找回当前会话的任务时使用 `Run operations list`。

调用格式为 `{"command":"operations","subcommand":"操作名","options":{...}}`。

| subcommand | 必填 options | 可选 options 与行为 |
|---|---|---|
| `list` | 无 | `status`、`offset=0`、`limit=50`，limit 为 1..200 |
| `read` | `run_id` | 查询当前会话运行结果 |
| `wait` | `run_id` | `timeout_ms=30000`，范围 1..60000 毫秒 |
| `cancel` | `run_id` | 请求取消，accepted 不等于已完成取消 |

status 可选 waiting_approval、queued、running、cancelling、completed、failed、cancelled、interrupted。offset 为非负整数。

```json
{"command":"operations","subcommand":"read","options":{"run_id":"{run_id}"}}
{"command":"operations","subcommand":"wait","options":{"run_id":"{run_id}","timeout_ms":30000}}
{"command":"operations","subcommand":"cancel","options":{"run_id":"{run_id}"}}
```

wait 单次最多 60000 毫秒；超时仅结束等待，不会取消任务，也不构成重新提交的理由。cancel 的 accepted=true 只表示已接收取消请求，要继续核对状态。上游可能继续执行时，如实说明，不声称费用或远程生成已撤回。

根据返回的状态、`result` 和错误判断实际结果；不能只看到外层 ok 或 run_id 就宣布成功。返回 files 的生成或导出操作，还要核对条目的 delivered、file_path 及错误；保存在会话中但目标交付失败时，说明可用副本和未完成的交付。ffmpeg execute 按 result.exit_code、status 和 log 判断执行结果。

每次提交生成或媒体加工命令都会发起新的尝试。确认原请求是否已接收时，先用 `Run operations list` 找回任务，再按 `run_id` 查询，不用重复提交代替查询。

任务明确失败后，先检查错误和已保存、已交付的输出；确实需要重新执行时，再提交新尝试。生成任务还要核对持久任务状态与已有产物，避免重复生成或计费；拒绝、取消后不能通过重新提交绕过用户决定。

`run_id` 用于当前会话运行控制，生成记录的 task_id 用于持久生成记录，不互相替代。取消当前作品的制片生成任务时，也可单独传 `options:{"task_id":"生成任务ID"}`；不能混传 run_id 或其他选项。返回的 result_applied 与 upstream_may_continue 用于判断结果是否已采用、上游是否仍可能执行。
