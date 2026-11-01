import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/export_preview.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_node_widget.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/canvas_export.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/shared/models/canvas_export_preview.dart';
import 'package:reveric/shared/services/canvas_export/resources.dart';
import 'package:reveric/shared/services/canvas_export/svg.dart';
import 'package:reveric/shared/services/canvas_export/validate.dart';
import 'package:reveric/shared/services/canvas_service.dart';
import 'package:reveric/shared/theme/canvas_colors.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'preview faces reuse the canvas card look, localized text and flow theme',
    (tester) async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      final service = CanvasService(db);
      late CanvasExportSnapshot snapshot;
      late String character, broken, sticky;
      await tester.runAsync(() async {
        final canvas = await service.createCanvas(name: 'Preview');
        sticky = await service.addNode(
          canvasId: canvas,
          type: 'sticky',
          content: '第一段\n第二段',
          x: 400,
          y: 0,
          style: const {canvasNodeColorStyleKey: 'sage'},
        );
        // 引用节点不经 service（它会校验资源存在），直接由便签行派生。
        final note = (await db.canvasDao.getNodesByCanvas(canvas)).single;
        character = 'character-node';
        broken = 'broken-node';
        final references = [
          note.copyWith(
            id: character,
            type: 'reference',
            refType: const Value('character'),
            refId: const Value('c1'),
            title: '一个非常非常长的人物名字，长到卡片里两行都放不下，只能省略掉尾巴',
            content: '',
            x: 0,
            y: 0,
            width: const Value(null),
            height: const Value(null),
            style: const Value(null),
          ),
          note.copyWith(
            id: broken,
            type: 'reference',
            refType: const Value('chapter'),
            refId: const Value('gone'),
            title: '已删除的章节',
            content: '',
            x: 0,
            y: 200,
            width: const Value(null),
            height: const Value(null),
            style: const Value(null),
          ),
        ];
        snapshot = buildCanvasExportSnapshot(
          canvas: (await db.canvasDao.getCanvasById(canvas))!,
          nodes: [note, ...references],
          edges: [
            CanvasEdge(
              id: 'edge',
              canvasId: canvas,
              sourceNodeId: character,
              targetNodeId: sticky,
              type: 'foreshadow_payoff',
              label: '伏笔',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          ],
          resources: const CanvasResourceCollection({}, []),
          workId: 'work',
          contentKind: 'novel',
          exportedAt: DateTime.utc(2026),
        );
      });

      late BuildContext context;
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const MergingAssetLoader(),
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          child: Builder(
            builder: (outer) => MaterialApp(
              localizationsDelegates: outer.localizationDelegates,
              supportedLocales: outer.supportedLocales,
              locale: outer.locale,
              theme: RevericThemeData.reveric.toThemeData(),
              builder: (_, child) =>
                  RevericTheme(data: RevericThemeData.reveric, child: child!),
              home: Builder(
                builder: (inner) {
                  context = inner;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final preview = (await tester.runAsync(
        () => buildCanvasExportPreview(
          context,
          snapshot: snapshot,
          invalidNodeIds: {broken},
          scenes: const {},
        ),
      ))!;
      final colors = RevericThemeData.reveric.colors;

      final person = preview.nodes[character]! as CanvasExportReferenceFace;
      expect(person.subtitle.lines, [canvasRefTypeLabel(context, 'character')]);
      expect(person.subtitle.lines.single, isNot('character'));
      expect(person.title.lines, hasLength(2));
      expect(person.title.lines.last, endsWith('…'));
      expect(person.iconColor, canvasRefTypeAccent(colors, 'character'));
      expect(preview.icons[person.icon], contains('<svg'));

      final gone = preview.nodes[broken]! as CanvasExportReferenceFace;
      expect(gone.fill, colors.surfaceDim);
      expect(gone.icon, RevericIcons.warning_circle);
      expect(gone.title.style.lineThroughColor, isNotNull);

      final note = preview.nodes[sticky]! as CanvasExportStickyFace;
      expect(note.fill, canvasStickyPaperColor(colors, 'sage'));
      expect(note.body.lines, ['第一段', '第二段']);

      final edge = preview.edges[snapshot.edges.single['id']]!;
      expect(edge.color, canvasEdgeColor(colors, 'foreshadow_payoff'));
      expect(edge.dash, canvasEdgeDashPattern('foreshadow_payoff'));
      expect(edge.label!.lines, ['伏笔']);

      // 引用没有资源数据会记成 error 问题；这里只看绘制，清掉问题再画。
      final svg = canvasExportSvg(
        CanvasExportSnapshot({...snapshot.json, 'issues': const []}),
        preview,
      );
      final document = XmlDocument.parse(svg);
      expect(
        document.findAllElements('text').map((e) => e.innerText),
        containsAll([...person.title.lines, ...person.subtitle.lines]),
      );
      expect(
        document.descendants.whereType<XmlElement>().any(
          (e) => e.attributes.any((a) => a.name.local == 'href'),
        ),
        isFalse,
      );
      await tester.runAsync(db.close);
    },
  );
}
