# 设置、状态、存储与安装

> 本篇定义“设置 / 插件”页面、插件状态、配置与凭据、数据库表、zip 安装与备份。任务进度只在[实施任务](README.md#实施任务)维护。

## 设置 / 插件

桌面端设置对话框和移动端设置页各新增“插件”入口，排在 MCP 之后。两端共用同一份页面内容。

| 里程碑 | 页面内容 |
| --- | --- |
| M1 | 插件列表：名称、版本、来源（内置 / 本地）、状态、开关；展开后显示描述、作者、当前提供的工具及其是否被其他插件覆盖、失败原因 |
| M2 | 增加：安装按钮（选择 zip）、配置表单、权限列表及撤销、更新（安装同 ID 新版本）、卸载（仅本地插件） |
| M3 | 无新增；插件页面入口在宿主导航中，见[自定义 View](views.md) |

不单独出设计稿，沿用现有设置页（如 MCP 设置）的列表、开关和详情样式实现。

### 插件状态

启用意愿与运行状态分开：用户打开开关不代表配置已齐全或运行时已就绪。

| 状态 | 条件 | 能力可用 |
| --- | --- | --- |
| 已关闭 | `enabled` 为 false | 否 |
| 当前平台不支持 | `platforms` 不含当前平台 | 否 |
| 待配置 | 已开启，但必填配置缺失（M2） | 否 |
| 激活中 | 正在执行激活 | 否 |
| 可用 | 激活成功 | 是 |
| 失败 | 清单无效、API 版本不兼容、激活失败或工具名冲突 | 否，显示原因 |

运行状态只保存在内存中，按 `enabled`、平台、配置完整性和激活结果计算；失败原因显示在设置页并写日志，不改变 `enabled`。

## 配置与凭据

M2 交付。插件在清单 `settings` 中声明配置字段，Host 负责表单、校验、持久化和运行时读取。

| `type` | 控件 | 其他属性 |
| --- | --- | --- |
| `string` | 单行输入 | `default`、`required`、`maxLength` |
| `text` | 多行输入 | `default`、`required`、`maxLength` |
| `integer`、`number` | 数字输入 | `default`、`required`、`min`、`max` |
| `boolean` | 开关 | `default` |
| `select` | 下拉选择 | `default`、`required`、`options: [{ value, label }]` |
| `secret` | 密钥输入 | `required` |

所有字段都有 `title`，可选 `description`。

插件对外只声明上表这种简化的 `settings`，不提供 A2UI 界面：表单必须在执行插件前就能展示，凭据的不回显、替换和清除由 Host 统一处理，插件之间的配置体验也保持一致。Host 内部把 `settings` 转换成 A2UI 消息，用[组件目录](views.md#渲染器与组件目录)渲染，与插件页面共用同一套组件：

| 部分 | 实现 |
| --- | --- |
| 字段模型与校验 | `lib/shared/models/plugin/setting_field.dart`：`parsePluginSettingFields` 解析清单 `settings`（已知属性类型错误、默认值不合规、`min > max`、选项重复等抛 `FormatException`，未知属性忽略）；`validatePluginSettingValue` 是保存前的唯一校验规则，T-09 的 service 写入前复用 |
| 表单 | `lib/shared/widgets/settings/plugins/config_form.dart` 的 `PluginConfigForm`：输入 `fields`、已保存的普通配置、已保存凭据的字段名和 `onSave` 回调；T-09 把它放进设置页，并在 `onSave` 中持久化 |
| 消息生成 | `config_surface.dart`：字段到组件的映射（`string` / `text` / `integer` / `number` / `secret` 用 TextField 的对应变体，`boolean` 用 Switch，`select` 用 ChoicePicker），以及把页面数据读回为提交内容 |

- 校验规则只在 Dart 侧维护一份：页面数据每次变化后，Host 用 `validatePluginSettingValue` 重算各字段，结果写入页面数据的 `/valid`，组件的 checks 只引用这些路径。字段在用户编辑后显示错误，保存按钮在全部规则通过前禁用；保存时再完整校验一次。
- 凭据原文不进入页面数据：输入框初始为空，已保存时占位提示「已设置，留空则保持不变」并显示「清空」。清空只标记待清除，点保存后才生效；必填凭据清空后要重新填写才能保存。`onSave` 收到的凭据只包含有变更的字段：新值或 `null`（清除）。
- 保存失败时表单显示「保存失败」，保留用户输入；底层错误只写日志。

插件运行时按需读取：

```js
const apiKey = await context.secrets.get("apiKey");
const maxResults = await context.settings.get("maxResults");
```

上下文已经绑定插件身份，两个读取接口只能访问当前插件的数据。凭据与普通配置一样保存在应用数据库中，不引入系统钥匙串或其他安全存储依赖；分开保存是为了让凭据不回显、不进入日志，而不是为了加密。

| 情况 | 预期行为 |
| --- | --- |
| 必填配置缺失 | 显示“待配置”，插件能力不可调用 |
| Key 已保存 | 设置页显示“已设置”，不回显原文，支持替换和清除 |
| Key 被替换 | 下一次调用读取最新值，不要求重启 |
| Key 被清除 | 必填时转为待配置，阻止新的调用 |
| 插件关闭 | 保留普通配置和凭据，停止提供能力 |
| 保存失败 | 明确提示失败，不把未保存值显示为已生效 |

配置完整与凭据有效是两件事，保存配置不发出网络请求。Key 不进入模型的工具参数、插件 View 的 DataModel、日志或工具结果（Host 配置表单的页面数据只临时持有用户正在输入的新值，保存后即清空）；Agent 只传业务参数，插件执行时通过 `context.secrets` 取 Key。

## 数据库

### 表结构

四张表都在 app 库（`reveric.sqlite`）中，内置插件和第三方插件使用同样的表和规则，不为内置插件预置数据或单独的开关存储。

| 表 | 主键 | 字段 | 职责 |
| --- | --- | --- | --- |
| `plugin_registry` | `plugin_id` | `version`、`source`、`package_path`、`enabled`、`created_at`、`updated_at`、`deleted_at` | 已知插件、当前版本、包位置和用户启停选择 |
| `plugin_permissions` | `plugin_id` + `permission` | `created_at`、`updated_at`、`deleted_at` | 用户对插件的授权记录 |
| `plugin_storage` | `plugin_id` + `key` | `value`（JSON 文本）、`created_at`、`updated_at` | 插件普通配置和插件自己的数据 |
| `plugin_secrets` | `plugin_id` + `key` | `value`、`created_at`、`updated_at` | API Key 等凭据，单独成表以便排除日志和回显 |

- `source`：`bundled` 随应用打包，`local` 用户安装。只用于找到插件包和决定能否卸载；加载、注册、启停、权限和配置的流程不按来源分支。
- `package_path`：内置插件为资源路径（如 `assets/plugins/reveric.web`），本地插件为相对应用数据目录的路径（如 `plugins/example.search/1.2.0`），备份恢复到其他设备后仍然有效。
- `plugin_storage` 中，配置字段的 key 为 `settings.<字段名>`，`context.storage` 的 key 为 `data.<key>`，两者互不可见。
- 单条 `plugin_storage.value` 不超过 256 KB，单个插件的 `data.*` 合计不超过 16 MB，超出时 `context.storage.set` 抛 `too_large`。
- 表结构只用列和主键声明，不使用外键、CHECK 等约束；`source` 等取值范围在 Dart 侧校验。时间戳使用 `dateTime()`。
- 所有 DAO 方法都带 `pluginId` 参数，查询都按 `plugin_id` 过滤。

### Migration

核对结果（2026-10-30）：最新正式发布 tag `v0.4.0` 中 app 库 `currentSchemaVersion` 为 1，当前分支同为 1，即当前 schema 已发布。因此新增四张表需要把 app 库升到 2，并在 `onUpgrade` 中增加 `from < 2` 的建表步骤。实施时如果当前分支已有尚未发布的 2，则把建表并入该版本。

```text
from version 1 to 2:
1. create table plugin_registry
2. create table plugin_permissions
3. create table plugin_storage
4. create table plugin_secrets
```

只新建表，不改动已有表和数据；新表初始为空，内置插件在首次启动时登记。降级打开新库时由现有版本检查拒绝。migration 测试使用 `v0.4.0` 的真实 app 库 fixture 升级到 2，断言 `user_version`、四张表结构与主键，以及已有表记录数不变。

## 状态规则

- **登记**：Host 启动时扫描内置插件。没有登记记录的插件按清单中的 `defaultEnabled` 写入 `plugin_registry`；用户安装的插件在安装完成时写入，`enabled` 为 false，用户开启后才运行。
- **启停**：用户开关只改 `enabled`。登记记录一经写入，后续启动和应用升级不再按 `defaultEnabled` 覆盖用户选择。
- **版本更新**：随应用升级的内置插件与用户更新的第三方插件同样处理：比较清单版本，更新 `version` 和 `package_path`，保留启停选择、配置和授权；新增权限需要用户确认后才激活。
- **授权**：用户确认后写入 `plugin_permissions`；撤销时设置 `deleted_at`，重新授权时清空该字段。
- **卸载**：只允许卸载 `source = local` 的插件，在 `plugin_registry` 上设置 `deleted_at`，保留配置、凭据和授权记录，重新安装同一 ID 时恢复。

## 安装、更新与卸载

M2 交付。安装包为 zip。

### 包格式

```text
example-search-1.2.0.zip
  plugin.json
  dist/index.js
  其他资源
```

- `plugin.json` 必须在 zip 根目录。
- zip 不超过 10 MB，解压后合计不超过 20 MB，条目不超过 500 个。
- 拒绝绝对路径、包含 `..` 的路径和符号链接条目。

### 安装与更新流程

```text
1. 用户在“设置 / 插件”选择 zip（按项目文件访问规则处理移动端路径）
2. 解压到临时目录，校验包格式、清单、pluginApiVersion、main 文件和大小；不执行插件代码
3. 同 ID 已安装时：新版本号必须高于当前版本；比较权限，列出新增权限
4. 展示插件信息与权限（更新时只列新增权限），用户确认
5. 移动到 plugins/<id>/<version>/
6. 在一个事务中写入或更新 plugin_registry，并写入授权记录
7. 更新时删除旧版本目录 plugins/<id>/<旧版本>/
8. 新安装保持关闭；更新时若插件已开启，用新版本重新激活
```

任一步失败时，删除临时目录，数据库和已安装版本保持不变，原版本继续可用。第 6 步失败时同时删除第 5 步移入的新版本目录。第 7 步在第 6 步事务提交后执行，此时登记记录已指向新版本；正在执行的调用已把入口代码读入内存，不受影响。删除旧版本目录失败时只记录日志，不影响更新结果，下次启动时清理 `plugins/<id>/` 下非当前版本的目录。删除范围只限插件包文件，不涉及配置、凭据、授权和业务数据。

当前平台不在 `platforms` 中时允许安装，状态显示“当前平台不支持”。

### 卸载

卸载只设置 `plugin_registry.deleted_at` 并移除注册项，不删除插件目录、配置、凭据和授权记录。重新安装同一 ID 时清空 `deleted_at`，恢复原有设置。

## 备份

备份对整个 app 库打包，因此插件表（包括 `plugin_secrets`）随备份保存，与 AI 供应商 Key 的现状一致。M2 把 `plugins` 目录加入备份目录列表，恢复后本地插件包和登记记录对应；恢复不改变插件的启停选择。

## 改动清单

#### `lib/shared/database/app_database.dart`（M1）
- 新增四张表定义，`currentSchemaVersion` 升到 2，`onUpgrade` 增加建表步骤。

#### NEW: `lib/shared/database/daos/plugin_dao.dart`（M1）
- `PluginDao`：四张表的读写，所有方法带 `pluginId`；M1 用到登记与启停相关方法。

#### NEW: `lib/desktop/widgets/settings/settings_plugins_section.dart`（M1）
- 桌面设置对话框的插件 section，包装共用页面内容。

#### `lib/desktop/widgets/settings/settings_dialog.dart`（M1）
- 新增 `plugins` 导航项，排在 `mcp` 之后。

#### NEW: `lib/shared/widgets/settings/plugins/section.dart`（M1）
- 插件列表、状态、开关和详情；M2 增加安装、配置、权限、更新与卸载。

#### `lib/mobile/pages/settings_page.dart`（M1）
- 新增插件导航项，进入共用页面内容。

#### i18n（M1、M2）
- 新增 `settings.plugins*` 系列 key，加到 `assets/translations/en/settings.json`、`assets/translations/zh-CN/settings.json` 及 `lib/shared/localization/locale_keys.dart`。

#### NEW: `lib/shared/services/plugins/installer.dart`（M2）
- `PluginInstallOrchestrator`：zip 校验、解压、权限比较、目录移动与登记事务。

#### `lib/shared/services/backup_service.dart`（M2）
- `_backupEntries` 增加 `plugins`。
