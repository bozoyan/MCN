// 职责: 测试 RevericPaths — 验证存储路径的相对/绝对解析逻辑。
// 关联文件:
//   lib/shared/utils/storage_paths.dart

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/utils/storage_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempSupport;

  setUp(() async {
    tempSupport = await Directory.systemTemp.createTemp('reveric_paths_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return tempSupport.path;
            }
            return null;
          },
        );
    await RevericPaths.initialize();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tempSupport.exists()) {
      await tempSupport.delete(recursive: true);
    }
  });

  test(
    'image result parts are restricted to the file workspace root and own prefix',
    () {
      expect(
        RevericPaths.isImageResultPart(
          tempSupport,
          '${tempSupport.path}/file_workspaces/reveric_image_result_1.png.part',
        ),
        true,
      );
      for (final relative in [
        'file_workspaces/other.png.part',
        'file_workspaces/reveric_image_result_1.png',
        'file_workspaces/work/reveric_image_result_1.png.part',
        'images/reveric_image_result_1.png.part',
        'media/reveric_image_result_1.png.part',
      ]) {
        expect(
          RevericPaths.isImageResultPart(
            tempSupport,
            p.join(tempSupport.path, relative),
          ),
          false,
        );
      }
    },
  );

  test('media paths isolate owners and normalize Windows names', () {
    expect(RevericPaths.fileWorkspaceDirectory('a'), 'file_workspaces/a');
    expect(RevericPaths.fileWorkspaceDirectory(null), 'file_workspaces/shared');
    expect(
      RevericPaths.mediaPath('a', 'image', r'目录\图片.png'),
      'file_workspaces/a/images/目录/图片.png',
    );
    expect(
      RevericPaths.mediaPath(null, 'audio', 'voice.wav'),
      'file_workspaces/shared/audio/voice.wav',
    );
    for (final id in [
      'shared',
      'SHARED',
      'Shared',
      '..',
      'a/b',
      r'a\b',
      'C:',
    ]) {
      expect(
        () => RevericPaths.mediaDirectory(id, 'image'),
        throwsArgumentError,
      );
    }
    for (final name in ['../x.png', r'..\x.png', '/x.png', r'C:\x.png']) {
      expect(
        () => RevericPaths.mediaPath('a', 'image', name),
        throwsArgumentError,
      );
    }
  });

  test(
    'in-place ownership rejects other works, shared, wrong type and links',
    () async {
      for (final relative in [
        'file_workspaces/a/images/x.png',
        'file_workspaces/b/images/x.png',
        'file_workspaces/shared/images/x.png',
        'file_workspaces/a/videos/x.png',
        'images/x.png',
      ]) {
        final file = File(p.join(tempSupport.path, relative));
        await file.parent.create(recursive: true);
        await file.writeAsString('fixture');
        expect(
          await RevericPaths.ownsMediaFile(tempSupport, 'a', 'image', file),
          relative == 'file_workspaces/a/images/x.png',
        );
      }
      final link = Link(
        p.join(tempSupport.path, 'file_workspaces/a/images/link.png'),
      );
      await link.create(
        p.join(tempSupport.path, 'file_workspaces/b/images/x.png'),
      );
      await expectLater(
        RevericPaths.ownsMediaFile(tempSupport, 'a', 'image', File(link.path)),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  group('RevericPaths.resolveStored', () {
    test('stale paths are not redirected to another file', () async {
      final owned = File(
        p.join(
          tempSupport.path,
          'file_workspaces',
          'book',
          'images',
          'same.png',
        ),
      );
      await owned.parent.create(recursive: true);
      await owned.writeAsBytes([1]);
      final legacy = File(p.join(tempSupport.path, 'images', 'same.png'));
      await legacy.parent.create(recursive: true);
      await legacy.writeAsBytes([2]);
      expect(
        RevericPaths.resolveStored(
          '/old/application/file_workspaces/book/images/same.png',
        ),
        isNull,
      );
    });

    // 用户场景：app 升级覆盖安装，DB 里存的是相对路径。
    // 期望：拼当前根能找到文件。
    test('relative stored path resolves under current support root', () async {
      final dir = Directory(p.join(tempSupport.path, 'novel_covers'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'demo.png'));
      await file.writeAsBytes([0x89, 0x50]);

      final resolved = RevericPaths.resolveStored('novel_covers/demo.png');
      expect(resolved, file.path);
    });

    // 用户场景：相对路径但文件不存在（被手动删除 / 老的孤儿引用）。
    // 期望：返回 null，让上层走占位，不要崩。
    test(
      'returns null when relative path does not point to an existing file',
      () {
        final resolved = RevericPaths.resolveStored('novel_covers/missing.png');
        expect(resolved, isNull);
      },
    );

    // 用户场景：备份恢复 / 换机后，DB 里残留旧容器的绝对路径。
    test('stale absolute image path remains missing', () async {
      final dir = Directory(p.join(tempSupport.path, 'novel_covers'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'demo.png'));
      await file.writeAsBytes([0x89, 0x50]);

      // 模拟旧 iOS 容器路径（容器 UUID 不同）。
      const stored =
          '/var/mobile/Containers/Data/Application/OLD-UUID/Library/Application Support/novel_covers/demo.png';

      final resolved = RevericPaths.resolveStored(stored);
      expect(resolved, isNull);
    });

    // 用户场景：当前会话内绝对路径仍然有效（用户刚选的文件 / 桌面端正常运行）。
    test('valid absolute path is returned as-is', () async {
      final outsideDir = await Directory.systemTemp.createTemp(
        'reveric_outside_',
      );
      addTearDown(() async {
        if (await outsideDir.exists()) {
          await outsideDir.delete(recursive: true);
        }
      });
      final file = File(p.join(outsideDir.path, 'picked.png'));
      await file.writeAsBytes([0x00]);

      final resolved = RevericPaths.resolveStored(file.path);
      expect(resolved, file.path);
    });

    // 边界：null / 空字符串 -> null。
    test('null and empty stored values resolve to null', () {
      expect(RevericPaths.resolveStored(null), isNull);
      expect(RevericPaths.resolveStored(''), isNull);
    });
  });

  group('RevericPaths.resolveDatabasePath', () {
    // 用户场景：新建小说，内容库 sqlite 文件还没创建。
    // 期望：即便文件不存在也返回拼好的绝对路径（供工厂创建）——
    // 这是与 resolveStored 的关键区别（后者会因不存在返回 null）。
    test('relative path joins current root even when file is absent', () {
      final resolved = RevericPaths.resolveDatabasePath(
        'novel_workspaces/new-novel.sqlite',
      );
      expect(
        resolved,
        p.join(tempSupport.path, 'novel_workspaces', 'new-novel.sqlite'),
      );
    });

    // 用户场景：app 升级后 DB 存的是相对路径，文件已存在。
    // 期望：解析到当前根下的实际文件。
    test('relative path joins current root for an existing file', () async {
      final dir = Directory(p.join(tempSupport.path, 'novel_workspaces'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'n1.sqlite'));
      await file.writeAsBytes([0x00]);

      final resolved = RevericPaths.resolveDatabasePath(
        'novel_workspaces/n1.sqlite',
      );
      expect(resolved, file.path);
    });

    // 用户场景：桌面端 / 本会话内绝对路径仍有效。
    // 期望：原样返回。
    test('valid absolute path is returned as-is', () async {
      final dir = Directory(p.join(tempSupport.path, 'novel_workspaces'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'n2.sqlite'));
      await file.writeAsBytes([0x00]);

      expect(RevericPaths.resolveDatabasePath(file.path), file.path);
    });

    // 用户场景：iOS 重装 / 换机后，DB 残留旧容器的绝对路径，文件已搬到新容器。
    test('absolute database paths are not re-anchored', () async {
      final dir = Directory(p.join(tempSupport.path, 'novel_workspaces'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'n3.sqlite'));
      await file.writeAsBytes([0x00]);

      const stored =
          '/var/mobile/Containers/Data/Application/OLD-UUID/Library/Application Support/novel_workspaces/n3.sqlite';

      expect(RevericPaths.resolveDatabasePath(stored), stored);
    });

    // 期望：返回原值，让 ensureNovelContentDatabasePath 判定缺失后重建，而非崩。
    test('unresolvable stale absolute path falls back to the original', () {
      const stored =
          '/var/mobile/Containers/Data/Application/OLD-UUID/Library/Application Support/novel_workspaces/gone.sqlite';
      expect(RevericPaths.resolveDatabasePath(stored), stored);
    });
  });

  for (final prefix in [
    '',
    r'C:\old\Reveric\',
    'C:/old/Reveric/',
    r'\\server\share\Reveric\',
  ]) {
    test(
      'foreign stored paths resolve to existing local files: $prefix',
      () async {
        final separator = prefix.endsWith('/') ? '/' : r'\';
        final db = File(
          p.join(tempSupport.path, 'novel_workspaces', 'book.sqlite'),
        );
        await db.parent.create(recursive: true);
        await db.writeAsBytes([0]);
        final cover = File(
          p.join(tempSupport.path, 'novel_covers', 'cover.png'),
        );
        await cover.parent.create(recursive: true);
        await cover.writeAsBytes([1]);
        final media = File(
          p.join(
            tempSupport.path,
            'file_workspaces',
            'book',
            'videos',
            'clip.mp4',
          ),
        );
        await media.parent.create(recursive: true);
        await media.writeAsBytes([2]);
        expect(
          RevericPaths.resolveDatabasePath(
            '${prefix}novel_workspaces${separator}book.sqlite',
          ),
          prefix.isEmpty
              ? db.path
              : '${prefix}novel_workspaces${separator}book.sqlite',
        );
        expect(
          RevericPaths.resolveStored(
            '${prefix}novel_covers${separator}cover.png',
          ),
          prefix.isEmpty ? cover.path : null,
        );
        expect(
          RevericPaths.resolveStored(
            '${prefix}file_workspaces${separator}book${separator}videos${separator}clip.mp4',
          ),
          prefix.isEmpty ? media.path : null,
        );
      },
    );
  }

  group('RevericPaths.toRelative', () {
    // 写入路径必须是相对路径，否则 DB 又会被绝对路径污染。
    test('absolute path under current root collapses to relative', () {
      final abs = p.join(tempSupport.path, 'novel_covers', 'foo.png');
      expect(RevericPaths.toRelative(abs), p.join('novel_covers', 'foo.png'));
    });

    // 已经是相对路径不应再次拼接，保持幂等。
    test('relative path passes through unchanged', () {
      expect(
        RevericPaths.toRelative('novel_covers/foo.png'),
        'novel_covers/foo.png',
      );
    });

    // 路径不在当前根下应返回 null —— 调用方应保留原值，不要把 DB 列写空。
    test('path outside support root returns null', () {
      expect(RevericPaths.toRelative('/somewhere/else/foo.png'), isNull);
    });
  });
}
