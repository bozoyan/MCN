---
name: patrol
description: Use this skill whenever the user asks to add, fix, run, or design Flutter Patrol tests, E2E tests, UI automation, `patrolTest`, Patrol finders, Patrol CLI setup, or project workflows under `patrol_test/`. This skill is especially important in this repo because Patrol tests need the right binding/run mode, stable keys, mocked providers, localization/theme wrappers, and careful dialog/overlay handling.
---

# Patrol

Use Patrol for Flutter UI/E2E coverage when the user wants to exercise a real app workflow through taps, text entry, scrolling, dialogs, and visible state assertions. Prefer it over plain `testWidgets` when the test reads like a user journey or may later need native automation.

Current project setup:

- Packages are already in `pubspec.yaml`: `patrol` and `patrol_cli`.
- Patrol config is already in `pubspec.yaml` under `patrol:` for Android, iOS, and macOS bundle/package IDs.
- Put tests in `patrol_test/`.
- Existing example: `patrol_test/workflow_edit_test.dart`.

## Quick Workflow

1. Read the widget/page under test and identify the smallest realistic user journey.
2. Add stable `ValueKey`s to controls that the test must interact with.
3. Build a harness around the widget if full app startup is unnecessary.
4. Mock Riverpod providers, shared preferences, localization, form scope, and theme as needed.
5. Write a `patrolTest` using Patrol finders.
6. Run the test with Patrol-compatible Flutter test mode.
7. Fix UI bugs surfaced by the test, not just the test.

## Test Shape

