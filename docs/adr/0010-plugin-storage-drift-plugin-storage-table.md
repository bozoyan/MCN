# 插件数据存储 = app Drift 加 plugin_storage 表

插件需要持久化自己的数据（配置、缓存、业务状态），且必须与其他插件、与 app 数据隔离。决策：在 app Drift database 新增 `plugin_storage` 表，schema 为 `(plugin_id TEXT, key TEXT, value TEXT, updated_at INTEGER)`，主键 `(plugin_id, key)`，value 存 JSON 字符串。DAO 层强制按 `plugin_id` 过滤，插件无法跨域读写。走现有 Drift migration 机制（遵循 `.agents/rules/db-migration.md`），不引入新存储依赖。

## Considered Options

- **app Drift 加 plugin_storage 表**（chosen）：统一走现有 Drift + migration 机制，无新依赖，支持基础查询（按 plugin_id / key 索引），value JSON blob 支持任意结构。隔离靠 DAO 层强制 plugin_id 过滤。代价是 value 是无 schema 的 JSON，复杂查询需在应用层做。
- **shared_preferences namespace**（`plugin_<id>_` 前缀）：简单但非结构化、性能差、不适合大量数据、无并发安全、移动端有尺寸限制。**拒绝**。
- **每插件独立 Drift database**：真隔离（文件级），但 migration 膨胀（每插件一份 schemaVersion）、连接管理复杂、打开/关闭开销大、清理需逐库处理。**拒绝**，隔离需求由 DAO 层过滤即可满足。
- **文件 KV（每插件目录 + JSON 文件）**：跨平台简单、可用户查看；但并发写不安全、无事务、性能差、大量小文件 IO 开销。**拒绝**，仅保留为后续"插件导出/导入"的序列化形式。

## Consequences

- 新增 `plugin_storage` 表，按 `.agents/rules/db-migration.md` 同步：app DB `schemaVersion` +1、`onUpgrade` 加建表语句、Dart 模型类 + DAO 同步生成（`flutter pub run build_runner build`）。
- value 存 JSON 字符串（Drift TEXT 字段 + JSON codec），插件可存任意可序列化结构。复杂查询（索引、聚合）由插件在应用层处理，或后续按需加 index / 独立表。
- 隔离边界：`PluginStorageDao` 所有方法强制带 `pluginId` 参数，查询 SQL 始终带 `WHERE plugin_id = ?`。单测锁定：插件 A 无法读插件 B 的数据。
- 单条 value 大小上限由 `plugin_security/resource_limiter.dart` 控制（建议 256KB / 条，单插件总量 16MB），防插件滥用 DB。
- 删除插件时 `PluginManager.uninstall()` 触发 `DELETE FROM plugin_storage WHERE plugin_id = ?`，确保清理。
- 不污染 novel_content DB（小说数据隔离）；插件数据是 app 级、跨小说。
- 后续若出现"插件需要结构化查询"的真实场景，可独立加表（如 `plugin_<id>_custom`），仍走 Drift migration，不影响 `plugin_storage` 主表。
