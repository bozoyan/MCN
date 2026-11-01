// 职责: 验证移动弹层的键盘与安全区布局、滚动可达性、关闭限制和嵌套返回值。
// 关联文件:
//   lib/mobile/widgets/sheet.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/mobile/widgets/sheet.dart';
import 'package:reveric/mobile/widgets/chapter_picker_sheet.dart';
import 'package:reveric/shared/models/chapter.dart';
import 'package:reveric/shared/components/reveric_button.dart';
import 'package:reveric/shared/components/reveric_text_field.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) {
  const data = RevericThemeData.reveric;
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) => MaterialApp(
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: data.toThemeData().copyWith(platform: TargetPlatform.android),
        builder: (context, child) => RevericTheme(data: data, child: child!),
        home: Scaffold(body: child),
      ),
    ),
  );
}

Widget _launcher(
  WidgetBuilder builder, {
  bool locked = false,
  bool handle = false,
  ValueChanged<int?>? onResult,
}) {
  return Builder(
    builder: (context) => TextButton(
      onPressed: () async {
        final result = await showMobileSheet<int>(
          context: context,
          builder: builder,
          isDismissible: !locked,
          enableDrag: !locked,
          showDragHandle: handle,
        );
        onResult?.call(result);
      },
      child: const Text('Open'),
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());

  for (final size in [const Size(375, 667), const Size(667, 375)]) {
    testWidgets('form stays reachable with keyboard at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
      addTearDown(tester.view.reset);
      int? saved;
      await tester.pumpWidget(
        _wrap(
          _launcher(
            (context) => MobileSheetScaffold(
              header: MobileSheetHeader.closable(
                title: 'A long configuration title',
                onClose: () => Navigator.of(context).pop(),
              ),
              footer: RevericButton.primary(
                label: 'Save',
                onPressed: () => Navigator.of(context).pop(42),
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 400),
                    const RevericTextField(
                      key: ValueKey('last-field'),
                      label: 'Name',
                    ),
                  ],
                ),
              ),
            ),
            onResult: (value) => saved = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final sheet = find.byType(MobileSheetScaffold);
      expect(
        tester.getSize(sheet).height,
        lessThanOrEqualTo(size.height * .78),
      );
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('last-field')));
      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = FakeViewPadding(
        bottom: size.height > 400 ? 300 : 140,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('last-field')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final keyboardTop = size.height - tester.view.viewInsets.bottom;
      expect(
        tester.getBottomLeft(sheet).dy,
        closeTo(keyboardTop, 0.01),
        reason:
            'Keyboard already covers the home indicator; no extra bottom inset',
      );
      expect(tester.getBottomLeft(find.text('Save')).dy, lessThan(keyboardTop));
      expect(
        tester.getBottomLeft(find.byType(TextField)).dy,
        lessThan(keyboardTop),
      );
      await tester.enterText(find.byType(TextField), 'A name');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, 42);
      expect(find.byType(BottomSheet), findsNothing);
    });
  }

  testWidgets('short menus shrink and long menus count the framework handle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final long in [false, true]) {
      await tester.pumpWidget(
        _wrap(
          _launcher(
            (context) => long
                ? ListView.builder(
                    itemCount: 80,
                    itemBuilder: (_, i) => ListTile(title: Text('Item $i')),
                  )
                : const Text('One action'),
            handle: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(tester.widget<BottomSheet>(sheet).showDragHandle, isTrue);
      expect(tester.getSize(sheet).height, lessThanOrEqualTo(667 * .78 + 1));
      if (long) {
        await tester.scrollUntilVisible(find.text('Item 79'), 300);
        expect(find.text('Item 79'), findsOneWidget);
      } else {
        expect(tester.getSize(sheet).height, lessThan(200));
      }
      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    }
  });

  testWidgets(
    'chapter picker preserves selected id, clear and cancellation results',
    (tester) async {
      tester.view.physicalSize = const Size(320, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.utc(2026);
      final results = <String?>[];
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              child: const Text('Chapters'),
              onPressed: () async => results.add(
                await showMobileChapterPickerSheet(
                  context,
                  selectedChapterId: 'one',
                  chapters: [
                    Chapter(
                      id: 'one',
                      type: nodeTypeChapter,
                      siblingOrder: 0,
                      title: 'Chapter one',
                      chapterNum: 1,
                      createdAt: now,
                      updatedAt: now,
                      deletedAt: notDeletedSentinel,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chapters'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Chapter one'));
      await tester.pumpAndSettle();
      expect(results, ['one']);
      await tester.tap(find.text('Chapters'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RevericButton));
      await tester.pumpAndSettle();
      expect(results, ['one', null]);
      await tester.tap(find.text('Chapters'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(results, ['one', null, null]);
    },
  );

  testWidgets(
    'locked sheet rejects barrier and drag but returns explicit discard',
    (tester) async {
      int? result;
      await tester.pumpWidget(
        _wrap(
          _launcher(
            (context) => MobileSheetScaffold(
              header: const MobileSheetHeader(title: 'Save new document'),
              footer: RevericButton.secondary(
                label: 'Discard',
                onPressed: () => Navigator.of(context).pop(0),
              ),
              child: const SizedBox(height: 100),
            ),
            locked: true,
            onResult: (value) => result = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(300, 20));
      await tester.drag(find.text('Save new document'), const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(result, 0);
    },
  );

  testWidgets('nested sheet returns to parent before parent completes', (
    tester,
  ) async {
    int? result;
    await tester.pumpWidget(
      _wrap(
        _launcher(
          (parentContext) => MobileSheetScaffold(
            header: const MobileSheetHeader(title: 'Parent'),
            child: TextButton(
              onPressed: () async {
                final child = await showMobileSheet<int>(
                  context: parentContext,
                  builder: (childContext) => MobileSheetScaffold(
                    header: MobileSheetHeader.closable(
                      title: 'Child',
                      onClose: () => Navigator.of(childContext).pop(),
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.of(childContext).pop(7),
                      child: const Text('Choose'),
                    ),
                  ),
                );
                if (parentContext.mounted && child != null) {
                  Navigator.of(parentContext).pop(child + 1);
                }
              },
              child: const Text('Next'),
            ),
          ),
          onResult: (value) => result = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(result, 8);
    expect(find.byType(BottomSheet), findsNothing);
  });
}
