# AI Shortcut Actions

## Summary

Add globally shared AI Shortcut Actions that let users trigger common AI writing tasks from workspace objects without manually typing the instruction in the Chat Panel.

Shortcut Actions are not Session Handoffs. A shortcut prepares a chat instruction and attaches relevant AI Context References. The Chat Orchestrator still handles the task through the normal chat path.

## Terms

| Term | Meaning |
|---|---|
| AI Shortcut Action | A built-in or user-created action, reusable across novels, shown on one or more workspace object types. |
| AI Shortcut Action Prompt | The plain-text task instruction used by a Shortcut Action. It is not an AgentRule or system prompt. |
| AI Context Reference | A pointer attached to chat so the Chat Orchestrator can read a workspace resource before answering. |

## Product Decisions

| Decision | Result |
|---|---|
| Storage scope | AppDatabase, global across novels. |
| User-created actions | Supported. |
| Applicable locations | Multi-select. |
| Prompt model | Plain text only. No variables. Prompt is required. |
| Prompt count | One prompt per Shortcut Action, even when multiple locations are selected. |
| Built-in actions | Cannot be hard deleted. They can be disabled and restored to default. |
| Custom actions | Can be edited, disabled, and deleted. |
| Default execution | Fill Chat composer and attach references. |
| Auto-send | Per-action option. Ignored while chat is already generating. |
| Existing composer text | Append shortcut prompt after a blank line. |
| In-flight chat request | Never cancel or queue. Only fill composer and references. |

## Management UI

Shortcut Actions are managed on the Home Page, not inside Novel Editor.

Home already has an AI section with collapsible lists for Agent, SubAgent, and Skill. Add Shortcut Actions as the same style of collapsible list:

```
AI
├─ Agent
├─ SubAgent
├─ Skill
├─ Shortcut Actions
└─ Recent Sessions
```

Behavior:

- The Shortcut Actions header has a `+` button.
- Expanding the section shows all global Shortcut Actions.
- Selecting an action opens a main-content edit panel.
- Pressing `+` opens a new Shortcut Action draft in the main content area.
- No new Home rail or section column is required for the first version.

## Edit Panel

Create a `ShortcutActionEditPanel` following the same management pattern as `AgentSkillEditPanel`.

Fields:

- Name, required.
- Prompt, required plain text.
- Applicable locations, required multi-select.
- Enabled toggle.
- Auto-send toggle.
- Built-in badge for built-in actions.

Built-in-only controls:

- Restore default.
- No hard delete.

Custom-only controls:

- Delete.

Applicable locations:

- Novel description
- Chapter
- Outline
- Outline beat
- Character
- Worldbuilding
- Material
- Skill entry
- Item
- Faction
- Creature
- Foreshadowing

Out of scope for first version:

- Search
- Model settings
- Memory
- Entity graph
- Maps and locations

## Built-in Defaults

Seed these built-in Shortcut Actions:

| Name | Applicable location | Prompt intent |
|---|---|---|
| Generate Chapter Outlines | Outline beat | Generate chapter outlines for the selected beat. |
| Generate Chapter Draft | Chapter | Draft chapter content from the current chapter context. |
| Polish Chapter | Chapter | Polish the current chapter. |
| Summarize Chapter | Chapter | Summarize the current chapter. |
| Generate Character Arc | Character | Design or refine the character arc. |
| Expand Setting | Worldbuilding, Material, Skill entry, Item, Faction, Creature | Expand the selected setting entry. |
| Design Payoff Plan | Foreshadowing | Design payoff options for the selected foreshadowing. |
| Generate Book Plan | Novel description | Generate an overall creation plan for the novel. |

Built-in prompts should be stored as product defaults in code or assets, then copied or overlaid into AppDatabase records for user edits.

## Data Model

Add an AppDatabase table for global Shortcut Actions.

Suggested table: `ai_shortcut_actions`

Fields:

- `id`: primary key.
- `builtin_id`: nullable stable internal id for built-in actions.
- `name`: user-visible name.
- `prompt`: required plain text.
- `locations`: JSON/string-list of applicable location ids.
- `enabled`: bool.
- `auto_send`: bool.
- `sort_order`: int.
- `created_at`: DateTime.
- `updated_at`: DateTime.
- `deleted_at`: DateTime sentinel for custom soft delete.

Notes:

