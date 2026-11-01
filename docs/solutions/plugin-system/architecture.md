# 插件组成、运行时与上下文 API

> 本篇定义插件包、清单、运行时模型和插件可调用的 Host API。工具相关规则见[工具扩展点](tools.md)，存储与设置见[设置与存储](settings-and-storage.md)。任务进度只在[实施任务](README.md#实施任务)维护。

## 插件由什么组成

| 内容 | 职责 |
| --- | --- |
| 插件清单 | 声明稳定 ID、名称、版本、宿主 API 版本要求、入口、默认启用状态、支持平台、权限和配置字段 |
| 入口实现 | 打包为单文件的 JS，导出 `apply(context)`，向 Host 注册能力和处理函数 |
| 可选资源 | 界面描述、图标及其他插件资源 |

清单中的配置和权限可以在执行插件前读取，用户因此可以先查看权限、填写 API Key，再启用插件。运行能力在 `apply` 中注册，不在清单和入口里各维护一套相同的工具或页面定义。

内置插件和第三方插件使用同一种包格式。内置插件包随应用资源打包，第三方插件包由用户以 zip 安装；两者共用插件身份、注册归属、配置、权限、启停规则和存储，Host 不为内置插件另设代码路径。聊天页面和业务代码只通过注册表访问插件能力，不直接依赖某个内置插件。

### 清单结构

清单是插件包根目录下的 `plugin.json`：

```json
{
  "id": "example.search",
  "name": "Example 搜索",
  "description": "通过 Example API 搜索网页",
  "version": "1.2.0",
  "author": "someone",
  "pluginApiVersion": "^1",
  "main": "dist/index.js",
  "defaultEnabled": false,
  "platforms": ["windows", "macos", "android"],
  "permissions": ["character.read", "character.write"],
  "settings": {
    "apiKey": { "type": "secret", "title": "API Key", "required": true },
    "maxResults": { "type": "integer", "title": "默认结果数量", "default": 5, "min": 1, "max": 20 }
  },
  "uiProtocol": "reveric-ui-v1"
}
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 稳定标识，反向域名格式，匹配 `^[a-z0-9]+(\.[a-z0-9-]+)+$`；更新时据此识别同一插件 |
| `name` | 是 | 设置页展示名称 |
| `description`、`author` | 否 | 设置页展示信息 |
| `version` | 是 | semver，更新时比较新旧版本 |
| `pluginApiVersion` | 是 | 依赖的 Host API 主版本范围，规则见 [ADR-0009](../../adr/0009-plugin-capability-api-versioning.md)；不在支持范围内拒绝加载 |
| `main` | 是 | JS 入口，相对插件目录，单文件，不超过 2 MB |
| `defaultEnabled` | 否 | 首次登记时是否开启，默认 false |
| `platforms` | 否 | 支持的平台，取值 `windows`、`macos`、`android`；省略表示全部支持 |
| `permissions` | 否 | 使用的业务数据权限，安装时展示给用户确认 |
| `settings` | 否 | 配置字段，Host 据此生成表单，见[配置与凭据](settings-and-storage.md#配置与凭据) |
| `uiProtocol` | 否 | 注册 View 的插件必填，见 [ADR-0007](../../adr/0007-plugin-runtime-fjs-a2ui.md) |

约定：

- 工具和页面不写进清单，只在 `apply` 中注册。
- 网络请求不属于权限，不需要声明。
- 权限名采用 `资源.read`、`资源.write` 形式。当前作品读取与跨作品批量读取使用不同的权限名。首批权限名随 M2 的[业务数据 API](data-api.md) 确定，示例中的权限名仅作说明。
- `name`、`description` 及插件提供的其他展示文案第一版只有一种语言，不做多语言。
- 当前平台不在 `platforms` 中时，插件可以安装和登记，但不运行 `apply`，设置页显示“当前平台不支持”，不改变用户的启停选择。
- 未知字段忽略；已知字段类型错误、未知 `platforms` 取值或 `main` 指向包外路径时，清单无效，插件不加载。
- 内置联网检索插件的清单见[联网检索插件](web-plugin.md#插件清单)。

## Host 与插件如何交互

插件上下文提供三个方面的能力：

| 方面 | 插件做什么 | Host 做什么 |
| --- | --- | --- |
| 业务 API | 读取或修改章节、人物，发起网络请求 | 校验权限和业务规则，执行并返回结果 |
| 能力注册 | 注册 Tool、View 等扩展点 | 保存注册信息，在相应位置展示或调用 |
| 回调订阅 | 订阅事件，注册明确的业务 Hook | 在已实现的业务节点派发回调（后续迭代） |

```text
Host 激活插件
  → 新建运行时，执行插件代码
  → 调用 apply(context)，收集注册项
  → 校验注册项，写入注册表
  → 关闭运行时

用户或 Agent 发起操作
  → Host 在注册表中找到注册项
  → 检查插件状态及调用权限
  → 新建运行时，重新执行 apply 取得处理函数
  → 调用处理函数，插件按需调用 Host API
  → 返回结果，关闭运行时
```

`apply` 只负责注册当前插件的能力，不应发起搜索、生成内容或调用其他 Host API；`apply` 期间调用这些接口直接报错。工具执行、页面交互和业务事件分别由注册的处理函数接收。

注册只能在 `apply` 执行期间完成；`apply` 结束后再调用注册接口直接报错。插件能力变化通过停用、重新启用或更新版本生效，不支持运行中动态增删注册。

插件通过桥接调用 Host API，输入输出都是 JSON。Host 从运行时绑定的插件身份判断归属和权限，不信任插件在参数里自行声明的身份或权限。插件不持有 Drift、Riverpod、BuildContext 等宿主内部对象。

## 扩展点

下面列的是扩展能力，而不是互斥的插件类型。Host 只接受已实现的扩展点和挂载位置，调用未实现的注册接口时 `apply` 报错。

| 扩展点 | 插件提供 | Host 的调用时机 | 交付 |
| --- | --- | --- | --- |
| Tool | 静态工具定义、展示方式与处理函数 | Agent 发起工具调用时 | M1，见[工具扩展点](tools.md) |
| View | 页面 ID、标题、位置及界面描述 | 用户打开对应页面时 | M3，见[自定义 View](views.md) |
| Command | 命令 ID 与处理函数 | 用户动作或插件界面触发时 | 后续迭代 |
| Provider | 模型、认证及请求处理能力 | 获取模型、登录、发起 AI 请求等节点 | 后续迭代 |
| 菜单入口 | 显示位置、标题和目标命令 | 用户打开菜单及点击入口时 | 后续迭代 |
| Event、Hook | 指定业务节点的处理函数 | 业务操作前后 | 后续迭代，见[业务数据 API](data-api.md#event-与-hook) |

配置表单来自清单，Host 的插件设置页在插件未启用时也可展示，不依赖 `apply` 注册自定义 View。

### 注册归属与释放

每项注册归属一个插件。Host 校验重复 ID、名称格式、工具名冲突和挂载位置，校验失败时整个 `apply` 视为失败，本次注册全部不生效，其他插件继续运行。工具名冲突规则见[工具名与覆盖](tools.md#工具名与覆盖)。

停用时 Host 先拒绝新的调用，再从注册表移除该插件的全部注册项并关闭它打开的页面。正在执行的调用允许完成，结果照常返回；其运行时在调用结束时关闭。

运行时按次创建，插件无法持有跨调用的资源，因此不提供 `onDispose` 之类的清理回调。插件停用后，正在执行的调用不能再注册能力；结果返回时如果对应页面已关闭，Host 丢弃结果。

## 运行时模型

### 每次执行新建运行时

插件代码运行在 fjs（QuickJS）中。一个 QuickJS 运行时同一时间只执行一段代码，为避免排队和跨调用状态，每次执行都新建运行时，执行结束即关闭：

| 执行 | 时机 | 内容 |
| --- | --- | --- |
| 激活 | 插件启用、应用启动、插件更新后 | 执行入口文件，调用 `apply` 收集注册项 |
| 工具调用 | Agent 每次调用插件工具 | 执行入口文件，调用 `apply` 取得处理函数，再调用对应处理函数 |
| View 动作 | M3 中用户每次触发页面动作 | 同工具调用，处理函数换为页面动作处理函数 |

处理函数是 JS 函数，不能跨运行时保存，所以每次执行都重新调用 `apply` 取得处理函数。由此要求：

- `apply` 必须是确定的：同一版本插件每次注册的名称和定义相同。执行时注册结果与激活时不一致，本次调用返回 `plugin_registration_mismatch`。
- 插件不能依赖调用之间的内存状态。需要持久化的数据写入 `context.storage`（M2）；View 的页面状态由 Host 保存，每次动作时传入。
- 一次调用内可以并发发起多个 Host API 请求，例如同时抓取多个网页。

运行时沿用 codemode 的接入方式（见 [codemode/runtime.dart](../../../lib/shared/services/ai/codemode/runtime.dart)）：

- `JsBuiltinOptions.none()`，不开放 fjs 的文件、网络、进程等内置模块，也不能加载外部模块；入口文件必须是打包好的单文件。
- 与 Host 之间只通过一个桥接函数传递 JSON 字符串；Host 侧逐个校验请求类型、字段和大小。
- Host 先执行生成的前置脚本，定义 `context` 对象和桥接封装，再执行插件入口文件，最后调用入口导出的 `apply`。

桥接消息都是带 `kind` 字段的 JSON 对象，Host 只接受下表中的类型，其余一律拒绝并终止本次执行：

| kind | 方向 | 内容 |
| --- | --- | --- |
| `register` | 插件 → Host | 一项注册：扩展点类型和定义（不含函数） |
| `call` | 插件 → Host | 一次 Host API 调用：方法名（如 `http.fetch`、`log.info`）和参数；Host 返回结果或 `PluginHostError` |
| `result` | 插件 → Host | 处理函数的返回值或未捕获异常，结束本次执行 |

处理函数本身留在 JS 中，前置脚本按工具名保存，Host 通过执行脚本传入工具名和输入来调用。

### 入口约定

入口文件打包为 IIFE，把导出对象挂在全局变量 `__revericPlugin` 上，至少包含 `apply` 函数。内置插件的打包方式见[构建与打包](web-plugin.md#构建与打包)，第三方插件用相同约定。

### 资源限制

| 限制 | 取值 | 超出时 |
| --- | --- | --- |
| 入口文件大小 | 2 MB | 清单无效 |
| 堆内存 | 64 MB | `plugin_memory_limit` |
| 栈 | 1 MB | `plugin_memory_limit` |
| 激活执行总时长 | 5 秒 | 激活失败 |
| 工具调用总时长（含等待 Host API） | 60 秒 | `plugin_timeout` |
| 单个工具输入 | 256 KB | `invalid_argument` |
| 单个工具结果 | 256 KB | `plugin_invalid_result` |
| 单次执行中同时进行的网络请求 | 4 个，多余的排队 | 不报错 |
| 同一插件同时进行的执行 | 4 个，多余的排队 | 不报错 |

取值参照 codemode 现有限制。同一插件的执行数限制用于控制 Android 上的内存峰值：每个运行时最多 64 MB，四个并发即 256 MB。M1 的 T-01 会实测运行时创建耗时和内存，数据不达标时调整取值并更新本表。

### 取消

Agent 取消工具调用时，Host 关闭对应运行时，中止该次执行发起的网络请求，并按现有约定返回取消结果。已经发出的请求不保证对方未收到。

## 插件上下文 API

下面是插件可见的 TypeScript 类型，M1 起随 `plugins/sdk` 提供。标注了里程碑的接口在对应里程碑交付，之前调用会报错。

```ts
type Json = null | boolean | number | string | Json[] | { [key: string]: Json };

interface PluginContext {
  readonly plugin: { readonly id: string; readonly version: string };
  readonly tools: ToolsApi;          // M1
  readonly http: HttpApi;            // M1
  readonly log: LogApi;              // M1
  readonly storage: StorageApi;      // M2
  readonly settings: SettingsApi;    // M2
  readonly secrets: SecretsApi;      // M2
  // 业务数据 API 随 M2 增加，见 data-api.md；views、ui 随 M3 增加，见 views.md
}

interface ToolsApi {
  register(tool: ToolRegistration): void;   // 只能在 apply 中调用
}

interface ToolRegistration {
  name: string;
  description: string;
  inputSchema: Json;                          // JSON Schema，type 必须为 object
  display?: ToolDisplay;
  handler(input: { [key: string]: Json }, call: ToolCall): Promise<{ [key: string]: Json }>;
}

interface ToolDisplay {
  title?: string;                             // 卡片标题，省略时显示工具名
  summaryArg?: string;                        // 卡片标题后显示的参数名，如 "query"
  result?: "items" | "text" | "json";         // 结果预览方式，默认 "json"
  resultPath?: string;                        // 结果中待展示字段的名称，如 "results"、"content"
}

interface ToolCall {
  readonly callId: string;
  readonly cancelled: boolean;               // Agent 已取消时为 true
}

interface HttpApi {
  fetch(url: string, init?: HttpRequest): Promise<HttpResponse>;
}

interface HttpRequest {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE" | "HEAD";   // 默认 GET
  headers?: { [name: string]: string };
  body?: string;
  timeoutMs?: number;                         // 默认 20000，最大 60000
  maxBytes?: number;                          // 默认 5 MB，最大 5 MB
  responseType?: "text" | "base64";           // 默认 text
}

interface HttpResponse {
  status: number;
  url: string;                                // 跟随重定向后的最终地址
  headers: { [name: string]: string };        // 名称统一为小写
  body: string;
}

interface LogApi {
  info(message: string, data?: Json): void;
  warn(message: string, data?: Json): void;
  error(message: string, data?: Json): void;
}

interface StorageApi {                         // M2
  get(key: string): Promise<Json | null>;
  set(key: string, value: Json): Promise<void>;
  remove(key: string): Promise<void>;
}

interface SettingsApi { get(key: string): Promise<Json | null>; }   // M2
interface SecretsApi { get(key: string): Promise<string | null>; }  // M2
```

### 网络请求

- 只允许 `http`、`https` 地址，不限制目标域名。
- 自动跟随重定向，最多 5 次。
- 非 2xx 状态码正常返回，由插件判断；只有请求本身失败才抛错。
- `text` 响应的解码沿用现有 Web 工具的规则：响应头声明了 charset 时按声明解码，否则优先按 UTF-8 解码，失败时按 Latin-1。
- 响应体超过 `maxBytes` 时中止读取并抛错，不返回截断内容。
- 与现有 Web 工具一致，直接连接，不使用 AI 供应商上的代理配置。
- 未设置 `User-Agent` 时，Host 使用现有 Web 工具的桌面浏览器 UA。

请求失败时 Promise 以 `PluginHostError` 拒绝，`code` 取值：

| code | 含义 |
| --- | --- |
| `invalid_url` | 地址无效或不是 http、https |
| `network` | 连接失败、DNS 失败等，`message` 保留底层错误信息 |
| `timeout` | 超过 `timeoutMs` |
| `too_large` | 响应体超过 `maxBytes` |
| `cancelled` | 调用已取消 |
| `rate_limited` | 本次执行的请求总数超过 50 个 |

### 日志

`context.log` 写入应用日志，自动带上插件 ID。插件不得把凭据写入日志；Host 在写日志前把当前插件 `plugin_secrets` 中的值替换为 `***`。

## 结果与错误

工具处理函数必须返回 JSON 对象，Host 原样作为工具结果交给 Agent。插件可以沿用 Host 工具的错误约定，返回 `{ "ok": false, "error": "...", "error_code": "..." }`。

Host 生成的错误结果使用以下 `error_code`，`error` 字段保留实际错误信息，供 Agent 判断原因：

| error_code | 情形 |
| --- | --- |
| `plugin_unavailable` | 插件已停用、待配置、激活失败或当前平台不支持 |
| `plugin_error` | 处理函数抛出未捕获的异常；附带 `plugin_id` 和 JS 错误信息 |
| `plugin_timeout` | 超过执行总时长 |
| `plugin_memory_limit` | 超过堆或栈限制 |
| `plugin_invalid_result` | 返回值不是 JSON 对象，或超过大小限制 |
| `plugin_registration_mismatch` | 执行时的注册结果与激活时不一致 |

插件抛出的 `PluginHostError` 未被捕获时，按 `plugin_error` 返回，并在结果中保留其 `code`。面向用户的界面不直接显示这些原始信息，工具卡片按现有失败样式展示。

## 运行时与权限边界

- 插件逻辑只获取 Host 提供的能力，运行时不开放文件系统和进程能力。
- 网络请求经 Host 接口完成，不限制目标地址，也不作为需要授权的权限。
- 授权只针对业务数据读写：安装时确认，每次调用 Host API 时复查。
- JS 运行时隔离、超时和资源限制可以防止插件意外耗尽资源，但不等于操作系统级安全沙箱，见 [ADR-0008](../../adr/0008-plugin-security-capability-allowlist.md)。
- 宿主 API 只新增兼容能力时保持主版本；破坏签名或语义时升主版本，见 [ADR-0009](../../adr/0009-plugin-capability-api-versioning.md)。

## 改动清单（M1）

#### NEW: `lib/shared/models/plugin/manifest.dart`
- `PluginManifest`：解析并校验 `plugin.json`，按上文规则产出字段或无效原因。

#### NEW: `lib/shared/services/plugins/runtime.dart`
- `PluginRuntime`：单次执行，参照 `FjsRuntime` 创建引擎、执行前置脚本和入口、处理桥接请求、执行资源限制与取消；提供激活和调用处理函数两种入口。

#### NEW: `lib/shared/services/plugins/prelude.dart`
- 生成前置脚本：定义 `context`、注册接口、`PluginHostError` 及桥接封装；`apply` 结束后关闭注册接口。

#### NEW: `lib/shared/services/plugins/http.dart`
- `PluginHttpApi`：执行网络请求，处理重定向、超时、大小限制、解码、代理和取消；可注入请求函数供测试使用，取代现有 `webToolHttpGet`。

#### NEW: `lib/shared/services/plugins/registry.dart`
- `PluginRegistry`：保存每个插件的注册项，执行工具名冲突与覆盖规则，计算当前生效的工具集合。

#### NEW: `lib/shared/services/plugins/host.dart`
- `PluginHostService`：扫描内置插件、读取登记记录、按启停和平台决定激活、维护运行状态与失败原因、处理启停切换。

#### NEW: `lib/shared/providers/plugin_providers.dart`
- 暴露 `PluginHostService`、插件列表与运行状态，供设置页和工具接入使用。

#### `lib/main.dart`
- `_AppLifecycleWatcherState.initState` 中与 MCP 初始化并列，调用 `PluginHostService.start()`：登记内置插件并激活所有已开启的插件，不等待完成；失败写日志，不影响启动。
