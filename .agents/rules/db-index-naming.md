# 数据库索引命名规则

- 索引名称统一使用 `{table}_by_{column}` 格式。
- 唯一索引在名称后添加 `_u` suffix，即 `{table}_by_{column}_u`。
- 多列索引使用下划线连接列名，例如 `{table}_by_{column1}_{column2}`。
- 在 Drift 中，`uniqueKeys` 会自动创建唯一约束，索引名称由数据库自动生成。如需完全控制索引名称，应在 migration 中手动创建索引。
