// 职责: 通过移动端父子编辑页面验证节拍稳定身份、自动保存、排序、删除及离开冲刷。
// 关联文件:
//   lib/mobile/pages/outline_editor_page.dart
//   lib/mobile/pages/outline_beat_editor_page.dart
//   lib/shared/services/outline_service.dart
//   lib/shared/database/novel_content_daos/outline_dao.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'dart:async';

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/mobile/pages/outline_editor_page.dart';
import 'package:reveric/mobile/pages/outline_beat_editor_page.dart';
import 'package:reveric/mobile/widgets/segmented_tabs.dart';
import 'package:reveric/shared/components/reveric_select.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/outline.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/outline_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/md/reveric_markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/outline_fixture.dart';

const _path = 'mobile-outline-save-test';

void main() {
  late NovelContentDatabase db;
  late _ControlledContentService service;
  final nav = GlobalKey<NavigatorState>();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() async {
    rootBundle.clear();
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = _ControlledContentService(db);
    final now = DateTime.fromMillisecondsSinceEpoch(100000);
    await insertOutlineFixture(
      db,
      OutlineDraft(
        documentId: 'main',
        title: 'Main',
        startChapterNum: 4,
        beats: [
          for (final id in ['a', 'b', 'c'])
            OutlineBeatDraft(
              id: id,
              title: id,
              content: 'body $id',
              chapterCount: 2,
              createdAt: now,
            ),
        ],
        createdAt: now,
        updatedAt: now,
        deletedAt: notDeletedSentinel,
      ),
    );
  });
  tearDown(() async => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<OutlineDraft> stored() async =>
      (await service.outlineService.getByDocumentId('main'))!;
  Future<void> showBeats(WidgetTester tester) async {
    tester
        .widget<MobileSegmentedTabs>(find.byType(MobileSegmentedTabs))
        .onSelected(1);
    await settle(tester);
  }

  Future<void> swipeOpen(WidgetTester tester, Finder card) async {
    await tester.drag(card, const Offset(-300, 0));
    await settle(tester);
  }

  Future<void> open(WidgetTester tester) async {
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const MobileOutlineEditorPage(
          databasePath: _path,
          outlineId: 'main',
        ),
      ),
    );
    await settle(tester);
    await showBeats(tester);
  }

  Future<void> mount(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelContentDatabaseProvider(_path).overrideWithValue(db),
          novelContentServiceProvider(_path).overrideWithValue(service),
          editorFontFamilyProvider.overrideWithValue('Georgia'),
          editorFontSizeProvider.overrideWithValue(16),
          editorLetterSpacingProvider.overrideWithValue(0),
          editorLineHeightProvider.overrideWithValue(1.8),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const MergingAssetLoader(),
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          child: Builder(
            builder: (context) => MaterialApp(
              navigatorKey: nav,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: RevericThemeData.reveric.toThemeData(),
              builder: (context, child) => RevericTheme(
                data: RevericThemeData.reveric,
                child: child!,
              ),
              home: const Scaffold(body: Text('Home')),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await open(tester);
  }

  Future<void> edit(
    WidgetTester tester,
    String title, {
    bool save = true,
  }) async {
    expect(find.byType(MobileOutlineBeatEditorPage), findsOneWidget);
    final titleField = find
        .descendant(
          of: find.byType(MobileOutlineBeatEditorPage),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(titleField, title);
    tester
            .widget<RevericMarkdownEditor>(find.byType(RevericMarkdownEditor))
            .controller
            .text =
        'body $title';
    tester
        .widget<RevericSelect<String>>(find.byType(RevericSelect<String>))
        .onChanged(outlineStatusFinished);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is RevericIcon && w.assetPath == RevericIcons.add,
      ),
    );
    if (save) {
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is RevericIcon && w.assetPath == RevericIcons.check,
        ),
      );
    } else {
      nav.currentState!.pop();
    }
    await settle(tester);
  }

  testWidgets(
    'add, edit, cancel, reorder, delete and reopen keep identities and tombstones',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Add Beat'));
      await settle(tester);
      await edit(tester, 'new');
      // This key exists before the parent's debounce writes anything.
      final listBeforeSave = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      expect(listBeforeSave.itemCount, 4);
      final newLocalKey =
          listBeforeSave
                  .itemBuilder(
                    tester.element(find.byType(ReorderableListView)),
                    3,
                  )
                  .key
              as ValueKey<String>;
      expect(newLocalKey.value, isNotEmpty);
      expect((await stored()).beats, hasLength(3));
      await tester.pump(const Duration(milliseconds: 900));
      await settle(tester);
      final added = (await stored()).beats.last;
      expect(added.id, isNotEmpty);
      expect(added.id, matches(RegExp(r'^obt_[A-Z0-9]{6}$')));
      expect(added.id, newLocalKey.value);
      expect(added.chapterCount, 6);
      expect(added.status, outlineStatusFinished);
      expect(await db.select(db.outlineBeats).get(), hasLength(4));

      await tester.tap(find.text('new'));
      await settle(tester);
      await edit(tester, 'new edited');
      await tester.pump(const Duration(milliseconds: 900));
      await settle(tester);
      final edited = (await stored()).beats.last;
      expect(edited.id, added.id);
      expect(edited.createdAt, added.createdAt);
      expect(edited.content, 'body new edited');
      expect(edited.chapterCount, 7);
      expect(await db.select(db.outlineBeats).get(), hasLength(4));

      final beforeCancel = (await db.select(db.outlineBeats).get())
          .map((r) => r.toJson())
          .toList();
      await tester.tap(find.text('Add Beat'));
      await settle(tester);
      await edit(tester, 'cancel new', save: false);
      await tester.tap(find.text('a'));
      await settle(tester);
      await edit(tester, 'cancel edit', save: false);
      await tester.pump(const Duration(milliseconds: 900));
      await settle(tester);
      expect(
        (await db.select(db.outlineBeats).get())
            .map((r) => r.toJson())
            .toList(),
        beforeCancel,
      );

      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(3, 0);
      await tester.pump(const Duration(milliseconds: 900));
      await settle(tester);
      expect((await stored()).beats.map((b) => b.id), [
        added.id,
        'a',
        'b',
        'c',
      ]);
      expect(
        (await db.select(db.outlineBeats).get()).every(
          (r) => r.deletedAt == notDeletedSentinel,
        ),
        true,
      );
      final card = find.byKey(const ValueKey('b'));
      await swipeOpen(tester, card);
      // Swiping only reveals the action; the beat stays until it is tapped.
      expect(find.text('Delete'), findsOneWidget);
      expect(card, findsOneWidget);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      // Leave before debounce: disposal must flush this last list after prior saves.
      nav.currentState!.pop();
      await settle(tester);
      expect((await stored()).beats.map((b) => b.id), [added.id, 'a', 'c']);
      expect(
        (await db.select(db.outlineBeats).get())
            .singleWhere((r) => r.id == 'b')
            .deletedAt,
        isNot(notDeletedSentinel),
      );
      await open(tester);
      expect(find.byKey(const ValueKey('b')), findsNothing);
      expect(find.text('new edited'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'rapid edits then deleting the only beat are flushed without resurrection',
    (tester) async {
      final current = await stored();
      await service.outlineService.saveOutline(
        current.copyWith(beats: [current.beats.first]),
      );
      await mount(tester);
      await tester.tap(find.text('a'));
      await settle(tester);
      await edit(tester, 'first');
      final firstSave = service.outlineService.pauseNextSave();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.text('first'));
      await settle(tester);
      await edit(tester, 'latest');
      firstSave.complete();
      await settle(tester);
      nav.currentState!.pop();
      await settle(tester);
      expect((await stored()).beats.single.title, 'latest');
      await open(tester);
      await swipeOpen(tester, find.byKey(const ValueKey('a')));
      await tester.tap(find.text('Delete'));
      await settle(tester);
      nav.currentState!.pop();
      await settle(tester);
      expect((await stored()).beats, isEmpty);
      expect(
        (await db.select(db.outlineBeats).get()).every(
          (r) => r.deletedAt != notDeletedSentinel,
        ),
        true,
      );
      await open(tester);
      expect(find.byType(ReorderableListView), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

// Hold a real save before its DB transaction to expose in-flight UI races.
class _ControlledOutlineService extends OutlineService {
  _ControlledOutlineService(super.database);
  Completer<void>? _nextSave;
  Completer<void> pauseNextSave() => _nextSave = Completer<void>();
  @override
  Future<void> saveOutline(OutlineDraft draft) async {
    final gate = _nextSave;
    _nextSave = null;
    if (gate != null) {
      await gate.future;
    }
    await super.saveOutline(draft);
  }
}

class _ControlledContentService extends NovelContentService {
  _ControlledContentService(super.db);
  late final _controlledOutline = _ControlledOutlineService(database);
  @override
  _ControlledOutlineService get outlineService => _controlledOutline;
}
