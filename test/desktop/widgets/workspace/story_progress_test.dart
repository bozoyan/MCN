// 职责: 测试章内事件卡片与当前进展面板的渲染与空态降级。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/shared/widgets/story_progress_panel.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/workspace.json
// 遵循的 Rules:
//   .agents/rules/i18n.md
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/workspace/chapter_editor.dart';
import 'package:reveric/shared/components/horizontal_wheel_scroll.dart';
import 'package:reveric/shared/widgets/story_progress_panel.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/md/reveric_markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  TargetPlatform platform = TargetPlatform.macOS,
}) {
  return EasyLocalization(
    key: UniqueKey(),
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData().copyWith(
              platform: platform,
            ),
            // 与 main.dart 一致：RevericTheme 包在 navigator 之上，
            // 这样 showDialog 弹出的对话框才能读到主题。
            builder: (context, child) {
              return RevericTheme(
                data: RevericThemeData.reveric,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: RevericTheme(
              data: RevericThemeData.reveric,
              // StoryProgressPanel 自持滚动，测试外壳只提供有界视口。
              child: Scaffold(body: child),
            ),
          ),
        );
      },
    ),
  );
}

Chapter _chapter({
  required String id,
  required int chapterNum,
  int? tension,
  List<String>? emotion,
}) {
  final now = DateTime.now();
  return Chapter(
    id: id,
    type: nodeTypeChapter,
    siblingOrder: chapterNum,
    title: '第 $chapterNum 章',
    chapterNum: chapterNum,
    tension: tension,
    emotion: emotion,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

void main() {
  setUp(() => rootBundle.clear());

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('chapter events card renders items and hides when empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ChapterEventsCard(
          events: [
            {
              'title': '密室交易',
              'summary': '林越换回卖身契',
              'state_change': '假印信落在对方手里',
            },
            {'title': '追兵入城', 'summary': '巡夜人封锁北门'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本章事件'), findsOneWidget);
    // 事件列表默认折叠，点开后再断言条目。
    await tester.tap(find.text('本章事件'));
    await tester.pumpAndSettle();
    expect(find.text('密室交易'), findsOneWidget);
    expect(find.text('林越换回卖身契'), findsOneWidget);
    expect(find.text('假印信落在对方手里'), findsOneWidget);
    expect(find.text('追兵入城'), findsOneWidget);
    // 只有第一条给了 state_change，标签就该只出现一次。
    expect(find.text('状态变化：'), findsOneWidget);

    // 空数组：整卡片不渲染，不留占位。
    await tester.pumpWidget(_wrap(const ChapterEventsCard(events: [])));
    await tester.pumpAndSettle();
    expect(find.text('本章事件'), findsNothing);

    // null（旧章节从未提取过）同样不渲染。
    await tester.pumpWidget(_wrap(const ChapterEventsCard(events: null)));
    await tester.pumpAndSettle();
    expect(find.text('本章事件'), findsNothing);

    const path = '/tmp/story_progress_test.sqlite';

    // 1. 没有快照也没有紧张度：显示引导空态。
    await tester.pumpWidget(
      _wrap(
        const StoryProgressPanel(databasePath: path, chapters: []),
        overrides: [
          currentStateSnapshotProvider(
            path,
          ).overrideWith((ref) => Stream.value(null)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有故事状态快照'), findsOneWidget);

    // 2. 只有四个章节有紧张度时，即使小说已有更多章节，也不足以形成趋势。
    await tester.pumpWidget(
      _wrap(
        StoryProgressPanel(
          databasePath: path,
          chapters: [
            _chapter(id: 'c1', chapterNum: 1, tension: 4, emotion: ['压抑']),
            _chapter(id: 'c2', chapterNum: 2, tension: 5),
            _chapter(id: 'c3', chapterNum: 3, tension: 6),
            _chapter(id: 'c4', chapterNum: 4, tension: 7),
            _chapter(id: 'c5', chapterNum: 5),
          ],
        ),
        overrides: [
          currentStateSnapshotProvider(
            path,
          ).overrideWith((ref) => Stream.value(null)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有故事状态快照'), findsOneWidget);
    expect(find.text('情绪张力曲线'), findsNothing);

    // 3. 至少五个章节有紧张度且还没有快照：曲线可单独查看。
    await tester.pumpWidget(
      _wrap(
        StoryProgressPanel(
          databasePath: path,
          chapters: [
            _chapter(id: 'c1', chapterNum: 1, tension: 4, emotion: ['压抑']),
            _chapter(id: 'c2', chapterNum: 2, tension: 9, emotion: ['决绝']),
            _chapter(id: 'c3', chapterNum: 3, tension: 6),
            _chapter(id: 'c4', chapterNum: 4, tension: 7),
            _chapter(id: 'c5', chapterNum: 5, tension: 8),
            // 未处理的章节没有 tension，不计入有效数据数量。
            _chapter(id: 'c6', chapterNum: 6),
          ],
        ),
        overrides: [
          currentStateSnapshotProvider(
            path,
          ).overrideWith((ref) => Stream.value(null)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有故事状态快照'), findsNothing);
    expect(find.text('情绪张力曲线'), findsOneWidget);
    expect(find.text('压抑'), findsOneWidget);
    expect(find.text('决绝'), findsOneWidget);

    // 4. 当前快照展示正文；单点曲线仍隐藏，不从正文生成章节进度标签。
    await tester.pumpWidget(
      _wrap(
        StoryProgressPanel(
          databasePath: path,
          chapters: [
            _chapter(id: 'c1', chapterNum: 1, tension: 4, emotion: ['压抑']),
            _chapter(id: 'c2', chapterNum: 2),
            _chapter(id: 'c3', chapterNum: 3),
          ],
        ),
        overrides: [
          currentStateSnapshotProvider(path).overrideWith(
            (ref) => Stream.value(
              NovelStateSnapshot(
                id: 'snap_1',
                content: '# 故事状态\n\n林越持有卖身契',
                status: novelStateSnapshotStatusActive,
                createdBy: novelStateSnapshotCreatedByChronicler,
                createdAt: DateTime.now(),
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('此快照可能已过时'), findsNothing);
    expect(find.text('截至第 1 章'), findsNothing);
    expect(find.textContaining('林越持有卖身契'), findsOneWidget);
    expect(find.text('情绪张力曲线'), findsNothing);

    // 4b. 编辑入口就地展开 Markdown 编辑器并预填快照内容；
    //     保存写库路径不在 widget 测试覆盖。
    await tester.tap(find.byTooltip('编辑当前状态'));
    await tester.pumpAndSettle();
    final editor = tester.widget<RevericMarkdownEditor>(
      find.byType(RevericMarkdownEditor),
    );
    expect(editor.controller.text, '# 故事状态\n\n林越持有卖身契');
    // 编辑态下不再重复给出编辑入口。
    expect(find.byTooltip('编辑当前状态'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(RevericMarkdownEditor), findsNothing);
    expect(find.byTooltip('编辑当前状态'), findsOneWidget);

    // 5. 几百章：自动挡按区间求均值，X 轴给区间而不是逐章刻度。
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      _wrap(
        StoryProgressPanel(
          databasePath: path,
          chapters: [
            for (var num = 1; num <= 120; num++)
              _chapter(
                id: 'c$num',
                chapterNum: num,
                tension: (num % 10) + 1,
                emotion: ['压抑'],
              ),
          ],
        ),
        overrides: [
          currentStateSnapshotProvider(
            path,
          ).overrideWith((ref) => Stream.value(null)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // 120 章 / 目标 30 点 → 阶梯落在 5。
    expect(find.text('每 5 章平均'), findsOneWidget);
    expect(find.text('1-5'), findsOneWidget);
    expect(find.text('116-120'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // 手动挡到 10 章：刻度跟着变，均值区间同步变宽。
    await tester.tap(find.text('10 章'));
    await tester.pumpAndSettle();
    expect(find.text('每 10 章平均'), findsOneWidget);
    expect(find.text('1-10'), findsOneWidget);
    expect(find.text('111-120'), findsOneWidget);
  });

  test('自动间隔随章节跨度放大，收敛到 30 个点以内', () {
    expect(autoTensionStep(0), 1);
    expect(autoTensionStep(30), 1);
    expect(autoTensionStep(31), 2);
    expect(autoTensionStep(120), 5);
    expect(autoTensionStep(300), 10);
    expect(autoTensionStep(600), 20);
    expect(autoTensionStep(1500), 50);
    // 超出最大阶梯后不再增长，宁可让曲线滚动也不无限压缩。
    expect(autoTensionStep(100000), 100);
  });

  testWidgets('snapshot draft survives scrolling away in a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const path = 'story-progress-scroll-draft';
    final snapshot = NovelStateSnapshot(
      id: 'scroll-draft',
      content: 'Original snapshot',
      status: novelStateSnapshotStatusActive,
      createdBy: novelStateSnapshotCreatedByChronicler,
      createdAt: DateTime.utc(2026, 8, 30),
    );
    await tester.pumpWidget(
      _wrap(
        StoryProgressPanel(
          databasePath: path,
          chapters: [
            for (var i = 1; i <= 120; i++)
              _chapter(id: 'draft-$i', chapterNum: i, tension: i % 10),
          ],
        ),
        overrides: [
          currentStateSnapshotProvider(
            path,
          ).overrideWith((ref) => Stream.value(snapshot)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑当前状态'));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final finder = find.byType(RevericMarkdownEditor);
    final editor = tester.widget<RevericMarkdownEditor>(finder);
    editor.controller.text = 'Unsaved snapshot draft';
    editor.focusNode.unfocus();
    await tester.pumpAndSettle();
    final state = tester.state(finder);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(state.mounted, isTrue);
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
      tester.widget<RevericMarkdownEditor>(finder).controller.text,
      'Unsaved snapshot draft',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    testWidgets(
      'narrow interval selector scrolls and restores auto on $platform',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const path = 'story-progress-intervals';
        await tester.pumpWidget(
          _wrap(
            StoryProgressPanel(
              databasePath: path,
              chapters: [
                for (var i = 1; i <= 120; i++)
                  _chapter(id: 'c$i', chapterNum: i, tension: i % 10 + 1),
              ],
            ),
            platform: platform,
            overrides: [
              currentStateSnapshotProvider(
                path,
              ).overrideWith((ref) => Stream.value(null)),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final selector = find.byType(HorizontalWheelScroll);
        final scrollable = find.descendant(
          of: selector,
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.maxScrollExtent, greaterThan(0));
        expect(find.text('每 5 章平均'), findsOneWidget);

        if (platform == TargetPlatform.macOS) {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              kind: PointerDeviceKind.mouse,
              position: tester.getCenter(selector),
              scrollDelta: const Offset(0, 500),
            ),
          );
        } else {
          await tester.drag(selector, const Offset(-500, 0));
        }
        await tester.pumpAndSettle();
        expect(position.pixels, greaterThan(0));
        await tester.tap(find.text('20 章'));
        await tester.pumpAndSettle();
        expect(find.text('每 20 章平均'), findsOneWidget);
        await tester.ensureVisible(find.text('自动'));
        await tester.tap(find.text('自动'));
        await tester.pumpAndSettle();
        expect(find.text('每 5 章平均'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
