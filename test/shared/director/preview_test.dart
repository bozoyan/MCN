// 职责: 验证导演预览图片通知、手动关闭生成与渲染顺序。
// 关联文件:
//   lib/shared/services/director/preview.dart
//   lib/shared/services/screenplay/staging.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/director/preview.dart';
import 'package:reveric/shared/services/director/file_output.dart';
import 'package:reveric/shared/services/director/renderer.dart';
import 'package:reveric/shared/models/director/document.dart';
import 'package:reveric/shared/services/director/storage.dart';
import 'package:reveric/shared/services/screenplay/staging.dart';
import 'package:path/path.dart' as path;

class DelayedRenderer implements FrameRenderer {
  DelayedRenderer(this.bytes, {this.release});
  final List<int> bytes;
  final Future<void>? release;
  final started = Completer<void>();
  bool disposed = false;
  @override
  Future<Uint8List> capture(
    DirectorDocument document,
    int frame,
    String cameraId,
  ) async {
    started.complete();
    await release;
    return Uint8List.fromList(bytes);
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  test(
    'preview completion retries the matching workspace after a cache miss',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'director-preview-',
      );
      final cache = DirectorPreview(DirectorStorage(directory, directory));
      final unrelated = <int>[];
      final other = DirectorPreview.updates(
        'other-workspace',
      ).listen(unrelated.add);
      try {
        expect(await cache.read(), isNull);
        final ready = DirectorPreview.updates(
          path.basename(directory.path),
        ).asyncMap((_) => cache.read()).first;
        final bytes = Uint8List.fromList([1, 2, 3]);
        await cache.write(bytes);
        expect(await ready, bytes);
        expect(unrelated, isEmpty);
        expect(await File('${directory.path}/preview.json').exists(), isFalse);
        await File(
          '${directory.path}/preview.json',
        ).writeAsString('obsolete metadata');
        expect(await cache.read(), bytes);
      } finally {
        await other.cancel();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'only manual close renders final saved content; ordinary saves never render',
    () async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      await db.screenplayDao.createStaging('staging', 'Original');
      final binding = VideoStagingBinding(db.screenplayDao, 'staging');
      final session = await binding.load(camera: 'Camera');
      final rendered = <String>[];
      final completed = Completer<void>();
      binding.updatePreview = (document) async {
        rendered.add(document.title);
        completed.complete();
      };
      try {
        session.history.execute((json) => json['title'] = 'First');
        session.history.execute((json) => json['title'] = 'Latest');
        await binding.flush();
        await session.save();
        expect(rendered, isEmpty);
        binding.dispose();
        session.dispose();
        await completed.future;
        binding.dispose();
        expect(rendered, ['Latest']);
      } finally {
        binding.dispose();
        await db.close();
      }
    },
  );

  test('opening and closing without a manual edit does not render', () async {
    final db = NovelContentDatabase.forTest(NativeDatabase.memory());
    await db.screenplayDao.createStaging('staging', 'Original');
    final binding = VideoStagingBinding(db.screenplayDao, 'staging');
    final session = await binding.load(camera: 'Camera');
    var rendered = false;
    binding.updatePreview = (_) async => rendered = true;
    binding.dispose();
    session.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(rendered, isFalse);
    await db.close();
  });

  test(
    'slow or failed close preview cannot delay disposal or alter saved data',
    () async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      await db.screenplayDao.createStaging('staging', 'Original');
      final binding = VideoStagingBinding(db.screenplayDao, 'staging');
      final session = await binding.load(camera: 'Camera');
      final started = Completer<void>(), release = Completer<void>();
      binding.updatePreview = (_) async {
        started.complete();
        await release.future;
        throw StateError('capture failed');
      };
      session.history.execute((json) => json['title'] = 'Latest');
      await binding.flush();
      binding.dispose();
      session.dispose();
      await started.future;
      expect(VideoStagingBinding.openFor(db.screenplayDao, 'staging'), isNull);
      expect((await db.screenplayDao.getStaging('staging'))!.title, 'Latest');
      release.complete();
      await Future<void>.delayed(Duration.zero);
      await db.close();
    },
  );

  test(
    'parallel previews write in invocation order without holding the database queue',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'director-preview-order-',
      );
      final storage = DirectorStorage(directory, directory);
      final release = Completer<void>();
      final first = DelayedRenderer([1], release: release.future);
      final second = DelayedRenderer([2]);
      try {
        final document = DirectorDocument.blank('First');
        final a = DirectorFileOutput.renderPreview(
          document,
          storage,
          renderer: first,
        );
        await first.started.future;
        final b = DirectorFileOutput.renderPreview(
          document.mutate((j) => j['title'] = 'Second'),
          storage,
          renderer: second,
        );
        await Future<void>.delayed(Duration.zero);
        expect(second.started.isCompleted, isFalse);
        release.complete();
        await Future.wait([a, b]);
        expect(await DirectorPreview(storage).read(), [2]);
        expect(first.disposed, isTrue);
        expect(second.disposed, isTrue);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
