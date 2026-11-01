// 职责: 验证小说内容库在普通关闭、进程退出和文件替换时对暂停查询流的关闭行为。
// 关联文件:
//   lib/shared/database/novel_content_database.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:path/path.dart' as p;

void main() {
  test('normal close waits for a paused content query stream', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'reveric_content_shutdown_',
    );
    addTearDown(() async {
      await NovelContentDatabase.closeAllCached();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final database = NovelContentDatabase(p.join(tempDir.path, 'novel.sqlite'));
    final firstResult = Completer<void>();
    final subscription = database.select(database.novelStates).watch().listen((
      _,
    ) {
      if (!firstResult.isCompleted) {
        firstResult.complete();
      }
    });
    await firstResult.future;
    subscription.pause();

    final closeFuture = NovelContentDatabase.closeAllCached();
    final closed = await Future.any<bool>([
      closeFuture.then((_) => true),
      Future<bool>.delayed(const Duration(milliseconds: 100), () => false),
    ]);

    if (!closed) {
      subscription.resume();
      await subscription.cancel();
      await closeFuture;
    } else {
      subscription.resume();
      await subscription.cancel();
    }

    expect(closed, isFalse);
  });

  test(
    'process exit does not wait for a paused content query stream',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'reveric_content_shutdown_exit_',
      );
      addTearDown(() async {
        await NovelContentDatabase.closeAllCached();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final database = NovelContentDatabase(
        p.join(tempDir.path, 'novel.sqlite'),
      );
      final firstResult = Completer<void>();
      final subscription = database.select(database.novelStates).watch().listen(
        (_) {
          if (!firstResult.isCompleted) {
            firstResult.complete();
          }
        },
      );
      await firstResult.future;
      subscription.pause();

      final closeFuture = NovelContentDatabase.closeAllCachedForProcessExit();
      final closed = await Future.any<bool>([
        closeFuture.then((_) => true),
        Future<bool>.delayed(const Duration(milliseconds: 100), () => false),
      ]);

      subscription.resume();
      await subscription.cancel();
      if (!closed) {
        await closeFuture;
      }

      expect(closed, isTrue);
    },
  );

  test('file replacement does not wait for a paused query stream', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'reveric_content_file_replacement_',
    );
    final databasePath = p.join(tempDir.path, 'content.sqlite');
    addTearDown(() async {
      await NovelContentDatabase.closeAllCached();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final database = NovelContentDatabase(databasePath);
    final firstResult = Completer<void>();
    final subscription = database.chapterDao.watchAll().listen((_) {
      if (!firstResult.isCompleted) {
        firstResult.complete();
      }
    });
    await firstResult.future;
    subscription.pause();

    await NovelContentDatabase.closeAllCachedForFileReplacement().timeout(
      const Duration(milliseconds: 100),
    );
    expect(NovelContentDatabase.isCachedForTesting(databasePath), isFalse);

    subscription.resume();
    await subscription.cancel();
    await database.close();
  });
}
