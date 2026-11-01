// 职责: 验证桌面与移动导出表单的范围选择、校验、格式联动和外壳布局。
// 关联文件:
//   lib/desktop/widgets/novel_export_dialog.dart
//   lib/mobile/widgets/novel_export_sheet.dart
//   lib/shared/services/novel_export.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/database/app_database.dart'
    show notDeletedSentinel;
import 'package:reveric/shared/components/dialog_feedback.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/models/novel.dart';
import 'package:reveric/shared/models/novel_type.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/desktop/widgets/novel_export_dialog.dart';
import 'package:reveric/mobile/widgets/novel_export_sheet.dart';
import 'package:reveric/mobile/widgets/sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  for (final locale in [const Locale('en'), const Locale('zh', 'CN')]) {
    testWidgets('mobile export uses a scrollable sheet in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showNovelExportSheet(context, _novel()),
              child: const Text('Open export'),
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open export'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(tr(LocaleKeys.libraryExportSelectFolder)), findsNothing);
      final body = find.byKey(const ValueKey('novel-export-scope-body'));
      await tester.ensureVisible(body);
      await tester.tap(body);
      await tester.pumpAndSettle();
      final chapterOutlines = find.byKey(
        const ValueKey('novel-export-scope-chapter_outlines'),
      );
      await tester.ensureVisible(chapterOutlines);
      await tester.tap(chapterOutlines);
      await tester.pumpAndSettle();
      expect(_scopeSelected(tester, 'chapter_outlines'), isTrue);
      expect(
        find.text(tr(LocaleKeys.libraryExportScopeChapterOutlinesHint)),
        findsOneWidget,
      );
      expect(find.text(tr(LocaleKeys.libraryExportBodyFormat)), findsNothing);

      final export = find.widgetWithText(
        FilledButton,
        tr(LocaleKeys.libraryExportAction),
      );
      for (final size in [
        const Size(320, 640),
        const Size(375, 812),
        const Size(844, 390),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(MobileSheetScaffold)).height,
          lessThanOrEqualTo(size.height * .78),
        );
        expect(tester.getRect(export).bottom, lessThan(size.height));
        expect(export.hitTestable(), findsOneWidget);
      }
      await tester.tap(
        find.widgetWithText(OutlinedButton, tr(LocaleKeys.commonCancel)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('directory chooser fits narrow and wide dialogs in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(NovelExportDialog(novel: _novel()), locale: locale),
      );
      await tester.pumpAndSettle();

      final chooser = find.widgetWithText(
        OutlinedButton,
        tr(LocaleKeys.libraryExportSelectFolder),
      );
      final preview = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == tr(LocaleKeys.libraryExportFolderPlaceholder) &&
            widget.maxLines == 1,
      );
      for (final width in [320.0, 375.0, 800.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpAndSettle();
        await tester.ensureVisible(chooser);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final buttonRect = tester.getRect(chooser);
        final previewRect = tester.getRect(preview);
        expect(previewRect.width, greaterThan(0));
        expect(buttonRect.left, greaterThanOrEqualTo(0));
        expect(buttonRect.right, lessThanOrEqualTo(width));
        expect(tester.widget<OutlinedButton>(chooser).onPressed, isNotNull);
        if (width < 400) {
          expect(buttonRect.top, greaterThanOrEqualTo(previewRect.bottom));
        } else {
          expect(buttonRect.center.dy, closeTo(previewRect.center.dy, 1));
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('scope selection drives validation and manuscript options', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(NovelExportDialog(novel: _novel())));
    await tester.pumpAndSettle();

    expect(_scopeSelected(tester, 'body'), isTrue);
    expect(_scopeSelected(tester, 'outlines'), isFalse);
    expect(_scopeSelected(tester, 'chapter_outlines'), isFalse);
    expect(find.text('Manuscript format'), findsOneWidget);

    final body = find.byKey(const ValueKey('novel-export-scope-body'));
    await tester.ensureVisible(body);
    await tester.tap(body);
    await tester.pumpAndSettle();

    expect(_scopeSelected(tester, 'body'), isFalse);
    expect(find.text('Select at least one type of content.'), findsOneWidget);
    expect(find.text('Manuscript format'), findsNothing);

    final outlines = find.byKey(const ValueKey('novel-export-scope-outlines'));
    await tester.ensureVisible(outlines);
    await tester.tap(outlines);
    await tester.pumpAndSettle();

    expect(_scopeSelected(tester, 'outlines'), isTrue);
    expect(find.text('Select at least one type of content.'), findsNothing);
    expect(find.text('Manuscript format'), findsNothing);

    final selectAll = find.text('Select all');
    await tester.ensureVisible(selectAll);
    await tester.tap(selectAll);
    await tester.pumpAndSettle();

    for (final scope in [
      'outlines',
      'chapter_outlines',
      'settings',
      'materials',
      'body',
    ]) {
      expect(_scopeSelected(tester, scope), isTrue);
    }
    expect(find.text('Manuscript format'), findsOneWidget);
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    final numberFormat = find.byKey(
      const ValueKey('novel-export-number-format'),
    );
    final alignment = find.byKey(
      const ValueKey('novel-export-title-alignment'),
    );
    expect(numberFormat, findsOneWidget);
    expect(alignment, findsOneWidget);
    expect(
      tester.getCenter(alignment).dy,
      greaterThan(tester.getCenter(numberFormat).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'screenplay scopes describe script exports without chapter options',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          NovelExportDialog(
            novel: _novel().copyWith(contentKind: contentKindScreenplay),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_scopeSelected(tester, 'body'), isTrue);
      expect(find.text('Script'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('novel-export-scope-chapter_outlines')),
        findsNothing,
      );
      expect(find.textContaining('One script file per season'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('novel-export-number-format')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('novel-export-title-alignment')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('novel-export-scope-body')));
      await tester.pumpAndSettle();
      expect(find.text('Select at least one type of content.'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('novel-export-scope-outlines')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Episode outlines, beats, and scene synopses'),
        findsOneWidget,
      );
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      for (final scope in ['outlines', 'settings', 'materials', 'body']) {
        expect(_scopeSelected(tester, scope), isTrue);
      }
      expect(find.text('4/4 selected'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Manuscript format'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

bool _scopeSelected(WidgetTester tester, String scope) {
  return tester
          .widget<Semantics>(find.byKey(ValueKey('novel-export-scope-$scope')))
          .properties
          .selected ??
      false;
}

Novel _novel() {
  final now = DateTime(2026);
  return Novel(
    id: 'novel_1',
    title: 'Test Novel',
    authorName: '',
    description: '',
    status: contentStatusInProgress,
    type: novelTypeOriginal,
    contentKind: contentKindNovel,
    contentDatabasePath: '/tmp/test-content.sqlite',
    wordCount: 0,
    draft: false,
    category: '',
    tags: const <String>[],
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: locale,
    child: Builder(
      builder: (context) {
        return ProviderScope(
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: Center(
                  child: DialogFeedback.scope(builder: (_) => child),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
