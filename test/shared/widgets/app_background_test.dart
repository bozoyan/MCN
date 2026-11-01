// 职责: 全局背景回归测试 — 验证图片背景在非铺满适配时不会露出底层窗口黑色。
// 关联文件:
//   lib/shared/widgets/app_background.dart
//   lib/shared/providers/settings_providers.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/app_background.dart';

void main() {
  testWidgets('image background paints blurred cover behind contain image', (
    tester,
  ) async {
    const theme = RevericThemeData.reveric;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackgroundImagePathProvider.overrideWithValue(
            'assets/images/background/plum_blossom.webp',
          ),
          appBackgroundFitProvider.overrideWithValue(AppBackgroundFit.contain),
          appBackgroundThemeProvider.overrideWithValue(null),
        ],
        child: RevericTheme(
          data: theme,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 300,
              height: 100,
              child: AppBackgroundLayer(),
            ),
          ),
        ),
      ),
    );

    final tint = find.byWidgetPredicate((widget) {
      return widget is ColoredBox &&
          widget.color == theme.colors.canvas.withValues(alpha: 0.18);
    });

    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(tint, findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
  });
}
