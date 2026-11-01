# 数据库时间戳规则

- 所有时间戳字段使用 Drift 的 `DateTimeColumn` + `dateTime()` 存储，映射为 SQLite `INTEGER`（Unix 秒时间戳）。禁止使用 `DATETIME`、`TEXT`、`TIMESTAMP` 等字符串格式。
- 参考现有惯例：`dateTime()` → 默认 `DateTime` 映射，`clientDefault(() => DateTime.now())` 设置当前时间。
- 编写 raw SQL migration 时，若需手动插入时间戳，使用 `unixepoch()`（秒），例如 `INTEGER NOT NULL DEFAULT (unixepoch())`。
- 新增或修改 schema 时，确保 Dart 侧 `dateTime()` 与 SQLite column type 一致（INTEGER），不一致则必须在 migration 中修复。
