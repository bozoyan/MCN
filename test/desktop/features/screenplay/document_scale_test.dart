// 职责: 实测 2400 节点文档的输入、跨场拖选、保存及局部重建/更新范围。
// 关联文件:
//   lib/shared/widgets/screenplay/document_editor.dart
//   lib/shared/widgets/screenplay/document_session.dart
//   lib/shared/database/novel_content_daos/screenplay_dao.dart
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/screenplay/script.dart';
import 'package:reveric/shared/widgets/screenplay/editing_scope.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/models/novel_type.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reveric/shared/widgets/screenplay/text_field.dart';
import 'package:reveric/shared/widgets/screenplay/document_heading.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  testWidgets('2400 nodes retain local rebuilds and one-row text persistence', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppDatabase.forTest(NativeDatabase.memory());
    final db = NovelContentDatabase.forTest(NativeDatabase.memory());
    final service = ScreenplayService(db);
    final initial = await service.createInitialStructure();
    final root = (await db.screenplayDao.getRoot())!;
    for (var i = 0; i < 30; i++) {
      await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
      );
    }
    final headings = await db.screenplayDao.getDocumentElements(
      initial.episodeId,
    );
    final nodes = <ScreenplayElement>[];
    for (final (scene, heading) in headings.indexed) {
      nodes.add(heading);
      for (var j = 0; j < 79; j++) {
        nodes.add(
          ScreenplayElement(
            id: 'node_${scene}_$j',
            episodeId: initial.episodeId,
            sceneId: heading.sceneId,
            type: ScreenplayElementType.action,
            text: 'Scene $scene paragraph $j. The door opens quietly.',
          ),
        );
      }
    }
    await db.screenplayDao.reconcileDocuments(
      {initial.episodeId: nodes},
      newElementIds: {
        for (final node in nodes)
          if (!node.isHeading) node.id!,
      },
    );
    await db.customStatement('CREATE TEMP TABLE changed_elements (id TEXT)');
    await db.customStatement(
      'CREATE TEMP TRIGGER record_element_update AFTER UPDATE ON screenplay_scene_elements BEGIN INSERT INTO changed_elements VALUES (new.id); END',
    );
    const path = 'memory:screenplay_scale';
    Future<void> Function()? flush;
    final initialWatch = Stopwatch()..start();
    await tester.pumpWidget(
      _wrap(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(app),
            novelContentDatabaseProvider(path).overrideWithValue(db),
          ],
          child: Scaffold(
            body: ScreenplayScriptRegion(
              novel: _screenplay(path),
              registerFlush: (value) => flush = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    initialWatch.stop();
    final scope = tester.state<ScreenplayEditingScopeState>(
      find.byType(ScreenplayEditingScope),
    );
    final c = scope.controller;
    expect(c.value, hasLength(2400));
    var fieldBuilds = 0;
    var headingBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is ScreenplayElementField) {
        fieldBuilds++;
      }
      if (element.widget is ScreenplayDocumentHeading) {
        headingBuilds++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    final inputWatch = Stopwatch()..start();
    await tester.enterText(find.byType(TextField).first, 'Changed opening');
    await tester.pump();
    inputWatch.stop();
    final saveWatch = Stopwatch()..start();
    await flush!();
    await tester.pumpAndSettle();
    saveWatch.stop();
    final changed = await db
        .customSelect('SELECT id FROM changed_elements')
        .get();
    expect(changed.map((r) => r.read<String>('id')), ['node_0_0']);
    expect(fieldBuilds, lessThan(10));
    expect(headingBuilds, 0);
    Offset point(int index, int offset) {
      final render = scope.rowAt(index)!.editable!.renderEditable;
      return render.localToGlobal(
        render.getLocalRectForCaret(TextPosition(offset: offset)).centerLeft,
      );
    }

    final dragWatch = Stopwatch()..start();
    final mouse = await tester.startGesture(
      point(1, 2),
      kind: PointerDeviceKind.mouse,
    );
    // Move across all mounted scene boundaries, using the same global selection handler.
    await mouse.moveTo(point(81, 8));
    await tester.pump();
    await mouse.up();
    dragWatch.stop();
    expect(c.crossesElements, isTrue);
    expect(c.selectedText(), isNot(contains('\uFFFC')));
    debugPrint(
      'SCREENPLAY_SCALE nodes=2400 first_frame_ms=${initialWatch.elapsedMilliseconds} input_ms=${inputWatch.elapsedMilliseconds} save_ms=${saveWatch.elapsedMilliseconds} drag_ms=${dragWatch.elapsedMilliseconds} field_builds=$fieldBuilds heading_builds=$headingBuilds element_updates=${changed.length}',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await db.close();
    await app.close();
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
