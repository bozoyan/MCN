// 职责: 验证备份恢复子页面的模式切换、小说选择和提交范围。
// 关联文件:
//   lib/shared/widgets/settings/backup_restore_page.dart
//   lib/shared/services/backup_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/services/backup_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/settings/backup_restore_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders as a child page and submits selected novel ids', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    BackupRestoreSelection? submitted;
    var backCount = 0;

    await tester.pumpWidget(
      _wrap(
        BackupRestorePage(
          preview: BackupRestorePreview(
            zipPath: '/tmp/backup.zip',
            createdAt: DateTime.utc(2026, 8, 5, 12),
            warningCount: 0,
            novels: const [
              BackupNovelSummary(
                id: 'novel-a',
                title: 'Novel A',
                existsInCurrentLibrary: true,
                hasTitleConflict: false,
                hasContentDatabase: true,
              ),
              BackupNovelSummary(
                id: 'novel-conflict',
                title: 'Novel Conflict',
                existsInCurrentLibrary: false,
                hasTitleConflict: true,
                hasContentDatabase: true,
              ),
            ],
          ),
          compact: false,
          isRestoring: false,
          onBack: () {
            backCount += 1;
          },
          onRestore: (selection) async {
            submitted = selection;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('restore_back_button')), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<RestoreMode>>(find.byType(RadioGroup<RestoreMode>))
          .groupValue,
      RestoreMode.selectedNovels,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('restore_novel_novel-a')),
          )
          .value,
      isFalse,
    );
    expect(tester.widget<FilledButton>(_restoreButton).onPressed, isNull);

    await tester.tap(find.byKey(const Key('restore_mode_full')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_restoreButton).onPressed, isNotNull);
    await tester.tap(_restoreButton);
    await tester.pump();
    expect(submitted?.mode, RestoreMode.fullReplacement);
    expect(submitted?.novelIds, isEmpty);

    await tester.tap(find.byKey(const Key('restore_mode_selected')));
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(_restoreButton).onPressed, isNull);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('restore_novel_novel-conflict')),
          )
          .onChanged,
      isNull,
    );

    await tester.tap(find.byKey(const Key('restore_novel_novel-a')));
    await tester.pump();
    await tester.tap(_restoreButton);
    await tester.pump();

    expect(submitted?.mode, RestoreMode.selectedNovels);
    expect(submitted?.novelIds, {'novel-a'});
    expect(backCount, 0);

    await tester.binding.setSurfaceSize(const Size(700, 550));
    await tester.pumpWidget(
      _wrap(
        BackupRestorePage(
          preview: BackupRestorePreview(
            zipPath: '/tmp/backup.zip',
            createdAt: DateTime.utc(2026, 8, 5, 12),
            warningCount: 0,
            novels: List.generate(
              16,
              (index) => BackupNovelSummary(
                id: 'novel-$index',
                title: 'Novel $index',
                existsInCurrentLibrary: true,
                hasTitleConflict: false,
                hasContentDatabase: true,
              ),
            ),
          ),
          compact: false,
          isRestoring: false,
          onBack: () {},
          onRestore: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restore_mode_selected')));
    await tester.pumpAndSettle();

    final restoreButton = _restoreButton;
    expect(tester.getRect(restoreButton).bottom, lessThanOrEqualTo(550));
  });

  testWidgets('compact empty backup requires choosing full replacement', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    BackupRestoreSelection? submitted;
    await tester.pumpWidget(
      _wrap(
        BackupRestorePage(
          preview: BackupRestorePreview(
            zipPath: '/tmp/backup.zip',
            createdAt: DateTime.utc(2026, 8, 5, 12),
            warningCount: 0,
            novels: const [],
          ),
          compact: true,
          isRestoring: false,
          onBack: () {},
          onRestore: (selection) async => submitted = selection,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final restoreButton = _restoreButton;
    expect(tester.widget<FilledButton>(restoreButton).onPressed, isNull);
    await tester.tap(find.byKey(const Key('restore_mode_full')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(restoreButton).onPressed, isNotNull);
    await tester.tap(restoreButton);
    await tester.pump();
    expect(submitted?.mode, RestoreMode.fullReplacement);
    expect(submitted?.novelIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long novel list scrolls inside its box, not the page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _wrap(
        BackupRestorePage(
          preview: BackupRestorePreview(
            zipPath: '/tmp/backup.zip',
            createdAt: DateTime.utc(2026, 8, 5, 12),
            warningCount: 0,
            novels: List.generate(
              12,
              (index) => BackupNovelSummary(
                id: 'novel-$index',
                title: 'Novel $index',
                existsInCurrentLibrary: true,
                hasTitleConflict: false,
                hasContentDatabase: true,
              ),
            ),
          ),
          compact: false,
          isRestoring: false,
          onBack: () {},
          onRestore: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final page = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(page.position.maxScrollExtent, 0);
    final list = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(list.position.maxScrollExtent, greaterThan(0));
    final footerTop = tester
        .getRect(
          find
              .ancestor(
                of: find.byKey(const Key('restore_confirmation_notice')),
                matching: find.byType(DecoratedBox),
              )
              .first,
        )
        .top;
    expect(
      footerTop - tester.getRect(find.byType(ListView)).bottom,
      greaterThanOrEqualTo(RevericSpacing.lg),
    );
  });

  for (final scenario in [
    (width: 1100.0, compact: false, locale: const Locale('en'), scale: 1.0),
    (
      width: 520.0,
      compact: false,
      locale: const Locale('zh', 'CN'),
      scale: 1.0,
    ),
    (width: 390.0, compact: true, locale: const Locale('zh', 'CN'), scale: 1.0),
    (width: 390.0, compact: true, locale: const Locale('en'), scale: 2.0),
  ]) {
    testWidgets('restore footer stays readable and reachable: $scenario', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(scenario.width, 550));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _wrap(
          MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(scenario.scale),
              padding: const EdgeInsets.only(bottom: 34),
            ),
            child: BackupRestorePage(
              preview: BackupRestorePreview(
                zipPath: '/tmp/backup.zip',
                createdAt: DateTime.utc(2026, 8, 5, 12),
                warningCount: 0,
                novels: const [
                  BackupNovelSummary(
                    id: 'novel-a',
                    title: 'Novel A',
                    existsInCurrentLibrary: true,
                    hasTitleConflict: false,
                    hasContentDatabase: true,
                  ),
                ],
              ),
              compact: scenario.compact,
              isRestoring: false,
              onBack: () {},
              onRestore: (_) async {},
            ),
          ),
          locale: scenario.locale,
        ),
      );
      await tester.pumpAndSettle();

      final notice = tester.getRect(
        find.byKey(const Key('restore_confirmation_notice')),
      );
      final button = tester.getRect(_restoreButton);
      expect(notice.overlaps(button), isFalse);
      expect(notice.left, greaterThanOrEqualTo(20));
      expect(notice.top, greaterThanOrEqualTo(0));
      expect(button.right, lessThanOrEqualTo(scenario.width - 20));
      expect(button.bottom, lessThanOrEqualTo(550 - 34));
      final scrollView = find.byType(CustomScrollView);
      final footer = find
          .ancestor(
            of: find.byKey(const Key('restore_confirmation_notice')),
            matching: find.byType(DecoratedBox),
          )
          .first;
      expect(
        tester.getRect(scrollView).bottom,
        tester.getRect(footer).top,
        reason: 'Scrolling content must not be clipped above a dead strip',
      );
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(of: scrollView, matching: find.byType(Scrollable))
            .first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      expect(
        tester.getRect(footer).top -
            tester.getRect(find.byType(ListView)).bottom,
        greaterThanOrEqualTo(RevericSpacing.lg),
        reason: 'Scrolled to the end, the list must keep a gap above footer',
      );
      if (scenario.width > 1000) {
        final list = tester.getRect(find.byType(ListView));
        expect(notice.left, list.left - 1);
        expect(button.right, list.right + 1);
      }
    });
  }
}

Finder get _restoreButton => find.descendant(
  of: find.byKey(const Key('restore_confirm_button')),
  matching: find.byType(FilledButton),
);

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: locale,
    saveLocale: false,
    child: Builder(
      builder: (context) {
        return MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: Scaffold(body: child),
          ),
        );
      },
    ),
  );
}
