# AI Chat Expanded Mode

## Summary

Add an expand button to `ChatHeader` that switches the AI chat panel from the right 360px sidebar into a full-width main content area. In expanded mode, the TODO panel and Pending Changes summary card move into a right-side panel alongside the expanded chat.

## Layout Changes

```
Normal (current):
┌──────────┬──────────────────────────┬──────────────┐
│ Sidebar  │     Workspace Content     │  Chat (360)  │
│  280px   │     (Expanded)           │              │
└──────────┴──────────────────────────┴──────────────┘

Expanded (new):
┌──────────┬───────────────────────────────┬──────────────┐
│ Sidebar  │  Chat (Expanded)              │ TODO         │
│  280px   │  Messages + Composer          │ ───Divider── │
│          │                               │ PendingChgs  │
└──────────┴───────────────────────────────┴──────────────┘
```

When expanded:
- Chat moves from right sidebar into the main content area (`Expanded`)
- Right AI panel is hidden (`SizedBox.shrink()`)
- A 360px side panel shows TODO (top, flex:1) + Pending Changes (bottom, flex:1)
- Messages and tool cards adapt to wider container

## New Files

### `lib/desktop/widgets/ai/chat/expanded_chat_area.dart`
- A `StatelessWidget` that builds the expanded layout: `Row([Expanded(AiChatPanel), Divider, SidePanel])`
- Receives all the same props that `AiChatPanel` normally gets from `_buildAiArea`, plus `pendingAiChanges` and `onCollapse`
- Passes `isExpanded: true` to `AiChatPanel`

### `lib/desktop/widgets/ai/chat/chat_side_panel.dart`
- A `StatelessWidget`: `Column([Header+CollapseBtn, Divider, Expanded(flex:1, TodoPanel), Divider, Expanded(flex:1, PendingChangesSummaryCard)])`
- `TodoPanel` uses existing Riverpod provider (`sessionTodosProvider`)
- `PendingChangesSummaryCard` receives `databasePath` + `changes` as props
- Thin header at top with collapse chevron button

## Modified Files

### 1. `lib/desktop/pages/novel_editor.dart`
- Add `_EditorAiChatExpandedSelection` sealed class variant
- Add case in `mainContent` switch rendering `ExpandedChatArea`
- Compute `pendingAiChanges` before the switch for reuse
- Pass `onExpandChat` to `AiChatPanel` in `_buildAiArea` callsite

### 2. `lib/desktop/pages/novel_editor_ai_area.dart`
- When `chatExpanded` is true, return `const SizedBox.shrink()`
- Need a `bool chatExpanded` parameter passed from `novel_editor.dart`

### 3. `lib/desktop/widgets/ai/chat/panel.dart`
- Add `isExpanded` param (default `false`)
- Conditionally render `TodoPanel`: only when `!isExpanded`
- Pass `pendingAiChanges: isExpanded ? const [] : pendingAiChanges` to `ChatComposer`
- Pass `isExpanded` to `_buildChatMessage` for bubble width

### 4. `lib/desktop/widgets/ai/chat/header.dart`
- Add `VoidCallback? onExpand` prop
- Add expand icon button using phosphor `arrows_out` icon
- Tooltip: `LocaleKeys.aiChatExpand`

### 5. `lib/desktop/widgets/ai/chat/composer.dart`
- No changes needed — already checks `if (pendingAiChanges.isNotEmpty)` before rendering `PendingChangesSummaryCard`

### 6. `lib/desktop/widgets/ai/chat/message_renderer.dart`
- Accept `bool isExpanded` param in `_buildChatMessage`
- Use `RevericSizes.chatBubbleMaxWidthExpanded` (560) when expanded, else `RevericSizes.chatBubbleMaxWidth` (300)

### 7. `lib/shared/theme/reveric_spacing.dart`
- Add `static const double chatBubbleMaxWidthExpanded = 560;`

### 8. `lib/desktop/widgets/ai/tools/image_tool_card.dart`
- Remove `maxWidth: 360` from `ConstrainedBox`, keep only `maxHeight: 420`

### 9. `lib/desktop/widgets/ai/tools/character_image_tool_card.dart`
- Same: remove `maxWidth: 360` from `ConstrainedBox`

### 10. `lib/desktop/widgets/ai/tools/ask_user_card.dart`
- Remove hardcoded `right: RevericSpacing.x2l` margin

## i18n

- New keys: `aiChatExpand`, `aiChatCollapse` in `LocaleKeys`
- Translations in `assets/translations/en/ai.json` and `assets/translations/zh-CN/ai.json`

## Verification

1. **Expand button**: Click expand in ChatHeader → chat moves to main content area, TODO and Pending Changes appear in right panel, right sidebar hides
2. **Collapse button**: Click collapse in side panel header → returns to workspace content, chat returns to right sidebar
3. **TODO panel**: Still functional in side panel — lists todos, expandable, auto-expands on new task
4. **Pending Changes**: Still functional in side panel — shows file changes, accept/reject, detail dialog works
5. **Image tool cards**: Images fill available width in expanded mode without being capped at 360px
6. **Message bubbles**: User messages are wider (560 vs 300) in expanded mode
7. **Composer**: Input area stretches full width of expanded panel
8. **AskUserCard**: No right margin offset, fills available width
9. **Design system**: All colors/spacing/tokens from RevericTheme, no hardcoded values
10. **Session persistence**: Sessions continue to save/load correctly in expanded mode
