// 职责: 验证地图工作台的子地点地图导航 — 选中地点切到画着它的图、进入地点自己的图、面包屑返回。
// 关联文件:
//   lib/desktop/features/map/map_studio_page.dart
//   lib/desktop/features/map/map_cartographer_panel.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/providers/map_studio_controller.dart';
import 'package:reveric/desktop/features/map/map_studio_page.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/maps_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('selecting a place shows the map it is drawn on', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final maps = StreamController<List<NovelMap>>();
    addTearDown(maps.close);
    final container = ProviderContainer(
      overrides: [
        mapsProvider('submaps').overrideWith((ref) => maps.stream),
        locationsProvider('submaps').overrideWith(
          (ref) => Stream.value([
            _location(id: 'world', name: 'World'),
            _location(
              id: 'village',
              name: 'Village',
              type: locationTypeVillage,
              parentId: 'world',
            ),
            _location(
              id: 'plaza',
              name: 'Plaza',
              type: locationTypeBuilding,
              parentId: 'village',
            ),
          ]),
        ),
        for (final mapId in ['map_world', 'map_village']) ...[
          mapLocationsProvider(
            databasePath: 'submaps',
            mapId: mapId,
          ).overrideWith((ref) => Stream.value(const <MapLocation>[])),
          mapStudioControllerProvider(
            'submaps',
            mapId,
          ).overrideWithValue(const MapStudioState()),
        ],
      ],
    );
    addTearDown(container.dispose);

    // 模拟 workspace：页面回写的 selection 再原样传回来。
    final selection = ValueNotifier<String?>(null);
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      _wrap(
        container: container,
        child: SizedBox.expand(
          child: ValueListenableBuilder<String?>(
            valueListenable: selection,
            builder: (context, worldId, _) => MapStudioPage(
              novelId: 'novel-test',
              databasePath: 'submaps',
              worldId: worldId,
              onWorldSelected: (id) => selection.value = id,
            ),
          ),
        ),
      ),
    );
    maps.add([_worldMap]);
    await tester.pumpAndSettle();

    const trailToWorld = ValueKey('map_trail_world');
    const pendingCanvas = ValueKey('map_studio_pending_canvas');

    // 村镇默认不展开，也没有自己的图。
    expect(find.text('Plaza'), findsNothing);
    expect(find.byKey(trailToWorld), findsNothing);

    await tester.tap(find.text('Village').first);
    await tester.pumpAndSettle();
    expect(find.byKey(trailToWorld), findsNothing);
    expect(find.text('Create a map for Village'), findsOneWidget);

    // 为子地点制作地图：进入待生成状态，面包屑能回到 world，子地点展开。
    await tester.tap(find.text('Create a map for Village'));
    await tester.pumpAndSettle();
    expect(find.byKey(pendingCanvas), findsOneWidget);
    expect(find.byKey(trailToWorld), findsOneWidget);
    expect(find.text('Plaza'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('map_generate_target')),
        matching: find.text('Village'),
      ),
      findsOneWidget,
    );

    // 上层地图已经画好：默认带上它作为画风参考图，可以取消。
    const parentToggle = ValueKey('map_studio_reference_parent_image_toggle');
    expect(find.byKey(parentToggle), findsOneWidget);
    bool promptMentionsParent() => tester
        .widgetList<EditableText>(find.byType(EditableText))
        .any((widget) => widget.controller.text.contains('上层地图「World」'));
    expect(promptMentionsParent(), isTrue);
    await tester.ensureVisible(find.byKey(parentToggle));
    await tester.tap(find.byKey(parentToggle));
    await tester.pumpAndSettle();
    expect(promptMentionsParent(), isFalse);

    // 待生成的图也算「画着它的图」，选子地点不会被弹回上层。
    await tester.tap(find.text('Plaza').first);
    await tester.pumpAndSettle();
    expect(find.byKey(pendingCanvas), findsOneWidget);

    await tester.tap(find.byKey(trailToWorld));
    await tester.pumpAndSettle();
    expect(find.byKey(pendingCanvas), findsNothing);
    expect(find.byKey(trailToWorld), findsNothing);

    // 子地点的图落库后：地点树出现进入图标，选它的子地点切到这张图。
    maps.add([
      _worldMap,
      _map(id: 'map_village', locationId: 'village', type: mapTypeCity),
    ]);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('map_rail_enter_map_village')),
      findsOneWidget,
    );

    await tester.tap(find.text('Plaza').first);
    await tester.pumpAndSettle();
    expect(find.byKey(trailToWorld), findsOneWidget);
    expect(find.text('Village · v0'), findsOneWidget);

    // 选中子地图的所属地点本身，回到画着它的上层图。
    await tester.tap(find.text('Village').first);
    await tester.pumpAndSettle();
    expect(find.byKey(trailToWorld), findsNothing);
    expect(find.text('Open map'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map_rail_enter_map_village')));
    await tester.pumpAndSettle();
    expect(find.text('Village · v0'), findsOneWidget);
    expect(selection.value, 'village');
    // 子地图同样可以交给 Agent 设计。
    expect(find.byKey(const ValueKey('map_ask_agent')), findsOneWidget);

    // 外部导航（Agent 投递草稿）按子地点 id 直接进入它的地图。
    await tester.tap(find.byKey(trailToWorld));
    await tester.pumpAndSettle();
    expect(selection.value, 'world');
    selection.value = 'village';
    await tester.pumpAndSettle();
    expect(find.text('Village · v0'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

// 世界图已经画过，作为子地图的画风来源。
final _worldMap = _map(
  id: 'map_world',
  locationId: 'world',
  settings: const {
    'studioVersion': 1,
    'image': 'images/maps/map_world/map-v1.webp',
    'canvasWidth': 2048,
    'canvasHeight': 1152,
    'style': '水墨舆图',
  },
);

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

NovelMap _map({
  required String id,
  required String locationId,
  String type = mapTypeWorld,
  Map<String, dynamic>? settings,
}) {
  final now = DateTime(2026);
  return NovelMap(
    id: id,
    name: id,
    description: '',
    type: type,
    locationId: locationId,
    width: 1280,
    height: 720,
    settings: settings,
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
