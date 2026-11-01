// 职责: 验证分段选择的键盘与选中语义，以及占位组件的跨平台布局和操作边界。
// 关联文件:
//   lib/shared/components/reveric_segmented_control.dart
//   lib/shared/components/reveric_placeholder.dart
//   lib/shared/components/reveric_button.dart
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_button.dart';
import 'package:reveric/shared/components/reveric_placeholder.dart';
import 'package:reveric/shared/components/reveric_segmented_control.dart';
import 'package:reveric/shared/theme/theme.dart';

Widget _wrap(
  Widget child, {
  bool mobile = false,
  bool dark = false,
  TextDirection direction = TextDirection.ltr,
}) {
  final data = dark ? RevericThemeData.revericDark : RevericThemeData.reveric;
  return MaterialApp(
    theme: data.toThemeData().copyWith(
      platform: mobile ? TargetPlatform.android : TargetPlatform.macOS,
    ),
    home: RevericTheme(
      data: data,
      child: Scaffold(
        body: Directionality(
          textDirection: direction,
          child: Center(child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('short badge leaves enough width for a fitting label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 340,
          child: RevericSegmentedControl<int>(
            selected: 0,
            onChanged: (_) {},
            segments: const [
              RevericSegment(
                value: 0,
                label: 'History',
                icon: RevericIcons.history_outlined,
                badgeLabel: '99+',
              ),
              RevericSegment(value: 1, label: 'Current'),
            ],
          ),
        ),
        mobile: true,
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('History'),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard selects exactly one option and reports its value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final value = ValueNotifier(1);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 260,
            child: ValueListenableBuilder(
              valueListenable: value,
              builder: (context, selected, _) => RevericSegmentedControl<int>(
                segments: const [
                  RevericSegment(value: 0, label: 'Manual'),
                  RevericSegment(
                    value: 1,
                    label: 'Automatic',
                    badgeLabel: '12',
                  ),
                ],
                selected: selected,
                onChanged: (next) => value.value = next,
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Automatic 12'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(value.value, 0);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Manual'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Automatic 12'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      await tester.tap(find.text('Automatic'));
      await tester.pumpAndSettle();
      expect(value.value, 1);
    } finally {
      semantics.dispose();
    }
  });

  for (final mobile in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'narrow long labels, badges and placeholders mobile=$mobile dark=$dark',
        (tester) async {
          var retries = 0;
          await tester.pumpWidget(
            _wrap(
              SizedBox(
                width: 240,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RevericSegmentedControl<int>(
                      selected: 0,
                      onChanged: (_) {},
                      segments: const [
                        RevericSegment(
                          value: 0,
                          label: 'Very long option label',
                          icon: RevericIcons.clock,
                          badgeLabel: '123456',
                        ),
                        RevericSegment(
                          value: 1,
                          label: '另一个较长的选项',
                          badgeLabel: '999',
                        ),
                      ],
                    ),
                    RevericPlaceholder.error(
                      title: 'Could not load the list',
                      description:
                          'A longer explanation that should wrap within a narrow mobile content area.',
                      action: RevericButton.secondary(
                        label: 'Retry',
                        onPressed: () => retries++,
                      ),
                    ),
                  ],
                ),
              ),
              mobile: mobile,
              dark: dark,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final option = find
              .descendant(
                of: find.byType(RevericSegmentedControl<int>),
                matching: find.byType(InkWell),
              )
              .first;
          expect(
            tester.getSize(option).height,
            greaterThanOrEqualTo(mobile ? 48 : 34),
          );
          await tester.tap(find.text('Retry'));
          expect(retries, 1);
        },
      );
    }
  }

  testWidgets('single option and RTL preserve indicator position', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 240,
          child: RevericSegmentedControl<int>(
            segments: const [RevericSegment(value: 0, label: 'Only')],
            selected: 0,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 240,
          child: RevericSegmentedControl<int>(
            segments: const [
              RevericSegment(value: 0, label: 'First'),
              RevericSegment(value: 1, label: 'Second'),
            ],
            selected: 0,
            onChanged: (_) {},
          ),
        ),
        direction: TextDirection.rtl,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byType(FractionallySizedBox)).dx,
      closeTo(tester.getCenter(find.text('First')).dx, 1),
    );
  });

  testWidgets('invalid selected value fails explicitly', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 240,
          child: RevericSegmentedControl<int>(
            segments: const [RevericSegment(value: 0, label: 'Only')],
            selected: 1,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isAssertionError);
  });

  testWidgets('empty state without optional content has no action spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const RevericPlaceholder.empty(
          icon: RevericIcons.account_tree,
          title: 'No documents',
        ),
      ),
    );
    final titleBottom = tester.getBottomLeft(find.text('No documents')).dy;
    final bottom = tester.getBottomLeft(find.byType(RevericPlaceholder)).dy;
    expect(bottom - titleBottom, RevericSpacing.x4l);
    expect(find.byType(RevericButton), findsNothing);
  });
}
