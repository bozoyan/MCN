// 职责: 验证移动端分集卡在允许删除时提供左滑删除操作。
// 关联文件:
//   lib/mobile/features/screenplay/episode_card.dart
//   lib/shared/providers/screenplay_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/features/screenplay/episode_card.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('adds a left-swipe delete action when deletion is enabled', (
    tester,
  ) async {
    final database = NovelContentDatabase.forTest(NativeDatabase.memory());
    final service = ScreenplayService(database, novelId: 'novel_1');
    await service.createInitialStructure();
    final root = (await database.screenplayDao.getRoot())!;
    final season = (await database.screenplayDao.getSeasons(root.id)).single;
    final episode = (await database.screenplayDao.getEpisodes(
      season.id,
    )).single;
    const path = 'memory:mobile_episode_card';
    addTearDown(database.close);

    await tester.pumpWidget(
      _wrap(
        ProviderScope(
          overrides: [
            novelContentDatabaseProvider(path).overrideWithValue(database),
          ],
          child: Scaffold(
            body: MobileScreenplayEpisodeCard(
              path: path,
              episode: episode,
              onTap: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Slidable), findsOneWidget);
    expect(find.text('Delete'), findsNothing);

    await tester.drag(find.byType(Slidable), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Widget _wrap(Widget child) {
  if (child is ProviderScope) {
    return ProviderScope(overrides: child.overrides, child: _wrap(child.child));
  }
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
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
