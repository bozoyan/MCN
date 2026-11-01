# 插件注册表与权限授权持久化 = app Drift plugin_registry + plugin_permissions 表

插件需要持久化"已安装清单 + 启用状态 + 用户已授权限"，否则 app 重启后无法知道加载哪些插件、各自授过什么权限。决策：在 app Drift **与 `plugin_storage` 同一次 migration** 内新增 `plugin_registry` + `plugin_permissions` 两张表（见 [ADR-0010](0010-plugin-storage-drift-plugin-storage-table.md)）。**进 MVP，不后置**——这是 correctness / security 要求，不是 feature。

## 背景

[ADR-0008](0008-plugin-security-capability-allowlist.md) 规定权限"安装时显示给用户 + 运行时每次调用复校验"，但未规定授权存哪里。solution 4.3 安装流程第 4 步已做安装时授权。若不持久化：app 重启后要么每次重扫目录 + 重弹权限（体验差），要么授权不落地（安全洞——`PermissionManager.require` 无记忆）。原 solution 4.6 曾把注册表"后置到后续 migration"，与 ADR-0008 的授权模型冲突，本 ADR 推翻该延后。

## Considered Options

- **app Drift 加 `plugin_registry` + `plugin_permissions` 两表**（chosen）：与 `plugin_storage` 同 migration、同机制，无新依赖；结构化查询（按 plugin_id / 按 permission）；卸载一条 `DELETE` 清三表；DAO 层强制 `plugin_id` 过滤隔离。代价是一次 migration 建三表（可接受）。
- **复用 `plugin_storage`（KV）存注册 / 权限信息**：避免新表，但注册与权限是结构化关系（按 plugin_id 查启用、按 permission 查授权），塞进无 schema 的 JSON value 违反"Metadata 字段业务判断规则"（业务关系必须显式建模），且无法用 SQL 索引 / 聚合。**拒绝**。
- **文件持久化（plugin.json + permissions.json per 插件目录）**：跨平台简单、可用户查看；但并发写不安全、无事务、移动端同步不可靠、卸载需逐文件清。**拒绝**，仅保留为后续"插件导出 / 导入"的序列化形式。
- **后置到阶段 4**：solution 初版曾如此计划，但与 ADR-0008 安装时授权模型冲突（授权无处落地）。**拒绝**，进 MVP。

## Consequences

- 三张表（`plugin_storage` / `plugin_registry` / `plugin_permissions`）共用一次 `schemaVersion` +1（与 ADR-0010 合并 migration，见 solution 4.6）。
- `plugin_registry(plugin_id PK, version, enabled, manifest_path, installed_at, updated_at)`：app 启动读 `enabled=1` 的插件 → PluginManager 加载；enable / disable 写 `enabled` 字段。manifest 全文仍从插件目录读，registry 只存路径 + 摘要字段，避免双写不一致。
- `plugin_permissions(plugin_id, permission, granted_at)`：`PermissionManager.require(pluginId, permission)` 先查此表；安装时用户授权 → 写入；撤销权限 → 删行。
- 卸载：`PluginManager.uninstall()` 对三张表统一 `DELETE WHERE plugin_id = ?`（ADR-0010 已规定 `plugin_storage` 清理，另两表同步）。
- 权限升级：插件升级新增 permission → diff 旧授权 → 缺权限时重新弹窗 → 写入 `plugin_permissions`；未授权的新 capability 调用即被拒。
- DAO 层强制 `plugin_id` 过滤（与 `PluginStorageDao` 一致），单测锁定：插件 A 无法读 / 改插件 B 的注册与权限。
- 注册表是 app 级、跨小说（与 `plugin_storage` 一致），不污染 `novel_content` DB。
- 后续若需"按 permission 反查所有插件"等聚合查询，再加 index（遵循 `.agents/rules/db-index-naming.md`），不影响主表 schema。
