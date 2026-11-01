// 职责: 验证历史折叠、误录确认、基线保护和并发冲突反馈。
// 关联文件:
//   lib/shared/widgets/relation/history.dart
//   lib/shared/services/entity_relations_service.dart
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/entity_relations_service.dart';
import 'package:reveric/shared/widgets/relation/history.dart';
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
  Future<String> create() => service.createRelation(
    sourceType: 'character',
    sourceId: 'a',
    targetType: 'character',
    targetId: 'b',
    relationType: 'friend',
    proof: 'initial proof',
  );
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'history defaults collapsed, baseline has no delete, middle removal keeps later state',
    (tester) async {
      final id = await create();
      final first = await service.recordChange(
        id: id,
        relationType: 'enemy',
        proof: 'enemy proof',
        reason: 'betrayal',
      );
      await service.recordChange(
        id: id,
        relationType: 'lover',
        proof: 'lover proof',
        reason: 'reconciled',
      );
      await tester.pumpWidget(
        relationHarness(
          db,
          SingleChildScrollView(
            child: RelationHistory(databasePath: 'test', relationId: id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Changes (2)'), findsOneWidget);
      expect(find.text('enemy proof'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('relation-history-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('enemy proof'), findsOneWidget);
      expect(find.textContaining('Original record updated'), findsOneWidget);
      expect(find.text('Delete mistaken change'), findsNWidgets(2));
      final remove = find.byKey(ValueKey('remove-change-${first.changeId}'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Delete this record. The current relation will stay unchanged.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect((await service.getRelationById(id))!.relationType, 'lover');
      expect(find.text('enemy proof'), findsNothing);
      expect(
        find.textContaining('Friendship · Active → Lover'),
        findsOneWidget,
      );
      await close(tester);
    },
  );

  testWidgets(
    'single change opens by default, can collapse, and rejects stale removal',
    (tester) async {
      final id = await create();
      final first = await service.recordChange(
        id: id,
        relationType: 'enemy',
        proof: 'enemy proof',
        reason: 'betrayal',
      );
      await tester.pumpWidget(
        relationHarness(
          db,
          SingleChildScrollView(
            child: RelationHistory(databasePath: 'test', relationId: id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('enemy proof'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('relation-history-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('enemy proof'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('relation-history-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('remove-change-${first.changeId}')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('will return to “Friendship · Active”'),
        findsOneWidget,
      );
      await service.recordChange(
        id: id,
        relationType: 'lover',
        proof: 'later',
        reason: 'later',
      );
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect((await service.getRelationById(id))!.changeLogs, hasLength(3));
      expect(
        find.byKey(const ValueKey('relation-history-error')),
        findsOneWidget,
      );
      await close(tester);
    },
  );

  for (final change in ['remove predecessor', 'correct latest']) {
    testWidgets('latest confirmation rejects $change and refreshes its impact', (
      tester,
    ) async {
      service = EntityRelationsService(
        db,
        clock: () => DateTime.utc(2026, 9, 24),
      );
      final id = await create();
      final middle = await service.recordChange(
        id: id,
        relationType: 'enemy',
        proof: 'enemy proof',
        reason: 'betrayal',
      );
      final latest = await service.recordChange(
        id: id,
        relationType: 'lover',
        proof: 'lover proof',
        reason: 'reconciled',
      );
      await tester.pumpWidget(
        relationHarness(
          db,
          SingleChildScrollView(
            child: RelationHistory(databasePath: 'test', relationId: id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('relation-history-toggle')));
      await tester.pumpAndSettle();
      final remove = find.byKey(ValueKey('remove-change-${latest.changeId}'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('will return to “Hostile · Active”'),
        findsOneWidget,
      );
      if (change == 'remove predecessor') {
        await service.removeChange(id: id, snapshotId: middle.changeId!);
      } else {
        await service.correctCurrentFields(
          id: id,
          proof: 'corrected latest proof',
        );
      }
      final expected = (await service.getRelationById(id))!;
      expect(expected.changeLogs.last.id, latest.changeId);
      expect(expected.updatedAt, latest.relation.updatedAt);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      final current = (await service.getRelationById(id))!;
      expect(
        current.changeLogs.map((s) => s.toJson()).toList(),
        expected.changeLogs.map((s) => s.toJson()).toList(),
      );
      expect(current.proof, expected.proof);
      expect(
        find.byKey(const ValueKey('relation-history-error')),
        findsOneWidget,
      );

      // A new confirmation must use the refreshed sequence and restoration state.
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          change == 'remove predecessor'
              ? 'will return to “Friendship · Active”'
              : 'will return to “Hostile · Active”',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(
        (await service.getRelationById(id))!.relationType,
        change == 'remove predecessor' ? 'friend' : 'enemy',
      );
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }
}
