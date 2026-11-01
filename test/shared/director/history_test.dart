// 职责: 验证导演编辑器通过回调保存、处理并发编辑并保持可撤销恢复语义。
// 关联文件:
//   lib/shared/services/director/session.dart
//   lib/shared/models/director/persistence.dart
import 'dart:async';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/persistence.dart';
import 'package:reveric/shared/services/director/session.dart';

void main() {
  test(
    'an existing camera error cannot mask a new error in an edited actor dependency',
    () {
      final s = DirectorSession(DirectorDocument.blank('Dependencies'));
      addTearDown(s.dispose);
      s.history.addObject('actor.male.v1', 'Actor');
      final actor = s.history.document.objects.single['id'];
      final dependent = DirectorDocument.newCamera(
        'Valid dependent',
        [0, 1, 2],
        [0, 1, 0],
        35,
      );
      dependent['camera_target'] = {
        'type': 'object',
        'object_id': actor,
        'offset': [0, 1, 0],
      };
      s.restore(
        s.history.document.mutate((j) {
          j['cameras'][0]['position'] = [0, 1.6, 0];
          j['cameras'].add(dependent);
        }),
      );
      final before = s.history.document, undo = s.history.undoCount;
      expect(
        () => s.history.previewProperty(actor, 'position', [0, 0, 2], 0),
        throwsA(
          isA<DocumentError>().having(
            (e) => e.reason,
            'reason',
            'zero_direction',
          ),
        ),
      );
      expect(s.history.document, same(before));
      expect(s.history.preview, isNull);
      expect(s.history.undoCount, undo);
      s.history.setValue(actor, 'position', [1, 0, 0], 0);
      expect(sampleCamera(s.history.document, dependent['id'], 0)['target'], [
        1,
        1,
        0,
      ]);
      expect(
        () => sampleDocument(s.history.document, 0),
        throwsA(isA<DocumentError>()),
      );
    },
  );

  test(
    'save acknowledges only submitted content and coalesces repeated clicks',
    () async {
      final pending = Completer<DirectorRevision?>();
      var calls = 0;
      late DirectorDocument submitted;
      final session = DirectorSession(
        DirectorDocument.blank('Initial'),
        onSave: (doc) {
          calls++;
          submitted = doc;
          return pending.future;
        },
      );
      addTearDown(session.dispose);
      session.history.execute((j) => j['title'] = 'Saved');
      final save = session.save();
      final repeated = session.save();
      session.history.execute((j) => j['title'] = 'Still editing');
      expect(calls, 1);
      pending.complete(DirectorRevision(id: 'r1', savedAt: DateTime(2026)));
      await Future.wait([save, repeated]);
      expect(submitted.title, 'Saved');
      expect(session.history.document.title, 'Still editing');
      expect(session.history.dirty, isTrue);
      session.history.undo();
      expect(session.history.dirty, isFalse);
    },
  );

  test('failed save keeps changes and can be retried', () async {
    var fail = true;
    final session = DirectorSession(
      DirectorDocument.blank('Initial'),
      onSave: (doc) async {
        if (fail) {
          throw StateError('offline');
        }
        return null;
      },
    );
    addTearDown(session.dispose);
    session.history.execute((j) => j['title'] = 'Edited');
    await expectLater(session.save(), throwsStateError);
    expect(session.history.dirty, isTrue);
    expect(session.saving, isFalse);
    fail = false;
    await session.save();
    expect(session.history.dirty, isFalse);
  });

  test(
    'change callbacks ignore previews, selection, playback and save acknowledgements',
    () async {
      final changes = <DirectorDocument>[];
      final session = DirectorSession(
        DirectorDocument.blank('Initial'),
        onChanged: changes.add,
        onSave: (_) async => null,
      );
      addTearDown(session.dispose);
      session.history.previewEdit((j) => j['title'] = 'Preview');
      session.history.cancelGesture();
      session.select(session.viewCameraId);
      session.seek(1);
      expect(changes, isEmpty);
      session.history.execute((j) => j['title'] = 'Edited');
      await session.save();
      session.history.undo();
      session.history.redo();
      expect(changes.map((d) => d.title), ['Edited', 'Initial', 'Edited']);
    },
  );

  test(
    'restore is undoable and keeps the receiving document identity',
    () async {
      final original = DirectorDocument.blank('Initial');
      final imported = DirectorDocument.blank('Imported');
      final session = DirectorSession(original);
      addTearDown(session.dispose);
      session.restore(imported);
      expect(session.history.document.id, original.id);
      expect(session.history.document.title, 'Imported');
      session.history.undo();
      expect(
        session.history.document.businessContent,
        original.businessContent,
      );
    },
  );

  test('late save cannot mark a different loaded document as saved', () async {
    final pending = Completer<DirectorRevision?>();
    final session = DirectorSession(
      DirectorDocument.blank('First'),
      onSave: (_) => pending.future,
    );
    addTearDown(session.dispose);
    final saving = session.save();
    session.replace(DirectorDocument.blank('Second'), saved: true);
    pending.complete(DirectorRevision(id: 'first', savedAt: DateTime(2026)));
    await saving;
    expect(session.history.document.title, 'Second');
    expect(session.savedRevisionId, isNull);
    expect(session.history.dirty, isFalse);
  });
}
