# Heuristic Onboarding System

## Summary

Onboarding is not a feature tour. In Reveric, onboarding succeeds when the writer creates a novel and saves the first real piece of story work inside that novel.

The system is split into two phases:

1. **Activation Onboarding**: guide the user from an empty app to the first meaningful output.
2. **Post-Onboarding Discovery**: after activation, surface optional feature suggestions without interrupting writing.

Daily recommendations are **not** part of core onboarding. They are post-onboarding discovery and should only run after the activation goal has been reached.

## First Meaningful Output

The first meaningful output is:

> The user saves a piece of real, reusable story work in their own novel workspace.

Priority order:

1. **First chapter draft saved**: a chapter has title/content that can be edited, expanded, or revised.
2. **First chapter outline saved**: a chapter/outlining artifact exists and can guide actual writing.
3. **Story seed saved**: novel description plus a core conflict, character, or premise exists.

Not counted:

- Completing onboarding profile fields.
- Creating an empty novel shell.
- Opening a feature.
- Seeing a modal.
- Receiving AI text that is not saved into the novel structure.

## Success Criteria

Activation onboarding is complete when:

- The user has created or opened their own novel.
- The user has saved at least one chapter draft, chapter outline, or story seed.
- The saved output belongs to a real workspace record, not a temporary demo or chat-only response.

Target metric:

- New users should reach first meaningful output within 5 minutes.

## Design Principles

1. **Output before exploration**: guide toward one saved artifact before introducing secondary tools.
2. **The manuscript stays central**: AI, Council, characters, maps, and cover tools are supporting paths, not onboarding goals.
3. **Interrupt only when value is immediate**: modals are reserved for high-value activation moments.
4. **Inline first, modal sparingly**: use empty states and contextual actions before blocking dialogs.
5. **Dismissals are respected**: every recurring suggestion must have a persistent opt-out.
6. **No demo novel as default**: user starts with their own novel. Demo remains optional.

## Architecture

```
                  ╭─────────────────────────────────────────╮
                  │     HeuristicEngine (singleton)         │
                  │  candidate priority + session quota +   │
                  │  global cooldown + idle gate            │
                  ╰────────────────┬────────────────────────╯
                                   │
     ╭─────────────────────────────┼─────────────────────────────╮
     ▼                             ▼                             ▼
╭───────────────────╮     ╭────────────────────╮     ╭────────────────────╮
│ ActivationGuide   │     │ SceneHeuristic     │     │ DiscoveryPrompt    │
│ inline / hero     │     │ editor top banner  │     │ home top banner    │
├───────────────────┤     ├────────────────────┤     ├────────────────────┤
│ rendered inside   │     │ fired on save +    │     │ fired on editor →  │
│ novel hero region │     │ user-idle event,   │     │ home transition,   │
│ until activated.  │     │ NOT on editor      │     │ NOT on app start.  │
│ NEVER a modal.    │     │ open.              │     │ Daily cap + stop.  │
╰───────────────────╯     ╰────────────────────╯     ╰────────────────────╯
                  shared persistence: dedicated onboarding tables
```

Prompt priority:

1. ActivationGuide (priority `0`)
2. SceneHeuristic (priority `10`)
3. DiscoveryPrompt (priority `20`)

The engine must select candidates by priority before consuming the session quota. A lower-priority prompt must not block a higher-priority activation prompt simply because its async check completed first.

### UI Form Factors

`AlertDialog` is reserved for at most one milestone moment (e.g. "activation completed" celebration, if introduced later). All three runtime surfaces below are **non-modal** so the user can keep typing or browsing.

| Surface | Form | Why |
|---|---|---|
| Activation | Novel **hero region** inline card | Lives where the user lands; disappears once `firstOutputAt` is set; no app-level modal can ever pre-empt focus. |
| Scene | Editor **top banner** (inside the workspace content column) | Avoids colliding with the right-side AI chat panel; one row, one CTA, dismissible. |
| Discovery | Home **top banner** above the novel list | Browsable, dismissible per day, includes a "stop suggestions" affordance. |

Forbidden:

- Opening an `AlertDialog`, `Dialog`, or `BottomSheet` for any of the three runtime surfaces.
- Floating cards in the editor's right-bottom region (it overlaps the AI chat panel and its input box).
- Triggering any heuristic surface during app start, while a route transition animation is running, or before the relevant async data is `AsyncData`.

