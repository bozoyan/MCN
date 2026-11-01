// 职责: 测试全局大纲对比板按起始章节锚定卡片、跨大纲同章节对齐（不同节拍序号亦对齐），并等高可读。
// 关联文件:
//   lib/desktop/widgets/workspace/outline_global_view.dart
//   lib/shared/models/outline.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/workspace/outline_global_view.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/outline.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('aligns beats across outlines exactly by start chapter', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapTimeline(
        SizedBox(
          width: 1200,
          height: 800,
          // 主线（章节最多 → 作为刻度基准）: 4×5 章 → 节拍起始 1/6/11/16 章。
          // 感情线: 2×10 章 → 节拍起始 1/11 章。
          // 两条线「第 11 章」的节拍分别是主线第 3 拍、感情线第 2 拍（序号不同），
          // 只有按起始章节锚定（而非按行号）时两者顶部才会重合。
          // 暗线从第 6 章开始，它的第一拍应与主线第二拍对齐。
          child: AllOutlinesArchitectureView(
            outlines: [
              _outline(
                title: '主线',
                beats: [
                  for (var index = 0; index < 4; index++)
                    _beat(index: index, title: 'Main $index', chapters: 5),
                ],
              ),
              _outline(
                title: '感情线',
                beats: [
                  _beat(index: 0, title: 'Side 0', chapters: 10),
                  _beat(index: 1, title: 'Side 1', chapters: 10),
                ],
              ),
              _outline(
                title: '暗线',
                startChapterNum: 6,
                beats: [_beat(index: 0, title: 'Hidden 0', chapters: 5)],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('主线'), findsOneWidget);
    expect(find.text('感情线'), findsOneWidget);

    // 等高卡片始终展示标题；Tooltip 承载完整信息。
    expect(find.text('Main 0'), findsOneWidget);
    expect(find.text('Side 0'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) {
        return widget is Tooltip && (widget.message ?? '').startsWith('Main 0');
      }),
      findsOneWidget,
    );

    // 都从第 1 章开始 → 顶部对齐。
    expect(
      _topOf(tester, 'global-beat-0-0'),
      closeTo(_topOf(tester, 'global-beat-1-0'), 0.5),
    );
    // 都从第 11 章开始（主线第 3 拍 vs 感情线第 2 拍，序号不同）→ 顶部对齐。
    expect(
      _topOf(tester, 'global-beat-0-2'),
      closeTo(_topOf(tester, 'global-beat-1-1'), 0.5),
    );
    expect(
      _topOf(tester, 'global-beat-0-1'),
      closeTo(_topOf(tester, 'global-beat-2-0'), 0.5),
    );
  });
}

double _topOf(WidgetTester tester, String key) {
  return tester.getTopLeft(find.byKey(ValueKey(key))).dy;
}

Widget _wrapTimeline(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('zh', 'CN'),
    startLocale: const Locale('zh', 'CN'),
    child: Builder(
      builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(body: child),
          ),
        );
      },
    ),
  );
}

OutlineDraft _outline({
  required String title,
  required List<OutlineBeatDraft> beats,
  int startChapterNum = 1,
}) {
  final now = DateTime(2026);
  return OutlineDraft(
    documentId: title,
    title: title,
    startChapterNum: startChapterNum,
    beats: beats,
    createdAt: now,
    updatedAt: now,
    deletedAt: now,
  );
}

OutlineBeatDraft _beat({
  required int index,
  required String title,
  required int chapters,
}) {
  return OutlineBeatDraft(
    id: 'beat_$index',
    title: title,
    chapterCount: chapters,
    sortOrder: index,
  );
}
