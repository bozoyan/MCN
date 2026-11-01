// 职责: 验证标准图标按钮、筛选项、徽标和下拉选择的键盘操作、语义及平台布局边界。
// 关联文件:
//   lib/shared/components/reveric_icon_button.dart
//   lib/shared/components/reveric_filter_chip.dart
//   lib/shared/components/reveric_badge.dart
//   lib/shared/components/reveric_select.dart
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_badge.dart';
import 'package:reveric/shared/components/reveric_filter_chip.dart';
import 'package:reveric/shared/components/reveric_icon_button.dart';
import 'package:reveric/shared/components/reveric_select.dart';
import 'package:reveric/shared/theme/theme.dart';

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

void main() {
  testWidgets('icon action supports keyboard, label and disabled feedback', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var calls = 0;
      await tester.pumpWidget(
        _wrap(
          RevericIconButton(
            icon: RevericIcons.undo,
            tooltip: 'Undo',
            onPressed: () => calls++,
          ),
        ),
      );
      final node = tester.getSemantics(find.byType(IconButton));
      expect(node.getSemanticsData().tooltip, 'Undo');
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(
        node.getSemanticsData().flagsCollection.isEnabled,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, 1);
      await tester.pumpWidget(
        _wrap(
          const RevericIconButton(
            icon: RevericIcons.undo,
            tooltip: 'Undo',
            onPressed: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, 1);
      final context = tester.element(find.byType(RevericIcon));
      expect(
        IconTheme.of(context).color,
        RevericThemeData.reveric.colors.textSubtle,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('filter keeps optional counts and exposes keyboard selection', (
    tester,
  ) async {
    final selected = ValueNotifier(false);
    addTearDown(selected.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder(
            valueListenable: selected,
            builder: (context, value, _) => RevericFilterChip(
              label: 'Characters',
              count: 0,
              selected: value,
              onTap: () => selected.value = !value,
            ),
          ),
        ),
      );
      expect(find.text('Characters 0'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(selected.value, isTrue);
      expect(
        tester
            .getSemantics(find.byType(FilterChip))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      await tester.pumpWidget(
        _wrap(
          const RevericFilterChip(
            label: 'Characters',
            selected: true,
            onTap: null,
          ),
        ),
      );
      await tester.tap(find.byType(FilterChip));
      expect(find.text('Characters'), findsOneWidget);
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).onSelected,
        isNull,
      );
    } finally {
      semantics.dispose();
    }
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets('controls retain platform hit targets on $platform', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericIconButton(
                icon: RevericIcons.add,
                tooltip: 'Add',
                onPressed: () => presses++,
              ),
              RevericFilterChip(
                label: 'All',
                selected: false,
                onTap: () => presses++,
              ),
            ],
          ),
          platform: platform,
        ),
      );
      final icon = tester.getRect(find.byType(RevericIconButton));
      final chip = tester.getRect(find.byType(RevericFilterChip));
      if (platform == TargetPlatform.macOS) {
        expect(icon.size, const Size(32, 32));
      } else {
        expect(icon.width, greaterThanOrEqualTo(48));
        expect(icon.height, greaterThanOrEqualTo(48));
        expect(chip.height, greaterThanOrEqualTo(48));
      }
      await tester.tapAt(icon.topLeft + const Offset(2, 2));
      await tester.tapAt(chip.topCenter + const Offset(0, 2));
      expect(presses, 2);
    });
  }

  testWidgets('badge truncates visually but keeps full accessible status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      const label = '等待处理 Waiting for processing';
      await tester.pumpWidget(
        _wrap(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SizedBox(
              width: 100,
              child: RevericBadge(
                label: label,
                color: RevericThemeData.reveric.colors.warningText,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(tester.getSize(find.byType(RevericBadge)).width, 100);
      await tester.longPress(find.byType(RevericBadge));
      await tester.pumpAndSettle();
      expect(find.text(label), findsNWidgets(2));
    } finally {
      semantics.dispose();
    }
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      'select shows notice on trigger, highlights in menu and closes before '
      'footer action '
      'on $platform',
      (tester) async {
        var footerTaps = 0;
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              width: 180,
              child: RevericSelect<String>(
                value: 'a',
                menuWidth: 240,
                items: const [
                  RevericSelectItem(
                    value: 'a',
                    label: 'model-a',
                    subtitle: 'Provider',
                    badges: Tooltip(message: 'tip', child: Text('tag')),
                    notice: Text('notice'),
                  ),
                ],
                onChanged: (_) {},
                footerAction: (label: 'Add Model', onTap: () => footerTaps++),
              ),
            ),
            platform: platform,
          ),
        );
        expect(find.text('tag'), findsNothing);
        expect(find.text('notice'), findsOneWidget);
        await tester.tap(find.text('model-a'));
        await tester.pumpAndSettle();
        expect(find.text('tag'), findsOneWidget);
        expect(find.text('notice'), findsNWidgets(2));
        // 菜单内的 Tooltip 需要 layout 阶段的绝对位置，悬停不得抛异常。
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('tag')));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(find.text('tip'), findsOneWidget);
        // 未设 dropUp 时菜单贴在触发器下方。
        expect(
          tester.getTopLeft(find.text('model-a').last).dy,
          greaterThan(tester.getBottomLeft(find.text('model-a').first).dy),
        );
        await tester.tap(find.text('Add Model'));
        await tester.pumpAndSettle();
        expect(footerTaps, 1);
        expect(find.text('Add Model'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
