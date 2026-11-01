// 职责: 验证桌面剧本概览的继续写作落点、简介统计与分集看板的定稿/分镜计数。
// 关联文件:
//   lib/desktop/features/screenplay/overview.dart
//   lib/desktop/features/screenplay/overview_cards.dart
//   lib/shared/providers/screenplay_providers.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/screenplay/overview.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/models/novel_type.dart';
import 'package:reveric/shared/models/screenplay.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('continue card quotes the current scene and board counts '
      'finals and adopted storyboard items', (tester) async {
    tester.view.physicalSize = const Size(1100, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final appDb = AppDatabase.forTest(NativeDatabase.memory());
    final contentDb = NovelContentDatabase.forTest(NativeDatabase.memory());
    final service = ScreenplayService(contentDb, novelId: 'screenplay_1');
    final initial = await service.createInitialStructure();
    final root = (await contentDb.screenplayDao.getRoot())!;
    await service.updateEpisode(
      episodeId: initial.episodeId,
      title: 'Boarding',
    );
    await service.createEpisode(seasonId: initial.seasonId, title: 'Fog');
    final sceneIds = <String>[];
    for (final (title, stage) in [
      ('Dock', screenplayStageFinal),
      ('Cabin', screenplayStageFinal),
      ('Hidden box', screenplayStageDraft),
    ]) {
      sceneIds.add(
        await service.createScene(
          screenplayId: root.id,
          episodeId: initial.episodeId,
          title: title,
          stage: stage,
        ),
      );
    }
    await service.writeElements(
      sceneId: sceneIds.first,
      elements: const [
        ScreenplayElement(
          type: ScreenplayElementType.action,
          text: 'He slides the box under the bench.',
        ),
        ScreenplayElement(
          type: ScreenplayElementType.action,
          text: 'The lamp gutters; nobody moves.',
        ),
      ],
    );
    final storyboard = StoryboardService(contentDb);
    await storyboard.create(sceneIds.first);
    await storyboard.create(sceneIds.first);
    const databasePath = 'memory:desktop_screenplay_overview';
    final novel = _screenplay(databasePath);
    addTearDown(() async {
      await contentDb.close();
      await appDb.close();
    });
    final boundary = GlobalKey();

    await tester.pumpWidget(
      _wrap(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(appDb),
            novelContentDatabaseProvider(
              databasePath,
            ).overrideWithValue(contentDb),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: ScreenplayOverviewRegion(
                novel: novel,
                screenplayId: root.id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (Platform.environment['OVERVIEW_SCREENSHOTS'] != null) {
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/screenplay-overview-desktop.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    expect(find.text('Logline'), findsOneWidget);
    expect(
      find.text('Six strangers, one boat, three days of fog.'),
      findsOneWidget,
    );
    // 工作区默认选中本集第一场 → 继续写作落在这一场，并引它的最后一句。
    expect(find.text('The lamp gutters; nobody moves.'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('Boarding'), findsWidgets);
    expect(find.text('Fog'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Novel _screenplay(String databasePath) {
  final now = DateTime(2026);
  return Novel(
    id: 'screenplay_1',
    title: 'Night Boat',
    authorName: '',
    description: 'Six strangers, one boat, three days of fog.',
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