Start from this structure for widget-level Patrol tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  setUpAll(() async {
    // Initialize app-level singletons/mocks here.
  });

  patrolTest('does the user workflow', ($) async {
    await $.pumpWidgetAndSettle(const TestHarness());

    await $(#primary_action_button).tap();
    await $(#name_field).enterText('Example');

    expect($('Expected text'), findsOneWidget);
  });
}
```

Use these finder patterns:

- `$(#some_key)` for stable keyed controls.
- `$('Visible text')` for user-facing assertions.
- `$(SomeWidgetType)` for broad structural checks.
- Chain finders for scoped interactions, for example `$(Scaffold).$(#toolbar).$('Save')`.

Prefer keys for actions and text for assertions. Text-only taps are brittle when i18n changes or when multiple widgets share a label.

## Running Tests

For this repo, use:

```bash
flutter test --dart-define=PATROL_HOT_RESTART=true patrol_test/<test_file>.dart
```

Do not treat this as equivalent:

```bash
flutter test patrol_test/<test_file>.dart
```

Plain `flutter test` may fail with `LateInitializationError: Field 'patrolAppService' has not been initialized` even when the test logic is fine.

If the task needs real native automation rather than widget-level Patrol finders, use Patrol CLI instead of plain Flutter test. Check the current project scripts/config first, then prefer a focused command for the target platform.

## Test Bundle Registration

Every new patrol test file must be registered in `patrol_test/test_bundle.dart` or the native Patrol runner will not discover it:

1. Add an import alias in the `// START/END: GENERATED TEST IMPORTS` block:
   ```dart
   import 'my_new_test.dart' as my_new_test;
   ```
2. Add a `group(...)` entry in the `// START/END: GENERATED TEST GROUPS` block:
   ```dart
   group('my_new_test', my_new_test.main);
   ```

`test_bundle.dart` carries a `DO NOT MODIFY BY HAND` header but is committed in this repo; edit it by hand to match the existing `workflow_edit_test` entry's shape. A patrol test that compiles and runs standalone with `PATROL_HOT_RESTART=true` but is not registered will still be invisible to `patrol test` runs on device.

## Harness Requirements

When testing project widgets directly, wrap enough app context for the widget to behave like production:

- `ProviderScope` with overrides for DB/network-heavy providers.
- `EasyLocalization` and the project asset loader when visible text uses translations.
- `MaterialApp` with localization delegates and theme.
- `RevericTheme` around widgets that call `RevericTheme.of/colorsOf/typographyOf`.
- `HookFormScope` for widgets using `lib/third/form`.
- `SharedPreferences.setMockInitialValues({})` before localization/settings code needs it.
- **Mock `path_provider` + `RevericPaths.initialize()` whenever the test drives real provider/service code** (chat turn runner, AI session turns, anything reaching past a pure widget). Several production paths construct `AppDatabase()` directly (`chat_turn_runner.dart`, `novel_providers.dart`, `agent_council_providers.dart`, etc.), bypassing any overridden `appDatabaseProvider`, so `_openConnection` still runs and calls `getTemporaryDirectory`/`getApplicationSupportDirectory`. In the test host those plugin channels are unbound. Pattern (matches `test/shared/services/novel_actions_test.dart` and `test/shared/utils/storage_paths_test.dart`):
  ```dart
  late Directory tempSupport;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();

    tempSupport = await Directory.systemTemp.createTemp('reveric_<test>_support_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory' ||
            call.method == 'getTemporaryDirectory') {
          return tempSupport.path;
        }
        return null;
      },
    );
    await RevericPaths.initialize();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tempSupport.exists()) {
      await tempSupport.delete(recursive: true);
    }
  });
  ```
  `NovelContentDatabase` opens by explicit file path and needs no mock; only the app-DB / `RevericPaths` paths do.
- `path_provider` channel mock + `RevericPaths.initialize()` whenever the test exercises real service code that constructs `AppDatabase()` directly (e.g. `chat_turn_runner.dart`, several `*_providers.dart`) rather than reading the overridden `appDatabaseProvider`. Direct construction bypasses provider overrides and hits `_openConnection` → `getTemporaryDirectory`/`getApplicationSupportDirectory`, which have no channel handler in a plain test host. See "Path Provider Mocking" below.

A minimal harness for this repo often looks like:

```dart
await EasyLocalization.ensureInitialized();
SharedPreferences.setMockInitialValues({});

await $.pumpWidgetAndSettle(
  EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: ProviderScope(
      overrides: [
        someProvider.overrideWith(...),
      ],
      child: Builder(
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: HookFormScope(
              messages: const I18nFormErrorMessages(),
              child: const WidgetUnderTest(),
            ),
          ),
        ),
      ),
    ),
  ),
);
```

Trim the harness to what the widget actually needs.

## Keys

Add `ValueKey`s only for elements that tests need to act on or disambiguate. Use stable, domain-readable names:

```dart
key: const ValueKey('workflow_edit_save_button')
key: const ValueKey('workflow_step_name_field')
```

Do not key every widget. Avoid generated or localized key names.

## Provider Fakes

Prefer small fake notifiers/providers over a real database when the test is about UI behavior:

- Store state in memory.
- Preserve the public provider API shape.
- Assert side effects on the fake after user actions.
- Keep IDs deterministic, for example `workflow_1`.

When the test is about persistence or runner behavior, use a real in-memory DB in a normal unit/widget test instead of making a large Patrol harness.

## Dialogs And Overlays

Dialogs are inserted through a route/overlay and may not inherit every custom inherited widget in the way the page body does. If a dialog reads project theme/localization/form scopes and a test reports missing inherited context, capture and re-provide the needed scope at `showDialog`:

```dart
final theme = RevericTheme.of(context);
final result = await showDialog<Result>(
  context: context,
  builder: (context) => RevericTheme(
    data: theme,
    child: const MyDialog(),
  ),
);
```

Do not put `Spacer` or `Expanded` directly inside `AlertDialog.actions`; Flutter renders actions with an `OverflowBar`, not a `Row`. Use normal buttons, `actionsAlignment`, or a custom `content` layout if the dialog needs complex action placement.

After `await showDialog`, guard uses of the original `BuildContext` with `context.mounted`.

## Assertions

Assert both UI result and underlying fake/provider state when possible:

```dart
expect($('Scene drafting'), findsAtLeastNWidgets(1));
expect(fake.savedNames, contains('Scene drafting'));
expect(fake.findByName('Scene drafting')!.steps, hasLength(1));
```

This catches cases where the UI appears to update but the saved payload is incomplete.

## Common Failure Modes

- `patrolAppService has not been initialized`: rerun with `--dart-define=PATROL_HOT_RESTART=true` or use the correct Patrol CLI mode.
- `MissingPluginException ... getTemporaryDirectory (or getApplicationSupportDirectory) on channel plugins.flutter.io/path_provider`: the test is reaching real `AppDatabase()` / `RevericPaths` code that bypasses your provider overrides. Mock the `path_provider` MethodChannel and call `RevericPaths.initialize()` in `setUpAll` — see Harness Requirements above. The error surfaces *after* the test body completes, so it can mask an otherwise-passing assertion; fix the channel before trusting the result.
- Finder timeout for a field inside a dialog: check for an earlier widget exception in the logs; the missing finder is often a symptom, not the cause.
- `No RevericTheme found in context`: the test harness or dialog route is missing `RevericTheme`.
- `Incorrect use of ParentDataWidget`: look for `Spacer`/`Expanded` inside `AlertDialog.actions`, `Stack`, `OverflowBar`, or other non-Flex parents.
- Save button disabled after editing child data: ensure local child-edit state participates in the parent form's dirty/changed calculation.
- Multiple widgets found: add a stable key or scope the Patrol finder.

## When To Broaden Coverage

Use Patrol for the highest-value workflow path first:

- create -> edit -> save
- open dialog -> enter required fields -> confirm
- list selection -> detail panel state updates
- persistence payload includes nested data

Keep lower-level business logic in unit tests. Patrol should prove the user can complete the workflow, not duplicate every model edge case.
