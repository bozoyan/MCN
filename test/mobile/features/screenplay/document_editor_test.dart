// 职责: 验证移动单场编辑及双端失效引用提示、保存与重新关联。
// 关联文件:
//   lib/mobile/features/screenplay/scene_editor.dart
//   lib/shared/widgets/screenplay/document_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:reveric/shared/widgets/screenplay/loading.dart';
import 'package:reveric/shared/widgets/screenplay/document_editor.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/widgets/screenplay/document_toolbar.dart';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reveric/mobile/features/screenplay/scene_editor.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/content_status.dart';
import 'package:reveric/shared/models/novel_type.dart';
import 'package:reveric/shared/models/screenplay_element.dart';
import 'package:reveric/shared/models/screenplay.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/screenplay_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/screenplay/editing_scope.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    if (Platform.environment.containsKey('SCREENPLAY_CAPTURE_DIR')) {
      for (final family in ['Georgia', 'Roboto', 'Ahem']) {
        final path = family == 'Georgia'
            ? '/System/Library/Fonts/Supplemental/Georgia.ttf'
            : '/System/Library/Fonts/Supplemental/Arial.ttf';
        final loader = FontLoader(family)
          ..addFont(
            Future.value(ByteData.sublistView(await File(path).readAsBytes())),
          );
        await loader.load();
      }
    }
  });
  for (final mobile in [false, true]) {
    testWidgets(
      'missing references warn and save in ${mobile ? 'mobile' : 'desktop'} editor',
      (tester) async {
        tester.view.physicalSize = mobile
            ? const Size(400, 850)
            : const Size(1100, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final app = AppDatabase.forTest(NativeDatabase.memory());
        final db = NovelContentDatabase.forTest(NativeDatabase.memory());
        final service = ScreenplayService(db);
        final content = NovelContentService(db);
        final character = await content.createCharacterProfile(
          name: 'Original',
        );
        final replacement = await content.createCharacterProfile(
          name: 'Replacement',
        );
        final location = await content.locationsService.createLocation(
          name: 'Place',
        );
        final initial = await service.createInitialStructure();
        final root = (await db.screenplayDao.getRoot())!;
        final scene = await service.createScene(
          screenplayId: root.id,
          episodeId: initial.episodeId,
          locationId: location,
        );
        await service.writeElements(
          sceneId: scene,
          elements: [
            ScreenplayElement(
              type: ScreenplayElementType.character,
              characterId: character,
            ),
            const ScreenplayElement(
              type: ScreenplayElementType.dialogue,
              text: 'Before',
            ),
          ],
        );
        await content.deleteCharacterProfile(character, restoreHistory: true);
        await content.locationsService.deleteLocation(
          location,
          restoreHistory: true,
        );
        const path = 'memory:missing_references';
        Future<void> Function()? flush;
        await tester.pumpWidget(
          _wrap(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(app),
                novelContentDatabaseProvider(path).overrideWithValue(db),
              ],
              child: Scaffold(
                body: ScreenplayDocumentEditor(
                  novel: _screenplay(path),
                  scope: ScreenplayEditorScope(initial.episodeId),
                  registerFlush: (value) => flush = value,
                  pickCharacter: (_, _) async => replacement,
                  mobile: mobile,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Deleted character', findRichText: true),
          findsWidgets,
        );
        expect(
          find.textContaining('Deleted location', findRichText: true),
          findsWidgets,
        );
        await tester.tap(find.text('Before'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).last,
          'Saved with missing references',
        );
        await tester.pumpAndSettle();
        await flush!();
        await tester.pumpAndSettle();
        expect(
          (await db.screenplayDao.getElementRows(scene)).last.textContent,
          'Saved with missing references',
        );
        final toolbar = tester.widget<ScreenplayDocumentToolbar>(
          find.byType(ScreenplayDocumentToolbar),
        );
        expect(toolbar.actions!.session.queue.lastError, isNull);
        expect(toolbar.actions!.session.queue.isDirty, isFalse);
        if (Platform.environment['SCREENPLAY_CAPTURE_DIR']
            case final directory?) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            await File(
              '$directory/missing-${mobile ? 'mobile' : 'desktop'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        final roleLine = find.textContaining(
          'Deleted character：',
          findRichText: true,
        );
        await tester.tap(roleLine);
        await tester.pumpAndSettle();
        await flush!();
        await tester.pumpAndSettle();
        expect(
          (await db.screenplayDao.getElementRows(scene)).first.characterId,
          replacement,
        );
        expect(
          find.textContaining('Deleted character', findRichText: true),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await db.close();
        await app.close();
      },
    );
  }

  testWidgets(
    'mobile split extends the editable range and undo saves both scenes',
    (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = AppDatabase.forTest(NativeDatabase.memory());
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      final service = ScreenplayService(db);
      final initial = await service.createInitialStructure();
      final root = (await db.screenplayDao.getRoot())!;
      final a = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
      );
      final outside = await service.createScene(
        screenplayId: root.id,
        episodeId: initial.episodeId,
      );
      await service.writeElements(
        sceneId: a,
        elements: const [
          ScreenplayElement(
            type: ScreenplayElementType.action,
            text: 'Before after',
          ),
        ],
      );
      await service.writeElements(
        sceneId: outside,
        elements: const [
          ScreenplayElement(
            type: ScreenplayElementType.action,
            text: 'Outside',
          ),
        ],
      );
      final summary = ScreenplaySceneSummary(
        id: a,
        episodeId: initial.episodeId,
        sceneNumber: 1,
        synopsis: '',
        stage: 'draft',
        timeLabel: '',
        pageEighths: 0,
        wordCount: 0,
        dialogueLineCount: 0,
      );
      const path = 'memory:mobile_screenplay_document';
      Future<void> Function()? flush;
      await tester.pumpWidget(
        _wrap(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(app),
              novelContentDatabaseProvider(path).overrideWithValue(db),
            ],
            child: Scaffold(
              body: MobileScreenplaySceneEditor(
                novel: _screenplay(path),
                scene: summary,
                registerFlush: (value) => flush = value,
              ),
            ),
          ),
        ),
      );
      // 等待本地化资源完成首轮加载，再检查编辑器的加载帧。
      for (
        var frame = 0;
        frame < 30 && find.byType(ScreenplayLoading).evaluate().isEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.byType(ScreenplayLoading), findsOneWidget);
      expect(find.byType(ScreenplayEditingScope), findsNothing);
      final toolbar = find.byType(ScreenplayDocumentToolbar);
      final toolbarRect = tester.getRect(toolbar);
      expect(tester.widget<ScreenplayDocumentToolbar>(toolbar).actions, isNull);
      await tester.pumpAndSettle();
      expect(find.byType(ScreenplayLoading), findsNothing);
      expect(tester.getRect(toolbar), toolbarRect);

      final scopeBeforeRefresh = tester.state<ScreenplayEditingScopeState>(
        find.byType(ScreenplayEditingScope),
      );
      await service.updateScene(sceneId: a, synopsis: 'Updated in background');
      await tester.pumpAndSettle();
      expect(find.byType(ScreenplayLoading), findsNothing);
      expect(
        tester.state<ScreenplayEditingScopeState>(
          find.byType(ScreenplayEditingScope),
        ),
        same(scopeBeforeRefresh),
      );
      expect(tester.getRect(toolbar), toolbarRect);
      expect(find.text('Outside'), findsNothing);
      await tester.tap(find.text('Before after'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField).first);
      field.controller!.selection = const TextSelection.collapsed(offset: 7);
      await tester.tap(find.text('Scene'));
      await tester.pumpAndSettle();
      await flush!();
      await tester.pumpAndSettle();
      final editor = tester
          .widget<ScreenplayEditingScope>(find.byType(ScreenplayEditingScope))
          .controller;
      expect(editor.value.where((e) => e.isHeading), hasLength(2));
      expect(find.text('after'), findsOneWidget);
      if (Platform.environment['SCREENPLAY_CAPTURE_DIR']
          case final directory?) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first,
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ImageByteFormat.png);
          await File(
            '$directory/mobile.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(find.text('Outside'), findsNothing);
      await tester.enterText(
        find.byType(TextField).last,
        'Mobile continuation',
      );
      await tester.pumpAndSettle();
      await flush!();
      await tester.pumpAndSettle();
      final rows = await db.screenplayDao.getSceneRows(initial.episodeId);
      expect(rows, hasLength(3));
      expect(
        (await db.screenplayDao.getElementRows(rows[1].id)).single.textContent,
        'Mobile continuation',
      );
      editor.undo();
      await flush!();
      await tester.pumpAndSettle();
      editor.undo();
      await flush!();
      await tester.pumpAndSettle();
      expect(
        (await db.screenplayDao.getSceneRows(
          initial.episodeId,
        )).map((e) => e.id),
        [a, outside],
      );
      expect(
        (await db.screenplayDao.getElementRows(a)).single.textContent,
        'Before after',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
      await app.close();
    },
  );
}

Novel _screenplay(String databasePath) {
  final now = DateTime(2026);
  return Novel(
    id: 'screenplay_1',
    title: 'Screenplay Test',
    authorName: '',
    description: '',
    status: contentStatusInProgress,
    type: novelTypeOriginal,
    contentKind: contentKindScreenplay,
    contentDatabasePath: databasePath,
    wordCount: 0,
    draft: false,
    category: '',
    tags: const [],
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

Widget _wrap(Widget child) {
  if (child is ProviderScope) {
    return ProviderScope(overrides: child.overrides, child: _wrap(child.child));
  }
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/translations',
    assetLoader: const MergingAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    child: Builder(
      builder: (context) => RevericTheme(
        data: RevericThemeData.reveric,
        child: MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: RevericThemeData.reveric.toThemeData(),
          home: child,
        ),
      ),
    ),
  );
}
