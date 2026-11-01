// 职责: 验证 [showConfirmDialog] 返回值、variant 着色与 onConfirm 回调。
// 关联文件:
//   lib/shared/widgets/confirm_dialog.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:easy_localization/easy_localization.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/confirm_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('showConfirmDialog confirm, cancel, variant, and onConfirm', (
    tester,
  ) async {
    var deleteConfirmed = false;
    var callbackRan = false;
    var warningConfirmed = true;

    await tester.pumpWidget(
      _wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              key: const Key('open-delete'),
              onPressed: () async {
                deleteConfirmed = await showConfirmDialog(
                  tester.element(find.byKey(const Key('open-delete'))),
                  title: 'Delete item?',
                  message: 'This cannot be undone.',
                  confirmLabel: 'Delete',
                  variant: ConfirmDialogVariant.error,
                  onConfirm: () async {
                    callbackRan = true;
                  },
                );
              },
              child: const Text('Open delete'),
            ),
            FilledButton(
              key: const Key('open-warning'),
              onPressed: () async {
                warningConfirmed = await showConfirmDialog(
                  tester.element(find.byKey(const Key('open-warning'))),
                  title: 'Proceed?',
                  message: 'Continue?',
                  variant: ConfirmDialogVariant.warning,
                );
              },
              child: const Text('Open warning'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open delete'));
    await tester.pumpAndSettle();

    final colors = RevericTheme.colorsOf(tester.element(find.text('Delete')));
    final deleteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete'),
    );
    expect(
      deleteButton.style?.backgroundColor?.resolve({}),
      colors.deletionBorder,
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleteConfirmed, isTrue);
    expect(callbackRan, isTrue);

    await tester.tap(find.text('Open warning'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(warningConfirmed, isFalse);
  });

  testWidgets('pending confirmation cannot be submitted or dismissed twice', (
    tester,
  ) async {
    final done = Completer<void>();
    var calls = 0;
    bool? result;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showConfirmDialog(
                context,
                title: 'Delete',
                message: 'This cannot be undone.',
                confirmLabel: 'Delete',
                onConfirm: () {
                  calls += 1;
                  return done.future;
                },
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    expect(calls, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ConfirmDialog), findsOneWidget);
    expect(result, isNull);
    done.complete();
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(ConfirmDialog), findsNothing);
  });

  testWidgets('blockedReason disables confirm and shows the reason', (
    tester,
  ) async {
    final check = Completer<String?>();
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showConfirmDialog(
              context,
              title: 'Delete',
              message: 'This cannot be undone.',
              confirmLabel: 'Delete',
              variant: ConfirmDialogVariant.error,
              blockedReason: check.future,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    FilledButton deleteButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete'),
    );
    expect(deleteButton().onPressed, isNull);

    check.complete('Still used by scene 1');
    await tester.pumpAndSettle();
    expect(find.text('Still used by scene 1'), findsOneWidget);
    expect(deleteButton().onPressed, isNull);
  });
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
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(body: Center(child: child)),
          ),
        );
      },
    ),
  );
}
