// 职责: 验证弹窗提示的局部范围、语义分档、替换与关闭生命周期。
// 关联文件:
//   lib/shared/components/dialog_feedback.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/components/dialog_feedback.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    rootBundle.clear();
  });

  testWidgets('intrinsic dialog keeps its size and form remains interactive', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DialogFeedback.scope(
                builder: (context) => AlertDialog(
                  title: const Text('Title'),
                  content: DialogFeedback.surface(
                    key: const ValueKey('surface'),
                    builder: (_) => SizedBox(
                      width: 360,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => taps++,
                            child: const Text('Edit'),
                          ),
                          const SizedBox(height: 160),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Local message'),
                              showCloseIcon: true,
                            ),
                          ),
                      child: const Text('Notify'),
                    ),
                    TextButton(
                      onPressed: () {
                        final host = DialogFeedback.hostMessengerOf(context);
                        Navigator.of(context).pop();
                        host.showSnackBar(
                          const SnackBar(content: Text('Saved on page')),
                        );
                      },
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final contentRect = tester.getRect(find.byKey(const ValueKey('surface')));
    await tester.tap(find.text('Edit'));
    expect(taps, 1);
    await tester.tap(find.text('Notify'));
    await tester.pumpAndSettle();
    expect(find.text('Local message'), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('surface'))), contentRect);
    expect(contentRect.contains(tester.getCenter(_pill)), isTrue);
    await tester.tap(find.text('Edit'));
    expect(taps, 2);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Saved on page'), findsOneWidget);
    expect(find.text('Title'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scopes, styles, replaces and disposes dialog feedback', (
    tester,
  ) async {
    var sequence = 0;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: SizedBox(
                  width: 400,
                  height: 300,
                  child: DialogFeedback(
                    builder: (context) => Column(
                      children: [
                        TextButton(
                          onPressed: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('message ${++sequence}'),
                                ),
                              ),
                          child: const Text('Notify'),
                        ),
                        TextButton(
                          onPressed: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  showCloseIcon: true,
                                  content: DialogToast(
                                    variant: DialogToastVariant.error,
                                    child: Text('failed'),
                                  ),
                                ),
                              ),
                          child: const Text('Fail'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close dialog'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final dialogRect = tester.getRect(find.byType(DialogFeedback));

    // 中性档：落在 dialog 内、不超过 toast 最大宽度、无关闭按钮。
    await tester.tap(find.text('Notify'));
    await tester.pumpAndSettle();
    expect(find.text('message 1'), findsOneWidget);
    final snackRect = tester.getRect(find.byType(SnackBar));
    expect(dialogRect.intersect(snackRect), snackRect);
    expect(
      tester.getSize(_pill).width,
      lessThanOrEqualTo(RevericSizes.toastMaxWidth),
    );
    expect(_icon(RevericIcons.info), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing);

    // 新提示替换旧提示，不叠加。
    await tester.tap(find.text('Notify'));
    await tester.pumpAndSettle();
    expect(find.text('message 1'), findsNothing);
    expect(find.text('message 2'), findsOneWidget);

    // error 档换图标；showCloseIcon 透传后由自绘按钮承接。
    await tester.tap(find.text('Fail'));
    await tester.pumpAndSettle();
    expect(find.text('failed'), findsOneWidget);
    expect(_icon(RevericIcons.info), findsNothing);
    expect(_icon(RevericIcons.warning_circle), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    // 关掉 dialog 时提示随局部 messenger 一起销毁，重开不残留。
    await tester.tap(find.text('Notify'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close dialog'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// toast 自绘的 pill 容器 —— SnackBar 内唯一带 BoxDecoration 的 Container。
final _pill = find.descendant(
  of: find.byType(SnackBar),
  matching: find.byWidgetPredicate(
    (widget) => widget is Container && widget.decoration is BoxDecoration,
  ),
);

Finder _icon(String assetPath) => find.descendant(
  of: find.byType(SnackBar),
  matching: find.byWidgetPredicate(
    (widget) => widget is RevericIcon && widget.assetPath == assetPath,
  ),
);

Widget _wrap(Widget child) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          // 和 main.dart 一致挂在 builder 上：dialog 走 Navigator，
          // 挂在 home 里的话弹窗子树看不到 RevericTheme。
          builder: (context, navigator) => RevericTheme(
            data: RevericThemeData.reveric,
            child: navigator!,
          ),
          home: Scaffold(body: child),
        );
      },
    ),
  );
}