## Data Layer

Use dedicated tables in the global `AppDatabase`. Do not store onboarding state in `app_states`.

Reasoning:

- The state has real domain structure: activation, prompt lifecycle, feature usage, discovery cadence.
- KV keys make migrations, queries, tests, and duplicate prevention harder.
- Dedicated tables let the implementation use typed DAO methods instead of string key conventions.
- The data is app-level, not per-novel content, so it belongs in `lib/shared/database/app_database.dart`, not `novel_content_database.dart`.

### Tables

#### `OnboardingProgresses`

One row tracks activation and discovery cadence for the local app profile.

```dart
class OnboardingProgresses extends Table {
  TextColumn get id => text().withDefault(const Constant('default'))();

  TextColumn get firstOutputType => text().nullable()();
  DateTimeColumn get firstOutputAt => dateTime().nullable()();
  TextColumn get firstOutputNovelId => text().nullable()();
  TextColumn get firstOutputArtifactId => text().nullable()();

  DateTimeColumn get discoveryLastShownAt => dateTime().nullable()();
  IntColumn get discoveryShownCount => integer().withDefault(const Constant(0))();
  BoolColumn get discoveryDisabled => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

Rules:

- `id` is always `default` unless the app later supports multiple local profiles.
- Activation is complete when `firstOutputAt != null`.
- `firstOutputType` must be one of `chapter_draft`, `chapter_outline`, `story_seed`.
- `discoveryLastShownAt` stores a timestamp; compare its local calendar date to decide whether a prompt was shown today.

#### `HeuristicPromptStates`

One row per prompt or scene trigger.

```dart
class HeuristicPromptStates extends Table {
  TextColumn get promptId => text()();
  TextColumn get promptType => text()();

  DateTimeColumn get firstShownAt => dateTime().nullable()();
  DateTimeColumn get lastShownAt => dateTime().nullable()();
  DateTimeColumn get dismissedAt => dateTime().nullable()();
  IntColumn get shownCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column<Object>> get primaryKey => {promptId};
}
```

Rules:

- `promptType` should be `activation`, `scene`, or `discovery`.
- A permanently dismissed prompt has `dismissedAt != null`.
- A one-shot prompt is considered seen when `firstShownAt != null`.
- Session-only dismissals are not written.

#### `FeatureUsages`

One row per feature the user intentionally enters or uses.

```dart
class FeatureUsages extends Table {
  TextColumn get featureId => text()();

  DateTimeColumn get firstUsedAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime()();
  IntColumn get usedCount => integer().withDefault(const Constant(1))();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column<Object>> get primaryKey => {featureId};
}
```

Rules:

- `featureId` uses `FeatureId.storageKey`.
- Re-entering a feature updates `lastUsedAt`, increments `usedCount`, and preserves `firstUsedAt`.
- Do not infer usage from passive rendering alone; record usage from explicit navigation or meaningful action handlers.

### Migration

Adding these tables requires an `AppDatabase` schema migration:

- Add the three tables to `@DriftDatabase(tables: [...])`.
- Add the DAO to `@DriftDatabase(daos: [...])`.
- Increase `schemaVersion` from the current version.
- Add `onUpgrade` steps that create the new tables when `from < newVersion`.
- Run code generation so `app_database.drift.dart` is updated.

All timestamp fields must use Drift `dateTime()` so SQLite stores INTEGER milliseconds, matching `.agents/rules/db-timestamps.md`.

All DB writes must follow the project DB rule:

- Wrap writes in try-catch.
- Log failures with `[DB]`.
- Include table name, operation, primary key, and full exception/stack details.
- Do not silently fallback to success.

### `HeuristicOnboardingDao`

Use a typed DAO instead of passing raw tables around UI code.

```dart
class HeuristicOnboardingDao {
  Future<OnboardingProgress?> getProgress();
  Future<bool> hasFirstOutput();
  Future<void> markFirstOutput({
    required FirstOutputType type,
    required String novelId,
    required String artifactId,
  });

  Future<bool> hasSeenPrompt(String promptId);
  Future<bool> isPromptDismissed(String promptId);
  Future<void> markPromptShown({
    required String promptId,
    required HeuristicPromptType type,
  });
  Future<void> dismissPrompt(String promptId);

