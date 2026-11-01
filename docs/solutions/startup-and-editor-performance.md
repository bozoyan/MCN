# 启动与编辑器页面性能优化方案

## 现状总结

冷启动加载链（阻塞型）：
```
main()
 ├─ PromptTemplateService.loadAll()         — 38 个 .md 文件同步读取并解析 Mustache
 ├─ _configureDesktopWindow()              — SharedPreferences + WindowManager
 └─ runApp()
      └─ MyApp.build()
           ├─ appSettingsNotifierProvider   — DB 打开 + 18 次独立 key-value 读取 + 18 次独立写回
           ├─ onboardingCompletedProvider   — 独立 AppDatabase 实例 + 1 次 DB 读取
           └─ storageCleanupScheduler       — 后台定时器
```
→ 在 `appSettingsNotifierProvider` + `onboardingCompletedProvider` 完成前，UI 停留在 `_LoadingScreen`（CircularProgressIndicator）。

进入 NovelEditor 时：
- **21 个 provider 在 `build()` 中被 watch**，其中 14 个是 StreamProvider（Drift DAO `.watch()`）
- 14 个内容 StreamProvider **同时触发**（chapters, worldbuilding, outlines, materials, characters, skills, items, factions, foreshadowings, maps, workingChanges, chat sessions + workingOverlay）
- AiChatPanel **eagerly 构建**（默认 `aiPanelCollapsed = false`），触发 7+ 个额外 provider + session 恢复
- LeftSidebar 同步渲染 15+ 个 `SvgPicture.asset` + `File.existsSync()` + `Image.file()` decode
- `workingOverlayServiceProvider` 触发 `ChapterEmbeddingSyncQueue` 创建 + `drainPending()` 调用

---

## 优化方案

### 一、Cold Start 优化（启动 → 首页）

#### 1.1 批量读取 app_settings，消除 18 次独立 key-value 查询

**问题：** `AppSettingsNotifier._loadSettings()` 用 18 次 `appSettingsDao.get(key)` 独立查询，每次一个 SQL `SELECT`。

**方案：** 在 `AppSettingsDao` 新增 `getAll()` 方法，返回 `Map<String, String>`：
```sql
SELECT key, value FROM app_settings
```
一次查询替代 18 次，约省 15-40ms。

**文件：**
- `lib/shared/database/app_database.dart` — AppSettingsDao 新增 `getAll()`
- `lib/shared/providers/settings_providers.dart` — `_loadSettings()` 改用 `getAll()`

#### 1.2 移除启动时的 `_persistFullSnapshot()` 无条件写回

**问题：** `_loadSettings()` 读取完所有设置后，调用 `_persistFullSnapshot()` 把 18 个设置无条件写回 DB（即使没变化）。首次安装时这些 key 本就不存在，写入无意义；后续启动时数据没变，写入浪费。

**方案：** 
- 删除 `_loadSettings()` 末尾的 `_persistFullSnapshot()` 调用
- 仅在 settings 实际被用户修改时（`setTheme`/`setLanguage` 等 setter）才写入
- `_persistFullSnapshot` 改为仅迁移场景使用（首次从 SharedPreferences 迁移到 DB 后写一次），通过 `_needsMigration` flag 控制

**文件：** `lib/shared/providers/settings_providers.dart`

#### 1.3 共享 AppDatabase 实例，消除重复构造

**问题：** `appSettingsDatabaseProvider`（keepAlive）和 `appDatabaseProvider`（keepAlive）各自构造一个 `AppDatabase()`。虽然是同一个 SQLite 文件，但 `AppDatabase()` 构造函数会执行 `_openConnection()`。

**方案：** 让 `appSettingsDatabaseProvider` 直接复用 `appDatabaseProvider`，或让 `AppDatabase` 使用真正的单例。

**文件：** `lib/shared/providers/settings_providers.dart`，`lib/shared/database/app_database.dart`

#### 1.4 按需加载 Prompt 模板

**问题：** `PromptTemplateService.loadAll()` 在 `main()` 中阻塞执行，一次加载 38 个 .md 文件。

**方案：** 
- 将 `loadAll()` 移到后台 isolate 或改为首次使用时延迟加载
- 或者改为：启动时只加载必要的 prompt（如 onboarding 相关的），其余按需加载

**文件：** `lib/shared/services/ai/prompt_template.dart`，`lib/main.dart`

### 二、Novel Editor 页面优化

#### 2.1 延迟加载内容 Provider — 只 watch 当前选中 section 的数据

**问题：** `NovelEditorPage.build()` 一次 watch 了 14 个内容 StreamProvider，包括 chapters、worldbuilding、outlines、materials、characters、skills、items、factions、foreshadowings、maps、workingChanges、chat sessions、workingOverlay。实际上用户同一时间只在看一个 section。

**方案：** 
- 将 `chaptersAsync`～`workingChangesAsync` 的 watch 从 `build()` 中移除
- 改为在 `NovelWorkspacePanel` 或其子 widget 内按需 watch
- 或者写一个根据 `selection` 动态 watch 的逻辑（用 `ref.watch` 的条件分支）
- 初始渲染只需要 `novelProvider(novelId)` + `novelsProvider`

**文件：**
- `lib/desktop/pages/novel_editor.dart` — 删除 14 个内容 provider 的 watch
- `lib/desktop/widgets/workspace/novel_workspace_panel.dart` — 接收 `selection` 参数，内部按需 watch

#### 2.2 AiChatPanel 延迟初始化

