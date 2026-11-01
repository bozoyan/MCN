---
name: debug
description: Use when: 没生效, 还是不行, 调试一下, 排查一下, 查查, 不工作, 不对, 状态丢失, 数据不更新, 写入成功但读取是旧值, 日志, debug, not working, not updating, still broken, 加日志, debugPrint, 打日志。通用的调试方法论与实际操作规程。适用场景：数据不更新、状态丢失、没生效、还是不行、排查、检查为什么不对、写入成功但读取仍是旧值。涵盖日志植入技巧、DB 读写链路排查、Provider 缓存、StreamProvider、Riverpod 调试、SQLite 直查等标准步骤。
---

# Debug 流程

## 通用原则

排查 bug 时禁止反复阅读代码猜测，应**立即在数据链路关键节点添加 `debugPrint` 日志**，覆盖完整链路：页面入口 → Provider → Service → DAO/数据库查询 → UI widget。

- 日志格式统一使用 `[TAG]` 前缀标识来源，例如 `[SIDEBAR]`、`[SESSION_PROVIDER]`、`[DAO]`、`[SESSION_LIST]`
- 每个日志点必须输出关键参数（如 `novelId`、`databasePath`、`limit`）和结果（如 `count`、`hasValue`、`isLoading`）
- 排查完成后应移除调试日志，不应合入正式提交

## 核心思路

涉及持久化 / 异步 / Provider 相关的 bug，根本原因通常是以下三类之一：

1. **写入没生效** — 参数错误、DB 操作异常、事务未提交
2. **读取走了缓存** — Provider 缓存了旧结果，DB 写入后未 invalidate
3. **时序问题** — 写入未完成就被 dispose、callback 被跳过

排查时**先分离读写路径**，不要同时改两端。下面是标准步骤。

## 1. 先加 DB 层日志

在读写的怀疑路径上直接加 `print`，不要先改业务逻辑。分别打写入和读取：

```dart
// 写入侧 — 打印所有参数和结果
Future<void> setXxx(int novelId, String? value) async {
  print('[DB] setXxx novelId=$novelId value=$value');
  await into(table).insertOnConflictUpdate(...);
  print('[DB] setXxx DONE');
}

// 读取侧 — 打印 key 和返回值
Future<String?> getXxx(int novelId) async {
  final row = await (select(table)..where((t) => t.novelId.equals(novelId))).getSingleOrNull();
  print('[DB] getXxx novelId=$novelId -> ${row?.value}');
  return row?.value;
}
```

通过这组日志可以立即判断：
- 写没写进去（有没有 `DONE`）
- 读没读出来（有没有 `->` 行）
- 读写的 key 是否一致（`novelId` 是否相同）

**如果没有读取日志**但界面显示了旧值 → 读取根本没走到 DB，Provider 直接返回了缓存值。

## 2. 确认 Provider 是否被 invalidate

`FutureProvider` 和 `StreamProvider` 首次 resolve 后缓存结果，后续 `ref.watch` 只返回缓存值，不会重新执行 provider 内的异步逻辑。

当通过 service / DAO 直接写入 DB 后，provider 不会自动感知变化，必须显式调用 `ref.invalidate(provider)`。

排查步骤：
1. 检查写入路径最后是否调用了 `ref.invalidate(provider)`
2. 如果 service 层没有 `Ref`，不在 service 里直接 invalidate — 而是在调用 service 的 provider / callback 中，写完后立即 invalidate
3. 若 `ref.invalidate` 不方便接入，考虑以下替代方案：
   - 封装为一个 `Notifier` action，写入 + invalidate 一体
   - 让 provider 监听 DB 变更流（`watch()` / stream）而非一次性查询

## 3. 读/写路径分离排查

不要同时改读和写，先确认一边正确：
- **写入侧**：DB 日志确认参数正确、写入完成
- **读取侧**：DB 日志确认是否真正走到了查询、参数是否正确、返回值是否正确

只有一边确认正确后，再去怀疑另一边。

## 4. StreamProvider/Stream 的常见调试模式

大部分 StreamProvider 的 bug 表现为「一直 loading」或「hasError=true 但看不出原因」。标准排查：

