// 职责: 用确定性文件故障验证输出取消、运行内暂停与空间保护。
// 关联文件:
//   lib/shared/services/director/export_task.dart
//   lib/shared/services/director/storage.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:uuid/uuid.dart';
import 'contract_test.dart' show actor;
import 'package:reveric/shared/services/director/renderer.dart';
import 'package:reveric/shared/services/director/storage.dart';
import 'package:reveric/shared/services/director/export_task.dart';

class FakeFrames implements FrameRenderer {
  int calls = 0;
  final List<String> cameras = [];
  bool disposed = false;
  int? failAt;
  void Function(int)? after;
  @override
  Future<Uint8List> capture(DirectorDocument d, int f, String c) async {
    calls++;
    cameras.add(c);
    if (f == failAt) {
      throw StateError('capture_failed');
    }
    after?.call(f);
    return Uint8List.fromList([137, 80, 78, 71, f]);
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  late Directory root;
  late DirectorStorage workspace;
  late DirectorDocument document;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('director_test_');
    workspace = DirectorStorage(
      Directory('${root.path}/support')..createSync(),
      Directory('${root.path}/tmp')..createSync(),
    );
    document = DirectorDocument.parse(
      File('test/fixtures/director/motion.director.json').readAsStringSync(),
    );
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('sequence cuts at 48 and frozen output ignores ongoing edits', () async {
    document = document.mutate(
      (j) => j['camera_cuts'].add({
        'id': const Uuid().v4(),
        'frame': 48,
        'camera_id': j['cameras'][1]['id'],
      }),
    );
    final frozen = document;
    final renderer = FakeFrames()
      ..after = (frame) {
        if (frame == 47) {
          document = document.mutate((j) => j['camera_cuts'].clear());
        }
      };
    final task = ExportTaskOrchestrator();
    await task.run(
      workspace: workspace,
      document: document,
      renderer: renderer,
      cameraMode: 'sequence',
      startFrame: 47,
      endFrame: 50,
      spaceProbe: (_) async => 1 << 40,
    );
    expect(task.state, OutputState.completed);
    expect(renderer.cameras, [
      frozen.defaultCameraId,
      frozen.cameras[1]['id'],
      frozen.cameras[1]['id'],
    ]);
    final manifest = jsonDecode(
      await File('${task.result!.path}/manifest.json').readAsString(),
    );
    expect(manifest['cameraMode'], 'sequence');
    expect(manifest['cameraId'], isNull);
    expect(
      (manifest['frames'] as List).map((f) => f['cameraId']),
      renderer.cameras,
    );
    final still = ExportTaskOrchestrator(), fixed = FakeFrames();
    await still.run(
      workspace: workspace,
      document: frozen,
      renderer: fixed,
      cameraMode: 'fixed',
      cameraId: frozen.defaultCameraId,
      singleFrame: 48,
      spaceProbe: (_) async => 1 << 40,
    );
    expect(still.state, OutputState.completed);
    final sequences = await ExportTaskOrchestrator.completedFor(
      workspace,
      frozen.id,
      null,
    );
    final singles = await ExportTaskOrchestrator.completedFor(
      workspace,
      frozen.id,
      frozen.defaultCameraId,
    );
    expect(sequences.single['cameraMode'], 'sequence');
    expect(singles.single['cameraMode'], 'fixed');
    expect(
      sequences.single['operationId'],
      isNot(singles.single['operationId']),
    );

    expect(fixed.cameras, [frozen.defaultCameraId]);
  });
  test(
    'output requires explicit mode and full frozen validation before capture',
    () async {
      for (final selection in [
        ('fixed', null),
        ('sequence', document.defaultCameraId),
        ('other', null),
      ]) {
        final renderer = FakeFrames(), task = ExportTaskOrchestrator();
        await task.run(
          workspace: workspace,
          document: document,
          renderer: renderer,
          cameraMode: selection.$1,
          cameraId: selection.$2,
          singleFrame: 0,
          spaceProbe: (_) async => 1 << 40,
        );
        expect(task.state, OutputState.failed);
        expect(task.errorCode, 'validation_failed');
        expect(renderer.calls, 0);
      }
      final a = actor();
      final invalid = DirectorDocument.blank('Scene').mutate((j) {
        j['objects'].add(a);
        j['tracks'].add({
          'id': const Uuid().v4(),
          'target_id': a['id'],
          'property': 'pose',
          'keys': [
            {
              'frame': 100,
              'value': {...a['pose'], 'root_offset_y': 50},
              'easing': 'hold',
            },
          ],
        });
      });
      final renderer = FakeFrames(), task = ExportTaskOrchestrator();
      await task.run(
        workspace: workspace,
        document: invalid,
        renderer: renderer,
        cameraMode: 'sequence',
        singleFrame: 0,
        spaceProbe: (_) async => 1 << 40,
      );
      expect(task.state, OutputState.failed);
      expect(renderer.calls, 0);
      expect(task.diagnostic!['frameTargetProperty'], contains('frame[100]'));
    },
  );
  test('frame range renders the frozen source coordinates', () async {
    final renderer = FakeFrames();
    final task = ExportTaskOrchestrator();
    await task.run(
      workspace: workspace,
      document: document,
      renderer: renderer,
      cameraMode: 'fixed',
      cameraId: document.activeCameras.first['id'],
      startFrame: 24,
      endFrame: 28,
      spaceProbe: (_) async => 1 << 40,
    );
    expect(task.state, OutputState.completed);
    final manifest = jsonDecode(
      await File('${task.result!.path}/manifest.json').readAsString(),
    );
    expect(manifest['frameCount'], 4);
    expect(manifest['frames'].first['sourceFrame'], 24);
    expect(manifest['frames'].last['sourceFrame'], 27);
    expect(renderer.disposed, true);
  });
  test('space preflight keeps existing output and releases renderer', () async {
    final existing = File('${workspace.root.path}/keep.txt')
      ..writeAsStringSync('keep');
    final r = FakeFrames(), task = ExportTaskOrchestrator();
    await task.run(
      workspace: workspace,
      document: document,
      renderer: r,
      cameraMode: 'fixed',
      cameraId: document.activeCameras.first['id'],
      spaceProbe: (_) async => 0,
    );
    expect(task.state, OutputState.failed);
    expect(task.errorCode, 'storage_full');
    expect(r.calls, 0);
    expect(r.disposed, true);
    expect(await existing.readAsString(), 'keep');
  });
  test('paused after frame37 resumes from38 and exports120', () async {
    final task = ExportTaskOrchestrator(), r = FakeFrames();
    r.after = (frame) {
      if (frame == 37) {
        task.pause();
      }
    };
    task.addListener(() {
      if (task.state == OutputState.paused) {
        expect(task.written, 38);
        task.resume();
      }
    });
    await task.run(
      workspace: workspace,
      document: document,
      renderer: r,
      cameraMode: 'fixed',
      cameraId: document.activeCameras.first['id'],
      spaceProbe: (_) async => 1 << 40,
    );
    expect(task.state, OutputState.completed);
    expect(r.calls, 120);
    final manifest = jsonDecode(
      await File('${task.result!.path}/manifest.json').readAsString(),
    );
    expect(manifest['frames'].last['sourceFrame'], 119);
  });
  test('cancel pause notification does not hang or delete completed', () async {
    final task = ExportTaskOrchestrator(), r = FakeFrames();
    r.after = (f) {
      if (f == 2) {
        task.pause();
      }
    };
    task.addListener(() {
      if (task.state == OutputState.paused) {
        task.cancel();
      }
    });
    await task.run(
      workspace: workspace,
      document: document,
      renderer: r,
      cameraMode: 'fixed',
      cameraId: document.activeCameras.first['id'],
      spaceProbe: (_) async => 1 << 40,
    );
    expect(task.state, OutputState.cancelled);
    expect(r.calls, 3);
    expect(
      await Directory(
        '${workspace.temporary.path}/${task.operationId}',
      ).exists(),
      false,
    );
    expect(
      await File(
        '${workspace.root.path}/tasks/${task.operationId}/source.director.json',
      ).exists(),
      false,
    );
  });
  test(
    'capture failure cleans temporary files without persisting a project snapshot',
    () async {
      final task = ExportTaskOrchestrator(),
          renderer = FakeFrames()..failAt = 2;
      final existing = File('${workspace.root.path}/existing_output')
        ..writeAsStringSync('keep');
      await task.run(
        workspace: workspace,
        document: document,
        renderer: renderer,
        cameraMode: 'fixed',
        cameraId: document.activeCameras.first['id'],
        spaceProbe: (_) async => 1 << 40,
      );
      expect(task.state, OutputState.failed);
      expect(task.errorCode, 'capture_failed');
      expect(renderer.disposed, true);
      expect(
        await Directory(
          '${workspace.temporary.path}/${task.operationId}',
        ).exists(),
        false,
      );
      expect(
        await File(
          '${workspace.root.path}/tasks/${task.operationId}/source.director.json',
        ).exists(),
        false,
      );
      expect(await existing.readAsString(), 'keep');
    },
  );
  test(
    'each output captures the current document and saves no project snapshot',
    () async {
      final first = ExportTaskOrchestrator();
      await first.run(
        workspace: workspace,
        document: document,
        renderer: FakeFrames(),
        cameraMode: 'fixed',
        cameraId: document.activeCameras.first['id'],
        singleFrame: 0,
        spaceProbe: (_) async => 1 << 40,
      );
      final renderer = FakeFrames();
      final second = ExportTaskOrchestrator();
      document = DirectorDocument.fromJson(document.toJson()..['revision'] = 2);
      await second.run(
        workspace: workspace,
        document: document,
        renderer: renderer,
        cameraMode: 'fixed',
        cameraId: document.activeCameras.first['id'],
        singleFrame: 1,
        spaceProbe: (_) async => 1 << 40,
      );
      expect(second.operationId, isNot(first.operationId));
      expect(renderer.calls, 1);
      expect(await Directory('${workspace.root.path}/tasks').exists(), false);
      expect(
        await File('${second.result!.path}/source.director.json').exists(),
        false,
      );
      final manifest =
          jsonDecode(
                await File(
                  '${second.result!.path}/manifest.json',
                ).readAsString(),
              )
              as Map;
      expect(manifest['startFrame'], 1);
      expect(manifest['documentRevision'], 2);
      expect(manifest.containsKey('documentSha256'), false);
    },
  );
}
