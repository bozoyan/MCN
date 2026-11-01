// 职责: 验证制作提交检查用存储路径打开真实内容库，并拒绝缺失文件而不新建空库。
// 关联文件:
//   lib/shared/providers/video_tasks.dart
//   lib/shared/services/production/result_service.dart
//   lib/shared/utils/storage_paths.dart

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/video_tasks.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/services/storyboard/service.dart';
import 'package:reveric/shared/utils/storage_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDatabase app;
  late ProviderContainer container;
  late String clipId;
  const relative = 'novel_workspaces/production.sqlite';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('production-result-path-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    await RevericPaths.initialize();
    await Directory('${root.path}/novel_workspaces').create();
    final content = NovelContentDatabase(relative);
    try {
      final screenplay = ScreenplayService(content);
      final initial = await screenplay.createInitialStructure();
      final scene = await screenplay.createScene(
        screenplayId: (await content.screenplayDao.getRoot())!.id,
        episodeId: initial.episodeId,
      );
      clipId = (await StoryboardService(content).create(scene)).id;
    } finally {
      await content.close();
    }
    app = AppDatabase.forTest(NativeDatabase.memory());
    container = ProviderContainer.test(
      overrides: [appDatabaseProvider.overrideWithValue(app)],
    );
  });
  tearDown(() async {
    container.dispose();
    await app.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await root.delete(recursive: true);
  });

  Future<void> insertWork(String stored) => app
      .into(app.novels)
      .insert(
        NovelsCompanion.insert(
          id: 'work',
          title: 'Production',
          description: '',
          contentKind: const Value('screenplay'),
          contentDatabasePath: Value(stored),
        ),
      );

  for (final kind in [
    'relative',
    'windows_relative',
    'absolute',
    'relocated',
  ]) {
    test(
      kind == 'relocated'
          ? 'stale absolute database path is not redirected to a local database'
          : '$kind database path resolves before checking production source',
      () async {
        final stored = switch (kind) {
          'relative' => relative,
          'windows_relative' => r'novel_workspaces\production.sqlite',
          'absolute' => '${root.path}/$relative',
          _ => r'C:\old-profile\novel_workspaces\production.sqlite',
        };
        await insertWork(stored);
        final results = container.read(productionResultServiceProvider);
        if (kind == 'relocated') {
          await expectLater(
            results.beforeCreate('work', 'production_clip', clipId),
            throwsStateError,
          );
        } else {
          await results.beforeCreate('work', 'production_clip', clipId);
        }
        expect((await app.novelDao.get('work'))!.contentDatabasePath, stored);
        expect(await app.select(app.generationTasks).get(), isEmpty);
      },
    );
  }
  test(
    'missing content database remains an error and is never recreated',
    () async {
      const missing = 'novel_workspaces/missing.sqlite';
      await insertWork(missing);
      await expectLater(
        container
            .read(productionResultServiceProvider)
            .beforeCreate('work', 'production_clip', clipId),
        throwsStateError,
      );
      expect(File('${root.path}/$missing').existsSync(), false);
    },
  );
}
