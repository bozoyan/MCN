// 职责: 验证已结束关系发现、共享详情证据与窄屏长文本布局。
// 关联文件:
//   lib/shared/widgets/relation/detail.dart
//   lib/shared/widgets/relation/list_region.dart
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_button.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/entity_relations_service.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/widgets/relation/detail.dart';
import 'package:reveric/shared/widgets/relation/list_region.dart';
import 'package:reveric/mobile/widgets/relation_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'harness.dart';

void main() {
  late NovelContentDatabase db;
  late EntityRelationsService service;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() {
    rootBundle.clear();
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = EntityRelationsService(db);
  });
  tearDown(() => db.close());
  const names = {'character_a': 'Aster', 'character_b': 'Briar'};
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('ended-only entity can reveal and select its existing relation', (
    tester,
  ) async {
    final id = await service.createRelation(
      sourceType: 'character',
      sourceId: 'a',
      targetType: 'character',
      targetId: 'b',
      relationType: 'lover',
      status: 'ended',
      proof: 'ended proof',
    );
    String? selected;
    await tester.pumpWidget(
      relationHarness(
        db,
        RelationListRegion(
          databasePath: 'test',
          entityKey: 'character_a',
          names: names,
          onOpenDetail: (id) => selected = id,
        ),
        width: 320,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('relation-row-$id')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('relation-show-ended')));
    await tester.pumpAndSettle();
    expect(find.text('Ended'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('relation-row-$id')));
    await tester.pumpAndSettle();
    expect(selected, id);
    expect(
      (await service.graphSearch(
        entityType: 'character',
        entityId: 'a',
      )).totalRelations,
      0,
    );
    await close(tester);
  });

  testWidgets(
    'desktop ended discovery and history expansion stay inside the relation region',
    (tester) async {
      final id = await service.createRelation(
        sourceType: 'character',
        sourceId: 'a',
        targetType: 'character',
        targetId: 'b',
        relationType: 'lover',
        status: 'ended',
        proof: 'ended desktop proof',
      );
      var graphHostBuilds = 0;
      await tester.pumpWidget(
        relationHarness(
          db,
          Builder(
            builder: (_) {
              graphHostBuilds++;
              return const RelationListRegion(
                databasePath: 'test',
                entityKey: 'character_a',
                names: names,
              );
            },
          ),
          width: 360,
        ),
      );
      await tester.pumpAndSettle();
      final settledBuilds = graphHostBuilds;
      expect(find.byKey(ValueKey('relation-row-$id')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('relation-show-ended')));
      await tester.pumpAndSettle();
      expect(find.byType(RelationDetail), findsOneWidget);
      final toggle = find.byKey(const ValueKey('relation-history-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.textContaining('Initial record'), findsOneWidget);
      expect(graphHostBuilds, settledBuilds);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets('mobile list opens ended detail before editing at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = await service.createRelation(
      sourceType: 'character',
      sourceId: 'a',
      targetType: 'character',
      targetId: 'b',
      relationType: 'lover',
      status: 'ended',
      proof: 'A complete ended relationship proof.',
    );
    await tester.pumpWidget(
      relationHarness(
        db,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showRelationListSheet(
              context,
              'test',
              'character_a',
              names,
              novelId: 'work',
            ),
            child: const Text('Open relations'),
          ),
        ),
        platform: TargetPlatform.android,
        width: 390,
        height: 844,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open relations'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('relation-show-ended')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('relation-row-$id')));
    await tester.pumpAndSettle();
    expect(find.byType(RelationDetail), findsOneWidget);
    expect(find.text('A complete ended relationship proof.'), findsOneWidget);
    expect(find.text('Restore relation'), findsNothing);
    expect(find.byKey(const ValueKey('relation-proof')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('relation-more-actions')));
    await tester.pumpAndSettle();
    expect(find.text('Restore relation'), findsOneWidget);
    await tester.tap(find.text('Restore relation'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('relation-proof')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    testWidgets('$platform groups secondary actions and confirms deletion', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final id = await service.createRelation(
        sourceType: 'character',
        sourceId: 'a',
        targetType: 'character',
        targetId: 'b',
        relationType: 'friend',
        proof: 'original proof',
      );
      await tester.pumpWidget(
        relationHarness(
          db,
          SingleChildScrollView(
            child: RelationDetail(
              databasePath: 'test',
              relationId: id,
              names: names,
            ),
          ),
          platform: platform,
          width: 320,
          height: 844,
        ),
      );
      await tester.pumpAndSettle();
      final more = find.byKey(const ValueKey('relation-more-actions'));
      expect(find.text('Record change'), findsOneWidget);
      expect(find.text('Correct current details'), findsNothing);
      expect(find.text('End relation'), findsNothing);
      expect(find.text('Delete relation'), findsNothing);
      expect(
        tester.getCenter(find.text('Record change')).dy,
        closeTo(tester.getCenter(more).dy, 1),
      );

      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(
        find.byType(BottomSheet),
        platform == TargetPlatform.android ? findsOneWidget : findsNothing,
      );
      expect(find.text('End relation'), findsOneWidget);
      await tester.tap(find.text('Correct current details'));
      await tester.pumpAndSettle();
      expect(find.text('Delete relation'), findsNothing);
      expect(find.byKey(const ValueKey('relation-proof')), findsOneWidget);
      expect(find.byKey(const ValueKey('relation-reason')), findsNothing);
      await tester.tap(find.widgetWithText(RevericButton, 'Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete relation'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Delete this mistaken relation and its entire history? This cannot be undone.',
        ),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(await service.getRelationById(id), isNotNull);
      await tester.tap(find.widgetWithText(RevericButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(await service.getRelationById(id), isNotNull);

      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete relation'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(RevericButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(await service.getRelationById(id), isNull);
      expect(find.text('This relation no longer exists.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }

  testWidgets(
    'narrow detail wraps long evidence and only valid evidence can navigate',
    (tester) async {
      final content = NovelContentService(db);
      final chapter = await content.createChapter(
        siblingOrder: 1,
        title: 'Old city',
      );
      final id = await service.createRelation(
        sourceType: 'character',
        sourceId: 'a',
        targetType: 'character',
        targetId: 'b',
        relationType: 'friend',
        chapterId: chapter,
        proof: List.filled(20, 'A long evidence passage.').join(' '),
      );
      String? jumped;
      await tester.pumpWidget(
        relationHarness(
          db,
          SingleChildScrollView(
            child: RelationDetail(
              databasePath: 'test',
              relationId: id,
              names: names,
              onOpenEvidence: (_, id) => jumped = id,
            ),
          ),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();
      final evidence = find.text('Chapter · Old city');
      await tester.ensureVisible(evidence);
      await tester.tap(evidence);
      await tester.pumpAndSettle();
      expect(jumped, chapter);
      await content.deleteChapter(chapter);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('relation-history-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('relation-history-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Evidence was deleted'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
}
