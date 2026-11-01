// 职责: 验证路径与运镜 Bake 的分通道误差、区间外保持及原子撤销。
// 关联文件:
//   lib/shared/services/director/bake.dart
//   lib/shared/services/director/commands.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/models/director/sampling.dart';
import 'package:reveric/shared/services/director/commands.dart';
import 'package:reveric/shared/services/director/bake.dart';
import 'package:uuid/uuid.dart';
import 'contract_test.dart' show actor;

void main() {
  test(
    'late single pose key toggles without changing the base and is undoable',
    () {
      final history = CommandHistory(
        DirectorDocument.blank(
          'Scene',
        ).mutate((j) => j['objects'].add(actor())),
      );
      final id = history.document.objects.single['id'];
      final base = history.document.objects.single['pose'];
      history.toggleKey(id, 'pose', 24);
      expect(history.document.tracks.single['keys'], hasLength(1));
      history.toggleKey(id, 'pose', 48);
      expect(history.document.tracks.single['keys'], hasLength(2));
      history.toggleKey(id, 'pose', 24);
      expect(history.document.tracks.single['keys'], hasLength(1));
      history.toggleKey(id, 'pose', 48);
      expect(history.document.tracks, isEmpty);
      expect(history.document.objects.single['pose'], base);
      history.undo();
      expect(history.document.tracks.single['keys'], hasLength(1));
    },
  );
  test('path bake keeps output and removes its control in one undo step', () {
    final id = const Uuid().v4();
    final d = DirectorDocument.blank('Scene').mutate((j) {
      final a = actor();
      j['objects'].add(a);
      j['motion_paths'].add({
        'id': id,
        'target_id': a['id'],
        'kind': 'line',
        'start_frame': 24,
        'end_frame': 72,
        'easing': 'smoothstep',
        'orient_to_path': false,
        'geometry': {
          'start': [0, 0, 0],
          'end': [2, 0, 0],
        },
      });
    });
    final history = CommandHistory(d);
    history.bake('motion_paths', id);
    expect(history.document.paths, isEmpty);
    expect(history.undoCount, 1);
    expect(
      (history.document.tracks.single['keys'] as List).length,
      lessThan(49),
    );
    for (var f = 0; f <= 120; f++) {
      expect(
        bakeError(
          'position',
          sampleDocument(d, f).objects.single['position'],
          sampleDocument(history.document, f).objects.single['position'],
        ),
        lessThanOrEqualTo(1.00000001),
      );
    }
    history.undo();
    expect(history.document.businessContent, d.businessContent);
  });
  test(
    'move bake preserves look-at mode, optics, rotation and unwrapped roll',
    () {
      final id = const Uuid().v4();
      final d = DirectorDocument.blank('Scene').mutate((j) {
        j['cameras'][0]['roll'] = 720;
        j['camera_moves'].add({
          'id': id,
          'camera_id': j['cameras'][0]['id'],
          'kind': 'dolly_in',
          'start_frame': 24,
          'end_frame': 72,
        });
      });
      final baked = DirectorDocument.fromJson(
        bakeControl(d, 'camera_moves', id),
      );
      expect(baked.moves, isEmpty);
      expect(baked.cameras.single['orientation_mode'], 'look_at');
      for (var f = 0; f <= 120; f++) {
        final a = sampleCamera(d, d.defaultCameraId, f),
            b = sampleCamera(baked, baked.defaultCameraId, f);
        expect(
          quaternionAngle(a['rotation'], b['rotation']),
          lessThanOrEqualTo(0.01000001),
        );
        expect(a['roll'], b['roll']);
        expect(
          bakeError('position', a['position'], b['position']),
          lessThanOrEqualTo(1.00000001),
        );
      }
    },
  );
  test(
    'manual continuous control cannot cross a path and rejection is atomic',
    () {
      final history = CommandHistory(
        DirectorDocument.blank(
          'Scene',
        ).mutate((j) => j['objects'].add(actor())),
      );
      final id = history.document.objects.single['id'];
      history.intervalKeys(id, 'position', 0, 120, [1, 0, 0]);
      final before = history.document.businessContent;
      expect(
        () => history.upsertPath({
          'id': const Uuid().v4(),
          'target_id': id,
          'kind': 'line',
          'start_frame': 24,
          'end_frame': 72,
          'easing': 'linear',
          'orient_to_path': false,
          'geometry': {
            'start': [0, 0, 0],
            'end': [2, 0, 0],
          },
        }),
        throwsA(isA<DocumentError>()),
      );
      expect(history.document.businessContent, before);
    },
  );
}
