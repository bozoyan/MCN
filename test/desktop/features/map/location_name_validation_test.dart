// 职责: 验证桌面地点编辑对话框和检查器显示同名错误并保留草稿。
// 关联文件:
//   lib/desktop/features/map/map_create_dialogs.dart
//   lib/desktop/features/map/map_cartographer_panel.dart
//   lib/shared/services/maps_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/features/map/map_create_dialogs.dart';
import 'package:reveric/desktop/features/map/map_cartographer_panel.dart';
import 'package:reveric/shared/models/map_studio_models.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/maps_providers.dart';
import 'package:reveric/shared/services/maps_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());
  testWidgets('duplicate edit remains open and correction saves both fields', (
    tester,
  ) async {
    final db = NovelContentDatabase.forTest(NativeDatabase.memory());
    final service = LocationsService(db);
    final parentId = await service.createLocation(
      name: 'Parent',
      type: locationTypeWorld,
    );
    await service.createLocation(name: 'Taken', parentId: parentId);
    final id = await service.createLocation(
      name: 'Draft',
      description: 'Original',
      type: locationTypeWorld,
      parentId: parentId,
    );
    final locations = await service.getLocations();
    var inspecting = false;
    String? selectedId = id;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationsServiceProvider('edit-test').overrideWithValue(service),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const MergingAssetLoader(),
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: RevericThemeData.reveric.toThemeData(),
              builder: (_, child) => RevericTheme(
                data: RevericThemeData.reveric,
                child: child!,
              ),
              home: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  body: inspecting
                      ? MapCartographerPanel(
                          novelId: 'test',
                          databasePath: 'edit-test',
                          map: null,
                          settings: const MapStudioSettings(),
                          locations: locations,
                          selectedLocationId: selectedId,
                          mappedLocationIds: const {},
                          onSelectionChanged: (next) =>
                              setState(() => selectedId = next),
                          onEnterMap: (_) {},
                          onClose: () {},
                        )
                      : Column(
                          children: [
                            TextButton(
                              onPressed: () => showEditLocationDialog(
                                context,
                                databasePath: 'edit-test',
                                locations: locations,
                                location: locations.singleWhere(
                                  (l) => l.id == id,
                                ),
                              ),
                              child: const Text('Open'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => inspecting = true),
                              child: const Text('Inspect'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Taken');
    await tester.enterText(find.byType(TextField).last, 'New description');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('A location with this name already exists.'),
      findsOneWidget,
    );
    expect((await service.getLocationById(id))!.description, 'Original');
    await tester.enterText(find.byType(TextField).first, 'Unique');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(EditLocationDialog), findsNothing);
    expect((await service.getLocationById(id))!.description, 'New description');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Inspect'));
    await tester.pumpAndSettle();
    final inspectorName = find.descendant(
      of: find.byKey(const ValueKey('map_location_inspector_name')),
      matching: find.byType(TextField),
    );
    await tester.enterText(inspectorName, 'Taken');
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('A location with this name already exists.'),
      findsOneWidget,
    );
    expect((await service.getLocationById(id))!.name, 'Unique');
    expect(selectedId, id);
    await tester.enterText(inspectorName, 'Inspector unique');
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await service.getLocationById(id))!.name, 'Inspector unique');
    expect(
      find.text('A location with this name already exists.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await db.close();
  });
}