  Future<Set<FeatureId>> getUsedFeatures();
  Future<bool> hasUsedFeature(FeatureId feature);
  Future<void> markFeatureUsed(FeatureId feature);

  Future<bool> wasDiscoveryShownToday();
  Future<bool> isDiscoveryDisabled();
  Future<int> getDiscoveryShownCount();
  Future<void> markDiscoveryShown();
  Future<void> disableDiscovery();
}
```

### `FeatureId`

Use stable storage keys and snake_case enum values because these represent feature categories.

```dart
enum FeatureId {
  overview,
  chapters,
  novel_description,
  outlines,
  characters,
  worldbuilding,
  maps,
  materials,
  foreshadowings,
  factions,
  creatures,
  items,
  skills,
  memory,
  entity_graph,
  search,
  ai_chat,
  ai_council,
  ai_monologue,
  ai_theater,
  ai_roleplay,
  ai_cover_studio,
  ai_style_polish,
  ai_review,
  agent_profile,
  sub_agent,
}
```

`FeatureId` must map explicitly from:

- `NovelWorkspaceSection`
- `AiSessionMode`
- cover studio state
- agent/subagent/skill management entries

Do not infer storage keys from display labels.

## Layer 1: Activation Onboarding

### Goal

Move the user from an empty app to one saved story artifact.

### Entry Points

1. Home empty state when there are no novels.
2. **Novel hero region** when the selected novel has no meaningful output.
3. Chapter/outline empty panel CTAs.

### Preferred UI — Novel Hero Region

When `dao.hasFirstOutput() == false` **and** the user is viewing a novel, the novel's hero region (`lib/desktop/widgets/workspace/hero.dart`) renders an **inline activation card** instead of (or above) the standard cover + metadata layout. Once `firstOutputAt` is set, the hero reverts to its normal form on the next build.

The activation card offers two concrete paths:

- **Write first scene** — selects `NovelWorkspaceSection.chapters` and, if no chapter exists, creates an empty one.
- **Plan first chapter** — selects `NovelWorkspaceSection.outlines` and, if no outline exists, creates an empty one.

Rules:

- The card is **not** a modal. The user can ignore it, scroll, switch sections, or open AI chat.
- The card disappears the moment activation completes; do **not** add a "close" affordance — closing it would re-introduce the problem the dialog had (a dismissed empty state).
- Home creation flow **must not** open `showActivationChoiceDialog` after novel insert. The hero region owns activation UI; the home flow just navigates into the new novel.

Home empty state (no novels yet) remains its own concern: a single "Create your first novel" primary action. It is not gated by the engine.

No daily recommendation, feature tour, or broad exploration prompt may appear before activation completes.

### Activation Detection

Activation completes when any of these is saved:

```dart
enum FirstOutputType {
  chapter_draft,
  chapter_outline,
  story_seed,
}
```

Detection points:

- Chapter save: content is non-empty and not placeholder text.
- Outline save: outline body or outline nodes are non-empty.
- Novel description/story seed save: description contains meaningful user-authored content.

The detection runs on write paths, not on editor entry. This avoids missing the exact moment and avoids false positives from loading state.

When activation is marked, the detection layer must additionally emit an in-memory `JustSavedFirstDraftSignal` so Layer 2 can use it without re-deriving from query state. See "Save Event Bus" below.

## Layer 2: Scene Heuristic

### Goal

After activation, offer contextual help when the user's current writing state suggests a clear next action.

### Trigger — Save + Idle, NOT Editor Open

The previous "fire on editor mount when data is ready" pattern interrupted the user precisely when they were entering writing flow. The new contract:

1. Subscribe to the save event bus (`SaveEventBus`, see below).
2. On any `chapterSaved` / `outlineSaved` / `novelDescriptionSaved` event:
   - Confirm activation is complete (`dao.hasFirstOutput()`).
   - Wait `idleDelay` (default **1500 ms**) and verify no further keystroke arrived through `UserActivitySignal` during that window. Restart the timer on every keystroke; cancel if the editor route is popped.
   - Confirm prompt has not been seen or permanently dismissed.
   - Build a `SceneContext` with **real** values (see below).
   - Submit a candidate to the singleton `HeuristicEngine`.

Hard rules:

- The scene layer **must not** be wired to `useEffect([chaptersAsync, outlinesAsync, charactersAsync, secondaryReady])`. That pattern caused multiple races in the first implementation.
- The engine, not the trigger, decides whether to show. Triggers only submit candidates.
- Do not treat `AsyncValue.loading()` as empty data when building `SceneContext`.

### SceneContext — Required Wiring

`SceneContext.hasUsed` **must** be wired to `await dao.getUsedFeatures()` taken once per dispatch. Hard-coding `(f) => false` defeats every trigger.

`SceneContext.justSavedFirstChapterDraft` **must** come from a one-shot signal emitted by the save path (see "Save Event Bus"). It must not be inferred from query state.

`SceneContext` must also expose `hasCover` so `cover_ready` honors the documented `ctx.cover == null` precondition.

### Scene Registry

```dart
final sceneRegistry = [
  SceneTrigger(
    id: 'outline_missing_after_draft',
    check: (ctx) =>
        ctx.hasChapterDraft &&
        ctx.outlines.isEmpty &&
        !ctx.hasUsed(FeatureId.outlines),
    feature: FeatureId.outlines,
    messageKey: 'heuristic.outline_missing_after_draft',
    actionLabelKey: 'heuristic.plan_outline',
  ),
  SceneTrigger(
    id: 'characters_growing',
    check: (ctx) =>
        ctx.characterCount >= 5 &&
        !ctx.hasUsed(FeatureId.entity_graph),
    feature: FeatureId.entity_graph,
    messageKey: 'heuristic.characters_growing',
    actionLabelKey: 'heuristic.open_entity_graph',
  ),
  SceneTrigger(
    id: 'first_chapter_ready_to_polish',
    check: (ctx) =>
        ctx.justSavedFirstChapterDraft &&
        !ctx.hasUsed(FeatureId.ai_style_polish),
    feature: FeatureId.ai_style_polish,
    messageKey: 'heuristic.first_chapter_ready_to_polish',
    actionLabelKey: 'heuristic.try_style_polish',
  ),
  SceneTrigger(
    id: 'cover_ready',
    check: (ctx) =>
        ctx.cover == null &&
        ctx.hasChapterDraft &&
        ctx.hasCharacters &&
        !ctx.hasUsed(FeatureId.ai_cover_studio),
    feature: FeatureId.ai_cover_studio,
    messageKey: 'heuristic.cover_ready',
    actionLabelKey: 'heuristic.open_cover_studio',
  ),
];
```

Notes:

- `justSavedFirstChapterDraft` should be an event signal from the save path, not guessed from editor entry.
- Council should not be the default first suggestion for an empty novel. It is useful when the writer is stuck after some story material exists.

### Banner Behavior

The scene surface is a **top banner** rendered inside the editor's workspace content column (not the right AI chat column, not a floating card). Single row, ~56 px high.

Layout: leading icon, one-line message, primary `TextButton` action, "Don't show again" overflow item, trailing `×` for session dismiss.

- Primary action closes the banner, calls `dao.markFeatureUsed(trigger.feature)`, and **navigates** to the target section via the editor's existing `onSelectionChanged` (or opens cover studio for `ai_cover_studio`). Navigation is mandatory — a no-op CTA is a bug.
- "Don't show again" sets `HeuristicPromptStates.dismissedAt` and closes the banner.
- `×` (session dismiss) closes the banner without writing `dismissedAt`. The same prompt may re-appear in a future session if still relevant.
- `HeuristicPromptStates.firstShownAt` / `lastShownAt` are written **when the banner mounts**, not when it closes. Dismissing without writing `firstShownAt` corrupts analytics and lets the same scene re-trigger on next save.
- The banner never auto-dismisses; only user action or activation-state change can remove it. (Auto-dismiss timing varies wildly between displays and creates "ghost banner" UX.)

Forbidden:

- Wrapping the scene surface in `showDialog`.
- Placing the surface in the editor's right-bottom area (collides with AI chat panel).
- Returning the i18n key string as a sentinel for "user accepted" — use an explicit `SceneResult` enum (`accepted`, `dismissedSession`, `dismissedPermanent`).

## Layer 3: Post-Onboarding Discovery

### Goal

Help users discover secondary tools after they already have a story artifact.

This is not core onboarding. It must never appear before `OnboardingProgress.firstOutputAt` exists.

### Trigger — Editor → Home Transition, NOT App Start

App start is the wrong moment: the user has the strongest intent ("continue yesterday's chapter"), the UI is still warming up, and a discovery banner reads as marketing.

The correct trigger surface is the **return to Home from an editor session**. Implementation:

1. The router (or `NovelHomePage`) listens for the editor route popping back to home.
2. After the pop completes and the home list has rendered, wait `homeDiscoveryDelay` (default **2500 ms**) so the route animation and any focus restoration finish.
3. Submit a discovery candidate to the singleton `HeuristicEngine`. The engine applies its global cooldown and session quota.

Gating (all must hold):

- `await dao.hasFirstOutput()` returns true.
- `OnboardingProgress.discoveryDisabled` is false.
- `OnboardingProgress.discoveryLastShownAt` is not today.
- `OnboardingProgress.discoveryShownCount < 5`.
- The home list is non-empty (`novelsAsync.asData?.value.isNotEmpty == true`).
- No higher-priority candidate exists for this engine cycle.
- A recommendation actually exists for the current `DiscoveryContext`.

Forbidden trigger points:

- App cold start / first frame.
- `NovelHomePage.build()` running because of an unrelated provider rebuild.
- Inside a `useEffect` whose dependency list contains an `AsyncValue` object (use `.asData?.value` instead so equal data does not retrigger).

### Cadence

Start conservative:

- Show at most once per day (`wasDiscoveryShownToday()` writes regardless of user choice except "Stop").
- Stop after a small cap, recommended: 5 total discovery banners.
- Provide "Stop suggestions" in addition to "Not today".

### Recommendation Algorithm

```dart
Future<FeatureId?> pickDiscoveryRecommendation(
  HeuristicOnboardingDao onboardingDao,
  DiscoveryContext ctx,
) async {
  final used = await onboardingDao.getUsedFeatures();
  final candidates = discoveryScheduleFor(ctx);
  return candidates.firstWhereOrNull(
    (feature) => !used.contains(feature),
  );
}
```

`discoveryScheduleFor(ctx)` must filter by writing-maturity stage, not return a fixed list. A hardcoded array (e.g. always `[outlines, characters, entity_graph, ...]`) ignores the user's actual story state and surfaces irrelevant suggestions.

Recommended ordering by maturity:

| Stage | Condition | Candidate features |
|---|---|---|
| 1 | first output saved | outlines, characters |
| 2 | outline or 2+ chapters | worldbuilding, foreshadowings |
| 3 | 3+ characters | entity_graph, ai_council |
| 4 | 1+ polished chapter | ai_review, ai_style_polish |
| 5 | story assets exist | maps, materials, items, factions, creatures |

### Banner Behavior

The discovery surface is a **top banner above the novel list** on `NovelHomePage`. Single row, ~56 px high, dismissible without losing the list.

Layout: leading icon, localized **feature-specific** name + one-line description, primary action `Go there`, secondary `Not today`, overflow `Stop suggestions`, trailing `×`.

- `Go there` closes the banner, calls `dao.markDiscoveryShown()`, calls `dao.markFeatureUsed(candidate)`, and **navigates** to the feature (open the matching novel/section). A no-op CTA is a bug.
- `Not today` closes the banner and calls `dao.markDiscoveryShown()`.
- `Stop suggestions` calls `dao.disableDiscovery()` and closes the banner. Does not increment the shown count.
- `×` (session dismiss) closes the banner without writing today-shown. The same banner may try again next editor→home transition (still subject to cooldown).
- The featureName / description **must** come from a `FeatureId → (LocaleKey name, LocaleKey description)` map. Hard-coding "Chapters" or the title key for every candidate is a bug.

If the user has no novel, do not show DiscoveryPrompt. The home empty state already owns that case.

Forbidden:

- Wrapping the discovery surface in `showDialog`.
- Showing the banner before the home list is laid out (causes layout jump).
- Using the discovery banner to advertise activation-stage features (outlines / chapters) when activation already used them — the algorithm must filter `used` first.

## HeuristicEngine Coordination

The engine is a **singleton**, exposed through a Riverpod provider so all three layers share session quota and cooldown:

```dart
final heuristicEngineProvider = Provider<HeuristicEngine>((ref) {
  return HeuristicEngine();
});
```

Constructing a fresh `HeuristicEngine()` inside a `useEffect` or callback is a bug — the session quota becomes per-invocation and stops working.

The engine separates candidate collection from display commitment, and adds a global cooldown + idle gate:

```dart
final class HeuristicCandidate {
  const HeuristicCandidate({
    required this.id,
    required this.priority,
    required this.show,
  });

