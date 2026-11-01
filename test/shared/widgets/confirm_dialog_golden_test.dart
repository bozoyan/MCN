// 职责: 验证通用确认弹窗在桌面、窄屏、明暗主题和大字号下的实际排版。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/confirm_dialog.dart';

RevericTypography _withTestFont(RevericTypography source) {
  return RevericTypography(
    display: source.display.copyWith(fontFamily: 'DialogTest'),
    heading2: source.heading2.copyWith(fontFamily: 'DialogTest'),
    body: source.body.copyWith(fontFamily: 'DialogTest'),
    bodySmall: source.bodySmall.copyWith(fontFamily: 'DialogTest'),
    bodyItalic: source.bodyItalic.copyWith(fontFamily: 'DialogTest'),
    ui: source.ui.copyWith(fontFamily: 'DialogTest'),
    uiMedium: source.uiMedium.copyWith(fontFamily: 'DialogTest'),
    uiSemibold: source.uiSemibold.copyWith(fontFamily: 'DialogTest'),
    uiSmall: source.uiSmall.copyWith(fontFamily: 'DialogTest'),
    uiSmallSemibold: source.uiSmallSemibold.copyWith(fontFamily: 'DialogTest'),
    uiTiny: source.uiTiny.copyWith(fontFamily: 'DialogTest'),
    uiTinySemibold: source.uiTinySemibold.copyWith(fontFamily: 'DialogTest'),
    mono: source.mono.copyWith(fontFamily: 'DialogTest'),
  );
}

void main() {
  setUpAll(() async {
    final font = FontLoader('DialogTest');
    font.addFont(rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf'));
    await font.load();
  });

  for (final mobile in [false, true]) {
    for (final dark in [false, true]) {
      final name =
          '${mobile ? 'mobile' : 'desktop'}_${dark ? 'dark' : 'light'}';
      testWidgets('delete dialog $name', (tester) async {
        tester.view.physicalSize = Size(mobile ? 375 : 640, mobile ? 667 : 360);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final data =
            (dark ? RevericThemeData.revericDark : RevericThemeData.reveric)
                .copyWith(
                  typography: _withTestFont(
                    mobile
                        ? RevericTypography.mobile
                        : RevericTypography.desktop,
                  ),
                );
        await tester.pumpWidget(
          _wrap(
            data,
            mobile,
            const ConfirmDialog(
              title: '删除',
              message: '删除后无法恢复。',
              confirmLabel: '删除',
              cancelLabel: '取消',
              variant: ConfirmDialogVariant.error,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final surface = find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Material),
            )
            .first;
        final width = tester.getSize(surface).width;
        expect(width, lessThanOrEqualTo(mobile ? 327 : 420));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('capture')),
          matchesGoldenFile('goldens/confirm_dialog_$name.png'),
        );
      });
    }
  }

  testWidgets('long content and large text fit a narrow short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = RevericThemeData.reveric.copyWith(
      typography: RevericTypography.mobile,
    );
    await tester.pumpWidget(
      _wrap(
        data,
        true,
        MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 480),
            textScaler: TextScaler.linear(2),
          ),
          child: ConfirmDialog(
            title: 'Delete selected documents',
            message: List.filled(
              12,
              'These records cannot be recovered after deletion.',
            ).join('\n'),
            confirmLabel: 'Delete permanently',
            cancelLabel: 'Keep records',
            variant: ConfirmDialogVariant.error,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.widgetWithText(FilledButton, 'Delete permanently').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Keep records').hitTestable(),
      findsOneWidget,
    );
  });
}

Widget _wrap(RevericThemeData data, bool mobile, Widget child) {
  return RepaintBoundary(
    key: const ValueKey('capture'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: data
          .toThemeData(fontFamily: 'DialogTest')
          .copyWith(
            platform: mobile ? TargetPlatform.android : TargetPlatform.macOS,
          ),
      home: RevericTheme(
        data: data,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}
