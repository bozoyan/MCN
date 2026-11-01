// 职责: 验证画布排列等待输入、写入和拖拽，并保留失败与中文组词边界。
// 关联文件:
//   lib/desktop/features/canvas/edit_session.dart
//   lib/desktop/features/canvas/widgets/canvas_sticky_editor.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/text-input-ime.md

import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/edit_session.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_flow_adapter.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;
import 'package:reveric/desktop/features/canvas/widgets/canvas_sticky_editor.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/canvas_service.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());
  test(
    'exclusive operation waits for drag, flush and queued writes; blocks reentry',
    () async {
      final session = CanvasEditSession();
      addTearDown(session.dispose);
      final gate = Completer<void>(), operation = Completer<void>();
      final order = <String>[];
      session.beginInteraction('node');
      session.register(
        'editor',
        CanvasEditorFlush(
          isComposing: () => false,
          flush: () => session.write('body', () async {
            await gate.future;
            order.add('saved');
          }),
        ),
      );
      final result = session.runExclusive(() async {
        order.add('operation');
        expect(session.editingLocked, isTrue);
        await operation.future;
      });
      await Future<void>.delayed(Duration.zero);
      expect(order, isEmpty);
      expect(session.busy, isTrue);
      await expectLater(
        session.runExclusive(() async {}),
        throwsA(
          isA<CanvasEditSessionException>().having(
            (e) => e.code,
            'code',
            'operation_in_progress',
          ),
        ),
      );
      session.endInteraction('node');
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(order, ['saved', 'operation']);
      operation.complete();
      await result;
      expect(session.busy, isFalse);
      expect(session.editingLocked, isFalse);
    },
  );
  test(
    'write failure prevents operation until the same field is saved again',
    () async {
      final session = CanvasEditSession();
      addTearDown(session.dispose);
      await expectLater(
        session.write('body', () async {
          throw StateError('disk');
        }),
        throwsStateError,
      );
      var ran = false;
      await expectLater(
        session.runExclusive(() async {
          ran = true;
        }),
        throwsA(isA<CanvasEditSessionException>()),
      );
      expect(ran, isFalse);
      await session.write('body', () async {});
      await session.runExclusive(() async {
        ran = true;
      });
      expect(ran, isTrue);
    },
  );
  test(
    'another service instance waits for live edits and drag, rejects failed/composing flush, and detaches by owner',
    () async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      final session = CanvasEditSession();
      final editorService = CanvasService(db);
      // 与 AI/cross-work 的构造方式相同，不依赖同一个 CanvasService 对象。
      final toolService = NovelContentService(db).canvasService;
      expect(identical(editorService, toolService), isFalse);
      final canvas = await editorService.createCanvas(name: 'Boundary');
      final node = await editorService.addNode(
        canvasId: canvas,
        type: canvasNodeTypeSticky,
        content: 'Old',
        x: 777,
        y: 333,
      );
      await editorService.addNode(
        canvasId: canvas,
        type: canvasNodeTypeSticky,
        content: 'Other',
        x: 888,
        y: 444,
      );
      final gate = Completer<void>();
      var composing = false, fail = false;
      session.register(
        'editor',
        CanvasEditorFlush(
          isComposing: () => composing,
          flush: () => session.write('content', () async {
            await gate.future;
            if (fail) {
              throw StateError('save failed');
            }
            await editorService.updateNodeContent(
              nodeId: node,
              content: 'Committed',
            );
          }),
        ),
      );
      final boundary = session.runLayout;
      editorService.registerLayoutBoundary(canvas, boundary);
      session.beginInteraction(node);
      try {
        final layout = toolService.applyLayout(canvas, canvasLayoutGrid);
        await Future<void>.delayed(Duration.zero);
        expect((await db.canvasDao.getCanvasById(canvas))!.layout, isNull);
        session.endInteraction(node);
        await Future<void>.delayed(Duration.zero);
        expect((await db.canvasDao.getNodeById(node))!.x, 777);
        gate.complete();
        await layout;
        expect((await db.canvasDao.getNodeById(node))!.content, 'Committed');
        expect(
          (await db.canvasDao.getCanvasById(canvas))!.layout,
          canvasLayoutGrid,
        );
        final before = (await db.canvasDao.getNodesByCanvas(
          canvas,
        )).map((n) => n.toJson()).toList();
        fail = true;
        await expectLater(
          toolService.applyLayout(canvas, canvasLayoutAuto),
          throwsA(
            isA<CanvasServiceException>().having(
              (e) => e.errorCode,
              'code',
              'layout_save_failed',
            ),
          ),
        );
        expect(
          (await db.canvasDao.getNodesByCanvas(
            canvas,
          )).map((n) => n.toJson()).toList(),
          before,
        );
        expect(
          (await db.canvasDao.getCanvasById(canvas))!.layout,
          canvasLayoutGrid,
        );
        fail = false;
        composing = true;
        await expectLater(
          toolService.applyLayout(canvas, canvasLayoutAuto),
          throwsA(
            isA<CanvasServiceException>().having(
              (e) => e.errorCode,
              'code',
              'layout_conflict',
            ),
          ),
        );
        editorService.unregisterLayoutBoundary(canvas, (action) => action());
        await expectLater(
          toolService.applyLayout(canvas, canvasLayoutAuto),
          throwsA(isA<CanvasServiceException>()),
        );
        editorService.unregisterLayoutBoundary(canvas, boundary);
        await toolService.applyLayout(canvas, canvasLayoutAuto);
        expect(
          (await db.canvasDao.getCanvasById(canvas))!.layout,
          canvasLayoutAuto,
        );
      } finally {
        editorService.unregisterLayoutBoundary(canvas, boundary);
        session.dispose();
        await db.close();
      }
    },
  );

  test(
    'resize event saves final geometry and a pending write cannot end a newer drag',
    () async {
      final session = CanvasEditSession();
      final controller = CanvasFlowController();
      session.attach(controller);
      final node = CanvasNode(
        id: 'geometry',
        canvasId: 'canvas',
        type: canvasNodeTypeSticky,
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
      final flowNode = canvasNodeToFlowNode(
        node,
        colors: RevericThemeData.reveric.colors,
      );
      controller.addNode(flowNode);
      final save = Completer<void>();
      (String, Offset, Size)? received;
      session.saveGeometry = (id, position, size) async {
        received = (id, position, size);
        await save.future;
      };
      session.onEvent(const flow.ResizeStarted('geometry', Size(280, 168)));
      flowNode.position.value = const Offset(90, 120);
      flowNode.setSize(const Size(330, 240));
      session.onEvent(
        const flow.ResizeEnded('geometry', Size(280, 168), Size(330, 240)),
      );
      var flushed = false;
      final pending = session.flushAndWait().then((_) => flushed = true);
      await Future<void>.delayed(Duration.zero);
      expect(received, (
        'geometry',
        const Offset(90, 120),
        const Size(330, 240),
      ));
      expect(flushed, isFalse);
      session.onEvent(const flow.NodeDragStarted({'geometry'}, Offset.zero));
      save.complete();
      await Future<void>.delayed(Duration.zero);
      expect(session.hasInteractions, isTrue);
      expect(flushed, isFalse);
      session.endInteraction('geometry');
      await pending;
      expect(flushed, isTrue);
      session.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'sticky clean refresh preserves selection and clamps only changed text',
    (tester) async {
      final node = ValueNotifier(
        CanvasNode(
          id: 'selection',
          canvasId: 'canvas',
          type: canvasNodeTypeSticky,
          title: '标题中间光标',
          content: '正文中间选区',
          x: 0,
          y: 0,
          zIndex: 0,
          sortOrder: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          deletedAt: notDeletedSentinel,
        ),
      );
      final session = CanvasEditSession();
      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<CanvasNode>(
            valueListenable: node,
            builder: (context, value, _) => SizedBox(
              width: 300,
              child: CanvasStickyEditor(
                node: value,
                session: session,
                actions: CanvasStickyActions(
                  onTitleChanged: (_) async {},
                  onContentChanged: (_) async {},
                  onColorChanged: (_) {},
                  onDelete: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 2; index++) {
        final finder = find.byType(TextField).at(index);
        await tester.tap(finder);
        final controller = tester.widget<TextField>(finder).controller!;
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 4,
        );
        final focus = FocusManager.instance.primaryFocus;
        final text = controller.text;
        node.value = node.value.copyWith(x: node.value.x + 1);
        await tester.pump();
        expect(controller.text, text);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
        expect(FocusManager.instance.primaryFocus, same(focus));
        node.value = index == 0
            ? node.value.copyWith(title: '短文')
            : node.value.copyWith(content: '短文');
        await tester.pump();
        expect(controller.text, '短文');
        expect(
          controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 2),
        );
        expect(FocusManager.instance.primaryFocus, same(focus));
        controller.text = 'local draft';
        controller.selection = const TextSelection.collapsed(offset: 3);
        node.value = index == 0
            ? node.value.copyWith(title: 'external title')
            : node.value.copyWith(content: 'external body');
        await tester.pump();
        expect(controller.text, 'local draft');
        expect(controller.selection, const TextSelection.collapsed(offset: 3));
        await session.flushAndWait();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      node.dispose();
      session.dispose();
    },
  );

  testWidgets(
    'sticky flush saves committed text immediately, preserves composing focus and never saves partial composition',
    (tester) async {
      final session = CanvasEditSession();
      addTearDown(session.dispose);
      final saved = <String>[];
      final node = CanvasNode(
        id: 'sticky',
        canvasId: 'canvas',
        type: canvasNodeTypeSticky,
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
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 300,
            child: CanvasStickyEditor(
              node: node,
              session: session,
              actions: CanvasStickyActions(
                onTitleChanged: (value) => session.write('title', () async {
                  saved.add('title:$value');
                }),
                onContentChanged: (value) => session.write('body', () async {
                  saved.add('body:$value');
                }),
                onColorChanged: (_) {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.byType(TextField).first,
          body = find.byType(TextField).last;
      await tester.enterText(title, '标题');
      await tester.tap(body);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '输入',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();
      final field = tester.widget<TextField>(body);
      final focus = FocusManager.instance.primaryFocus;
      await expectLater(
        session.flushAndWait(),
        throwsA(
          isA<CanvasEditSessionException>().having(
            (e) => e.code,
            'code',
            'input_composing',
          ),
        ),
      );
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(field.controller!.value.composing.isValid, isTrue);
      expect(saved.where((s) => s.startsWith('body:')), isEmpty);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '输入完成',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pump();
      await session.flushAndWait();
      expect(saved, contains('title:标题'));
      expect(saved, contains('body:输入完成'));
      expect(FocusManager.instance.primaryFocus, same(focus));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
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