  final String id;
  final int priority;
  final Future<void> Function() show;
}

final class HeuristicEngine {
  static const Duration _cooldown = Duration(minutes: 5);

  bool _surfaceShownThisSession = false;
  DateTime? _lastShownAt;

  Future<void> showBest(List<HeuristicCandidate> candidates) async {
    if (_surfaceShownThisSession) return;
    if (candidates.isEmpty) return;
    final last = _lastShownAt;
    if (last != null && DateTime.now().difference(last) < _cooldown) return;

    candidates.sort((a, b) => a.priority.compareTo(b.priority));
    _surfaceShownThisSession = true;
    _lastShownAt = DateTime.now();
    await candidates.first.show();
  }

  void resetSessionQuota() {
    _surfaceShownThisSession = false;
  }
}
```

Priority values:

- `0`: Activation surface (currently rendered inline in the hero, so usually not dispatched via the engine; reserved for any future activation milestone surface)
- `10`: Scene banner
- `20`: Discovery banner

Implementation requirements:

- Do not flip `_surfaceShownThisSession` during eligibility checks. Flip it only when commit-to-show happens.
- Do not consume quota for null recommendations.
- Do not show surfaces while a route transition animation is in progress.
- Reset session quota only on app restart (or when the user explicitly opens an "onboarding reset" debug action), not every rebuild.
- The engine is shared across pages; the same session must not show one banner per page.

### Save Event Bus

```dart
final class SaveEvent {
  const SaveEvent.chapter({required this.novelId, required this.id, required this.isFirstDraft});
  const SaveEvent.outline({required this.novelId, required this.id, required this.isFirstDraft});
  const SaveEvent.novelDescription({required this.novelId, required this.id, required this.isFirstDraft});

