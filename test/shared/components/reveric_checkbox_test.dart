// 职责: 验证复选框的键盘切换、禁用边界、语义标签和跨平台点击区域。
// 关联文件:
//   lib/shared/components/reveric_checkbox.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_checkbox.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  testWidgets('keyboard toggles selection and disabled input stays inert', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final enabled = ValueNotifier(true);
    final selected = ValueNotifier(false);
    addTearDown(enabled.dispose);
    addTearDown(selected.dispose);
    var calls = 0;

    await tester.pumpWidget(
      _wrap(
        ValueListenableBuilder(
          valueListenable: enabled,
          builder: (context, canChange, _) => ValueListenableBuilder(
            valueListenable: selected,
            builder: (context, value, _) => RevericCheckbox(
              value: value,
              semanticLabel: 'Chapter 1',
              onChanged: canChange
                  ? (next) {
                      calls++;
                      selected.value = next;
                    }
                  : null,
            ),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Chapter 1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(selected.value, isTrue);
    expect(calls, 1);

    await tester.tap(find.byType(RevericCheckbox));
    await tester.pumpAndSettle();
    expect(selected.value, isFalse);
    expect(calls, 2);

    enabled.value = false;
    await tester.pumpAndSettle();
    await tester.tap(find.byType(RevericCheckbox));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(selected.value, isFalse);
    expect(calls, 2);
    semantics.dispose();
  });

  testWidgets('disabled unchecked border stays visible on selected rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const RevericCheckbox(value: false, onChanged: null)),
    );
    final colors = RevericThemeData.reveric.colors;
    final side = tester.widget<Checkbox>(find.byType(Checkbox)).side!;
    final border = WidgetStateProperty.resolveAs<BorderSide?>(side, {
      WidgetState.disabled,
    })!;
    expect(border.color, colors.textSubtle);
    expect(border.color, isNot(colors.selected));
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets('target edges remain clickable on $platform', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _wrap(
          RevericCheckbox(value: false, onChanged: (_) => calls++),
          platform: platform,
        ),
      );
      final rect = tester.getRect(find.byType(RevericCheckbox));
      final minimum = platform == TargetPlatform.macOS
          ? RevericSizes.iconButtonSize
          : RevericSizes.touchTargetSize;
      expect(rect.width, greaterThanOrEqualTo(minimum));
      expect(rect.height, greaterThanOrEqualTo(minimum));
      await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _wrap(Widget child, {TargetPlatform platform = TargetPlatform.macOS}) {
  const data = RevericThemeData.reveric;
  return MaterialApp(
    theme: data.toThemeData().copyWith(platform: platform),
    home: RevericTheme(
      data: data,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}
