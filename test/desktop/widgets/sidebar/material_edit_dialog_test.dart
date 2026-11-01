// 职责: 验证素材编辑弹窗在打开和关闭动画期间正确持有输入控制器。
// 关联文件:
//   lib/desktop/widgets/sidebar/menus.dart
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:drift/native.dart';
import 'package:reveric/shared/database/app_database.dart' show AppDatabase;
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/widgets/sidebar/sidebar.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('material edit dialog survives opening and animated dismissal', (
    tester,
  ) async {
    final database = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(database.close);
    final saved = <String>[];
    await tester.pumpWidget(
      _wrapSidebar(
        database: database,
        selection: const WorkspaceSelection(
          section: NovelWorkspaceSection.materials,
        ),
        onCollapse: () {},
        onRename: (id, title, {category}) async {
          saved.add('$id/$title/$category');
        },
      ),
    );
    await tester.pumpAndSettle();
    await _openEditor(tester);
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    final controller = tester.widget<TextField>(fields.first).controller!;
    expect(controller.text, 'Test material');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(fields, findsNWidgets(2));
    void listener() {}
    controller.addListener(listener);
    controller.removeListener(listener);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(saved, isEmpty);
    expect(() => controller.addListener(listener), throwsFlutterError);

    // 每次重开必须创建新的 controller，并保留校验与提交行为。
    await _openEditor(tester);
    final reopened = tester.widget<TextField>(fields.first).controller!;
    expect(identical(reopened, controller), isFalse);
    await tester.enterText(fields.first, '');
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(saved, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(fields.first, ' Updated material ');
    await tester.enterText(fields.last, 'New category');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(saved, ['material-1/Updated material/New category']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);

    await _openEditor(tester);
    await tester.tapAt(const Offset(790, 590));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);

    await _openEditor(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(saved, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.text('Test material'), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

Widget _wrapSidebar({
  required AppDatabase database,
  required WorkspaceSelection selection,
  required VoidCallback onCollapse,
  required Future<void> Function(String, String, {String? category}) onRename,
}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            appSettingsNotifierProvider.overrideWith(
              _TestAppSettingsNotifier.new,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: LeftSidebar(
                  novelTitle: 'Test novel',
                  currentNovelId: 'novel-1',
                  databasePath: null,
                  selection: selection,
                  chapters: const [],
                  worldbuildingEntries: const [],
                  outlineEntries: const [],
                  materialEntries: [
                    Document(
                      id: 'material-1',
                      type: documentTypeMaterial,
                      title: 'Test material',
                      content: '',
                      category: 'Reference',
                      status: '',
                      tags: '[]',
                      isFolder: false,
                      sortOrder: 0,
                      createdAt: DateTime.utc(2026),
                      updatedAt: DateTime.utc(2026),
                      deletedAt: notDeletedSentinel,
                    ),
                  ],
                  characterProfiles: const [],
                  skillEntries: const [],
                  items: const [],
                  factionEntries: const [],
                  creatureEntries: const [],
                  foreshadowings: const [],
                  maps: const [],
                  locations: const [],
                  onSelect: (_) {},
                  onEditDetails: () {},
                  onCreateChapter: () async {},
                  onCollapse: onCollapse,
                  onExpand: () {},
                  onSwitchNovel: (_) {},
                  onRenameDocument: onRename,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _TestAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async {
    return AppSettings(
      theme: AppTheme.reveric,
      themeMode: AppThemeMode.light,
      language: 'en',
      aiSettings: AiSettings.defaults(),
    );
  }
}
