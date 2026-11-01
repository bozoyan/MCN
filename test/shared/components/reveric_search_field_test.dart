// 职责: 验证搜索框在输入、中文组词和清空时保持边框尺寸与焦点稳定，以及 debounce 变体的回调时机。
// 关联文件:
//   lib/shared/components/reveric_search_field.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/text-input-ime.md

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_search_field.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      testWidgets('stable painted search border: dark=$dark compact=$compact', (
        tester,
      ) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final theme = dark
            ? RevericThemeData.revericDark
            : RevericThemeData.reveric;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.toThemeData().copyWith(
              platform: compact ? TargetPlatform.android : TargetPlatform.macOS,
            ),
            home: RevericTheme(
              data: theme,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: compact ? 180 : 280,
                    child: RevericSearchField(
                      controller: controller,
                      hint: 'Search',
                      height: compact ? 44 : RevericSizes.fieldHeight,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final input = find.byType(TextField);
        await tester.tap(input);
        await tester.pumpAndSettle();
        final emptyBorder = _borderRect(tester);
        // 边框盒要等于声明高度，才能和同排的 RevericSelect 等高。
        expect(emptyBorder.height, compact ? 44 : RevericSizes.fieldHeight);
        final emptyField = tester.getRect(input);
        final inputState = tester.state(find.byType(EditableText));

        void expectStable() {
          // 外层 TextField 一直定高；必须测量实际绘制背景/边框的容器。
          expect(_borderRect(tester), emptyBorder);
          expect(tester.getRect(input), emptyField);
          expect(tester.state(find.byType(EditableText)), same(inputState));
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .focusNode
                .hasFocus,
            isTrue,
          );
        }

        await tester.enterText(input, '小');
        await tester.pumpAndSettle();
        expectStable();

        const composing = TextEditingValue(
          text: 'xiao',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange(start: 0, end: 4),
        );
        tester.testTextInput.updateEditingValue(composing);
        await tester.pumpAndSettle();
        expect(controller.value, composing);
        expectStable();

        await tester.enterText(input, 'A longer search query');
        await tester.pumpAndSettle();
        expectStable();
        await tester.tap(find.byType(InkWell));
        await tester.pumpAndSettle();
        expect(controller.text, isEmpty);
        expectStable();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('debounce 变体：种子值不回调，输入合并一次，清空立即生效', (tester) async {
    const debounce = Duration(milliseconds: 250);
    final emitted = <String>[];
    final theme = RevericThemeData.reveric;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.toThemeData(),
        home: RevericTheme(
          data: theme,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: RevericDebouncedSearchField(
                  hint: 'Search',
                  initialQuery: 'Seed',
                  debounce: debounce,
                  onDebouncedChanged: emitted.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 种子值只回填输入框：回调出去会把父级已有的 query 冲成 debounce 前的空值。
    await tester.pump(debounce * 2);
    expect(emitted, isEmpty);
    expect(find.text('Seed'), findsOneWidget);

    final input = find.byType(TextField);
    await tester.enterText(input, 'Ali');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(input, 'Alice ');
    await tester.pump(const Duration(milliseconds: 100));
    // 仍在 debounce 窗口内，中途输入不能外泄。
    expect(emitted, isEmpty);

    await tester.pump(debounce);
    await tester.pump();
    // 与 useDebouncedSearch 同口径：去空格 + 转小写。
    expect(emitted, ['alice']);

    await tester.tap(find.byType(InkWell));
    await tester.pump();
    // 清空不等 debounce，否则筛掉的结果会多停留 250ms。
    expect(emitted, ['alice', '']);

    await tester.pump(debounce * 2);
    expect(emitted, ['alice', '']);
    expect(tester.takeException(), isNull);
  });
}

Rect _borderRect(WidgetTester tester) {
  final container = InputDecorator.containerOf(
    tester.element(find.byType(EditableText)),
  )!;
  return container.localToGlobal(Offset.zero) & container.size;
}
