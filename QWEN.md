# QWEN.md — Reveric 项目索引

> 本文件是 Qwen Code 的项目入口索引：只回答"这是什么、代码在哪、命令怎么跑"。
> 硬性开发约束（安全边界、数据删除、DB 迁移、i18n、表单、桌面页头、技能版本等）以
> `AGENTS.md` 为唯一真源，本文件不复制也不覆盖。动代码前先读 `AGENTS.md`，再按其中的
> Rule 路由读命中的 `.agents/rules/*.md`。

## 1. 项目定位

Reveric（幻界 MCN）是一个 **本地优先、以智能体为核心的创作工作台**，覆盖从长篇小说到成片的全流程：

| 阶段 | 模块 |
| --- | --- |
| 写作 | 章节编辑、大纲、人物/势力/伏笔/地点/地图、实体关系图谱、版本历史 |
| 改编 | 专业剧本编辑器（场次、角色、对白、动作、转场），可对照原著 |
| 视觉化 | 无限画布（节点式分镜、定妆、生图流）、封面工作台 |
| 预演 | 3D 导演台（布景、机位、运镜、时间轴） |
| 成片 | 多轨剪辑台（6 轨）、渲染导出 |

- 目标用户是长篇小说作者：AI 是受约束的协作者，不是界面主角（见 `PRODUCT.md`）。
- 数据全部留在本机：SQLite 双库 + 本地工程目录；模型 BYOK 直连各厂商。
- 智能体可以读写作品里的每个模块，工具面覆盖小说、剧本、画布、导演台、剪辑台。

## 2. 平台与版本

- **支持平台：Windows、macOS、Android。** iOS / Linux 有工程目录，但不在支持范围。
- 版本号见 `pubspec.yaml`；Dart SDK 与 Flutter 下限同样以 `pubspec.yaml` 为准。
- Flutter SDK 由 `.fvmrc` 锁定（Flutter master 提交），本地一律 `fvm flutter ...`；
  CI 用 `subosito/flutter-action` 安装同一提交，直接调用 `flutter`，不装 FVM。

## 3. 技术栈

| 领域 | 选型 |
| --- | --- |
| UI / 状态 | Flutter、Riverpod 3（`flutter_riverpod` + `hooks_riverpod`）、`flutter_hooks`；MobX 仅存在于 `lib/third/flow` 内部 |
| 本地存储 | Drift（SQLite），两个数据库 + 本地文件工作区 |
| 3D | `flutter_scene`（导演台） |
| 媒体 | `fvp`、`video_player`、`ffmpeg_kit_flutter_new`（均为 `third/` 本地 fork） |
| AI 客户端 | `openai_dart`、`anthropic_sdk_dart`、`googleai_dart`、`open_responses`（`third/ai_clients_dart`）、`mcp_dart` |
| 原生桥 | `flutter_rust_bridge`（`fjs` 脚本引擎、`depth-native`） |
| 本地化 | `easy_localization` + `MergingAssetLoader` |
| 内置插件 | `plugins/`（Node + TS，产物进 `assets/plugins/`） |

## 4. 代码地图

```
lib/
├── main.dart            应用入口：平台分支、初始化、单实例、托盘、日志、崩溃上报
├── desktop/             桌面端：pages/（页面根）、features/（业务区域）、widgets/
├── mobile/              移动端：app.dart（作品/助手/设置三 Tab 壳）、pages/、features/、providers/
├── shared/              两端共用
│   ├── agent/           通用多 Agent 编排：orchestrator、tool_dispatcher、run_state、hooks、loop_detector
│   ├── services/
│   │   ├── ai/          聊天链路、提示词、tools_*.dart 工具实现、assistant/、codemode/、mcp/、subagents
│   │   └── ...          备份、导入导出、画布、导演台、剪辑、技能、更新、WebDAV 等 Orchestrator / Service
│   ├── database/        app_database + novel_content_database，daos/、queries/、*_indexes.dart
│   ├── providers/       Riverpod 生成源（改动后需 codegen）
│   ├── widgets/ components/ form/ theme/ localization/ logger/ models/ utils/
├── third/               flow（节点画布）、form（hook 表单）、toon
```

其他关键位置：

| 路径 | 内容 |
| --- | --- |
| `third/` | 9 个本地 fork 依赖，每个带 `*_UPSTREAM.md` 记录上游对照 |
| `assets/prompts/` | system / agent / task / fragments 提示词模板 |
| `assets/bundled_skills/`、`assets/official_skills/` | 内置与官方技能（SKILL.md + references） |
| `assets/translations/{en,zh-CN}/` | 按 namespace 拆分的翻译 JSON |
| `test/`、`integration_test/`、`patrol_test/` | 单元/Widget、集成、Patrol E2E |
| `designs/` | 桌面与移动端 mockup（改设计稿前先确认落点） |
| `API/` | **版本说明归档**：修改记录、更新说明、安装指南、调整总结、测试指南统一放这里 |
| `docs/` | 方案归档目录，常规任务不读不改 |

