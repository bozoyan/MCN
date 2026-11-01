// 职责: 验证桌面与移动集大纲的外部同步不会生成手动保存或覆盖本地输入。
// 关联文件:
//   lib/desktop/features/screenplay/outline.dart
//   lib/mobile/features/screenplay/outline_page.dart
//   lib/shared/services/screenplay_outline_save.dart
//   lib/shared/services/working_overlay.dart
//   lib/shared/providers/screenplay_workspace_state_provider.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/text-input-ime.md

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/screenplay/outline.dart';
import 'package:reveric/mobile/features/screenplay/outline_page.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/models/novel_type.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/screenplay_workspace_state_provider.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/md/reveric_markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final mobile in [false, true]) {
    for (final localEdit in [false, true]) {
      testWidgets(
        '${mobile ? 'mobile' : 'desktop'} outline preserves ${localEdit ? 'local input during AI writes' : 'consecutive AI writes without manual commits'}',
        (tester) async {
          tester.view.physicalSize = mobile
              ? const Size(390, 844)
              : const Size(1600, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final appDb = AppDatabase.forTest(NativeDatabase.memory());
          final database = NovelContentDatabase.forTest(
            NativeDatabase.memory(),
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await database.close();
            await appDb.close();
          });
          final overlay = WorkingOverlayService(
            database,
            NovelContentService(database),
            novelActionsService: NovelActionsService(appDb),
          );
          final service = ScreenplayService(database);
          final initial = await service.createInitialStructure();
          await service.updateEpisodeOutline(
            episodeId: initial.episodeId,
            outline: 'Original',
          );
          if (mobile) {
            final root = (await database.screenplayDao.getRoot())!;
            for (var i = 1; i <= 20; i++) {
              await service.createBeat(
                screenplayId: root.id,
                episodeId: initial.episodeId,
                actNumber: 1,
                title: 'Beat $i',
              );
            }
          }
          const path = 'memory:outline-sync';
          Future<void> Function()? flush;
          void registerFlush(Future<void> Function()? callback) {
            flush = callback;
          }

          // 翻译加载使用真实 asset IO；先完成挂载，再回到假时钟验证防抖顺序。
          await tester.runAsync(() async {
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  appDatabaseProvider.overrideWithValue(appDb),
                  appSettingsDatabaseProvider.overrideWithValue(appDb),
                  novelContentDatabaseProvider(
                    path,
                  ).overrideWithValue(database),
                  workingOverlayServiceProvider(
                    path,
                  ).overrideWithValue(overlay),
                ],
                child: _wrap(
                  mobile
                      ? MobileScreenplayOutlinePage(
                          novel: _screenplay(path),
                          registerFlush: registerFlush,
                        )
                      : ScreenplayOutlineRegion(
                          novel: _screenplay(path),
                          registerFlush: registerFlush,
                        ),
                ),
              ),
            );
            await const MergingAssetLoader().load(
              'assets/translations',
              const Locale('en'),
            );
          });
          await tester.pumpAndSettle();
          final finder = find.byType(RevericMarkdownEditor);
          expect(finder, findsOneWidget);
          final editor = tester.widget<RevericMarkdownEditor>(finder);
          final controller = editor.controller;
          expect(controller.text, 'Original');
          if (mobile) {
            final state = tester.state(finder);
            final registeredFlush = flush;
            final position = tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position;
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(state.mounted, isTrue);
            expect(identical(flush, registeredFlush), isTrue);
            position.jumpTo(0);
            await tester.pumpAndSettle();
            expect(
              tester.widget<RevericMarkdownEditor>(finder).controller,
              controller,
            );
          }
          if (localEdit) {
            editor.focusNode.requestFocus();
            await tester.pump();
            controller.value = const TextEditingValue(
              text: '用户输入',
              selection: TextSelection.collapsed(offset: 4),
              composing: TextRange(start: 0, end: 4),
            );
          }
          for (final text in ['AI first', 'AI second']) {
            final before = (await database.screenplayDao.getEpisode(
              initial.episodeId,
            ))!.outline;
            await overlay.stageTextChange(
              resourcePath: '/episodes/${initial.episodeId}/outline',
              resourceType: workingChangeResourceTypeScreenplayEpisodes,
              resourceId: initial.episodeId,
              field: 'outline',
              oldText: before,
              newText: text,
              source: workingChangeSourceAi,
              sourceSessionId: 'session_1',
              expectedCurrentText: before,
            );
            await tester.pump(const Duration(milliseconds: 40));
            await tester.pump();
          }
          if (localEdit) {
            expect(controller.text, '用户输入');
            expect(
              controller.value.composing,
              const TextRange(start: 0, end: 4),
            );
            expect(editor.focusNode.hasFocus, isTrue);
            controller.value = controller.value.copyWith(
              composing: TextRange.empty,
            );
          }
          await flush!();
          await tester.pumpAndSettle();
          final expectedText = localEdit ? '用户输入' : 'AI second';
          final saved = (await database.screenplayDao.getEpisode(
            initial.episodeId,
          ))!.outline;
          final shown = controller.text;
          final changes = await overlay.getWorkingChanges();
          final commits = await overlay.getChangeCommits();

          expect(saved, expectedText);
          expect(shown, expectedText);
          if (localEdit) {
            expect(
              commits.map((row) => row.source),
              contains(workingChangeSourceManual),
            );
          } else {
            expect(commits, isEmpty);
            expect(changes, hasLength(1));
            expect(changes.single.status, workingChangeStatusActive);
            expect(changes.single.newText, 'AI second');

            // 和改动记录入口一样按集 ID 导航，两个平台都必须显示目标季的大纲。
            final root = (await database.screenplayDao.getRoot())!;
            final target = await service.createSeason(screenplayId: root.id);
            await service.updateEpisodeOutline(
              episodeId: target.episodeId,
              outline: 'Target season outline',
            );
            final container = ProviderScope.containerOf(tester.element(finder));
            await container
                .read(
                  screenplayWorkspaceStateControllerProvider(
                    _screenplay(path).id,
                    path,
                  ).notifier,
                )
                .openEpisodeOutline(target.episodeId);
            await tester.pumpAndSettle();
            expect(
              tester.widget<RevericMarkdownEditor>(finder).controller.text,
              'Target season outline',
            );
          }
          // Drift stream 的取消 timer 必须在测试体结束前清掉。
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}

Novel _screenplay(String databasePath) {
  final now = DateTime(2026);
  return Novel(
    id: 'screenplay_outline_sync',
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
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    saveLocale: false,
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
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
}