- `builtin_id` is internal only. Users never see or edit it.
- Built-in actions use `deleted_at = 0` and `enabled = false` for disabled state.
- Custom actions can be soft deleted.
- The AppDatabase schema version must be incremented and `onUpgrade` must create the table.

Suggested location ids:

```text
novel_description
chapter
outline
outline_beat
character
worldbuilding
material
skill_entry
item
faction
creature
foreshadowing
```

## Providers And Services

Add an AppDatabase DAO and Riverpod providers:

- `AiShortcutActionDao`
  - `watchAll()`
  - `getAll()`
  - `upsert(action)`
  - `softDelete(id)`
  - `restoreBuiltinDefaults(builtinId)`
  - `reorder(ids)`
- `aiShortcutActionsProvider`
- `enabledAiShortcutActionsForLocationProvider(location)`

Service responsibilities:

- Seed built-in defaults if missing.
- Merge built-in defaults with user-edited records.
- Keep built-in restore behavior deterministic.
- Expose only enabled actions to Novel Editor usage menus.

## Novel Editor Usage

Shortcut Actions are used inside Novel Editor workspace objects, but managed from Home.

Display strategy:

- Use an `AI Shortcut Actions` icon/menu on object headers or cards.
- User-created shortcuts default to the menu.
- High-frequency built-ins may also be inline buttons where the UI has room.
- Menu items are filtered by the current workspace object type.

Execution behavior:

1. Resolve applicable Shortcut Actions for the current object type.
2. On click, build the relevant `AiContextReference`.
3. Open the Chat Panel if collapsed.
4. Append the shortcut prompt to the composer.
5. Attach the reference chip, avoiding duplicates.
6. If chat is idle and `autoSend = true`, send immediately.
7. If chat is in-flight, do not auto-send. Leave the prompt in composer.

Reference rules:

- Chapter: attach current chapter reference.
- Character: attach current character reference.
- Worldbuilding/material/skill entry: attach current document/item reference.
- Outline: attach current outline reference.
- Outline beat: attach the owning outline reference. Do not create a beat reference in the first version.
- Novel description: attach novel description reference.
- Foreshadowing: attach current foreshadowing reference.

## Chat Integration

Reuse the existing Chat Panel reference path:

- `AiContextReference`
- `state.attachedReferences`
- `ChatPromptBuilder.buildAgentTextWithReferences`
- `<user-remind>` rendering and parsing

Avoid using `AiChatHandoffDraft` for Shortcut Actions. That path is reserved for Session Handoff semantics.

The composer needs a small public entry point that can:

- Append text.
- Attach references.
- Optionally send when idle.
- Fall back to append-only while a request is in flight.

## i18n

Add new locale keys for:

- Shortcut Actions title.
- Create Shortcut Action.
- Edit Shortcut Action.
- Delete Shortcut Action.
- Restore Default.
- Enabled.
- Auto-send.
- Applicable locations.
- Prompt.
- Built-in badge.
- Custom badge.
- Empty state.
- Validation messages for required name, prompt, and locations.

Update:

- `lib/shared/localization/locale_keys.dart`
- `assets/translations/en/*.json`
- `assets/translations/zh-CN/*.json`

## Implementation Steps

1. Add model, DAO, AppDatabase table, schema migration, and generated Drift files.
2. Add provider/service layer with built-in seeding and restore-default behavior.
3. Add Home sidebar Shortcut Actions section and main-content selection variant.
4. Add `ShortcutActionEditPanel`.
5. Add Novel Editor menu usage for the first target locations.
6. Add Chat Panel composer entry point for appending prompt and references.
7. Add built-in default actions.
8. Add i18n.
9. Verify database migration and user workflows.

## Verification

1. Home shows Shortcut Actions under the AI section.
2. `+` creates a custom shortcut draft.
3. Saving requires name, prompt, and at least one location.
4. Custom shortcuts can be deleted.
5. Built-in shortcuts can be disabled and restored, but not hard deleted.
6. A shortcut can select multiple locations and appears in each matching workspace object menu.
7. Clicking a shortcut appends prompt text to the Chat composer.
8. Existing composer text is preserved and the shortcut prompt is appended after a blank line.
9. Duplicate context references are not added.
10. Auto-send sends only when chat is idle.
11. Auto-send does not fire while chat is generating.
12. Outline beat shortcut attaches the owning outline reference.
13. No Shortcut Action code uses `AiChatHandoffDraft`.
14. AppDatabase migrations work for existing databases.
15. All user-visible text is localized.
