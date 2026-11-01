# Memory Optimization Plan

## Problem
App sits at ~500MB memory. Target: sub-200MB idle, sub-300MB under normal use.

## Current Scope

This pass targets the observed problem: the Home page can sit at ~400-500MB
before opening AI chat or editor-heavy pages.

The scope is deliberately behavior-preserving:

- Keep user-visible data, session history, and chat behavior unchanged.
- Optimize image decode sizes for Home/editor thumbnails.
- Move Home-page statistics from Dart in-memory aggregation to SQL aggregation.
- Do not add cache eviction or truncation that could change navigation/session behavior without a separate product decision.

## Root Causes (ordered by Home-page relevance)

### P0 — Image Decoding at Native Resolution (~200MB recovery)

Every image decodes at full native res. AI-generated images up to 2848px rendered in 420px containers. Covers at 2000px+ shown as 80px thumbnails. Default `imageCache` = 100MiB ceiling, filled with giant frames.

**Fixes:**

1. **Tune Flutter `imageCache`** (`lib/main.dart`):
   ```dart
   final cache = PaintingBinding.instance.imageCache;
   cache.maximumSizeBytes = 50 << 20;  // 50 MiB (down from 100)
   ```

2. **Add `cacheWidth` to all image sites** — 12 locations:

| File | Fix |
|------|-----|
| `lib/shared/widgets/app_background.dart` (2 layers) | `cacheWidth: 1440` |
| `lib/desktop/widgets/novel_list.dart` (2 sites) | `cacheWidth: 220` |
| `lib/desktop/widgets/novel_form_dialog.dart` | `cacheWidth: 160` |
| `lib/desktop/widgets/workspace/novel_overview.dart` | `cacheWidth: 112` |
| `lib/desktop/widgets/sidebar/header.dart` | `cacheWidth: 64` |
| `lib/desktop/widgets/ai/tools/image_tool_card.dart` | `cacheWidth: 840` |
| `lib/desktop/widgets/ai/tools/character_image_tool_card.dart` | `cacheWidth: 840` |
| `lib/shared/widgets/character_avatar.dart` | `cacheWidth: 128` |
| `lib/shared/widgets/agent_avatar.dart` | `cacheWidth: 128` |
| `lib/shared/widgets/maps/map_canvas.dart` | Add `targetWidth` + dispose `ui.Image` |
| `lib/desktop/widgets/workspace/character_profile_editor.dart` (2 sites) | `cacheWidth: 200` |
| `lib/desktop/widgets/workspace/workspace_item_editor.dart` (2 sites) | `cacheWidth: 200` |

3. **Evict old images**: In `app_background.dart`, evict old background from cache on path change. In `map_canvas.dart`, dispose `ui.Image`.

---

### P1 — Home Statistics Loading Full Chapter Rows

Home right rail renders the current writing goal card. The previous
`currentMaxChapterNumProvider` path loaded every chapter row for every novel via
`chapterDao.getAll()`, then looped in Dart to compute the max chapter number.
The `chapters` view includes `content`, so this can load all novel正文 into
memory on the Home page.

**Fixes:**

1. Add a dedicated SQL aggregation method in `ChapterDao`:
   - `countActiveChapters()` runs `SELECT COUNT(*) FROM chapter_nodes WHERE type = 'chapter' AND deleted_at = 0`
   - This is equivalent for the current Home use because global `chapter_num` is a `ROW_NUMBER()` over active chapters, so `MAX(chapter_num) == COUNT(active chapters)`.
2. Update `currentMaxChapterNumProvider` to use the SQL aggregation method per novel and keep the previous cross-novel max behavior.
3. Add `.agents/rules/db-query-aggregation.md` so future count/max/sum/existence queries do not use `getAll()` plus Dart loops.

---

### Not Doing — Provider State Leaks

These are intentionally **not included** in this Home-page optimization pass.
They may be valid future work, but they either do not explain cold Home-page
memory or risk changing behavior.

1. **Global Map cleanup** (`lib/shared/providers/ai_providers.dart:25-28`):
   `_claimedAiChatNewSessionSignalsByNovel` and `_aiChatNewSignalToSessionId` never prune.
   - **Not doing now**: Home page does not create AI chat new-session signals.
   - Changing signal pruning can swallow duplicate/new-session edge cases if done incorrectly.

2. **16 session-mode providers with no `onDispose`** (4 files × 4 providers):
   - `lib/shared/providers/agent_council_providers.dart`
   - `lib/shared/providers/theater_providers.dart`
   - `lib/shared/providers/monologue_providers.dart`
   - `lib/shared/providers/roleplay_providers.dart`
   - **Not doing now**: these providers are `keepAlive`, so adding `ref.onDispose` alone does not release them during normal Home-page navigation.
   - Properly changing lifecycle would require a separate design because background AI work currently relies on session state surviving page switches.

3. **`RunHistoryStore` Map unbounded growth** (all 4 modes):
   - **Not doing now**: LRU eviction can remove historical run detail UI and changes behavior.

4. **`AiChatSession.messages` unbounded**:
   - **Not doing now**: truncating in-memory messages changes chat history display/scroll behavior.

5. **`AiModeProcessingTracker` Sets**: Periodic cleanup of old tokens.
   - **Not doing now**: not related to cold Home-page memory. Requires lifecycle semantics for completed/background sessions.

---

### Not Doing — Usage / DB Cache / Static Cache Changes

These are also intentionally **not included** in this pass:

1. **`UsageService._queryAllMessages()`** loads ALL messages from ALL novels:
   - **Not doing now**: Usage page is not part of the reported Home-page memory path.
   - This should be fixed when optimizing usage stats, preferably with SQL aggregation.

2. **`NovelContentDatabase._databaseCache`** no eviction:
   - **Not doing now**: DB eviction can affect long-lived providers and active editor/session assumptions.
   - Needs a lifecycle design before changing.

3. **Share `AppDatabase` / lazy-load prompt templates / replace `File.existsSync()` broadly**:
   - **Not doing now**: not proven as the primary Home-page RSS source.
   - `existsSync()` in build is a responsiveness concern, not necessarily a 400-500MB RSS cause.

---

## Estimated Impact

| Category | Before | After | Recovery |
|----------|--------|-------|----------|
| Image decoding | ~200MB | ~40MB | ~160MB |
| Home chapter statistic query | can load all chapter rows/content | count-only SQL | data dependent |
| Provider/session changes | not changed | not changed | none |
| Usage/DB/static cache changes | not changed | not changed | none |

## Verification Steps

1. Baseline RSS via Activity Monitor on launch + Home page idle
2. Verify images render correctly (no visible blur)
3. Verify Home right rail current chapter estimate is unchanged
4. DevTools Memory: confirm Home page no longer loads chapter `content` rows for the current chapter statistic
5. Novel editor / AI chat memory should be measured separately; this pass does not claim to fix those paths