**问题：** `AiChatPanel` 默认 eagerly 构建（`aiPanelCollapsed = false`），触发 session 恢复、agent profile 加载、subagent 加载。

**方案：**
- `aiPanelCollapsed` 默认值改为 `true`
- 用户点击展开时才创建 `AiChatPanel`
- 折叠态只渲染 `_CollapsedAiPanel`（极简占位 widget）

**文件：** `lib/desktop/pages/novel_editor.dart` 第 191 行

#### 2.3 `workingOverlayServiceProvider` 延迟初始化

**问题：** `workingOverlayServiceProvider` 触发 `ChapterEmbeddingSyncQueue` 创建并立即调用 `drainPending()`，还级联 watch 多个 AI model resolution provider。

**方案：**
- 不在 `NovelEditorPage.build()` 中 watch
- 改为在需要时才获取（比如进入 chapter editing 模式，或 AI 返回 working changes 后）
- 或者将其改为 `autoDispose` + family，仅在需要时创建

**文件：** `lib/desktop/pages/novel_editor.dart` 第 295 行，`lib/shared/providers/working_overlay_providers.dart`

#### 2.4 Sidebar 图标延迟渲染 + 封面异步加载

**问题：** LeftSidebar rail 同步构建 15+ 个 `SvgPicture.asset`，header 中 `File.existsSync()` 阻塞 UI 线程。

**方案：**
- 封面检查改用 `File.exists()`（async）+ `FutureBuilder`
- SvgPicture 添加 `RepaintBoundary` 包裹，减少不必要的重绘
- 可以将 sidebar rail 的图标改为 `precache` 或使用 `Image.asset`（PNG）替代 SVG 以获得更快的首帧渲染

**文件：** `lib/desktop/widgets/sidebar/left_sidebar_rail.dart`，`lib/desktop/widgets/sidebar/left_sidebar_header.dart`

#### 2.5 将 15 个 TextEditingController 和 14 个 FocusNode 移到需要的子 widget

**问题：** `NovelEditorPage.build()` 顶部创建了 15 个 `useTextEditingController()` 和 14 个 `useFocusNode()`，然后作为参数传给 `NovelWorkspacePanel`。这些 controller 在页面加载时全部初始化。

**方案：**
- 将 controller/focusNode 移到具体使用的 editor widget 内部（如 `ChapterEditor` 内创建 `chapterTitleController`）
- `NovelWorkspacePanel` 只接收数据和回调，不接收 controller

**文件：** `lib/desktop/pages/novel_editor.dart`，`lib/desktop/widgets/workspace/` 下各 editor

### 三、Onboarding 期间预初始化

#### 3.1 在 onboarding 第二步（用户填 profile）期间，后台执行 agent 初始化

**问题：** `ensureAppInitializationTasks()` 懒加载执行——首次访问 agent profile provider 时才跑 4 个 seed task。这个时机通常发生在进入首页后，阻塞侧边栏的 agent 列表渲染。

**方案：**
- Onboarding page 的 `_UserProfileStep` 或 `_AiProviderStep` mount 时，后台调用 `ensureAppInitializationTasks()`
- 由于初始化有 `_initLock` 保护，可以安全地在后台跑
- 用户填 profile 和 API key 通常需要数秒到数十秒，足够跑完 seed tasks

**文件：** `lib/desktop/pages/onboarding.dart`

#### 3.2 预打开 AppDatabase，在 onboarding 期间预热

**问题：** 首页 provider 首次打开 `AppDatabase` 时才执行 migration（如有）和 SQLite 连接建立。

**方案：**
- Onboarding page 构建时提前触发 `ref.watch(appDatabaseProvider)`（或 `ref.read`），让 DB 连接在后台建立
- 不影响 onboarding UI（onboarding 不依赖 DB 内容，除了 `completeOnboarding` 时才写入）

**文件：** `lib/desktop/pages/onboarding.dart`

#### 3.3 预加载 Prompt 模板在 onboarding 期间

**问题：** `PromptTemplateService.loadAll()` 已在 `main()` 中执行，所以 onboarding 期间不需要额外处理。但如果改为懒加载模式（见 1.4），可以在 onboarding 时后台预加载。

### 四、实施优先级与预估影响

| 优先级 | 优化项 | 影响范围 | 预期改善 |
|--------|--------|----------|----------|
| **P0** | 2.1 延迟加载内容 provider | Editor 首帧 | **最大** — 14 个 StreamProvider → 1-2 个 |
| **P0** | 2.2 AiChatPanel 默认折叠 | Editor 首帧 | **大** — 减少 7+ provider 触发 |
| **P1** | 2.3 workingOverlay 延迟 | Editor 首帧 | **中** — 减少级联 provider 链 |
| **P1** | 1.1 批量读取 settings | 冷启动 | **中** — 18 次 SQL → 1 次 |
| **P1** | 1.2 移除无条件 persist | 冷启动 | **中** — 18 次 SQL 写入消除 |
| **P1** | 3.1 预初始化 agent tasks | 首页进入 | **中** — 消除首页 agent 列表加载阻塞 |
| **P2** | 1.3 共享 DB 实例 | 冷启动 | **小** — 消除重复构造 |
| **P2** | 2.4 Sidebar 图标/封面优化 | Editor 首帧 | **小** — 减少渲染帧阻塞 |
| **P2** | 2.5 Controller/FocusNode 下放 | Editor 首帧 | **小** — 减少 hook 初始化 |
| **P3** | 1.4 按需加载 prompt | 冷启动 | **小** — 已在 main() 中异步执行 |
| **P3** | 3.2 预热 DB | 首页进入 | **微小** |
