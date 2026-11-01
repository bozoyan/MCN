// 职责: 验证关系表单的事务冲突保护、草稿保留及结束恢复操作。
// 关联文件:
//   lib/shared/widgets/relation/change_form.dart
//   lib/shared/widgets/relation_edit_dialog.dart
//   lib/shared/services/entity_relations_service.dart
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_select.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/entity_relations_service.dart';
import 'package:reveric/shared/widgets/relation/change_form.dart';
import 'package:reveric/shared/widgets/relation_edit_dialog.dart';
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
  Future<EntityRelation> create({String status = 'active'}) async {
    final id = await service.createRelation(
      sourceType: 'character',
      sourceId: 'a',
      targetType: 'character',
      targetId: 'b',
      relationType: 'friend',
      status: status,
      proof: 'original',
    );
    return (await service.getRelationById(id))!;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'new relation saves the default type without requiring a selection',
    (tester) async {
      var saved = false;
      await tester.pumpWidget(
        relationHarness(
          db,
          RelationChangeForm(
            databasePath: 'test',
            request: const RelationFormRequest(
              intent: RelationFormIntent.create,
              source: ('character', 'a'),
              target: ('character', 'b'),
            ),
            onSaved: () => saved = true,
          ),
          height: 570,
        ),
      );
      await tester.pumpAndSettle();
      final proof = find.byKey(const ValueKey('relation-proof'));
      await tester.ensureVisible(proof);
      await tester.enterText(proof, 'They are related.');
      final save = find.byKey(const ValueKey('relation-save'));
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      expect(find.text('Enter a value.'), findsNothing);
      expect((await service.getAllRelations()).single.relationType, 'family');
      await close(tester);
    },
  );

  testWidgets('changing endpoint type selects a valid default relation', (
    tester,
  ) async {
    await tester.pumpWidget(
      relationHarness(
        db,
        const RelationChangeForm(
          databasePath: 'test',
          request: RelationFormRequest(intent: RelationFormIntent.create),
        ),
        height: 570,
      ),
    );
    await tester.pumpAndSettle();
    final target = find.descendant(
      of: find.byKey(const ValueKey('relation-target-type')),
      matching: find.byType(RevericSelect<String>),
    );
    final type = find.descendant(
      of: find.byKey(const ValueKey('relation-type')),
      matching: find.byType(RevericSelect<String>),
    );
    for (final (entityType, relationType) in [
      ('faction', 'member'),
      ('creature', null),
      ('character', 'family'),
    ]) {
      final label = tester
          .widget<RevericSelect<String>>(target)
          .items
          .firstWhere((item) => item.value == entityType)
          .label;
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.widget<RevericSelect<String>>(type).value, relationType);
      final save = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('relation-save')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(save.onPressed, relationType == null ? isNull : isNotNull);
      expect(find.text('Enter a value.'), findsNothing);
    }
    await close(tester);
  });

  testWidgets('changing endpoint type keeps a relation that is still valid', (
    tester,
  ) async {
    await tester.pumpWidget(
      relationHarness(
        db,
        const RelationChangeForm(
          databasePath: 'test',
          request: RelationFormRequest(intent: RelationFormIntent.create),
        ),
        height: 570,
      ),
    );
    await tester.pumpAndSettle();
    final target = find.descendant(
      of: find.byKey(const ValueKey('relation-target-type')),
      matching: find.byType(RevericSelect<String>),
    );
    final type = find.descendant(
      of: find.byKey(const ValueKey('relation-type')),
      matching: find.byType(RevericSelect<String>),
    );
    Future<void> pick(Finder select, String value) async {
      final label = tester
          .widget<RevericSelect<String>>(select)
          .items
          .firstWhere((item) => item.value == value)
          .label;
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await pick(type, 'enemy');
    await pick(target, 'faction');
    expect(tester.widget<RevericSelect<String>>(type).value, 'enemy');
    await close(tester);
  });

  for (final mobile in [false, true]) {
    testWidgets(
      '${mobile ? 'mobile sheet' : 'desktop dialog'} keeps actions visible and preserves draft when space shrinks',
      (tester) async {
        tester.view.physicalSize = mobile
            ? const Size(390, 844)
            : const Size(1000, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final row = await create();
        final summary = (await service.getRelationSummaryById(row.id))!;
        await tester.pumpWidget(
          relationHarness(
            db,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => RelationEditDialog.showChange(
                  context,
                  databasePath: 'test',
                  relation: summary,
                  intent: RelationFormIntent.change,
                ),
                child: const Text('Open change form'),
              ),
            ),
            platform: mobile ? TargetPlatform.android : TargetPlatform.macOS,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open change form'));
        await tester.pumpAndSettle();
        final type = find.byKey(const ValueKey('relation-type'));
        final status = find.byKey(const ValueKey('relation-status'));
        final save = find.byKey(const ValueKey('relation-save'));
        if (!mobile) {
          expect(tester.getTopLeft(type).dy, tester.getTopLeft(status).dy);
          final surface = find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first;
          final contentHeight = tester.getSize(surface).height;
          tester.view.physicalSize = const Size(1000, 1800);
          await tester.pumpAndSettle();
          expect(tester.getSize(surface).height, contentHeight);
          expect(
            tester.getBottomRight(save).dx,
            tester
                .getBottomRight(find.byKey(const ValueKey('relation-proof')))
                .dx,
          );
        }
        final proof = find.byKey(const ValueKey('relation-proof'));
        final reason = find.byKey(const ValueKey('relation-reason'));
        await tester.ensureVisible(reason);
        await tester.enterText(reason, 'A new shared goal');
        await tester.ensureVisible(proof);
        await tester.enterText(proof, 'They agree to work together.');
        if (mobile) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        } else {
          tester.view.physicalSize = const Size(390, 560);
        }
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(status).dy,
          greaterThan(tester.getTopLeft(type).dy),
        );
        expect(find.text('A new shared goal'), findsOneWidget);
        expect(find.text('They agree to work together.'), findsOneWidget);
        expect(save.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(save);
        await tester.pumpAndSettle();
        final saved = (await service.getRelationById(row.id))!;
        expect(saved.changeLogs, hasLength(2));
        expect(saved.changeLogs.last.reason, 'A new shared goal');
        expect(saved.proof, 'They agree to work together.');
        expect(find.byKey(const ValueKey('relation-save')), findsNothing);
        expect(tester.takeException(), isNull);
        await close(tester);
      },
    );
  }

  testWidgets(
    'same-snapshot correction conflict preserves draft and can refresh before confirming',
    (tester) async {
      final row = await create();
      var saved = false;
      await tester.pumpWidget(
        relationHarness(
          db,
          RelationChangeForm(
            databasePath: 'test',
            request: RelationFormRequest(
              intent: RelationFormIntent.correct,
              relation: row,
            ),
            onSaved: () => saved = true,
          ),
          width: 320,
          height: 570,
        ),
      );
      await tester.pumpAndSettle();
      final proof = find.byKey(const ValueKey('relation-proof'));
      await tester.ensureVisible(proof);
      await tester.enterText(proof, 'my unsaved draft');
      await service.correctCurrentFields(
        id: row.id,
        proof: 'external correction',
      );
      expect(
        (await service.getRelationById(row.id))!.changeLogs.single.id,
        row.changeLogs.single.id,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('relation-save')));
      await tester.tap(find.byKey(const ValueKey('relation-save')));
      await tester.pumpAndSettle();
      expect(saved, isFalse);
      expect(find.text('my unsaved draft'), findsOneWidget);
      expect(find.byKey(const ValueKey('relation-form-error')), findsOneWidget);
      expect(
        (await service.getRelationById(row.id))!.proof,
        'external correction',
      );
      final refresh = find.text('Refresh current state, keep draft');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.text('my unsaved draft'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('relation-save')));
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      expect(
        (await service.getRelationById(row.id))!.proof,
        'my unsaved draft',
      );
      expect((await service.getRelationById(row.id))!.changeLogs, hasLength(1));
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  for (final intent in [RelationFormIntent.end, RelationFormIntent.restore]) {
    testWidgets('$intent records a real event with required proof and reason', (
      tester,
    ) async {
      final row = await create(
        status: intent == RelationFormIntent.end ? 'active' : 'ended',
      );
      var saved = false;
      await tester.pumpWidget(
        relationHarness(
          db,
          RelationChangeForm(
            databasePath: 'test',
            request: RelationFormRequest(intent: intent, relation: row),
            onSaved: () => saved = true,
          ),
          width: 320,
          height: 570,
        ),
      );
      await tester.pumpAndSettle();
      final reason = find.byKey(const ValueKey('relation-reason'));
      final proof = find.byKey(const ValueKey('relation-proof'));
      await tester.ensureVisible(reason);
      await tester.enterText(reason, 'a real change');
      await tester.ensureVisible(proof);
      await tester.enterText(proof, 'new evidence');
      await tester.ensureVisible(find.byKey(const ValueKey('relation-save')));
      await tester.tap(find.byKey(const ValueKey('relation-save')));
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      final result = (await service.getRelationById(row.id))!;
      expect(
        result.status,
        intent == RelationFormIntent.end ? 'ended' : 'active',
      );
      expect(result.relationType, 'friend');
      expect(result.changeLogs, hasLength(2));
      expect(result.changeLogs.first.proof, 'original');
      expect(result.changeLogs.last.proof, 'new evidence');
      expect(result.changeLogs.last.reason, 'a real change');
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }
}