`API/` 的命名约定：`v<版本号> <主题>.md`（如 `v0.5.5 全屏预览修复弹窗选中态与生成计时.md`）。
每完成一次功能或修复改动，按当前 `pubspec.yaml` 版本号新增或追加对应文件，不写进 `docs/`。

## 5. 关键运行链路

- **启动**：`main.dart` → `services/app_initialization.dart` → `AppStartupGate` →
  桌面 `desktop/pages/home.dart` 或移动 `mobile/app.dart`。
- **UI 分层**：Page 只组合区域与页面生命周期；region/feature 持有独立可见区域；
  本地编辑态用 Hooks / `lib/third/form`，跨页面状态用 Riverpod，多步写入用 Orchestrator。
- **聊天与工具**：`chat_session_controller` → `chat_turn_runner` → `chat_prompt_builder` →
  模型客户端；工具经 `tool_catalog` / `tool_search` 暴露，实现分散在 `services/ai/tools_*.dart`，
  子 Agent 委派走 `spawn_agent_handler`。
- **技能**：`bundled_control_skills` / `bundled_official_skills` 加载资源，
  `official_skill_sync` 同步官方版本，用户技能落 `novel_agent_skills*` 表。

## 6. 数据与日志

- **`app_database`**：应用级数据 —— 作品元数据与集合、设置、AI 供应商与用量、聊天会话、
  助手会话、资产与图片批次、生成任务、工具权限、记忆、技能安装记录等。
- **`novel_content_database`**：单个作品的内容 —— 章节、人物、道具、伏笔、地点、大纲、
  画布与节点、剧本结构、剪辑与导演台、实体关系、修订与变更提交等。
- 两个库各自维护 `schemaVersion` 与 migration；改 schema 前必读 `.agents/rules/db-migration.md`。
- 文件工作区与临时文件走 `services/file_workspace_orchestrator.dart`、`shared/utils/storage_paths.dart`。
- 运行日志（排查客户端问题时先看这里）：
  - macOS Debug：`~/Library/Application Support/ai.reveric.debug/logs/`
  - macOS Release：`~/Library/Application Support/ai.reveric/logs/`
  - `logs/latest.log` 为当前实例，`logs/startup_*.log` 为各次启动。

## 7. 命令速查

```bash
make deps                 # fvm flutter pub get
make codegen              # build_runner 生成（Riverpod / Drift / JSON）
make run-macos            # 本地跑 macOS（先构建 fjs runtime、fvp 依赖）
make build-macos          # 调试构建
make build-macos-release  # 发布构建
make build-windows-release
make package-macos-release   # fastforge 打包 DMG / EXE
make plugins              # 构建内置 JS 插件并更新 assets 产物
make check-agent-rules    # 校验 Agent 指令与规则引用

fvm flutter analyze
fvm flutter test test/<相关目录>        # 必须串行，禁止并行
```

约定：本地禁止用 PATH 里的 `flutter`；CI 反之不使用 FVM。

## 8. 验证纪律（摘要，细则见规则）

- 改完只跑受影响目录最窄且有意义的测试；多个 `flutter test` 串行执行。
- 测试输出重定向到文件再过滤，不要 pipe 给 `grep`；widget 测试带 `timeout`。
- 改生成源后跑 `make codegen` 并检查 diff；移动/删除带 `part '*.g.dart'` 的文件前先删旧生成文件。
- 未运行、被跳过或失败的验证必须如实报告，不得描述成通过。

## 9. 规则路由（完整表见 `AGENTS.md`）

| 场景 | 必读 |
| --- | --- |
| 任意 Dart 改动 | `.agents/rules/code-style.md` |
| 新页面 / Widget / feature | `directory-structure.md`、`widget-decomposition.md` |
| 表单、校验、提交 | `form.md`（外部 controller / 中文输入再读 `text-input-ime.md`） |
| Hooks、Riverpod | `hooks.md`、`state-management.md` |
| Service / Orchestrator | `service-naming.md` |
| UI、主题、间距、刷新 | `design-system.md`、`performance.md`（桌面页头再读 `desktop-window-frame.md`） |
| 用户可见文案 | `i18n.md` |
| 文件选择、导入导出、备份 | `file-access.md` |
| 错误与 fallback | `error-handling.md` |
| AI 调用、工具描述与路径 | `ai-calling.md`、`tools_path.md` |
| 内置/官方技能 | `agent-skills.md` |
| Drift schema / 索引 / JSON | `db-migration.md`、`db-index-naming.md`、`db-timestamps.md`、`db-query-aggregation.md`、`json.md` |
| 删除业务数据 | `data-deletion.md`（需用户明确确认） |
| 测试选择与隔离 | `testing.md` |
| 小说编辑器 | `novel-editor.md` |
| REST / 前后端契约 | `api-contract.md` |

## 10. 动手前自检

1. 读 `AGENTS.md` 中与本次改动相关的段落，再读命中的 rule 文件。
2. 确认改动是否跨平台：桌面与移动端往往需要同步处理。
3. 涉及公共 API、schema、平台权限、用户数据时，先说明影响再动手。
4. 涉及 `docs/`、`designs/`、`third/` 本地 fork 时，先确认是真源还是产物。