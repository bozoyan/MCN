# 代码风格规则

## 控制流

- **所有控制流语句（`if`、`else`、`for`、`while`、`do-while`）必须使用大括号 `{}`**，即使只有单条语句。
- 禁止省略大括号的单行写法，例如 `if (condition) doSomething();` 一律改为 `if (condition) { doSomething(); }`。
- 该规则通过 `curly_braces_in_flow_control_structures` lint 强制生效。

## 日志入口与模块

- 业务日志统一通过 `AppLogger.forModule('ModuleName')` 创建的模块日志器输出，包括启动、生命周期和全局错误桥接。静态 `AppLogger` 输出方法仅供日志封装内部使用；级别配置仍通过 `AppLogger` 管理。
- 文件顶部声明 `final _log = AppLogger.forModule('ModuleName');`，或在实例中持有一次创建的日志器；不要在打印时、getter 或 `build()` 中反复创建。已有模块日志器直接复用。
- 模块名使用稳定的业务名称。供应商类型、插件 ID、会话 ID 等动态值放进消息字段，不拼入模块名；移除消息里重复的模块前缀，但保留 `[DB]`、操作名称、记录 ID、错误对象和堆栈等诊断信息。

## Debug / Trace 日志

- 动态 debug / trace 日志必须先在调用处判断模块日志器的 `isDebugEnabled` / `isTraceEnabled`，再构造消息。这些 getter 与实际输出共享运行时级别判断，保留 Release 动态开启诊断日志的能力。
- 字符串插值、JSON 编码、堆栈获取、集合遍历及仅用于日志的中间计算，全部放进判断分支；不要先计算再判断。
- 不使用消息回调或闭包式延迟日志接口：关闭时也应避免创建消息闭包。仅在 `debug(String message)` 内过滤无法省掉调用前的参数求值。
- 固定字符串可以直接调用 `debug` / `trace`，日志入口负责提前过滤。不要统一用 `kDebugMode` 或 `assert` 禁用 Release 诊断日志。
- 临时排查结束后清理逐步打点、重建日志、无条件堆栈及只为这些日志存在的变量、Hook 和注释代码；保留有排障价值的诊断信息。

```dart
final _log = AppLogger.forModule('Example');

if (_log.isDebugEnabled) {
  final payload = jsonEncode(result);
  _log.debug('result=$payload');
}

if (_log.isTraceEnabled) {
  _log.trace('stack=${StackTrace.current}');
}
```
