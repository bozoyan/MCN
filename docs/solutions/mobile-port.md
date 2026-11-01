# 移动端适配（Mobile Port）总览

## Context（为什么做）

把桌面端的 Reveric 适配到移动端：底部 Tab 壳（首页 / 书架 / 助手 / 设置），作品内可写作、可真正聊天（发送/流式/工具/会话）。

**核心约束（用户明确）**：

- **复用全部共享层**（providers / services / 编排），移动端**只做 UI**。
- **单一实现**——能共享的逻辑（尤其 AI 聊天编排）桌面与移动端共用一份，不允许两端各维护一份、随时间漂移。

本文是移动端适配的**整体进度盘点**，记录已落地部分与剩余缺口，不再只覆盖 AI 聊天。

---

## 整体现状

### 应用壳与导航 ✅

- `lib/mobile/app.dart`：底部 Tab（首页 / 书架 / 助手 / 设置），`IndexedStack` 保活。
- `lib/mobile/widgets/mobile_tab_bar.dart`：Tab 栏。

### 各 Tab / 页面状态

| 区域 | 文件 | 状态 |
| --- | --- | --- |
| 首页 | `pages/home_page.dart` | ✅ 问候 / 继续写作卡 / 今日统计 / 作品网格（见「首页」一节） |
| 书架 | `pages/library_page.dart` | ✅ 搜索（debounce）/ 标签筛选 / 作品网格 / 长按操作 |
| 助手 Tab | `pages/mobile_chat_page.dart` + `mobile_chat_session_page.dart` + `providers/mobile_chat_providers.dart` | ✅ 只读浏览跨作品对话历史（不在此新建） |
| 设置 | `pages/settings_page.dart` | ✅ 复用 shared sections：general/appearance/fonts/ai_agents/providers/models/usage/storage/about/debug |
| 新建作品 | `pages/novel_create_page.dart` | ✅ 标题/简介/类型/分类/标签/封面表单 |
| Onboarding | `pages/onboarding_page.dart` | ✅ 填用户名 + 后台默认配置 + 创建 Demo |
| 作品编辑器 | `pages/novel_editor_page.dart` | ✅ 9 个写作分区 + 实体关系图（章节/角色/世界观/大纲/伏笔/道具/阵营/地图/素材/实体关系图），见「作品编辑器」一节 |
| 作品内 AI 聊天 | `pages/mobile_novel_chat_page.dart` + `widgets/mobile_chat_composer.dart` + `mobile_chat_message.dart` | ✅ 见「AI 聊天编排」一节，已全部接出 |

---

## AI 聊天编排：复用共享 `ChatSessionController`（已完成）

> 这是移动端适配里最复杂、最易分叉的一块，单独记录。

### turn 执行层 + 发送编排层，两端单一实现

- **`lib/shared/services/ai/chat_turn_runner.dart`（`ChatTurnRunner`）** —— turn 执行，平台无关，桌面 / 移动端与后台会话共用。无任何 `desktop/` 依赖。
- **`lib/shared/services/ai/chat_session_controller.dart`（`ChatSessionController` + `ChatScope` + `ChatHost` + `ChatComposerStore`）** —— 架在 turn runner 之上的**共享发送编排层**：排队消息、空发取消、临时→持久会话迁移、模型回退/额度兜底、send guard、references/handoff 拼装、slash 匹配、retry、cancel、首条标题生成、active workspace system-mind。
  - `ChatScope`（纯数据）= 编排真正读到的作用域字段。
  - `ChatHost`（回调包）= 真正触碰 composer/overlay/滚动的 UI 副作用，两端各自实现。
  - `ChatComposerStore`（注入式状态访问）= `attachedReferences` / `pendingHandoff` / `queuedMessage` / `sendGuardUntil`，桌面用 `_PanelComposerStore` 适配 panel-scoped state，移动端用 hooks-scoped `_MobileComposerStore`。`PendingChatHandoff` / `QueuedChatMessage` / `ChatComposerStore` / `DefaultChatComposerStore` 定义在共享控制器文件，桌面 `state.dart` 用 `export` 回吐。

### 桌面侧（薄包装）✅

`lib/desktop/widgets/ai/chat/runtime.dart`：`_handleSendMessage`/`_retryAssistantMessage`/`_cancelActiveRequest` 保持原签名，内部构造 `ChatSessionController` 转调 `send`/`retry`/`cancel`（`_buildChatSessionController` + `_PanelComposerStore`）。桌面行为逐字不变。

### 移动侧（薄调用）✅

`lib/mobile/pages/mobile_novel_chat_page.dart`：进入即 `createActiveSession` 建持久会话 + 设作用域，发送/重试/取消全走 `ChatSessionController`。已接出的 UI 能力：

