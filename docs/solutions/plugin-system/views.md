# 自定义 View

> M3 交付，其中渲染器与组件目录可与 M1 并行开发。本篇定义插件页面的注册、显示、状态、渲染器、组件目录和 UI 协议。任务进度只在[实施任务](README.md#实施任务)维护。

## 注册与显示

插件注册“人物整理”独立页面：

```js
export function apply(context) {
  context.views.register({
    id: "character-organizer",
    title: "人物整理",
    location: "plugin.page",
    source: "views/character-organizer.json",
    actions: {
      refresh: (data, event, call) => loadCharacters(context, data),
      save: (data, event, call) => saveCharacters(context, data),
    },
  });
}
```

- `plugin.page` 是独立插件页面位置，入口显示在宿主导航中。M3 只开放这一个位置；侧栏、人物详情面板、编辑器菜单等位置列入[后续迭代](README.md#后续迭代)。
- `source` 相对于插件目录，Host 校验资源属于当前插件。插件 ID 与页面 ID 共同作为页面身份。
- `source` 文件是一组 A2UI 消息（创建界面、更新组件、更新数据），格式见 [UI 协议与版本](#ui-协议与版本)。界面 ID 由 Host 分配，文件中的界面 ID 会被替换。
- action 处理函数收到当前页面数据快照和事件，返回一组数据更新 `[{ "path": "/characters", "value": [...] }]`，语义与 A2UI 的“更新数据”消息相同。
- 通知、确认框和选择器通过 `context.ui` 提供，不必为临时交互注册完整页面。

```text
views.register
  → 注册表保存页面归属和描述
  → 宿主导航显示“人物整理”

用户打开页面
  → PluginSurfaceHost 挂载页面
  → 读取 source 中的 A2UI 消息，交给渲染器建立界面和页面数据
  → 渲染器按组件目录构建 Flutter 组件

用户点击页面按钮
  → 渲染器把 action 交给该界面的事件处理方（插件页面即插件）
  → Host 新建运行时，调用对应 action，传入页面数据快照和事件
  → action 按需调用 Host API，返回数据更新
  → 渲染器应用更新，刷新相关组件
```

## 页面状态

插件运行时每次执行后关闭（见[运行时模型](architecture.md#运行时模型)），所以页面状态由 Host 持有：

- 每个页面实例有自己的 DataModel，保存草稿、选中项等界面状态，不镜像到全局 Riverpod，见 [ADR-0011](../../adr/0011-plugin-ui-state-boundary-datamodel-riverpod.md)。
- action 收到页面数据快照，返回按路径的数据更新；渲染器应用后刷新。同一页面的 action 按顺序执行，前一个返回后再执行下一个。
- 业务数据通过 Host API 读写，宿主继续通过自己的状态管理观察业务变化。
- 关闭一个页面不影响同插件的其他页面；页面关闭后返回的 action 结果直接丢弃。
- 插件停用时关闭它的全部页面。
- 页面含未保存编辑时，关闭前由 Host 弹出确认。

## 渲染器与组件目录

渲染分两层：

| 层 | 实现 | 职责 |
| --- | --- | --- |
| 协议层 | `a2ui_core`（纯 Dart，不依赖 Flutter） | 解析与校验 A2UI 消息（创建界面、更新组件、更新数据、删除界面），维护页面数据模型，解析 `path` 绑定与表达式，按组件目录的 JSON Schema 校验界面 |
| Flutter 层 | 自行实现 | 组件目录中每个组件的 builder；把扁平组件组装为 Widget 树，数据变化时只刷新受影响的组件；把组件上的 `action` 交给该界面注册的事件处理方 |

事件处理方可以替换，渲染器不关心处理方是谁：插件页面交给插件 action，以后 AI 生成的界面交给 Agent。

依赖选择：

- 不引入 `genui`。它标注为 “highly experimental”，正在拆分重写，且面向 AI 在对话中生成界面；插件页面是固定界面描述加插件处理事件，组件目录无论如何都要包装项目自己的组件。
- 引入 `a2ui_core` 作为协议层。它由官方 A2UI 仓库维护，支持 A2UI v0.9 与 v1.0，协议细节与官方一致，以后 AI 生成界面时也用它解析和校验模型输出。
- `a2ui_core` 仍是 0.x，更新频繁：锁定版本；只在渲染器内部使用，插件只认 `reveric-ui-v1`，接触不到它的 Dart 类型；它出现破坏性变化时只改渲染器内的适配代码。引入前按 `.agents/rules/local-dependencies.md` 处理。
- 官方 Flutter 渲染包（`a2ui_flutter`）发布并稳定后，可再评估是否替换 Flutter 层；界面格式一致，替换不影响插件。
- 采用 A2UI v1.0，`a2ui_core` 锁定 0.4.0。v1.0 目前是候选版，正式发布前若有不兼容变化，由渲染器跟进，`reveric-ui-v1` 在首个正式版之前随之调整。
- 渲染器位于 `lib/shared/widgets/a2ui/`：`session.dart` 持有单个界面的协议状态与 action 队列，`surface_view.dart` 与 `node_view.dart` 渲染组件树并按节点订阅刷新，`catalog.dart` 组装组件目录，`components/` 为各组件 builder。插件页面和以后的 AI 界面都通过 `A2uiSurfaceSession.load` 加载消息，用 `A2uiSurfaceView` 显示。

组件目录的每个条目包含：组件名称、一句用途说明、属性 JSON Schema、Flutter builder、支持的数据绑定属性和事件。属性 Schema 用于校验界面描述，用途说明和 Schema 以后也用于生成让 AI 绘制界面的提示词，所以两者都必须完整。

组件实现包装项目已有 Widget，沿用主题、间距、字体、输入框和操作菜单。组件目录 ID 为 `reveric-ui-v1`；`createSurface` 未写 `catalogId` 时由宿主补上。A2UI v1.0 基础目录已有的组件沿用官方名称与属性 Schema（直接取自 `a2ui_core` 的基础目录），基础目录没有的由 Reveric 补充：

| 组件 | 来源 | 主要属性 | 写回 / 事件 | 包装 |
| --- | --- | --- | --- | --- |
| Column、Row | 基础 | `children`、`justify`、`align`，子组件可设 `weight` | — | `Flex`，间距取 `RevericSpacing` |
| List | 基础 | `children`（常用数据模板）、`direction`、`align` | — | 高度有界时按需构建（`ListView.builder`），无界时退回普通排版；横向列表支持鼠标滚轮 |
| Card、Divider | 基础 | `child`；`axis` | — | `RevericElevatedCard`、主题分割线 |
| Text | 基础 | `text`、`variant`（`body` / `caption`） | — | 纯文本用 `Text`，含 Markdown 标记时用 `AiMarkdownText` |
| Icon | 基础 | `name`（基础目录的 59 个图标名） | — | 映射到 `RevericIcons`（Phosphor）；`svgPath` 不支持，显示帮助图标 |
| Button | 基础 | `child`（只能是 Text 或 Icon）、`variant`（`default` / `primary` / `borderless`）、`checks` | `action` | `RevericButton.secondary` / `.primary` / `.text`，Icon 子组件用 `RevericIconButton`；checks 未通过时禁用，action 处理中显示加载 |
| TextField | 基础 | `label`、`placeholder`、`variant`（`shortText` / `longText` / `number` / `obscured`）、`checks` | `value` | `RevericTextField`；IME 组词期间不写回 |
| ChoicePicker | 基础 | `label`、`options`、`variant`（单选 / 多选）、`displayStyle`（`checkbox` / `chips`）、`checks` | `value`（字符串数组） | 单选用 `RevericSelect`，多选用复选框列表，chips 用 `RevericFilterChip`；`filterable` 暂不支持 |
| CheckBox | 基础 | `label`、`checks` | `value` | `RevericCheckbox` 整行可点 |
| Gap | 自定义 | `size`（`xs`–`xl`） | — | 固定间距 |
| Markdown | 自定义 | `text` | — | `AiMarkdownText`，支持代码块与链接 |
| Loading | 自定义 | `label` | — | `RevericSpinner` |
| Switch | 自定义 | `label`、`checks` | `value`（布尔） | `RevericSwitch` |

基础目录中的 Image、Video、AudioPlayer、Tabs、Modal、Slider、DateTimeInput 暂不进入目录；人物选择器、章节选择器等业务组件按需求增加。自定义组件的 Schema 都带一句用途说明，与基础组件的 Schema 一起用于以后生成 AI 提示词。

- **校验提示**：A2UI v1.0 中校验函数自带的消息优先于 check 的 `message`，而 `a2ui_core` 内置函数的消息是英文。目录中的 `required`、`regex`、`length`、`numeric`、`email` 只返回是否通过，界面显示 check 里按用户语言写的 `message`；未写 `message` 时显示本地化的通用提示。输入组件在用户编辑后才显示错误。
- **滚动与表单**：界面高度有界时，根节点为 List 则由列表自己滚动，其他根节点外包 `SingleChildScrollView`；高度无界（如嵌在聊天卡片里）时按内容高度排版。A2UI 的输入值即时写入页面数据，`checks` 直接对页面数据求值，不依赖 Widget 存活，因此 List 可以按需构建，不受项目表单「禁止惰性回收字段」规则约束。
- **上限**：一个界面最多 500 个组件 ID、嵌套 32 层；一次加载的消息或一次 action 返回的数据更新序列化后不超过 1 MB。插件页面文件只能包含 v1.0 的 `createSurface`（首条）、`updateComponents`、`updateDataModel`；Agent 后续推送还可以 `deleteSurface`。校验失败时整个界面显示局部错误，错误码和原因写入日志，供插件作者与 Agent 排查。
- **事件处理方**：`A2uiActionHandler` 收到 action 名、来源组件、已解析的 context 和页面数据快照，返回 `A2uiDataUpdate` 列表。同一界面的 action 按触发顺序执行；处理方抛错时记录日志并回调 `onActionError`，下一个 action 照常执行；界面关闭后返回的结果丢弃。
- 内置插件的 View 同样使用 A2UI 消息和组件目录，不直接提供 Flutter Widget。
- 调试入口：设置 → 调试 →「A2UI 组件预览」，可切换内置样例和插件配置表单，查看页面数据与事件记录；样例同时作为测试夹具。

## 自定义工具卡片

M3 起，插件注册工具时可以提供 `display.view`，指向一份界面描述，用同一套渲染器和组件目录渲染工具结果；工具结果作为只读页面数据传入，卡片不触发 action。未提供时继续使用[通用插件卡片](tools.md#工具卡片)。

- 历史卡片始终用当前安装的插件版本中的界面描述渲染。插件更新后，旧调用的结果交给新版本的界面描述显示，插件自己负责兼容旧结果的字段。
- 插件已卸载、已停用、新版本不再提供 `display.view`，或界面描述渲染失败时，退回通用卡片，按调用时保存的 `display` 显示。插件声明 `display.view` 时应同时填写 `summaryArg`、`result`、`resultPath`，保证退回后仍可读。

## UI 协议与版本

- 对外 UI 协议名为 `reveric-ui-v1`，写在清单的 `uiProtocol` 中，对应 A2UI v1.0 的消息与组件格式（`"version": "v1.0"`，绑定写作 `{"@path": ...}`，函数调用写作 `{"@call": ..., "args": ...}`），加上本项目的组件目录 `reveric-ui-v1`。
- 不扩展 A2UI 协议本身：消息类型、属性写法、`path` 绑定、`action` 都按 A2UI v1.0。可以自定义的只有组件目录，这是 A2UI 允许的。这样插件页面与以后 AI 生成的界面使用同一种格式、同一个渲染器和同一套组件。
- A2UI 升级时由渲染器跟进；能兼容旧格式时 `reveric-ui-v1` 不变，不能兼容时新增 `reveric-ui-v2`，渲染器同时支持两版，见 [ADR-0007](../../adr/0007-plugin-runtime-fjs-a2ui.md)。
- UI 协议与宿主业务 API 分别版本化。每个组件的属性和事件都属于契约，只新增兼容能力时不升版本。
- 暂不把 WebView、动态 Dart 执行、任意原生库加载或独立进程扩展纳入范围。
