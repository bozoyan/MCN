// 职责: 验证 diff 视图按行审阅交互 — 双栏退回/恢复切换回调与图标状态、退回预览样式、空行不显示按钮、纯新增单栏只读无操作、锁定行禁用。
// 关联文件:
//   lib/shared/widgets/ai/diff/diff_view.dart
//   lib/shared/utils/line_accept.dart
//   lib/shared/utils/line_diff.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/diff.json
//   assets/translations/zh-CN/diff.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/diff/diff_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  // 注意：EasyLocalization 包裹的树在同进程第二个 testWidgets 中无法正确挂载
  // Navigator 内容（本环境既有问题，与业务代码无关），因此审阅交互集中在
  // 单个 testWidgets 内通过多次 pumpWidget 覆盖。
  testWidgets(
    'review mode: layouts, toggle button, preview styles and blank rule',
    (tester) async {
      final calls = <(List<String>, bool)>[];
      void onSetLinesRejected(List<String> keys, bool rejected) {
        calls.add((keys, rejected));
      }

      Widget buildView({
        required String oldText,
        required String newText,
        Set<String> rejectedLineKeys = const {},
        Set<String> lockedLineKeys = const {},
      }) {
        return _wrap(
          SizedBox(
            width: 600,
            child: AiDiffView(
              oldText: oldText,
              newText: newText,
              reviewMode: true,
              rejectedLineKeys: rejectedLineKeys,
              lockedLineKeys: lockedLineKeys,
              onSetLinesRejected: onSetLinesRejected,
            ),
          ),
        );
      }

      // 1) 删除+新增混合 → 双栏：修改行一个退回/恢复切换按钮，行键为 d:2|i:2；
      //    默认（已接受）态显示退回图标。
      await tester.pumpWidget(
        buildView(oldText: 'a\nb\nc', newText: 'a\nB\nc'),
      );
      await tester.pumpAndSettle();

      const toggleKey = ValueKey('diff-review-toggle-d:2|i:2');
      expect(find.byKey(toggleKey), findsOneWidget);
      expect(
        _iconFinder(RevericIcons.arrow_counter_clockwise),
        findsOneWidget,
      );

      await tester.tap(find.byKey(toggleKey));
      expect(calls.last.$1, ['d:2', 'i:2']);
      expect(calls.last.$2, isTrue);

      // 2) 退回态：右侧新增行划线变暗、左侧删除行恢复正常；按钮变为恢复图标，
      //    点击恢复接受。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        buildView(
          oldText: 'a\nb\nc',
          newText: 'a\nB\nc',
          rejectedLineKeys: const {'d:2', 'i:2'},
        ),
      );
      await tester.pumpAndSettle();

      final insertText = tester.widget<Text>(find.text('B'));
      expect(insertText.style?.decoration, TextDecoration.lineThrough);
      final deleteText = tester.widget<Text>(find.text('b'));
      expect(deleteText.style?.decoration, isNull);
      expect(_iconFinder(RevericIcons.arrow_clockwise), findsOneWidget);

      await tester.tap(find.byKey(toggleKey));
      expect(calls.last.$1, ['d:2', 'i:2']);
      expect(calls.last.$2, isFalse);

      // 3) 空行规则（双栏）：纯新增空白行（左空单元格 + 右空文本）不显示按钮。
      // old: [a, y, b] → new: [a, x, '', b]
      // rows: context a | (y, x) | (null, '') | context b
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        buildView(oldText: 'a\ny\nb', newText: 'a\nx\n\nb'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(toggleKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey('diff-review-toggle-i:3')),
        findsNothing,
      );

      // 4) 纯新增 → 单栏只读展示：无任何按钮，文本逐行渲染（含空白行占位）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(buildView(oldText: '', newText: 'x\n\ny'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('diff-review-toggle-i:1')),
        findsNothing,
      );
      expect(find.text('x'), findsOneWidget);
      expect(find.text('y'), findsOneWidget);

      // 5) 锁定行（已落库退回）：按钮禁用，点击不产生回调。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        buildView(
          oldText: 'a\nb\nc',
          newText: 'a\nB\nc',
          rejectedLineKeys: const {'d:2', 'i:2'},
          lockedLineKeys: const {'d:2', 'i:2'},
        ),
      );
      await tester.pumpAndSettle();

      final lockedCallCount = calls.length;
      await tester.tap(find.byKey(toggleKey));
      expect(calls.length, lockedCallCount);
    },
  );
}

Finder _iconFinder(String assetPath) {
  return find.byWidgetPredicate(
    (widget) => widget is RevericIcon && widget.assetPath == assetPath,
  );
}

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return RevericTheme(
          data: RevericThemeData.reveric,
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: Scaffold(body: Center(child: child)),
          ),
        );
      },
    ),
  );
}
