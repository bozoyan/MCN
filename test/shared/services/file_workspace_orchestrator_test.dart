// 职责: 验证文件工作区即时迁移、settings.local.json 持久化、冲突保护与新目录的读写。
// 关联文件:
//   lib/shared/services/file_workspace_orchestrator.dart
//   lib/shared/utils/storage_paths.dart
//   lib/shared/services/ai/files/session_files.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reveric/shared/services/ai/files/session_files.dart';
import 'package:reveric/shared/services/file_workspace_orchestrator.dart';
import 'package:reveric/shared/utils/storage_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory support;
  late Directory destination;
  final orchestrator = FileWorkspaceOrchestrator();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('workspace-location-');
    // Match real app roots while keeping path comparisons independent of /var aliases.
    root = Directory(await root.resolveSymbolicLinks());
    support = await Directory(p.join(root.path, 'support')).create();
    destination = await Directory(p.join(root.path, '中文 空间')).create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => support.path,
        );
    await RevericPaths.initialize();
  });

  tearDown(() async {
    await RevericPaths.initialize();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await root.delete(recursive: true);
  });

  Future<File> write(Directory parent, String relative, String content) async {
    final file = File(p.join(parent.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  test(
    'migrate copies the complete tree, keeps originals and writes to new root',
    () async {
      const files = [
        'file_workspaces/work/images/中文.png',
        'file_workspaces/work/videos/a.mp4',
        'file_workspaces/work/audio/a.wav',
        'file_workspaces/work/files/nested/a.csv',
        'file_workspaces/work/sessions/chat/a.md',
        'file_workspaces/shared/files/empty.txt',
        'file_workspaces/incomplete.part',
      ];
      for (final name in files) {
        await write(support, name, name.endsWith('empty.txt') ? '' : name);
      }
      await Directory(p.join(support.path, 'file_workspaces/empty')).create();
      await write(support, 'reveric.sqlite', 'database stays');
      final legacy = await write(support, 'avatars/a.png', 'avatar stays');

      expect(await orchestrator.prepare(destination.path), destination.path);
      expect(RevericPaths.fileWorkspaceParent, support.path);
      await orchestrator.migrate(destination.path);

      expect((await orchestrator.load()).activeParent, destination.path);
      expect(
        await File(p.join(support.path, 'settings.local.json')).readAsString(),
        '{"file_workspace_directory":${jsonEncode(destination.path)}}',
      );
      for (final name in files) {
        final original = File(p.join(support.path, name));
        final copy = File(p.join(destination.path, name));
        expect(await copy.readAsBytes(), await original.readAsBytes());
        expect(RevericPaths.resolveStored(name), copy.path);
        expect(RevericPaths.toRelative(copy.path), name);
      }
      expect(
        await Directory(
          p.join(destination.path, 'file_workspaces/empty'),
        ).exists(),
        true,
      );
      expect(
        RevericPaths.resolveDatabasePath('reveric.sqlite'),
        p.join(support.path, 'reveric.sqlite'),
      );
      expect(
        await File(p.join(destination.path, 'reveric.sqlite')).exists(),
        false,
      );
      expect(RevericPaths.resolveStored('avatars/a.png'), legacy.path);

      final sessions = SessionFiles(novelId: 'work');
      final newFile = await sessions.allocate('new_session', '.txt');
      await newFile.writeAsString('new data');
      expect(p.isWithin(destination.path, newFile.path), true);
      expect(
        sessions.reference(newFile),
        startsWith('file_workspaces/work/sessions/'),
      );
      expect(
        (await sessions.resolve(sessions.reference(newFile))).path,
        newFile.path,
      );
      expect((await sessions.resolve('avatars/a.png')).path, legacy.path);

      await RevericPaths.initialize();
      await orchestrator.initialize();
      expect(RevericPaths.fileWorkspaceParent, destination.path);
    },
  );

  for (final sessionResolver in [false, true]) {
    test(
      '${sessionResolver ? 'session' : 'stored'} dot paths use the migrated workspace, never the retained copy',
      () async {
        const relative = 'file_workspaces/work/files/data.txt';
        final original = await write(support, relative, 'old copy');
        await write(
          support,
          'file_workspaces/work/files/old-only.txt',
          'old only',
        );
        final current = await write(destination, relative, 'current copy');
        await RevericPaths.initialize(fileWorkspaceParent: destination.path);
        final sessions = SessionFiles(novelId: 'work');
        for (final path in [
          './file_workspaces/work/files/data.txt',
          '././file_workspaces/./work/files/data.txt',
          'file_workspaces/work/./files/data.txt',
          r'.\file_workspaces\work\files\data.txt',
          r'.\.\file_workspaces\work\files\data.txt',
          r'file_workspaces\work\.\files\data.txt',
          './file_workspaces//work/files/data.txt',
        ]) {
          if (sessionResolver) {
            final resolved = await sessions.resolve(path);
            expect(resolved.path, current.path, reason: path);
            expect(await resolved.readAsString(), 'current copy');
          } else {
            expect(
              RevericPaths.resolveRelative(path, support: support.path),
              current.path,
              reason: path,
            );
            expect(
              RevericPaths.resolveDatabasePath(path),
              current.path,
              reason: path,
            );
            expect(
              RevericPaths.resolveStored(path),
              current.path,
              reason: path,
            );
            expect(
              await File(RevericPaths.resolveStored(path)!).readAsString(),
              'current copy',
            );
          }
        }
        const missing = './file_workspaces/work/files/old-only.txt';
        if (sessionResolver) {
          await expectLater(
            sessions.resolve(missing),
            throwsA(isA<FileSystemException>()),
          );
        } else {
          expect(RevericPaths.resolveStored(missing), isNull);
        }
        for (final unsafe in [
          './file_workspaces/work/files/../files/data.txt',
          r'.\file_workspaces\work\files\..\files\data.txt',
          './file_workspaces/../file_workspaces/work/files/data.txt',
        ]) {
          if (sessionResolver) {
            await expectLater(sessions.resolve(unsafe), throwsFormatException);
          } else {
            expect(
              () => RevericPaths.resolveRelative(unsafe, support: support.path),
              throwsFormatException,
            );
            expect(
              () => RevericPaths.resolveDatabasePath(unsafe),
              throwsFormatException,
            );
          }
        }
        expect(await original.readAsString(), 'old copy');
        // Non-workspace paths still belong to Application Support.
        final avatar = await write(support, 'avatars/a.png', 'avatar');
        if (sessionResolver) {
          expect(
            (await sessions.resolve('./avatars/./a.png')).path,
            avatar.path,
          );
          expect(
            (await SessionFiles(
              root: support.path,
            ).resolve('./$relative')).path,
            original.path,
          );
        } else {
          expect(RevericPaths.resolveStored('./avatars/./a.png'), avatar.path);
          expect(
            RevericPaths.resolveDatabasePath(
              './novel_workspaces/./work.sqlite',
            ),
            p.join(support.path, 'novel_workspaces/work.sqlite'),
          );
        }
      },
    );
  }

  test(
    'different destination files stop migration without changing active path',
    () async {
      const relative = 'file_workspaces/work/files/same.txt';
      final original = await write(support, relative, 'source');
      final conflicting = await write(destination, relative, 'destination');
      await expectLater(
        orchestrator.migrate(destination.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(RevericPaths.fileWorkspaceParent, support.path);
      expect((await orchestrator.load()).activeParent, isNull);
      expect(await original.readAsString(), 'source');
      expect(await conflicting.readAsString(), 'destination');
      await orchestrator.initialize();
      expect(RevericPaths.fileWorkspaceParent, support.path);
    },
  );

  test('matching files allow retry and remaining files are copied', () async {
    const relative = 'file_workspaces/work/files/same.txt';
    await write(support, relative, 'identical');
    await write(destination, relative, 'identical');
    await write(support, 'file_workspaces/work/files/new.txt', 'new');
    await orchestrator.migrate(destination.path);
    expect(
      await File(
        p.join(destination.path, 'file_workspaces/work/files/new.txt'),
      ).readAsString(),
      'new',
    );
  });

  test('nested destination and symbolic links are rejected', () async {
    final nested = await Directory(
      p.join(support.path, 'file_workspaces/nested'),
    ).create(recursive: true);
    await expectLater(
      orchestrator.prepare(nested.path),
      throwsA(isA<FileSystemException>()),
    );
    final outside = await write(root, 'outside.txt', 'outside');
    await Link(
      p.join(support.path, 'file_workspaces/link.txt'),
    ).create(outside.path);
    await expectLater(
      orchestrator.migrate(destination.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await outside.readAsString(), 'outside');
    expect((await orchestrator.load()).activeParent, isNull);
  });

  test(
    'explicit recovery clears the active location and permits a new migration',
    () async {
      const relative = 'file_workspaces/work/files/original.txt';
      final original = await write(support, relative, 'original');
      await orchestrator.migrate(destination.path);
      final next = await Directory(p.join(root.path, 'next')).create();
      final offline = await destination.rename('${destination.path}-offline');
      await expectLater(
        orchestrator.initialize(),
        throwsA(isA<FileSystemException>()),
      );

      await orchestrator.useApplicationDirectory();
      await orchestrator.initialize();
      final recovered = await orchestrator.load();
      expect(recovered.activeParent, isNull);
      expect(await original.readAsString(), 'original');
      expect(
        await File(p.join(offline.path, relative)).readAsString(),
        'original',
      );

      await orchestrator.migrate(next.path);
      expect(RevericPaths.fileWorkspaceParent, next.path);
      expect(
        await File(p.join(next.path, relative)).readAsString(),
        'original',
      );
    },
  );

  test(
    'recovery from invalid configuration can start a fresh default workspace',
    () async {
      await File(
        p.join(support.path, 'settings.local.json'),
      ).writeAsString('[]');
      await expectLater(orchestrator.load(), throwsA(isA<TypeError>()));
      await orchestrator.useApplicationDirectory();
      await orchestrator.initialize();
      final file = await SessionFiles(
        novelId: 'work',
      ).allocate('session', '.txt');
      await file.writeAsString('new file');
      expect(
        p.isWithin(p.join(support.path, 'file_workspaces'), file.path),
        true,
      );
      expect(await file.readAsString(), 'new file');
    },
  );

  test(
    'unavailable active disk fails rather than recreating empty storage',
    () async {
      await orchestrator.migrate(destination.path);
      await destination.rename('${destination.path}-offline');
      await expectLater(
        orchestrator.initialize(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await destination.exists(), false);
    },
  );
}
