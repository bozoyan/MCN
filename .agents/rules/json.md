# JSON 存储规则

- Drift 表中具有明确 JSON 语义的列必须使用 `TypeConverter` 自动序列化/反序列化，禁止在业务层手动调用 `jsonEncode`/`jsonDecode`。
- 例外：`app_states`、`app_settings` 以及同类的通用 KV 表，其同一 `value` 列需要承载异构的标量或结构化值，可以由所属 Provider / Service 在领域边界集中手动编解码 JSON，不要为该 `value` 列配置全局 `TypeConverter`。
- KV 例外只适用于「一列承载多种值类型」的通用存储；专用业务表或具有单一 JSON 语义的列仍必须使用 `TypeConverter`，不得仅通过命名为 KV 规避本规则。
- 现有的 converter 定义在 `lib/shared/database/type_converters.dart`；需新增转换器时在此文件添加。
- 该规则确保数据读写路径一致，减少样板代码，防止类型不匹配。