```dart
return service
    .watchSomething()
    .handleError((e, st) {
      debugPrint('[TAG] stream error: $e\n$st');
    })
    .map((data) {
      debugPrint('[TAG] stream emit: count=${data.length}');
      // 可能的额外参数：key、id、limit 等
      return transformedData;
    });
```

`handleError` 放在 `.map` 之前，确保能捕获底层 stream（如 Drift 的 `watch()`）抛出的异常。

另外，widget 侧可以通过 AsyncValue 的三态直接输出：
```dart
debugPrint('[TAG] hasValue=${async.hasValue} hasError=${async.hasError} isLoading=${async.isLoading}');
if (async.hasError) debugPrint('[TAG] error=${async.error}');
```

## 5. SQLite 直查技巧

通过代码猜测 DB 数据远比直接查 SQLite 慢。先在 shell 里验证：

```bash
# 查出表结构
sqlite3 path/to/db.sqlite "PRAGMA table_info(table_name);"

# 查出实际存储的数据类型（SQLite 是动态类型，列声明≠实际类型）
sqlite3 path/to/db.sqlite "SELECT id, typeof(col), col FROM table_name;"

# 查出所有表
sqlite3 path/to/db.sqlite ".tables"
```

这在排查 Drift 类型不匹配时尤其有用——`typeof()` 直接告诉你 SQLite 存的是 `text`、`integer` 还是 `real`，比猜快得多。

## 6. 常见陷阱

- **`addPostFrameCallback` 里的操作可能被跳过**：如果用户在下一帧渲染前退出页面（退出小说、关闭对话框），`context.mounted` 变为 false，callback 被跳过。关键的状态写入（如创建 session、保存 active session ID）应放在 `Future` 微任务中而非 post-frame callback 中。

- **callback 中的 async 操作未 await**：`onXxxChanged: (value) async { await write(); }` 改成了 async，但调用方没有 `await` 这个 callback。此时写入是 fire-and-forget，可能未完成就被 dispose。

- **Provider 跨页面缓存**：`autoDispose` 的 provider 在页面退出后会被 dispose，但同一页面内多次 rebuild 期间仍然缓存。确认 provider 的 `keepAlive` / `autoDispose` 设置是否符合预期。

- **日志不够详细**：打日志时只打 `'error'` 或 `'failed'` 没有上下文，排查时无法定位。日志必须包含：操作目标（novelId、sessionId 等标识）、请求参数、返回结果、异常类型和堆栈。

- **`loading` 态返回伪默认值**：禁止在 loading 时返回可编辑表单使用的默认数据替代真实数据。对只读展示可以给 fallback，对可交互表单必须显式显示 loading / disabled 态。

- **DB 字段类型与 Drift 预期不匹配**：raw SQL migration 中误用 `DATETIME` 而非 `INTEGER`（Drift 的 `dateTime()` 默认存 Unix 毫秒时间戳），且 `CURRENT_TIMESTAMP` 返回 TEXT。这会导致 `FormatException: Invalid radix-10 number`。Drift 侧的列类型与 SQLite 实际列声明一致并不代表数据格式一致——`PRAGMA table_info` 显示 INT 也可能存了 TEXT（SQLite 动态类型）。规则：所有时间戳使用 `INTEGER NOT NULL DEFAULT (strftime('%s', 'now') * 1000)`，禁止 `DATETIME DEFAULT CURRENT_TIMESTAMP`。

- **`Value.absent()` 误触发 SQL 默认值导致类型污染**：Drift `Companion.insert()` 中 `createdAt` 为 `Value.absent()` 时，INSERT 走 SQL 默认值 `CURRENT_TIMESTAMP`（TEXT），但后续读时 Drift 按 INTEGER 解析，崩溃。UPDATE 时 `Value.absent()` 保留原值（正确）。正确做法：始终从 Dart 侧传入时间戳（`DateTime.now()`），不在 DAO 中依赖 SQL 默认值。

- **StreamProvider 错误不可见**：stream 抛异常时 AsyncValue 只有 `hasError=true`，没有错误详情。排查时必须在 stream 链路上加 `.handleError((e, st) => debugPrint(...))` 才能看到异常。
