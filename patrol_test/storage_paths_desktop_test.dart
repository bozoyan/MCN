// 职责: Patrol 桌面端 E2E — 验证内容库头像/Agent 头像渲染，以及内容库 sqlite 在相对路径/旧容器绝对路径下仍打开同一物理文件
// 关联文件:
//   lib/shared/utils/storage_paths.dart
//   lib/shared/widgets/character_avatar.dart
//   lib/shared/widgets/agent_avatar.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/production/asset_content.dart';
import 'package:reveric/shared/providers/novel_providers.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/utils/storage_paths.dart';
import 'package:reveric/shared/widgets/agent_avatar.dart';
import 'package:reveric/shared/widgets/character_avatar.dart';
import 'package:patrol/patrol.dart';
import 'package:path/path.dart' as p;

// 1x1 PNG，保证 Image.file 能真正解码、不触发 widget 层 decode 异常。
const _png1x1 = <int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
  0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
  0x42, 0x60, 0x82,
];

void main() {
  late Directory supportRoot;
  late AppDatabase app;
  Widget harness(Widget child) => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(app)],
    child: _harness(child),
  );
  Future<void> avatarAsset(String path) => app.assetDao.insertAsset(
    AssetsCompanion.insert(
      id: 'avatar',
      type: 'image',
      purpose: 'avatar',
      path: Value(path),
      content: const Value(ImageAssetContent(mimeType: 'image/png')),
    ),
  );
  // 测试自己写入的文件路径；tearDown 只删这些，绝不递归删 novel_workspaces 等真实目录。
  final createdPaths = <String>[];

  setUp(() async {
    // Patrol native runner 跑在真实 app 里，path_provider 用真实实现 —
    // 不能 mock channel（macOS 的 path_provider_foundation 走 pigeon，legacy
    // MethodChannel mock 不生效）。直接用真实 Application Support 根，
    // 写入唯一文件名的 fixture，结束后逐个删除。
    await RevericPaths.initialize();
    supportRoot = Directory(RevericPaths.supportRoot);
    // Patrol tests run outside test/, but still require an isolated database.
    // ignore: invalid_use_of_visible_for_testing_member
    app = AppDatabase.forTest(NativeDatabase.memory());
  });

  tearDown(() async {
    await app.close();
    for (final path in createdPaths.reversed) {
      for (final candidate in [
        path,
        '$path-wal',
        '$path-shm',
        '$path-journal',
      ]) {
        final file = File(candidate);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
    createdPaths.clear();
  });

  // 写一张真实图片到「当前容器根」下的某个已知子目录，返回其绝对路径。
  Future<String> writeImage(String subdir, String filename) async {
    final dir = Directory(p.join(supportRoot.path, subdir));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(_png1x1);
    createdPaths.add(file.path);
    return file.path;
  }

  // 用户场景（桌面工作区角色卡）：DB 里角色头像存的是相对路径（升级覆盖安装）。
  // 期望：拼当前根解析到真实文件并渲染 Image.file，而不是退回首字母占位。
  patrolTest('content-library avatar stored as a relative path renders', (
    $,
  ) async {
    final absolute = await writeImage('novel_workspaces/images', 'alice.png');
    const stored = 'novel_workspaces/images/alice.png';
    await avatarAsset(stored);

    _setDesktopSurface($, const Size(1600, 900));
    await $.pumpWidgetAndSettle(
      harness(
        const CharacterAvatar(avatarAssetId: 'avatar', fallbackName: 'Alice'),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(
      _fileImageOf($.tester.widget<Image>(find.byType(Image))).file.path,
      absolute,
    );
    // 没有走首字母占位。
    expect(find.text('A'), findsNothing);
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
  });

  // 用户场景（备份恢复/换机）：DB 里残留旧容器的绝对路径，文件已随容器搬到新根。
  // 期望：resolveStored 抠 novel_workspaces 段重锚定当前根，照常渲染。
  patrolTest(
    'stale old-container absolute avatar path re-anchors and renders',
    ($) async {
      final absolute = await writeImage('novel_workspaces/images', 'bob.png');
      const stored =
          '/var/mobile/Containers/Data/Application/OLD-UUID/Library/'
          'Application Support/novel_workspaces/images/bob.png';
      await avatarAsset(stored);

      _setDesktopSurface($, const Size(1600, 900));
      await $.pumpWidgetAndSettle(
        harness(
          const CharacterAvatar(avatarAssetId: 'avatar', fallbackName: 'Bob'),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(
        _fileImageOf($.tester.widget<Image>(find.byType(Image))).file.path,
        absolute,
      );
      await $.pumpWidgetAndSettle(const SizedBox.shrink());
    },
  );

  // 用户场景：文件真不存在（孤儿引用）。期望：退回首字母占位，不崩、不裂图。
  patrolTest('missing avatar path falls back to the initial placeholder', (
    $,
  ) async {
    _setDesktopSurface($, const Size(1600, 900));
    await $.pumpWidgetAndSettle(
      harness(
        const CharacterAvatar(avatarAssetId: 'missing', fallbackName: 'Carol'),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.text('C'), findsOneWidget);
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
  });

  // 用户场景（桌面 AI 助手/SubAgent 头像）：相对路径头像同样经中心组件兜底渲染。
  patrolTest('agent avatar stored as a relative path renders', ($) async {
    final absolute = await writeImage('agent_avatars', 'ai_agent.png');
    const stored = 'agent_avatars/ai_agent.png';

    _setDesktopSurface($, const Size(1600, 900));
    await $.pumpWidgetAndSettle(
      harness(const AgentAvatar(avatarPath: stored, size: 56)),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(
      _fileImageOf($.tester.widget<Image>(find.byType(Image))).file.path,
      absolute,
    );
  });

  // Commit 3 — 内容库 sqlite 路径相对化。
  // 在当前根的 novel_workspaces/ 下 seed 一个内容库（1 个 outline），关闭并清缓存后，
  // 用「存储形态」（相对 / 旧容器绝对）重新打开，断言读到的是 seed 过的同一物理文件，
  // 而不是工厂在错误路径上新建的空库（空库 onCreate 后 outline 数为 0）。
  Future<String> seedContentDb(String filename) async {
    final dir = Directory(p.join(supportRoot.path, 'novel_workspaces'));
    await dir.create(recursive: true);
    final absolute = p.join(dir.path, filename);
    final seeded = NovelContentDatabase(absolute);
    await seeded.seedDefaultWorkspace();
    // 关闭并强制清缓存，确保下面是从磁盘重新打开（而非命中工厂缓存的同一实例）。
    await NovelContentDatabase.closeAllCached();
    createdPaths.add(absolute);
    return absolute;
  }

  // 用户场景（升级覆盖安装）：DB 里 content_database_path 存的是相对路径。
  // 期望：工厂 resolve 相对当前根 → 打开已存在的内容库（读到 seed 的 1 个 outline）。
  patrolTest('content database stored as a relative path opens the same file', (
    $,
  ) async {
    await seedContentDb('rel-novel.sqlite');
    const stored = 'novel_workspaces/rel-novel.sqlite';

    final reopened = NovelContentDatabase(stored);
    addTearDown(NovelContentDatabase.closeAllCached);

    // 工厂 resolve 相对当前根 → 打开 seed 过的物理文件，而非新建空库（空库 outline 数为 0）。
    expect(await reopened.select(reopened.outlines).get(), hasLength(1));
  });

  // 用户场景（备份恢复 / 换机）：DB 残留旧容器绝对路径，文件已随容器搬到新根。
  // 期望：工厂抠出 novel_workspaces 段重锚到当前根 → 打开已存在的内容库。
  patrolTest('stale old-container content database path re-anchors and opens', (
    $,
  ) async {
    await seedContentDb('stale-novel.sqlite');
    const stored =
        '/var/mobile/Containers/Data/Application/OLD-UUID/Library/'
        'Application Support/novel_workspaces/stale-novel.sqlite';

    final reopened = NovelContentDatabase(stored);
    addTearDown(NovelContentDatabase.closeAllCached);

    expect(await reopened.select(reopened.outlines).get(), hasLength(1));
  });
}

// Image.file(..., cacheWidth:) 会把 FileImage 包进 ResizeImage（真机渲染时生效），
// 解包拿到底层 FileImage 再断言路径。
FileImage _fileImageOf(Image image) {
  final provider = image.image;
  return (provider is ResizeImage ? provider.imageProvider : provider)
      as FileImage;
}

void _setDesktopSurface(PatrolIntegrationTester $, Size size) {
  $.tester.view.devicePixelRatio = 1.0;
  $.tester.view.physicalSize = size;
  addTearDown(() {
    $.tester.view.resetPhysicalSize();
    $.tester.view.resetDevicePixelRatio();
  });
}

Widget _harness(Widget child) {
  return MaterialApp(
    theme: RevericThemeData.reveric.toThemeData(),
    home: RevericTheme(
      data: RevericThemeData.reveric,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}
