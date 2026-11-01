// 职责: 验证导出按钮保存最新便签、保留组词边界，并直接导出 ZIP。
// 关联文件:
//   lib/desktop/features/canvas/export_button.dart
//   lib/shared/services/canvas_export/save.dart
//   lib/desktop/features/canvas/edit_session.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/text-input-ime.md

import 'dart:async';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/features/canvas/edit_session.dart';
import 'package:reveric/desktop/features/canvas/export_button.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_sticky_editor.dart';
import 'package:reveric/desktop/features/canvas/widgets/floating_cluster.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/canvas_export.dart';
import 'package:reveric/shared/providers/canvas_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/canvas_service.dart';
import 'package:reveric/shared/services/canvas_export/save.dart';
import 'package:reveric/shared/theme/theme.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => rootBundle.clear());
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  testWidgets(
    'immediate export flushes latest committed sticky content into the snapshot',
    (tester) async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      final service = CanvasService(db);
      late String canvas, nodeId;
      late CanvasNode node;
      await tester.runAsync(() async {
        canvas = await service.createCanvas(name: 'Export');
        nodeId = await service.addNode(
          canvasId: canvas,
          type: 'sticky',
          content: 'Before',
          x: 0,
          y: 0,
        );
        node = (await db.canvasDao.getNodeById(nodeId))!;
      });
      final session = CanvasEditSession();
      final exported = Completer<CanvasExportArtifact>();
      final container = ProviderContainer(
        overrides: [
          novelContentDatabaseProvider('memory:export').overrideWithValue(db),
          canvasContentStreamProvider((
            canvasId: canvas,
            databasePath: 'memory:export',
          )).overrideWith(
            (ref) => Stream.value((nodes: [node], edges: <CanvasEdge>[])),
          ),
          // 真实 provider 挂在 drift .watch() 上，testWidgets 的假时钟里会让 pumpAndSettle 挂死。
          canvasInvalidNodeIdsProvider((
            canvasId: canvas,
            databasePath: 'memory:export',
          )).overrideWith((ref) async => const <String>{}),
          canvasSceneReferencesProvider(
            'memory:export',
          ).overrideWith((ref) async => const {}),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(
            Column(
              children: [
                SizedBox(
                  width: 300,
                  child: CanvasStickyEditor(
                    node: node,
                    session: session,
                    actions: CanvasStickyActions(
                      onTitleChanged: (value) => session.write(
                        'title',
                        () => service.updateNodeTitle(
                          nodeId: nodeId,
                          title: value,
                        ),
                      ),
                      onContentChanged: (value) =>
                          session.write('body', () async {
                            await service.updateNodeContent(
                              nodeId: nodeId,
                              content: value,
                            );
                          }),
                      onColorChanged: (_) {},
                      onDelete: () {},
                    ),
                  ),
                ),
                CanvasExportButton(
                  source: (
                    canvasId: canvas,
                    databasePath: 'memory:export',
                    workId: 'work',
                    contentKind: 'novel',
                  ),
                  session: session,
                  saveArtifact: (artifact) async {
                    exported.complete(artifact);
                    return const CanvasExportSaveResult(
                      CanvasExportSaveStatus.saved,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '最新已提交正文');
      await tester.tap(find.byTooltip('Export'));
      // Flush FakeAsync editor work while allowing real isolate messages to arrive.
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!exported.isCompleted && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(exported.isCompleted, isTrue);
      final artifact = await exported.future;
      await tester.pumpAndSettle();
      expect(artifact.format, CanvasExportFormat.zip);
      final archive = ZipDecoder().decodeBytes(artifact.bytes);
      final data =
          jsonDecode(
                utf8.decode(
                  archive.findFile('canvas.json')!.content as List<int>,
                ),
              )
              as Map<String, dynamic>;
      expect((data['nodes'] as List).single['content'], '最新已提交正文');
      expect(data.containsKey('issues'), isFalse);
      expect(session.editingLocked, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Canvas exported.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      container.dispose();
      session.dispose();
      await tester.runAsync(db.close);
    },
  );
  for (final count in [0, 1]) {
    testWidgets(
      '$count nodes: empty canvas disables export and composing input blocks collection',
      (tester) async {
        final session = CanvasEditSession();
        session.register(
          'input',
          CanvasEditorFlush(
            isComposing: () => true,
            flush: () async {
              throw StateError('must not flush composition');
            },
          ),
        );
        final node = CanvasNode(
          id: 'n',
          canvasId: 'canvas',
          type: 'sticky',
          title: '',
          content: '',
          x: 0,
          y: 0,
          zIndex: 0,
          sortOrder: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          deletedAt: notDeletedSentinel,
        );
        final container = ProviderContainer(
          overrides: [
            novelContentDatabaseProvider('memory:export').overrideWith(
              (ref) =>
                  throw StateError('Database must not open during composition'),
            ),
            canvasContentStreamProvider((
              canvasId: 'canvas',
              databasePath: 'memory:export',
            )).overrideWith(
              (ref) => Stream.value((
                nodes: count == 0 ? <CanvasNode>[] : [node],
                edges: <CanvasEdge>[],
              )),
            ),
            // 真实 provider 挂在 drift .watch() 上，testWidgets 的假时钟里会让 pumpAndSettle 挂死。
            canvasInvalidNodeIdsProvider((
              canvasId: 'canvas',
              databasePath: 'memory:export',
            )).overrideWith((ref) async => const <String>{}),
            canvasSceneReferencesProvider(
              'memory:export',
            ).overrideWith((ref) async => const {}),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _wrap(
              CanvasExportButton(
                source: (
                  canvasId: 'canvas',
                  databasePath: 'memory:export',
                  workId: 'work',
                  contentKind: 'novel',
                ),
                session: session,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (count == 0) {
          expect(
            tester
                .widget<CanvasFloatingButton>(find.byType(CanvasFloatingButton))
                .onTap,
            isNull,
          );
        } else {
          await tester.tap(find.byTooltip('Export'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            find.text('Finish the current text input before continuing.'),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        container.dispose();
        session.dispose();
        await tester.pumpAndSettle();
      },
    );
  }
}

Widget _wrap(Widget child) => EasyLocalization(
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
      theme: RevericThemeData.reveric.toThemeData(),
      builder: (context, child) =>
          RevericTheme(data: RevericThemeData.reveric, child: child!),
      home: Scaffold(body: child),
    ),
  ),
);
