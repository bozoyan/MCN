// 职责: 验证小说编辑侧栏折叠入口布局与作品切换菜单的局部订阅生命周期。
// 关联文件:
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/desktop-window-frame.md

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/widgets/sidebar/sidebar.dart';
import 'package:reveric/shared/database/app_database.dart'
    show Novel, notDeletedSentinel;
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  testWidgets(
    'switcher subscribes only while open',
    (tester) async {
      var subscriptions = 0;
      var cancellations = 0;
      var current = [
        _novel('novel-1', 'Current draft', draft: true),
        _novel('other', 'Other work'),
        _novel('hidden', 'Hidden draft', draft: true),
      ];
      late MultiStreamController<List<Novel>> updates;
      final selected = <Novel>[];
      await tester.pumpWidget(
        _wrapSidebar(
          selection: const WorkspaceSelection(
            section: NovelWorkspaceSection.chapters,
          ),
          onCollapse: () {},
          onSwitchNovel: selected.add,
          novelStream: () => Stream.multi((controller) {
            subscriptions++;
            updates = controller;
            controller.add(current);
            controller.onCancel = () {
              cancellations++;
            };
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(subscriptions, 0);
      final switcher = find.byKey(const ValueKey('sidebar-novel-switcher'));
      final titlePosition = tester.getTopLeft(find.text('Test novel'));
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      expect(subscriptions, 1);
      expect(find.text('Current draft'), findsOneWidget);
      expect(find.text('Other work'), findsOneWidget);
      expect(find.text('Hidden draft'), findsNothing);

      current = [current.first, _novel('other', 'Renamed work')];
      updates.add(current);
      await tester.pumpAndSettle();
      expect(find.text('Other work'), findsNothing);
      expect(find.text('Renamed work'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Test novel')), titlePosition);

      await tester.tap(find.text('Current draft'));
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      expect(cancellations, 1);
      expect(subscriptions, 1);

      current = [current.first, _novel('other', 'Latest work')];
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      expect(subscriptions, 2);
      expect(find.text('Latest work'), findsOneWidget);
      await tester.tap(find.text('Latest work'));
      await tester.pumpAndSettle();
      expect(selected.single.title, 'Latest work');
      expect(cancellations, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'collapse control follows the sidebar edge across rail-only and panel modes',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      var collapseCount = 0;
      await tester.pumpWidget(
        _wrapSidebar(
          selection: const WorkspaceSelection.overview(),
          onCollapse: () {
            collapseCount++;
          },
        ),
      );
      await tester.pumpAndSettle();

      final collapseButton = find.byKey(
        const ValueKey('sidebar-collapse-button'),
      );
      expect(collapseButton, findsOneWidget);
      _expectCollapseAtSidebarRightEdge(tester);

      await tester.tap(collapseButton);
      expect(collapseCount, 1);

      await tester.pumpWidget(
        _wrapSidebar(
          selection: const WorkspaceSelection(
            section: NovelWorkspaceSection.chapters,
          ),
          isAgentRulesActive: true,
          onCollapse: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sidebar-collapse-button')),
        findsOneWidget,
      );
      _expectCollapseAtSidebarRightEdge(tester);

      await tester.pumpWidget(
        _wrapSidebar(
          selection: const WorkspaceSelection(
            section: NovelWorkspaceSection.chapters,
          ),
          onCollapse: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sidebar-collapse-button')),
        findsOneWidget,
      );
      _expectCollapseAtSidebarRightEdge(tester);
    },
  );
}

void _expectCollapseAtSidebarRightEdge(WidgetTester tester) {
  final sidebarRect = tester.getRect(find.byType(LeftSidebar));
  final buttonRect = tester.getRect(
    find.byKey(const ValueKey('sidebar-collapse-button')),
  );
  expect(
    sidebarRect.right - buttonRect.right,
    moreOrLessEquals(RevericSpacing.sm),
  );
}

Widget _wrapSidebar({
  required WorkspaceSelection selection,
  required VoidCallback onCollapse,
  bool isAgentRulesActive = false,
  Stream<List<Novel>> Function()? novelStream,
  ValueChanged<Novel>? onSwitchNovel,
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
            if (novelStream != null)
              novelsProvider.overrideWith((ref) => novelStream()),
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
                  materialEntries: const [],
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
                  onSwitchNovel: onSwitchNovel ?? (_) {},
                  isAgentRulesActive: isAgentRulesActive,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

Novel _novel(String id, String title, {bool draft = false}) {
  final now = DateTime.utc(2026);
  return Novel(
    id: id,
    title: title,
    authorName: '',
    description: '',
    status: 'in_progress',
    type: 'original',
    contentKind: 'novel',
    wordCount: 0,
    draft: draft,
    category: '',
    tags: const [],
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
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
