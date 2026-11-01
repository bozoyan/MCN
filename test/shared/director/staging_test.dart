// 职责: 验证导演调度即时保存、会话和 AI 回合快照，以及交错编辑保持独立字段。
// 关联文件:
//   lib/shared/services/screenplay/staging.dart
//   lib/shared/services/screenplay/staging_edit.dart
//   lib/shared/database/novel_content_daos/screenplay_dao.dart
import 'dart:async';
import '../../fixtures/director/animated.dart';
import 'dart:math' as math;
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/screenplay/staging.dart';
import 'package:reveric/shared/services/screenplay/staging_edit.dart';
import 'package:reveric/shared/services/screenplay_service.dart';

void main() {
  late NovelContentDatabase db;
  late StagingEditService service;
  final bindings = <VideoStagingBinding>[];
  Future<VideoStagingBinding> open(String id) async {
    final binding = VideoStagingBinding(db.screenplayDao, id);
    await binding.load(camera: 'Camera');
    bindings.add(binding);
    return binding;
  }

  Future<List<RevisionRow>> revisions(String id) =>
      (db.select(db.revisions)..where((t) => t.entityId.equals(id))).get();
  setUp(() async {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = StagingEditService(db);
    await ScreenplayService(db).createInitialStructure();
    await db.screenplayDao.createStaging('a', 'Director 1');
    await db.screenplayDao.createStaging('b', 'Director 2');
  });
  tearDown(() async {
    for (final binding in bindings) {
      await binding.flush();
      binding.dispose();
      binding.session.dispose();
    }
    bindings.clear();
    await db.close();
  });

  test(
    'multiple invalid actors and cameras repair independently, persist each step and reopen',
    () async {
      final binding = await open('a');
      final h = binding.session.history;
      h.addObject('actor.male.v1', 'A');
      h.addObject('actor.female.v1', 'B');
      final healthy = h.document;
      final source = healthy.mutate((j) {
        for (final actor in j['objects']) {
          actor['pose']['root_offset_y'] = 50;
        }
        j['cameras'][0]['position'] = [0, 1.6, 0];
        j['cameras'].add(
          DirectorDocument.newCamera('B', [0, 1.6, 0], [0, 1, 0], 35),
        );
      });
      binding.session.restore(source);
      binding.session.seek(12);
      await binding.flush();
      final a = healthy.objects.first['id'], b = healthy.objects.last['id'];
      h.setValue(a, 'pose', healthy.objects.first['pose'], 12);
      await binding.flush();
      expect(
        (await service.require(
          'a',
        )).document!['objects'][0]['pose']['root_offset_y'],
        0,
      );
      final camera = h.document.cameras.first['id'];
      h.setValue(camera, 'position', [0, 1.6, 2], 12);
      await binding.flush();
      final before = h.document, undo = h.undoCount;
      expect(
        () => h.previewProperty(a, 'pose', {
          ...healthy.objects.first['pose'] as Json,
          'root_offset_y': 50,
        }, 12),
        throwsA(isA<DocumentError>()),
      );
      expect(h.document, same(before));
      expect(h.preview, isNull);
      expect(h.undoCount, undo);
      // Changing an already-invalid target without resolving it must also fail.
      expect(
        () => h.setValue(b, 'scale', [2, 2, 2], 12),
        throwsA(isA<DocumentError>()),
      );
      expect(h.document, same(before));
      h.setValue(b, 'pose', healthy.objects.last['pose'], 12);
      h.setValue(h.document.cameras.last['id'], 'position', [0, 1.6, 2], 12);
      await binding.flush();
      binding.dispose();
      final reopened = await open('a');
      final sample = sampleDocument(reopened.session.history.document, 12);
      expect(
        sample.objects.every((o) => o['pose']['root_offset_y'] == 0),
        isTrue,
      );
      expect(sample.cameras.values.every((c) => c['position'][2] == 2), isTrue);
    },
  );

  test(
    'AI may persist dynamic diagnostics and an open editor can repair and resave',
    () async {
      final binding = await open('a');
      final h = binding.session.history;
      final camera = h.document.cameras.single['id'];
      h.execute((j) => j['title'] = 'Persisted');
      await binding.flush();
      await service.save(
        'a',
        turnId: 'dynamic-error',
        edits: [
          {
            'op': 'write',
            'collection': 'cameras',
            'id': camera,
            'data': {
              'position': [0, 1.6, 0],
            },
          },
        ],
      );
      await binding.flush();
      expect(h.document.cameras.single['position'], [0, 1.6, 0]);
      final stored = DirectorDocument.fromJson(
        (await service.require('a')).document!,
      );
      expect(
        () => sampleDocument(stored, 0),
        throwsA(
          isA<DocumentError>().having(
            (e) => e.reason,
            'reason',
            'parallel_reference_up',
          ),
        ),
      );
      h.setValue(camera, 'position', [0, 1.6, 2], 0);
      await binding.flush();
      binding.dispose();
      final reopened = await open('a');
      expect(
        sampleDocument(
          reopened.session.history.document,
          0,
        ).cameras[camera]!['position'],
        [0, 1.6, 2],
      );
    },
  );

  test(
    'earlier cuts and moved cuts persist through automatic save and reopen',
    () async {
      final binding = await open('a');
      final h = binding.session.history;
      final camera = h.document.cameras.single['id'] as String;
      h.setCut(48, camera);
      await binding.flush();
      h.setCut(24, camera);
      await binding.flush();
      expect(binding.session.error, isNull);
      expect(h.document.cuts.map((c) => c['frame']), [24, 48]);
      final moved = h.document.cuts.last['id'] as String;
      h.editCut(moved, 12, camera);
      await binding.flush();
      expect(h.document.cuts.map((c) => c['frame']), [12, 24]);
      final before = h.document.businessContent;
      expect(() => h.editCut(moved, 24, camera), throwsA(isA<DocumentError>()));
      expect(h.document.businessContent, before);
      binding.dispose();
      final reopened = await open('a');
      expect(reopened.session.history.document.cuts.map((c) => c['frame']), [
        12,
        24,
      ]);
    },
  );

  test(
    'queued cut frame edits preserve concurrent AI camera fields by ID',
    () async {
      final binding = await open('a');
      final h = binding.session.history;
      final first = h.document.cameras.single['id'] as String;
      final second = DirectorDocument.newCamera(
        'Second',
        [3, 2, 5],
        [0, 1, 0],
        50,
      );
      h.execute((j) => j['cameras'].add(second));
      h.setCut(48, first);
      h.setCut(24, first);
      await binding.flush();
      final cut = h.document.cuts.last['id'] as String;
      final gate = Completer<void>();
      final blocked = db.screenplayDao.serializeStaging('a', () => gate.future);
      final ai = service.save(
        'a',
        turnId: 'cut-camera',
        edits: [
          {
            'op': 'write',
            'collection': 'camera_cuts',
            'id': cut,
            'data': {'camera_id': second['id']},
          },
        ],
      );
      h.editCut(cut, 12, first);
      gate.complete();
      await blocked;
      await ai;
      await binding.flush();
      expect(binding.session.error, isNull);
      final saved = DirectorDocument.fromJson(
        (await service.require('a')).document!,
      );
      expect(saved.cuts.map((c) => c['frame']), [12, 24]);
      expect(saved.cuts.first, containsPair('camera_id', second['id']));
      expect(h.document.businessContent, saved.businessContent);
      binding.dispose();
      final reopened = await open('a');
      expect(
        reopened.session.history.document.businessContent,
        saved.businessContent,
      );
    },
  );

  test(
    'new animation survives persisted reopen and history restore with identical samples',
    () async {
      final expected = animatedDirectorDocument();
      final row = await service.create(
        expected.title,
        document: expected.toJson(),
      );
      final first = await open(row.id);
      for (final frame in [0, 12, 24, 47, 48, 60, 95, 96, 120]) {
        final actual = sampleDocument(first.session.history.document, frame);
        final source = sampleDocument(expected, frame);
        expect(actual.objects, source.objects);
        expect(actual.cameras, source.cameras);
        expect(actual.lighting, source.lighting);
        expect(actual.cameraId, source.cameraId);
      }
      first.session.history.execute((j) {
        j['camera_cuts'] = [];
        j['motion_paths'] = [];
        j['tracks'] = [];
        j['title'] = 'Changed';
      });
      await first.flush();
      final snapshot = (await first.session.historyEntries()).last;
      await first.session.restoreHistory(snapshot);
      await first.flush();
      first.dispose();
      final reopened = await open(row.id);
      expect(
        reopened.session.history.document.businessContent,
        expected.businessContent,
      );
      expect(
        (await service.require(row.id)).document!['motion_paths'],
        expected.toJson()['motion_paths'],
      );
      final sampled = sampleDocument(reopened.session.history.document, 48);
      expect(sampled.cameraId, expected.cameras.last['id']);
      expect(
        sampled.objects.single['pose']['root_offset_y'],
        closeTo(0.3, 1e-10),
      );
    },
  );
  test(
    'AI saves airborne transforms and tracks, then UI reopens the same animation',
    () async {
      final binding = await open('a');
      binding.session.history.addObject('actor.male.v1', 'Actor');
      await binding.flush();
      final before = binding.session.history.document;
      final actor = before.objects.single['id'];
      final json = before.toJson();
      json['objects'][0]['position'] = [0, 0.9, 1];
      json['objects'][0]['rotation'] = [-0.34, 0, 0, 0.94];
      json['tracks'] = [
        {
          'id': '40000000-0000-4000-8000-000000000001',
          'target_id': actor,
          'property': 'position',
          'keys': [
            {
              'frame': 0,
              'value': [0, 0.9, 1],
              'easing': 'linear',
            },
            {
              'frame': 24,
              'value': [0, 3, 2],
              'easing': 'linear',
            },
            {
              'frame': 48,
              'value': [0, 0.2, 4],
              'easing': 'hold',
            },
          ],
        },
        {
          'id': '40000000-0000-4000-8000-000000000002',
          'target_id': actor,
          'property': 'rotation',
          'keys': [
            {
              'frame': 0,
              'value': [0, 0, 0, 1],
              'easing': 'linear',
            },
            {
              'frame': 48,
              'value': [-0.707, 0, 0, 0.707],
              'easing': 'hold',
            },
          ],
        },
      ];
      await service.save('a', turnId: 'airborne', document: json);
      await binding.flush();
      final stored = (await service.require('a')).document!;
      // 直接检查 DB 返回值，避免再次构造 DirectorDocument 后才归一化掩盖写入问题。
      expect(
        stored['objects'][0]['rotation'][0],
        closeTo(-0.3401360816544381, 1e-14),
      );
      expect(
        stored['tracks'][1]['keys'][1]['value'][0],
        closeTo(-math.sqrt(0.5), 1e-14),
      );
      final snapshotCount = (await revisions('a')).length;
      final retried = await service.save(
        'a',
        turnId: 'rounded-retry',
        document: json,
      );
      expect(retried.document, stored);
      expect(await revisions('a'), hasLength(snapshotCount));
      final saved = DirectorDocument.fromJson(stored);
      expect(
        binding.session.history.document.businessContent,
        saved.businessContent,
      );
      expect(sampleDocument(saved, 24).objects.single['position'], [0, 3, 2]);
      binding.session.history.undo();
      await binding.flush();
      expect(
        binding.session.history.document.businessContent,
        before.businessContent,
      );
      binding.session.history.redo();
      await binding.flush();
      binding.dispose();
      final reopened = await open('a');
      for (final frame in [48, 12, 24, 0, 120]) {
        expect(
          sampleDocument(reopened.session.history.document, frame).objects,
          sampleDocument(saved, frame).objects,
        );
      }
    },
  );
  test(
    'opening and no-op edits do not create snapshots or write documents',
    () async {
      final binding = await open('a');
      binding.session.history.execute((j) => j['title'] = 'Director 1');
      await binding.flush();
      expect((await db.screenplayDao.getStaging('a'))!.document, isNull);
      expect(await revisions('a'), isEmpty);
    },
  );

  test(
    'first edit snapshots blank; subsequent edits save without closing',
    () async {
      final binding = await open('a');
      binding.session.history.execute((j) => j['title'] = 'A1');
      await binding.flush();
      expect((await db.screenplayDao.getStaging('a'))!.title, 'A1');
      binding.session.history.execute((j) => j['title'] = 'A2');
      await binding.flush();
      final snapshots = await revisions('a');
      expect(snapshots, hasLength(1));
      expect(snapshots.single.version, 0);
      expect(snapshots.single.value['title'], 'Director 1');
      expect((await db.screenplayDao.getStaging('a'))!.title, 'A2');
      binding.dispose();
      final reopened = await open('a');
      expect(reopened.session.history.document.title, 'A2');
      reopened.session.history.execute((j) => j['title'] = 'A3');
      await reopened.flush();
      expect((await revisions('a')).map((r) => r.value['title']), [
        'Director 1',
        'A2',
      ]);
      expect(await revisions('b'), isEmpty);
    },
  );

  test(
    'AI snapshots once per turn and staging, including interleaved turns',
    () async {
      final a = await service.create('A'), b = await service.create('B');
      await service.save(a.id, turnId: 'one', title: 'A1');
      await service.save(b.id, turnId: 'one', title: 'B1');
      await service.save(a.id, turnId: 'one', title: 'A2');
      expect((await revisions(a.id)).single.value['title'], 'A');
      expect((await revisions(b.id)).single.value['title'], 'B');
      await service.save(a.id, turnId: 'two', title: 'A3');
      await service.save(a.id, turnId: 'one', title: 'A4');
      expect((await revisions(a.id)).map((r) => r.value['title']), ['A', 'A2']);
    },
  );

  test(
    'no-op and invalid AI edits do not consume the turn checkpoint',
    () async {
      final row = await service.create('A');
      await service.save(row.id, turnId: 'one', title: 'A');
      await expectLater(
        service.save(
          row.id,
          turnId: 'one',
          edits: [
            {
              'op': 'write',
              'collection': 'objects',
              'id': 'missing',
              'data': {'name': 'X'},
            },
          ],
        ),
        throwsA(isA<DocumentError>()),
      );
      expect(await revisions(row.id), isEmpty);
      await service.save(row.id, turnId: 'one', title: 'A1');
      expect((await revisions(row.id)).single.value['title'], 'A');
    },
  );

  test(
    'queued UI, AI and UI edits preserve fields; last same-field edit wins',
    () async {
      final row = await service.create('A');
      final binding = await open(row.id);
      final history = binding.session.history;
      final camera = history.document.activeCameras.single['id'];
      final gate = Completer<void>();
      final blocked = db.screenplayDao.serializeStaging(
        row.id,
        () => gate.future,
      );
      history.execute((j) => j['title'] = 'Local 1');
      final ai = service.save(
        row.id,
        turnId: 'one',
        title: 'AI',
        edits: [
          {
            'op': 'write',
            'collection': 'cameras',
            'id': camera,
            'data': {'focal_length_mm': 50},
          },
        ],
      );
      history.execute((j) => j['title'] = 'Local 2');
      gate.complete();
      await blocked;
      await ai;
      await binding.flush();
      final stored = (await service.require(row.id)).document!;
      expect(stored['title'], 'Local 2');
      expect(stored['cameras'][0]['focal_length_mm'], 50);
      expect(history.document.title, 'Local 2');
      expect(history.document.activeCameras.single['focal_length_mm'], 50);
      expect(await revisions(row.id), hasLength(2));
      history.undo();
      await binding.flush();
      expect((await service.require(row.id)).title, 'Local 2');
      expect(
        (await service.require(
          row.id,
        )).document!['cameras'][0]['focal_length_mm'],
        35,
      );
      expect(await revisions(row.id), hasLength(2));
    },
  );

  test(
    'AI can reference a manually added actor and remains one valid undo step',
    () async {
      final row = await service.create('A');
      final binding = await open(row.id);
      final history = binding.session.history;
      history.addObject('actor.male.v1', 'Actor');
      await binding.flush();
      final actorId = history.document.objects.single['id'];
      await service.save(
        row.id,
        turnId: 'one',
        edits: [
          {
            'op': 'create',
            'collection': 'tracks',
            'id': '28d12c44-6bda-4391-8d0e-78f6a6d132f4',
            'data': {
              'target_id': actorId,
              'property': 'pose',
              'keys': [
                {
                  'frame': 24,
                  'value': history.document.objects.single['pose'],
                  'easing': 'linear',
                },
              ],
            },
          },
        ],
      );
      expect(history.document.tracks, hasLength(1));
      history.undo();
      await binding.flush();
      expect(history.document.tracks, isEmpty);
      expect(history.document.objects, hasLength(1));
      history.undo();
      await binding.flush();
      expect(history.document.objects, isEmpty);
      expect((await service.require(row.id)).document!['objects'], isEmpty);
    },
  );

  test(
    'AI delete commits, invalid pending reference reports locally, and later edits save',
    () async {
      final row = await service.create('A');
      final binding = await open(row.id);
      final history = binding.session.history;
      history.addObject('actor.male.v1', 'Actor');
      await binding.flush();
      final actorId = history.document.objects.single['id'];
      final gate = Completer<void>();
      final blocked = db.screenplayDao.serializeStaging(
        row.id,
        () => gate.future,
      );
      final ai = service.save(
        row.id,
        turnId: 'delete',
        edits: [
          {'op': 'remove', 'collection': 'objects', 'id': actorId},
        ],
      );
      history.toggleKey(actorId, 'pose', 24);
      gate.complete();
      await blocked;
      await ai;
      await binding.flush();
      expect(binding.session.error, isNotNull);
      expect(history.document.tracks, isEmpty);
      expect(history.document.objects, isEmpty);
      history.execute((j) => j['title'] = 'Still editable');
      await binding.flush();
      expect((await service.require(row.id)).title, 'Still editable');
      expect((await service.require(row.id)).document!['tracks'], isEmpty);
    },
  );

  test(
    'save acknowledges the final drained document when another edit arrives while saving',
    () async {
      final binding = await open('a');
      final gate = Completer<void>();
      final blocked = db.screenplayDao.serializeStaging('a', () => gate.future);
      binding.session.history.execute((j) => j['title'] = 'A');
      final save = binding.session.save();
      binding.session.history.execute((j) => j['title'] = 'B');
      gate.complete();
      await blocked;
      await save;
      await binding.flush();
      expect((await db.screenplayDao.getStaging('a'))!.title, 'B');
      expect(binding.session.history.document.title, 'B');
      expect(binding.session.history.dirty, isFalse);
    },
  );

  test(
    'gesture previews do not save, committing saves and restore autosaves',
    () async {
      final binding = await open('a');
      final history = binding.session.history;
      history.previewEdit((j) => j['title'] = 'Preview');
      await binding.flush();
      expect(await revisions('a'), isEmpty);
      history.commitGesture();
      await binding.flush();
      expect((await db.screenplayDao.getStaging('a'))!.title, 'Preview');
      final original = (await binding.session.historyEntries()).last;
      await binding.session.restoreHistory(original);
      await binding.flush();
      expect((await db.screenplayDao.getStaging('a'))!.title, 'Director 1');
      expect(await revisions('a'), hasLength(1));
    },
  );

  test('thumbnail rendering never delays automatic database writes', () async {
    final binding = await open('a');
    binding.updatePreview = (_) => Completer<void>().future;
    binding.session.history.execute((j) => j['title'] = 'Saved');
    await binding.flush().timeout(const Duration(seconds: 2));
    expect((await db.screenplayDao.getStaging('a'))!.title, 'Saved');
  });
}
