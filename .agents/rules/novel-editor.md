# Novel Editor Main 与 Rail 规则

- 在 `lib/desktop/pages/novel_editor.dart` 相关任务中，用户提到“主内容区域”“主内容区”“Main”“中间内容区”时，默认指 `NovelEditorPage` 通过 `contentSelection` / `_EditorContentSelection` 切换渲染的 Main 区域。
- 不要把 Main 理解为 `LeftSidebar` 的 Middle Column、rail 展开后的列表面板、`sections.dart` 中 `_buildAgentList()` 的内容。
- 涉及点击 rail 后改变主内容时，优先检查：
  - `lib/desktop/pages/novel_editor.dart`
  - `_EditorContentSelection`
  - `contentSelection.value = ...`
  - `switch (contentSelection.value)`
  - `lib/desktop/widgets/sidebar/rail.dart`
  - `lib/desktop/widgets/sidebar/sections.dart`
- 需求同时提到 rail 和主内容区域时，先确认要更新 Main 的 `contentSelection` 渲染，而不是只改 Middle Column 的 sidebar panel。
