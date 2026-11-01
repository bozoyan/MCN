// 职责: 验证制片工作区打开时补建空剪辑，并在关联失效时显示加载失败。
// 关联文件:
//   lib/desktop/features/editing/shell.dart
//   lib/shared/services/production/editing_orchestrator.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/editing/shell.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  testWidgets(
    'production open initializes an empty editing and refuses a deleted link',
    (tester) async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      final first = await ScreenplayService(db).createInitialStructure();
      await (db.update(db.screenplayEpisodes)
            ..where((t) => t.id.equals(first.episodeId)))
          .write(const ScreenplayEpisodesCompanion(editingId: Value(null)));
      Widget screen(int revision) => ProviderScope(
        overrides: [novelContentDatabaseProvider('test').overrideWithValue(db)],
        child: EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const MergingAssetLoader(),
          startLocale: const Locale('en'),
          fallbackLocale: const Locale('en'),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: RevericTheme(
                data: RevericThemeData.reveric,
                child: Scaffold(
                  body: EditingShell(
                    novelId: 'work',
                    key: ValueKey(revision),
                    identity: (path: 'test', episodeId: first.episodeId),
                    registerFlush: (_) {},
                    builder: (_, _) => const Text('Production ready'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      try {
        await tester.pumpWidget(screen(0));
        await tester.pumpAndSettle();
        expect(find.text('Production ready'), findsOneWidget);
        final episode = (await db.screenplayDao.getEpisode(first.episodeId))!;
        final editing = (await db.editingDao.get(episode.editingId!))!;
        expect(editing.document.clips, isEmpty);
        expect(editing.revision, 0);
        await db.editingDao.softDelete(editing.id);
        await tester.pumpWidget(screen(1));
        await tester.pumpAndSettle();
        expect(find.text('Production ready'), findsNothing);
        expect(find.text('Failed to load'), findsOneWidget);
        expect(
          (await db.screenplayDao.getEpisode(first.episodeId))!.editingId,
          editing.id,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await db.close();
      }
    },
  );
}
