// 职责: 复现正文往上滚回顶部、以及外部跳回旧场次时高亮与正文脱节的场景。
// 关联文件:
//   lib/shared/widgets/screenplay/document_rows.dart
//   lib/desktop/features/screenplay/script.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/screenplay/script.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/models/novel_type.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/screenplay_workspace_state_provider.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/screenplay/editing_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('scrolling back to the top carries the current scene with it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final appDb = AppDatabase.forTest(NativeDatabase.memory());
    final contentDb = NovelContentDatabase.forTest(NativeDatabase.memory());
    final service = ScreenplayService(contentDb, novelId: 'screenplay_1');
    final initial = await service.createInitialStructure();
    final root = (await contentDb.screenplayDao.getRoot())!;
    final sceneIds = <String>[];
    for (var index = 0; index < 12; index++) {
      final id = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
        timeLabel: 'Day',
      );
      await service.writeElements(
        sceneId: id,
        elements: [
          for (var line = 0; line < 3; line++)
            ScreenplayElement(
              type: ScreenplayElementType.action,
              text: 'Scene $index line $line.',
            ),
        ],
      );
      sceneIds.add(id);
    }

    const path = 'memory:desktop_screenplay_desync';
    await tester.pumpWidget(
      _wrap(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(appDb),
            novelContentDatabaseProvider(path).overrideWithValue(contentDb),
          ],
          child: Scaffold(
            body: ScreenplayScriptRegion(
              novel: _screenplay(path),
              registerFlush: (_) {},
            ),
          ),
        ),
      ),
    );
    for (
      var frame = 0;
      frame < 30 && find.byType(ScreenplayEditingScope).evaluate().isEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ScreenplayEditingScope)),
    );
    final stateProvider = screenplayWorkspaceStateControllerProvider(
      'screenplay_1',
      path,
    );
    final scrollFinder = find.descendant(
      of: find.byType(ScreenplayEditingScope),
      matching: find.byType(SingleChildScrollView),
    );
    final controller = tester
        .widget<SingleChildScrollView>(scrollFinder)
        .controller!;

    // 1. 用户滚下去，跟随把当前场次带到靠后的一场。
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    final scrolledScene = container.read(stateProvider).sceneId;
    expect(scrolledScene, isNotNull);
    expect(sceneIds.indexOf(scrolledScene!), greaterThan(0));

    // 2. 往上滚回顶部：当前场次必须跟回第一场，不能卡在刚才那一场。
    controller.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(
      container.read(stateProvider).sceneId,
      sceneIds.first,
      reason: '滚回顶部时没有标题越过顶沿，当前场次仍要落到第一场',
    );

    // 3. 外部（AI 活动 / 跳转）把当前场次指回已上报过的一场，正文要跟过去。
    container
        .read(stateProvider.notifier)
        .update(container.read(stateProvider).copyWith(sceneId: scrolledScene));
    await tester.pumpAndSettle();
    expect(
      controller.position.pixels,
      greaterThan(0),
      reason: '外部把选中指回已上报过的场次时，正文仍要跟过去',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await contentDb.close();
    await appDb.close();
  });
}

Novel _screenplay(String databasePath) {
  final now = DateTime(2026);
  return Novel(
    id: 'screenplay_1',
    title: 'Screenplay Test',
    authorName: '',
    description: '',
    status: contentStatusInProgress,
    type: novelTypeOriginal,
    contentKind: contentKindScreenplay,
    contentDatabasePath: databasePath,
    wordCount: 0,
    draft: false,
    category: '',
    tags: const [],
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Widget _wrap(Widget child) {
  if (child is ProviderScope) {
    return ProviderScope(overrides: child.overrides, child: _wrap(child.child));
  }
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) => RevericTheme(
        data: RevericThemeData.reveric,
        child: MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: child,
        ),
      ),
    ),
  );
}
