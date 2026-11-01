// 职责: 验证制图师地点库只展示直接 children，并支持逐层进入与返回父地点。
// 关联文件:
//   lib/shared/widgets/map/map_location_children.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/map/map_location_children.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('shows direct children in order and drills into the next level', (
    tester,
  ) async {
    final locations = [
      _location(id: 'world', name: 'World', type: locationTypeWorld),
      _location(id: 'south', name: 'South', parentId: 'world', sortOrder: 2),
      _location(id: 'north', name: 'North', parentId: 'world', sortOrder: 1),
      _location(
        id: 'kingdom',
        name: 'Kingdom',
        type: locationTypeCountry,
        parentId: 'north',
      ),
      _location(
        id: 'city',
        name: 'City',
        type: locationTypeCity,
        parentId: 'kingdom',
      ),
      _location(
        id: 'district',
        name: 'District',
        type: locationTypeDistrict,
        parentId: 'city',
      ),
    ];

    await tester.pumpWidget(_wrap(_DrillDownHarness(locations: locations)));
    await tester.pumpAndSettle();

    expect(find.text('North'), findsOneWidget);
    expect(find.text('South'), findsOneWidget);
    expect(find.text('Kingdom'), findsNothing);
    expect(
      tester.getTopLeft(find.text('North')).dy,
      lessThan(tester.getTopLeft(find.text('South')).dy),
    );

    await tester.tap(find.byKey(const ValueKey('map_location_child_north')));
    await tester.pumpAndSettle();
    expect(find.text('Kingdom'), findsOneWidget);
    expect(find.text('City'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('map_location_child_kingdom')));
    await tester.pumpAndSettle();
    expect(find.text('City'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map_location_child_city')));
    await tester.pumpAndSettle();
    expect(find.text('District'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map_location_child_district')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('map_location_children_section')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('map_location_parent_city')));
    await tester.pumpAndSettle();
    expect(find.text('District'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map_location_parent_kingdom')));
    await tester.pumpAndSettle();
    expect(find.text('City'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DrillDownHarness extends HookWidget {
  const _DrillDownHarness({required this.locations});

  final List<Location> locations;

  @override
  Widget build(BuildContext context) {
    final parentId = useState('world');
    final selectedLocation = locations
        .where((location) => location.id == parentId.value)
        .first;
    final parentLocation = selectedLocation.parentId == null
        ? null
        : locations
              .where((location) => location.id == selectedLocation.parentId)
              .firstOrNull;
    return Scaffold(
      body: SizedBox(
        width: 300,
        child: ListView(
          padding: const EdgeInsets.all(RevericSpacing.md),
          children: [
            Text(parentId.value, key: const ValueKey('selected_parent')),
            if (parentLocation != null)
              MapLocationParentLink(
                parent: parentLocation,
                onSelected: (value) => parentId.value = value,
              ),
            MapLocationChildren(
              parentId: parentId.value,
              locations: locations,
              onSelected: (value) => parentId.value = value,
            ),
          ],
        ),
      ),
    );
  }
}

Location _location({
  required String id,
  required String name,
  String type = locationTypeContinent,
  String? parentId,
  int sortOrder = 0,
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
    sortOrder: sortOrder,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Widget _wrap(Widget child) {
  return EasyLocalization(
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
          home: RevericTheme(data: RevericThemeData.reveric, child: child),
        );
      },
    ),
  );
}