  final String novelId;
  final String id;
  final bool isFirstDraft;
}

final saveEventBusProvider = Provider<StreamController<SaveEvent>>((ref) {
  final controller = StreamController<SaveEvent>.broadcast();
  ref.onDispose(controller.close);
  return controller;
});
```

- The activation detection layer publishes `SaveEvent` after a successful save and only marks `isFirstDraft = true` when `markFirstOutput` actually transitioned the DB (existing rows do not re-trigger).
- Layer 2 subscribes to this stream; this is what powers `SceneContext.justSavedFirstChapterDraft`.
- This bus is **session-only** state. Do not persist to DB.

### UserActivitySignal

```dart
final class UserActivitySignal {
  DateTime? _lastKeystrokeAt;

  void recordKeystroke() => _lastKeystrokeAt = DateTime.now();

  bool isIdleFor(Duration window) {
    final last = _lastKeystrokeAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= window;
  }
}

final userActivityProvider = Provider<UserActivitySignal>((_) => UserActivitySignal());
```

- The editor input fields call `recordKeystroke()` on every text change.
- Layer 2's idle gate consults `isIdleFor(const Duration(milliseconds: 1500))` before submitting a candidate.
- This signal is session-only. Do not persist.

## Files Summary

### New Files

| File | Purpose |
|---|---|
| `lib/shared/models/feature_id.dart` | Stable feature IDs with snake_case enum values |
| `lib/shared/models/onboarding_state.dart` | First output type and heuristic prompt IDs |
| `lib/shared/database/daos/heuristic_onboarding_dao.dart` | Typed DAO for onboarding progress, prompt state, and feature usage |
| `lib/shared/heuristic/heuristic_engine.dart` | Singleton engine; candidate priority + session quota + cooldown |
| `lib/shared/heuristic/scene_registry.dart` | Contextual scene triggers |
| `lib/shared/heuristic/save_event_bus.dart` | Session-only save event stream that powers `justSavedFirstChapterDraft` |
| `lib/shared/heuristic/user_activity_signal.dart` | Session-only keystroke timestamp used by the scene idle gate |
| `lib/shared/heuristic/feature_metadata.dart` | `FeatureId → (name LocaleKey, description LocaleKey)` map for discovery banner |
| `lib/desktop/widgets/workspace/hero_activation_card.dart` | Inline activation card rendered inside the novel hero region |
| `lib/desktop/widgets/heuristic/scene_heuristic_banner.dart` | Top banner shown in the editor workspace column |
| `lib/desktop/widgets/heuristic/discovery_banner.dart` | Top banner shown on the home page above the novel list |

### Modified Files

| File | Change |
|---|---|
| `lib/shared/database/app_database.dart` | Add onboarding tables, DAO registration, schemaVersion bump, and migration |
| `lib/shared/database/app_database.drift.dart` | Regenerate after table and DAO changes |
| `lib/shared/database/daos/heuristic_onboarding_dao.drift.dart` | Generated DAO mixin |
| `lib/shared/heuristic/activation_detection.dart` | After successful save, publish `SaveEvent(isFirstDraft: ...)` on the bus |
| `lib/desktop/widgets/workspace/hero.dart` | Render `HeroActivationCard` when `!hasFirstOutput`, otherwise normal hero |
| `lib/desktop/pages/home.dart` | Remove `showActivationChoiceDialog`; subscribe to editor→home transition; render `DiscoveryBanner` via engine |
| `lib/desktop/pages/novel_editor.dart` | Replace `useEffect` scene trigger with `SaveEvent` subscription + idle gate; render `SceneHeuristicBanner` via engine; call `userActivity.recordKeystroke()` on chapter/outline text changes |
| `lib/shared/localization/locale_keys.dart` | Add `heuristic.*`, activation, and feature-name keys |
| `assets/translations/en/heuristic.json` | English heuristic copy + per-feature display names/descriptions |
| `assets/translations/zh-CN/heuristic.json` | Chinese heuristic copy + per-feature display names/descriptions |

### Removed Files

| File | Reason |
|---|---|
| `lib/desktop/widgets/onboarding/activation_choice_dialog.dart` | Replaced by hero inline card; activation is never modal |
| `lib/desktop/widgets/heuristic/scene_heuristic_modal.dart` | Replaced by `scene_heuristic_banner.dart` |
| `lib/desktop/widgets/heuristic/discovery_prompt_dialog.dart` | Replaced by `discovery_banner.dart` |

### Unchanged Files

| File | Reason |
|---|---|
| `lib/desktop/pages/onboarding.dart` | Initial setup remains language/profile/theme/provider setup |

## Implementation Order

1. Data layer: onboarding tables, `FeatureId`, `HeuristicOnboardingDao`, first output model, migration, generated Drift files.
2. Session-only infrastructure: `heuristicEngineProvider` (singleton), `saveEventBusProvider`, `userActivityProvider`, `feature_metadata.dart`.
3. Activation detection: mark first meaningful output on save paths and publish `SaveEvent` on the bus.
4. Activation UI: replace dialog with `HeroActivationCard` in `hero.dart`; remove `showActivationChoiceDialog` call from home.
5. SceneHeuristic: subscribe to `SaveEvent`, apply idle gate, submit candidate to the singleton engine, render `SceneHeuristicBanner`.
6. DiscoveryPrompt: trigger on editor→home transition, debounce, submit candidate to the singleton engine, render `DiscoveryBanner` with stage-filtered candidates and feature-specific copy.
7. i18n: heuristic keys plus per-feature display names/descriptions.
8. Cleanup: delete the three removed dialog files; remove unused stubs (`OutlineDraftInfo`, `SceneContext.outlines`).

## Open Questions

- What minimum content threshold should count as a chapter draft: any non-empty content, or a higher character count?
- Should story seed activation require both novel description and one named character/conflict, or is description alone enough?
- Should the 5-minute target be tracked with local analytics, debug logs, or left as a product metric for later?
- Should the engine's global cooldown be longer than 5 minutes given that surfaces are now non-modal (less intrusive)?
- Should there be a one-time milestone surface (e.g. a toast) when activation completes, or do we keep activation completion silent and let the hero swap itself?
- Should `UserActivitySignal` also track pointer movement, or is keystroke-only enough for the scene idle gate?