- **Slash 菜单**：输入 `/` 时 composer 上方弹 user-visible sub-agent 建议，点选填入（CJK 合成期不匹配）。
- **排队消息**：`_MobileComposerStore`（hooks `ValueNotifier` adapter）；忙碌且有文本 ⇒ Stop+Send，Send 走 controller 排队；上方可清除排队气泡。
- **References**：composer「+」→ 底部弹窗挑章节/人物写入 `attachedReferences`；上方可移除引用 chip；`mobile_chat_message` 解析 `<user-remind>`/handoff 标签为 chip + 干净正文。
- **Handoff（接收端）**：`MobileNovelChatPage` 接受可选 `PendingChatHandoff`，进入时 seed 一次并显示可清除 handoff chip，首次发送由 controller 拼入正文。
- **Handoff 发起入口**：⏸️ 有意延后。接收端已就位（传 `handoff:` 即可），「从哪个移动端屏幕触发 handoff」按用户决定暂不加。需要时只需在发起方 push `MobileNovelChatPage(handoff: ...)`。

---

## 首页

### 已有

- Header：问候语（时段）+ 日期 + 用户名首字头像
- 最近作品卡（封面 + 标题 + 简介 + 继续写作按钮）
- 今日统计（3 卡：今日更新作品数 / 今日字数 / 作品总数）
- 作品网格（2 列封面 + 标题 + 字数 + 状态 chip + 新建卡）

今日目标、专注计时、创作待办、AI 建议、远程公告与本地每日提示已从两端移除，不属于移动端待补齐能力。记忆提取使用默认聊天模型。

### 相比桌面端缺失

| 缺失项 | 桌面端说明 |
| --- | --- |
| Agent 管理入口 | profiles / sub-agents / skills / shortcuts 列表 |

---

## 作品编辑器

### 已有

- Header：返回 + 作品名 + 章节号/保存状态 + 目录/角色/更多按钮
- 9 分区 chip 横向滚动切换（全部可用）
- 章节写作面板：卷/章标签 + 标题 + 大纲折叠编辑 + 正文 + 实体提及 chip + toolbar（字数/保存状态/历史/格式/AI 助手）
- 角色：`MobileCharactersPanel` 列表 + `MobileCharacterEditorPage`（头像/照片/名称/角色/小传/状态/首次出场）
- 大纲：`MobileOutlinesPanel` 列表 + `MobileOutlineEditorPage`（标题/状态/正文 markdown）+ `MobileOutlineBeatEditorPage`（标题/状态/章数/正文）
- 伏笔：`MobileForeshadowingsPanel` 列表 + `MobileForeshadowingEditorPage`（标题/状态/铺垫/兑现/关联章节）
- 地图：`MobileMapsPanel` 地点树 + `MobileLocationEditorPage`（名称/类型/父级/描述/子地点）
- 简单分区（世界观/道具/阵营/素材）：`MobileSectionPanel` + `MobileEntryEditorPage` 条目编辑
- 实体关系图：`MobileEntityGraphPanel`（复用共享 `EntityGraphWidget` 力导向画布 + `RelationEditDialog`）。工具栏：深度 / 关系类型筛选 / 标签 / 方向 / 重置；点击节点 → 底部信息条展示该实体关系数，点开底部弹层逐条编辑、可新增关系；空状态走 `MobileSectionEmptyState`。关系/实体类型标签本地化抽到共享 `lib/shared/widgets/entity_graph_labels.dart`，桌面 `EntityGraphPanel` 同步改用，避免两端漂移。
- 角色底部弹层（从 header 角色按钮触发，展示角色卡片列表）
- Overview 分区
- Novel Description 分区

### 相比桌面端缺失

| 缺失项 | 桌面端说明 |
| --- | --- |
| Search 分区 | 全文搜索 |
| Skills 分区 | 技能管理 |
| Creatures 分区 | 生物管理 |
| 大纲 timeline 视图 | 桌面有 beat timeline + mindmap |
| 大纲 beat 拖拽排序 | 桌面支持拖拽调整 beat 顺序 |
| 章节导入 | 桌面支持导入 |
| 图片生成 | 桌面支持生成 |

---

## 验证

- 每改一处 `flutter analyze`（改动文件 0 issue）。
- 桌面 AI 聊天「逐字不变」靠 analyze + 纯搬运保证，最终由用户手测验收（发送 / 工具调用 / 接受变更 / slash / handoff / 排队 / 重试 / 取消）。
- 移动端：作品内新建对话→发送→流式→工具卡→取消→重进会话仍在；助手 Tab 可见；模型选择生效；slash/引用/排队/handoff chip 各路径手测。
- 触及目录若有测试则运行（Rule 14）；`lib/mobile` 暂无测试，以 analyze + 手测说明。
