// 职责: 验证 Map Studio 在无 world 与有 world 无 Map 状态下的关键桌面布局。
// 关联文件:
//   lib/desktop/features/map/map_studio_page.dart
//   lib/desktop/features/map/map_create_dialogs.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/en/workspace.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/map/map_cartographer_panel.dart';
import 'package:reveric/shared/providers/map_studio_controller.dart';
import 'package:reveric/desktop/features/map/map_studio_page.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/map_agent.dart';
import 'package:reveric/shared/providers/map_agent_providers.dart';
import 'package:reveric/shared/providers/maps_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders the key empty, draft, and generating states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final maps = StreamController<List<NovelMap>>();
    final locations = StreamController<List<Location>>();
    addTearDown(maps.close);
    addTearDown(locations.close);
    final container = ProviderContainer(
      overrides: [
        mapsProvider('map-states').overrideWith((ref) => maps.stream),
        locationsProvider('map-states').overrideWith((ref) => locations.stream),
        mapLocationsProvider(
          databasePath: 'map-states',
          mapId: 'map_1',
        ).overrideWith((ref) => Stream.value(const <MapLocation>[])),
        mapStudioControllerProvider('map-states', 'map_1').overrideWithValue(
          const MapStudioState(
            phase: MapStudioPhase.generating,
            stageIndex: 1,
            totalImageCalls: 1,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final worlds = [
      for (var i = 0; i < 24; i++) _location(id: 'world_$i', name: 'World $i'),
      _location(
        id: 'orphan_continent',
        name: 'Orphan Continent',
        type: locationTypeContinent,
      ),
    ];
    final campus = _location(
      id: 'campus',
      name: 'Campus',
      type: locationTypeCity,
      parentId: 'world_0',
    );
    await tester.pumpWidget(
      _wrap(
        container: container,
        child: const SizedBox.expand(
          child: MapStudioPage(
            novelId: 'novel-test',
            databasePath: 'map-states',
            onWorldSelected: _ignoreSelection,
          ),
        ),
      ),
    );
    maps.add(const <NovelMap>[]);
    locations.add(const <Location>[]);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('map_studio_create_first_world')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('map_studio_world_rail')), findsNothing);
    expect(find.byType(MapCartographerPanel), findsNothing);

    locations.add([...worlds, campus]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map_studio_world_rail')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('map_studio_pending_canvas')),
      findsOneWidget,
    );
    expect(find.text('Not painted yet'), findsNothing);
    expect(find.text('Not on map'), findsNothing);
    expect(find.text('Use my own image'), findsNothing);
    expect(find.text('Orphan Continent'), findsNothing);
    // 无地图的 world 默认打开制图师，落在生成 tab。
    expect(find.byType(MapCartographerPanel), findsOneWidget);
    expect(tester.takeException(), isNull);

    final closePendingCartographer = find.descendant(
      of: find.byKey(const ValueKey('map_cartographer_header')),
      matching: find.byType(IconButton),
    );
    expect(closePendingCartographer, findsOneWidget);
    await tester.tap(closePendingCartographer);
    await tester.pump();
    expect(find.byType(MapCartographerPanel), findsNothing);

    await tester.tap(find.text('World 0').first);
    await tester.pump();
    expect(find.byType(MapCartographerPanel), findsOneWidget);
    await tester.tap(closePendingCartographer);
    await tester.pump();

    container
        .read(mapDesignDraftsProvider.notifier)
        .submit(
          databasePath: 'map-states',
          draft: const MapDesignDraft(
            worldId: 'world_1',
            prompt: 'Draft for another world',
          ),
        );
    await tester.pump();
    await tester.pump();
    expect(find.byType(MapCartographerPanel), findsNothing);

    container
        .read(mapDesignDraftsProvider.notifier)
        .submit(
          databasePath: 'map-states',
          draft: const MapDesignDraft(
            worldId: 'world_0',
            prompt: 'Agent-authored map prompt',
            styleId: 'engraving',
            resolutionId: '4k',
            qualityId: 'high',
            includeLocations: false,
          ),
        );
    await tester.pump();
    await tester.pump();

    expect(find.byType(MapCartographerPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('map_agent_draft_card')), findsOneWidget);
    final cartographerScrollable = find
        .descendant(
          of: find.byType(MapCartographerPanel),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('map_studio_prompt_field')),
      200,
      scrollable: cartographerScrollable,
    );
    final promptEditor = find.descendant(
      of: find.byKey(const ValueKey('map_studio_prompt_field')),
      matching: find.byType(EditableText),
    );
    expect(
      tester.widget<EditableText>(promptEditor).controller.text,
      isNot('Agent-authored map prompt'),
    );
    await tester.drag(cartographerScrollable, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('map_agent_draft_apply')),
    );
    await tester.pumpAndSettle();
    final applyDraft = find
        .byKey(const ValueKey('map_agent_draft_apply'))
        .hitTestable();
    expect(applyDraft, findsOneWidget);
    await tester.tap(applyDraft);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('map_studio_prompt_field')),
      200,
      scrollable: cartographerScrollable,
    );

    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any(
            (widget) => widget.controller.text == 'Agent-authored map prompt',
          ),
      isTrue,
    );
    expect(
      container.read(
        mapDesignDraftProvider(databasePath: 'map-states', worldId: 'world_0'),
      ),
      isNull,
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('map_prompt_header')),
        matching: find.byKey(const ValueKey('map_ask_agent')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('map_cartographer_header')),
        matching: find.byKey(const ValueKey('map_ask_agent')),
      ),
      findsNothing,
    );
    expect(find.text('AI Generate'), findsOneWidget);
    // 表单字段是 ListView 的单个子项，scrollUntilVisible 不会真的滚动；点击前显式滚到可见。
    await tester.ensureVisible(find.byKey(const ValueKey('map_ask_agent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map_ask_agent')));
    await tester.pumpAndSettle();

    final handoff = container.read(mapAgentHandoffProvider);
    expect(handoff, isNotNull);
    expect(handoff!.worldId, 'world_0');
    expect(handoff.worldName, 'World 0');
    expect(handoff.styleId, 'engraving');
    expect(handoff.styleWord, '版画线描');

    await tester.tap(find.text('Campus'));
    await tester.pumpAndSettle();

    expect(find.byType(MapCartographerPanel), findsOneWidget);
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((widget) => widget.controller.text == 'Campus'),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('World 23'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('World 23'), findsOneWidget);
    expect(tester.takeException(), isNull);

    maps.add([_map(id: 'map_1', locationId: 'world_0')]);
    for (
      var i = 0;
      i < 10 &&
          find
              .byKey(const ValueKey('map_studio_generating_canvas'))
              .evaluate()
              .isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.byKey(const ValueKey('map_studio_generating_canvas')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('map_studio_generating_canvas')),
        matching: find.text('Creating…'),
      ),
      findsOneWidget,
    );
    expect(find.text("This map hasn't been painted"), findsNothing);
    expect(find.byType(MapCartographerPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('map_agent_draft_card')), findsNothing);
    expect(tester.takeException(), isNull);

    final closeCartographer = find.descendant(
      of: find.byKey(const ValueKey('map_cartographer_header')),
      matching: find.byType(IconButton),
    );
    expect(closeCartographer, findsOneWidget);
    await tester.tap(closeCartographer);
    await tester.pump();
    expect(find.byType(MapCartographerPanel), findsNothing);

    container
        .read(mapDesignDraftsProvider.notifier)
        .submit(
          databasePath: 'map-states',
          draft: const MapDesignDraft(
            worldId: 'world_0',
            prompt: 'Updated agent-authored map prompt',
          ),
        );
    await tester.pump();
    await tester.pump();
    expect(find.byType(MapCartographerPanel), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

void _ignoreSelection(String _) {}

Location _location({
  required String id,
  required String name,
  String type = locationTypeWorld,
  String? parentId,
}) {
  final now = DateTime(2026);
  return Location(
    id: id,
    name: name,
    description: '',
    type: type,
    parentId: parentId,
    tags: '',
    status: locationStatusActive,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

NovelMap _map({required String id, required String locationId}) {
  final now = DateTime(2026);
  return NovelMap(
    id: id,
    name: 'World map',
    description: '',
    type: mapTypeWorld,
    locationId: locationId,
    width: 1280,
    height: 720,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Widget _wrap({required ProviderContainer container, required Widget child}) {
  return UncontrolledProviderScope(
    container: container,
    child: EasyLocalization(
      key: UniqueKey(),
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            builder: (context, child) => RevericTheme(
              data: RevericThemeData.reveric,
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(body: child),
          );
        },
      ),
    ),
  );
}
