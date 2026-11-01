// 职责: 当前进展面板就地编辑态黄金图（加载真实字体），人工目检 Markdown 编辑器与操作行的排版。
// 关联文件:
//   lib/shared/widgets/story_progress_panel.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/providers/novel_providers.dart

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/story_progress_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _path = 'story-progress-edit-golden';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 编辑器读设置会在建树时打开 AppDatabase，需要给 path_provider 兜底目录。
    final tempDir = await Directory.systemTemp.createTemp('story-progress-');
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
    await _loadFont('LXGWWenKai', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Georgia', 'assets/fonts/LXGWWenKai-Regular.ttf');
  });

  testWidgets('当前进展面板就地编辑态黄金图', (tester) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final snapshot = NovelStateSnapshot(
      id: 'snap_1',
      content:
          '【全书状态快照】\n\n'
          '主角顾长戈：帝都顾家废少，16 岁，天赋尽废，父亲失势被夺爵。\n'
          '打脸升级系统刚觉醒。\n\n'
          'CRUD 测试完成，所有功能正常。',
      status: novelStateSnapshotStatusActive,
      createdBy: novelStateSnapshotCreatedByChronicler,
      createdAt: DateTime.utc(2026, 8, 30),
    );

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh', 'CN')],
        path: 'assets/translations',
        assetLoader: const MergingAssetLoader(),
        fallbackLocale: const Locale('zh', 'CN'),
        startLocale: const Locale('zh', 'CN'),
        child: Builder(
          builder: (context) {
            return ProviderScope(
              overrides: [
                currentStateSnapshotProvider(
                  _path,
                ).overrideWith((ref) => Stream.value(snapshot)),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                // 显式给 UI 字体：默认走平台字体，测试环境里会渲染成方块。
                theme: RevericThemeData.reveric.toThemeData(
                  fontFamily: 'LXGWWenKai',
                ),
                home: RevericTheme(
                  data: RevericThemeData.reveric,
                  child: const Scaffold(
                    body: StoryProgressPanel(databasePath: _path, chapters: []),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑当前状态'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(StoryProgressPanel),
      matchesGoldenFile('goldens/story_progress_edit.png'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
