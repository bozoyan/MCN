// 职责: 验证桌面剧本正文滚动后当前场次跟随，且跟随不会把正文回拉到场首。
// 关联文件:
//   lib/desktop/features/screenplay/script.dart
//   lib/shared/widgets/screenplay/document_rows.dart
//   lib/shared/providers/screenplay_workspace_state_provider.dart
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

  testWidgets('scrolling the script carries the current scene downwards', (
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

    const path = 'memory:desktop_screenplay_scroll_sync';
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
    // 工作区先异步恢复当前集，正文才开始加载。
    for (
      var frame = 0;
      frame < 30 && find.byType(ScreenplayEditingScope).evaluate().isEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();
    expect(find.byType(ScreenplayEditingScope), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ScreenplayEditingScope)),
    );
    final stateProvider = screenplayWorkspaceStateControllerProvider(
      'screenplay_1',
      path,
    );
    final before = container.read(stateProvider).sceneId;

    final scrollFinder = find.descendant(
      of: find.byType(ScreenplayEditingScope),
      matching: find.byType(SingleChildScrollView),
    );
    final controller = tester
        .widget<SingleChildScrollView>(scrollFinder)
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    // 上报有 120ms 防抖，等它落下来。
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final after = container.read(stateProvider).sceneId;
    expect(after, isNotNull);
    expect(after, isNot(before));
    expect(
      sceneIds.indexOf(after!),
      greaterThan(before == null ? -1 : sceneIds.indexOf(before)),
    );
    // 跟随写回状态不得反过来把正文 ensureVisible 拉回场首。
    expect(
      controller.position.pixels,
      closeTo(controller.position.maxScrollExtent, 1),
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
