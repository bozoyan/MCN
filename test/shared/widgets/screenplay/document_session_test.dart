// 职责: 验证保存期间的新输入与同期外场修改都能保留，冲突草稿必须显式重读。
// 关联文件:
//   lib/shared/widgets/screenplay/document_session.dart
//   lib/shared/services/document_save_coordinator.dart
//   lib/shared/services/screenplay_edit_orchestrator.dart
import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/screenplay_document.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/widgets/screenplay/document_session.dart';
import 'package:reveric/shared/utils/short_entity_id.dart';

class _DelayedService extends ScreenplayService {
  _DelayedService(super.database, {super.idBuilder});
  final entered = Completer<void>();
  final release = Completer<void>();
  var first = true;
  @override
  Future<
    ({
      ScreenplayDocument document,
      Map<String, String> sceneIds,
      Map<String, String> elementIds,
    })
  >
  applyDocument(
    ScreenplayDocument baseline,
    ScreenplayDocument target,
    Set<String> dirty,
  ) async {
    if (first) {
      first = false;
      entered.complete();
      await release.future;
    }
    return super.applyDocument(baseline, target, dirty);
  }
}

void main() {
  test('collided draft IDs remap pending typing and saved undo/redo', () async {
    final db = NovelContentDatabase.forTest(NativeDatabase.memory());
    final app = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      await app.close();
    });
    final regular = ScreenplayService(db);
    final initial = await regular.createInitialStructure();
    final root = (await db.screenplayDao.getRoot())!;
    final a = await regular.createScene(
      screenplayId: root.id,
      episodeId: initial.episodeId,
    );
    await regular.writeElements(
      sceneId: a,
      elements: const [
        ScreenplayElement(
          type: ScreenplayElementType.action,
          text: 'beforeafter',
        ),
      ],
    );
    final counts = <ShortEntityIdType, int>{};
    final service = _DelayedService(
      db,
      idBuilder: (type) {
        final count = counts.update(type, (n) => n + 1, ifAbsent: () => 20);
        return '${shortEntityIdPrefixes[type]}_${count.toString().padLeft(6, '0')}';
      },
    );
    final overlay = WorkingOverlayService(
      db,
      NovelContentService(db),
      novelActionsService: NovelActionsService(app),
    );
    final baseline = await regular.readDocument(initial.episodeId);
    final session = ScreenplayDocumentSession(
      baseline,
      database: db,
      service: service,
      overlay: overlay,
    );
    addTearDown(session.dispose);
    final draft = baseline.split(
      ScreenplayPosition(baseline.sceneElements(a).last.id!, 6),
    );
    final draftScene = draft.newSceneIds.single;
    await db
        .into(db.screenplayScenes)
        .insert(
          ScreenplayScenesCompanion.insert(
            id: draftScene,
            screenplayId: root.id,
            episodeId: initial.episodeId,
            synopsis: const Value('unrelated archived scene'),
            deletedAt: Value(DateTime(2020)),
          ),
        );
    for (final id in draft.newElementIds) {
      await db
          .into(db.screenplaySceneElements)
          .insert(
            ScreenplaySceneElementsCompanion.insert(
              id: id,
              episodeId: initial.episodeId,
              sceneId: draftScene,
              sortOrder: -100,
              type: 'action',
              textContent: const Value('unrelated archived element'),
              deletedAt: Value(DateTime(2020)),
            ),
          );
    }
    final c = session.controller;
    c.editDocument(draft);
    final saving = session.flush();
    await service.entered.future;
    c.edit([
      for (final e in c.value)
        e.sceneId == draftScene && !e.isHeading
            ? e.copyWith(text: 'later typing')
            : e,
    ]);
    service.release.complete();
    await saving;
    final saved = await regular.readDocument(initial.episodeId);
    expect(saved.sceneOrder, [a, 'scn_000020']);
    expect(saved.sceneElements('scn_000020').last.text, 'later typing');
    expect(saved.sceneElements('scn_000020').map((e) => e.id).toSet(), {
      'elm_000020',
      'elm_000021',
    });
    expect(c.screenplay!.newSceneIds, isEmpty);
    expect(c.screenplay!.newElementIds, isEmpty);
    expect(session.queue.isDirty, isFalse);
    expect(c.canUndo, isTrue);
    c.undo();
    await session.flush();
    expect(
      (await regular.readDocument(initial.episodeId)).sceneOrder,
      saved.sceneOrder,
    );
    c.undo();
    await session.flush();
    expect((await regular.readDocument(initial.episodeId)).sceneOrder, [a]);
    c.redo();
    await session.flush();
    expect(
      (await regular.readDocument(initial.episodeId)).sceneOrder,
      saved.sceneOrder,
    );
    c.redo();
    await session.flush();
    expect(
      (await regular.readDocument(
        initial.episodeId,
      )).sceneElements('scn_000020').last.text,
      'later typing',
    );
    final archived = await (db.select(
      db.screenplayScenes,
    )..where((t) => t.id.equals(draftScene))).getSingle();
    expect(archived.synopsis, 'unrelated archived scene');
    expect(archived.deletedAt, DateTime(2020));
    expect(counts[ShortEntityIdType.screenplayScene], 20);
    expect(counts[ShortEntityIdType.screenplayElement], 21);
  });

  test(
    'serial save rebases untouched external scenes and retains later input',
    () async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      final app = AppDatabase.forTest(NativeDatabase.memory());
      final service = _DelayedService(db);
      final regular = ScreenplayService(db);
      final initial = await service.createInitialStructure();
      final root = (await db.screenplayDao.getRoot())!;
      final a = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
      );
      final b = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
      );
      for (final id in [a, b]) {
        await service.writeElements(
          sceneId: id,
          elements: const [
            ScreenplayElement(
              type: ScreenplayElementType.action,
              text: 'original',
            ),
          ],
        );
      }
      final overlay = WorkingOverlayService(
        db,
        NovelContentService(db),
        novelActionsService: NovelActionsService(app),
      );
      final session = ScreenplayDocumentSession(
        await service.readDocument(initial.episodeId),
        database: db,
        service: service,
        overlay: overlay,
      );
      final c = session.controller;
      await regular.writeElements(
        sceneId: b,
        elements: [
          c.screenplay!.sceneElements(b).last.copyWith(text: 'external B'),
        ],
      );
      c.edit([
        for (final e in c.value)
          e.sceneId == a && !e.isHeading
              ? e.copyWith(text: 'first local A')
              : e,
      ]);
      expect(session.lastSavedAt, isNull);
      final saving = session.flush();
      await service.entered.future;
      expect(session.lastSavedAt, isNull);
      c.edit([
        for (final e in c.value)
          e.sceneId == a && !e.isHeading
              ? e.copyWith(text: 'second local A')
              : e,
      ]);
      service.release.complete();
      await saving;
      expect(session.lastSavedAt, isNotNull);
      final savedAt = session.lastSavedAt;
      expect(
        (await db.screenplayDao.getElementRows(a)).single.textContent,
        'second local A',
      );
      expect(
        (await db.screenplayDao.getElementRows(b)).single.textContent,
        'external B',
      );
      expect(c.screenplay!.sceneElements(a).last.text, 'second local A');
      expect(c.screenplay!.sceneElements(b).last.text, 'external B');
      expect(session.queue.isDirty, isFalse);
      await regular.writeElements(
        sceneId: a,
        elements: [
          c.screenplay!.sceneElements(a).last.copyWith(text: 'another writer'),
        ],
      );
      c.edit([
        for (final e in c.value)
          e.sceneId == a && !e.isHeading
              ? e.copyWith(text: 'conflicting local draft')
              : e,
      ]);
      await expectLater(session.flush(), throwsException);
      expect(session.lastSavedAt, savedAt);
      expect(
        c.screenplay!.sceneElements(a).last.text,
        'conflicting local draft',
      );
      await session.reload();
      expect(c.screenplay!.sceneElements(a).last.text, 'another writer');
      expect(session.queue.isDirty, isFalse);
      session.dispose();
      await db.close();
      await app.close();
    },
  );
}
