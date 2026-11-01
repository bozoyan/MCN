// 职责: 验证共享按钮的加载布局、点击与键盘禁用、主题继承及跨平台触控目标。
// 关联文件:
//   lib/shared/components/reveric_button.dart
//   lib/shared/theme/reveric_theme.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/reveric_button.dart';
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
  for (final data in [
    RevericThemeData.reveric,
    RevericThemeData.revericDark,
    RevericThemeData.reveric,
    RevericThemeData.revericDark,
  ]) {
    testWidgets(
      'danger text has readable contrast in ${data.colors.deletionBorder} / ${data.brightness}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: data.toThemeData(),
            home: RevericTheme(
              data: data,
              child: Scaffold(
                body: RevericButton.danger(label: 'Delete', onPressed: () {}),
              ),
            ),
          ),
        );
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        final background = button.style!.backgroundColor!
            .resolve({})!
            .computeLuminance();
        final foreground = button.style!.foregroundColor!
            .resolve({})!
            .computeLuminance();
        final ratio = foreground > background
            ? (foreground + 0.05) / (background + 0.05)
            : (background + 0.05) / (foreground + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      },
    );
  }

  for (final icon in [null, RevericIcons.arrows_clockwise]) {
    testWidgets('loading keeps bounds and blocks repeated input (icon=$icon)', (
      tester,
    ) async {
      final busy = ValueNotifier(false);
      addTearDown(busy.dispose);
      var calls = 0;
      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder(
            valueListenable: busy,
            builder: (context, loading, _) => RevericButton.secondary(
              label: 'Check for Updates',
              icon: icon,
              loading: loading,
              onPressed: () {
                calls++;
                busy.value = true;
              },
            ),
          ),
        ),
      );
      final button = find.byType(OutlinedButton);
      final before = tester.getRect(button);
      final labelBefore = tester.getRect(find.text('Check for Updates'));
      if (icon == null) {
        // Plain buttons only hug their label; no idle space is reserved.
        expect(
          before.width,
          labelBefore.width + RevericSizes.buttonPaddingH * 2,
        );
      }
      await tester.tap(button);
      await tester.pump();
      expect(tester.getRect(button), before);
      expect(tester.getRect(find.text('Check for Updates')), labelBefore);
      expect(find.text('Check for Updates'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      await tester.tap(button);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, 1);
      busy.value = false;
      await tester.pumpAndSettle();
      expect(tester.getRect(button), before);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(button);
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('standard buttons retain native keyboard and hover interaction', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(RevericButton.primary(label: 'Save', onPressed: () => calls++)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, 1);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      'compact target is usable on $platform with large localized text',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var calls = 0;
        await tester.pumpWidget(
          _wrap(
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    RevericButton.secondary(
                      label: '检查更新',
                      icon: RevericIcons.arrows_clockwise,
                      size: RevericButtonSize.compact,
                      onPressed: () => calls++,
                    ),
                    RevericButton.secondary(
                      label: 'Browse worldbuilding settings and outlines',
                      icon: RevericIcons.book_open,
                      size: RevericButtonSize.compact,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
            platform: platform,
          ),
        );
        final button = find.byType(OutlinedButton).first;
        final rect = tester.getRect(button);
        expect(
          rect.height,
          greaterThanOrEqualTo(platform == TargetPlatform.macOS ? 32 : 48),
        );
        // Check the edge of the reserved hit region, not only the text itself.
        await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    testWidgets('size tiers resolve the agreed heights on $platform', (
      tester,
    ) async {
      final mobile = platform == TargetPlatform.android;
      await tester.pumpWidget(
        _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericButton.primary(label: 'Standard', onPressed: () {}),
              RevericButton.primary(
                label: 'Prominent',
                size: RevericButtonSize.prominent,
                onPressed: () {},
              ),
              RevericButton.primary(
                label: 'Compact',
                size: RevericButtonSize.compact,
                onPressed: () {},
              ),
            ],
          ),
          platform: platform,
        ),
      );
      // 移动端外层有 48px padded 触控区，量 Material 本体才是可见高度。
      double height(String label) => tester
          .getSize(
            find.descendant(
              of: find.widgetWithText(FilledButton, label),
              matching: find.byType(Material),
            ),
          )
          .height;
      expect(
        height('Standard'),
        mobile ? RevericSizes.buttonHeight : RevericSizes.buttonHeightDesktop,
      );
      expect(height('Prominent'), RevericSizes.buttonHeight);
      expect(height('Compact'), RevericSizes.buttonHeightSm);
    });
  }

  testWidgets(
    'semantic variants inherit the current theme and expose disabled state',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericButton.primary(label: 'Primary', onPressed: () {}),
              const RevericButton.secondary(
                label: 'Secondary',
                onPressed: null,
              ),
              RevericButton.text(label: 'Text', onPressed: () {}),
              RevericButton.danger(label: 'Delete', onPressed: () {}),
            ],
          ),
        ),
      );
      final primary = find.widgetWithText(FilledButton, 'Primary');
      final theme = Theme.of(tester.element(primary));
      final text = tester.element(find.text('Primary'));
      expect(
        DefaultTextStyle.of(text).style.color,
        theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
      );
      final danger = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete'),
      );
      expect(
        danger.style!.backgroundColor!.resolve({}),
        RevericThemeData.reveric.colors.deletionBorder,
      );
      expect(
        tester.getSemantics(find.widgetWithText(OutlinedButton, 'Secondary')),
        matchesSemantics(
          label: 'Secondary',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasFocusAction: false,
        ),
      );
      semantics.dispose();
    },
  );
}
