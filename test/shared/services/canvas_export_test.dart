// 职责: 验证全资源画布快照、严格导出产物、图错误和大文本 isolate 完整性。
// 关联文件:
//   lib/shared/services/canvas_export/orchestrator.dart
//   lib/shared/services/canvas_export/resources.dart
//   lib/shared/services/canvas_export/format.dart
//   lib/shared/services/canvas_export/validate.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color;
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/database/novel_content_daos/canvas_dao.dart';
import 'package:reveric/shared/models/canvas_export.dart';
import 'package:reveric/shared/models/canvas_export_preview.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/shared/services/canvas_export/orchestrator.dart';
import 'package:reveric/shared/services/canvas_export/format.dart';
import 'package:reveric/shared/services/canvas_export/resources.dart';
import 'package:reveric/shared/services/canvas_export/schema.dart';
import 'package:reveric/shared/services/canvas_export/svg.dart';
import 'package:reveric/shared/services/canvas_export/validate.dart';
import 'package:reveric/shared/services/canvas_service.dart';
import 'package:reveric/shared/services/screenplay_service.dart';

const special =
    '中文正文\n```\n# <script>alert("x")</script> & [link](https://invalid.example)\n完整结尾';
final exportTime = DateTime.utc(2026, 9, 22, 10);

void main() {
  late NovelContentDatabase db;
  late CanvasService service;
  late String canvas;
  final exporter = CanvasExportOrchestrator();
  setUp(() async {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = CanvasService(db);
    canvas = await service.createCanvas(name: '交接 <&> 图', description: '说明');
  });
  tearDown(() async {
    await db.close();
  });
  Future<CanvasExportSnapshot> snapshot({String kind = 'novel'}) =>
      exporter.snapshot(
        database: db,
        canvasId: canvas,
        workId: 'work-1',
        contentKind: kind,
        exportedAt: exportTime,
      );

  test(
    'all eleven types preserve every whitelist field, direct wins and parent identities never expand children',
    () async {
      final scene = await _seedAll(db, service, canvas);
      final result = await snapshot(kind: 'screenplay');
      expect(result.hasErrors, isFalse);
      final direct = {
        for (final r in result.resources.where(
          (r) => r['detail_level'] == 'content',
        ))
          r['type'] as String: r,
      };
      expect(direct.keys.toSet(), canvasNodeRefTypes.toSet());
      expect(direct['outline']!['id'], 'outline-document-id');
      expect(direct['chapter']!['payload'], {
        'node_kind': 'chapter',
        'parent_id': 'volume',
        'sibling_order': 3,
        'content': special,
        'outline': '写前',
        'brief': '写后',
        'status': 'draft',
        'word_count': 77,
      });
      expect(direct['outline']!['payload'], {
        'content': '大纲正文',
        'status': 'pending',
        'start_chapter_num': 5,
        'beats': [
          {
            'id': 'beat-1',
            'title': '节拍一',
            'content': '节拍正文一',
            'status': 'pending',
            'chapter_count': 2,
            'sort_order': 1,
          },
          {
            'id': 'beat-2',
            'title': '节拍二',
            'content': '节拍正文二',
            'status': 'pending',
            'chapter_count': 3,
            'sort_order': 2,
          },
        ],
      });
      expect(direct['character']!['payload'], {
        'role': 'supporting',
        'gender': 'unknown',
        'aliases': ['旧名', '称号'],
        'tags': ['人物标签'],
        'biography': '小传',
        'appearance': '外貌',
        'description': '描述',
        'current_state': '近况',
        'identity': '身份',
        'age': '二十',
        'motivation': '动机',
        'arc': '弧光',
        'personality': '性格',
        'behavior_tags': [
          {'tag': '行为', 'context': '情境'},
        ],
        'first_appear_chapter_id': 'first',
      });
      expect(direct['foreshadowing']!['payload'], {
        'setup': '铺垫',
        'payoff': '兑现',
        'status': 'pending',
        'setup_chapter_id': 'chapter',
        'payoff_chapter_id': 'missing-chapter',
        'setup_scene_id': scene,
        'payoff_scene_id': null,
      });
      expect(direct['location']!['payload'], {
        'description': '地点正文',
        'location_type': 'generic',
        'tags': '地点,标签',
        'status': 'active',
        'parent_id': 'country',
      });
      for (final type in ['item', 'faction', 'skill', 'creature']) {
        expect(direct[type]!['payload'], {
          'content': '$type 正文',
          'category': '$type 分类',
          'status': 'active',
        });
      }
      expect(direct['document']!['payload'], {
        'document_type': 'historical-custom-type',
        'content': '文档正文',
        'category': '文档分类',
        'tags': '文档,标签',
        'status': 'active',
        'parent_id': 'folder',
        'is_folder': false,
      });
      final payload = direct['screenplay_scene']!['payload'] as Map;
      expect(payload.keys.toSet(), {
        'season',
        'episode',
        'scene_number',
        'synopsis',
        'stage',
        'elements',
      });
      expect(payload['scene_number'], 1);
      expect(payload['synopsis'], '场次梗概');
      expect((payload['season'] as Map)['number'], 1);
      expect((payload['episode'] as Map)['number'], 1);
      final elements = payload['elements'] as List;
      expect(elements.map((e) => e['type']), [
        'scene_heading',
        'action',
        'character',
        'parenthetical',
        'dialogue',
        'transition',
        'subtitle',
        'note',
      ]);
      expect(elements.last['text'], '作者 note\n完整注释');
      expect(elements[2]['character_id'], 'guest');
      expect(elements[2]['extension'], 'O.S.');
      expect(elements[4]['text'], '第一行对白\n第二行对白');
      for (final id in [
        'volume',
        'root-volume',
        'first',
        'country',
        'folder',
        'guest',
        'missing-chapter',
      ]) {
        final r = result.resources.singleWhere((r) => r['id'] == id);
        expect(r['detail_level'], 'identity');
        expect(r['payload'], isNull);
      }
      expect(
        result.resources.where((r) => r['id'] == 'guest').single['title'],
        '配角',
      );
      expect(
        result.resources
            .where((r) => r['id'] == 'missing-chapter')
            .single['status'],
        'missing',
      );
      expect(
        result.resources.any(
          (r) => ['secret-first', 'unselected-child'].contains(r['id']),
        ),
        isFalse,
      );
      expect(result.nodes.where((n) => n['ref_id'] == scene), hasLength(2));
      expect(result.resources.where((r) => r['id'] == scene), hasLength(1));
      final json = canvasExportJson(result);
      for (final hidden in [
        'private-avatar',
        'private-photo',
        'SECRET_META',
        'SECRET_AI',
      ]) {
        expect(json, isNot(contains(hidden)));
      }
      expect(
        () => result.nodes.first['title'] = 'mutate',
        throwsUnsupportedError,
      );
      expect(
        () => ((direct['character']!['payload'] as Map)['aliases'] as List).add(
          'mutate',
        ),
        throwsUnsupportedError,
      );
      await _fixture('all_types', result);
    },
  );

  test(
    'JSON equals zipped truth; fixed package, safe Markdown and parsed static SVG use frozen data',
    () async {
      await _seedAll(db, service, canvas);
      final result = await snapshot(kind: 'screenplay');
      final json = await exporter.encode(result, CanvasExportFormat.json);
      final zip = await exporter.encode(
        result,
        CanvasExportFormat.zip,
        preview: _preview(result),
      );
      final files = {
        for (final file in ZipDecoder().decodeBytes(zip.bytes))
          file.name: utf8.decode(file.content as List<int>),
      };
      expect(files.keys.toSet(), {
        'canvas.json',
        'canvas.schema.json',
        'README.md',
        'review.md',
        'preview.svg',
      });
      expect(files['canvas.json'], utf8.decode(json.bytes));
      // The fixture contains diagnostics, but exported files contain only content.
      expect(result.issues, isNotEmpty);
      expect(
        (jsonDecode(files['canvas.json']!) as Map).containsKey('issues'),
        isFalse,
      );
      for (final issue in result.issues) {
        for (final content in files.values) {
          expect(content, isNot(contains(issue['message'] as String)));
        }
      }
      expect(files['README.md'], isNot(contains('## Checks')));
      expect(
        (jsonDecode(files['canvas.schema.json']!) as Map)['properties'],
        isNot(contains('issues')),
      );
      expect(
        files['canvas.schema.json'],
        contains('https://json-schema.org/draft/2020-12/schema'),
      );
      expect(files['review.md'], contains('````\n$special\n````'));
      expect(files['review.md'], contains('作者 note\n完整注释'));
      expect(files['review.md'], contains('配角'));
      final xml = XmlDocument.parse(files['preview.svg']!);
      expect(xml.findAllElements('script'), isEmpty);
      expect(xml.findAllElements('foreignObject'), isEmpty);
      expect(
        xml.descendants.whereType<XmlElement>().any(
          (e) => e.attributes.any((a) => a.name.local == 'href'),
        ),
        isFalse,
      );
      expect(files['preview.svg'], contains('&lt;'));
      final idsBefore = [for (final node in result.nodes) node['id']];
      final first = result.nodes.first['id'] as String;
      await service.updateNodePosition(nodeId: first, x: -1000, y: 3000);
      await (db.update(
        db.chapters,
      )..where((t) => t.id.equals('chapter'))).write(
        const ChaptersCompanion(title: Value('新标题'), content: Value('手机新正文')),
      );
      final fresh = await snapshot(kind: 'screenplay');
      expect(fresh.nodes.map((n) => n['id']), idsBefore);
      expect(
        fresh.resources.singleWhere((r) => r['id'] == 'chapter')['title'],
        '新标题',
      );
      expect(
        (fresh.resources.singleWhere((r) => r['id'] == 'chapter')['payload']
            as Map)['content'],
        '手机新正文',
      );
      expect(canvasExportJson(result), utf8.decode(json.bytes));
      expect((await db.canvasDao.getNodeById(first))!.x, -1000);
    },
  );

  test(
    'ordinary novel and sticky canvases export without screenplay root or implicit container children',
    () async {
      await db
          .into(db.chapters)
          .insert(
            ChaptersCompanion.insert(
              id: 'volume',
              type: nodeTypeVolume,
              siblingOrder: 0,
              title: const Value('卷'),
            ),
          );
      await db
          .into(db.chapters)
          .insert(
            ChaptersCompanion.insert(
              id: 'unselected',
              type: nodeTypeChapter,
              siblingOrder: 0,
              parentId: const Value('volume'),
              content: const Value('not selected'),
            ),
          );
      await service.addNode(
        canvasId: canvas,
        type: canvasNodeTypeReference,
        refType: 'chapter',
        refId: 'volume',
        x: 0,
        y: 0,
      );
      final novel = await snapshot();
      expect(novel.resources, hasLength(1));
      expect(novel.hasErrors, isFalse);
      expect(novel.issues.any((i) => i['code'] == 'empty_content'), isFalse);
      await _fixture('novel', novel);
      final stickyCanvas = await service.createCanvas(name: 'Sticky');
      await service.addNode(
        canvasId: stickyCanvas,
        type: 'sticky',
        title: '便签',
        content: special,
        x: -800,
        y: -400,
      );
      final sticky = await exporter.snapshot(
        database: db,
        canvasId: stickyCanvas,
        workId: 'work-1',
        contentKind: 'novel',
        exportedAt: exportTime,
      );
      expect(sticky.resources, isEmpty);
      expect(sticky.nodes.single['content'], special);
      await _fixture('sticky', sticky);
    },
  );

  test(
    'all direct resource soft deletions block and retain offending node IDs',
    () async {
      await _seedAll(db, service, canvas);
      final tables = <TableInfo>[
        db.chapters,
        db.outlines,
        db.characterProfiles,
        db.foreshadowings,
        db.locations,
        db.items,
        db.documents,
        db.screenplayScenes,
      ];
      for (final table in tables) {
        await db.customUpdate(
          'UPDATE ${table.actualTableName} SET deleted_at = 123',
          updates: {table},
        );
      }
      final result = await snapshot(kind: 'screenplay');
      final errors = result.issues
          .where((i) => i['code'] == 'invalid_direct_reference')
          .toList();
      expect(errors, hasLength(12));
      expect(errors.every((i) => i['node_id'] != null), isTrue);
      await expectLater(
        exporter.encode(result, CanvasExportFormat.json),
        throwsA(isA<CanvasExportException>()),
      );
    },
  );

  test(
    'empty-content diagnostics cover written resources but do not demand container or character fields',
    () async {
      final scene = await _seedAll(db, service, canvas);
      await (db.update(db.chapters)..where((t) => t.id.equals('chapter')))
          .write(const ChaptersCompanion(content: Value('')));
      await (db.update(db.outlines)
            ..where((t) => t.documentId.equals('outline-document-id')))
          .write(const OutlinesCompanion(content: Value('')));
      await db
          .update(db.outlineBeats)
          .write(
            const OutlineBeatsCompanion(title: Value(''), content: Value('')),
          );
      await (db.update(db.documents)..where((t) => t.id.equals('document')))
          .write(const DocumentsCompanion(content: Value('')));
      await (db.update(db.screenplaySceneElements)..where(
            (t) => t.sceneId.equals(scene) & t.type.isNotValue('scene_heading'),
          ))
          .write(
            ScreenplaySceneElementsCompanion(deletedAt: Value(DateTime(2020))),
          );
      await service.addNode(
        canvasId: canvas,
        type: 'sticky',
        content: '',
        x: 0,
        y: 0,
      );
      await service.addNode(
        canvasId: canvas,
        type: 'reference',
        refType: 'chapter',
        refId: 'volume',
        x: 0,
        y: 0,
      );
      await service.addNode(
        canvasId: canvas,
        type: 'reference',
        refType: 'document',
        refId: 'folder',
        x: 0,
        y: 0,
      );
      final result = await snapshot(kind: 'screenplay');
      final empty = result.issues
          .where((i) => i['code'] == 'empty_content')
          .toList();
      expect(empty, hasLength(5));
      expect(
        empty
            .where((i) => i['resource_id'] != null)
            .map((i) => i['resource_id'])
            .toSet(),
        {'chapter', 'outline-document-id', 'document', scene},
      );
      expect(result.hasErrors, isFalse);
    },
  );

  test(
    'parent cycles stop; missing indirect identities preserve known title without following character relationships',
    () async {
      await db
          .into(db.locations)
          .insert(
            LocationsCompanion.insert(
              id: 'a',
              name: 'A',
              parentId: const Value('b'),
            ),
          );
      await db
          .into(db.locations)
          .insert(
            LocationsCompanion.insert(
              id: 'b',
              name: 'B',
              parentId: const Value('a'),
            ),
          );
      await service.addNode(
        canvasId: canvas,
        type: 'reference',
        refType: 'location',
        refId: 'a',
        x: 0,
        y: 0,
      );
      final result = await snapshot();
      expect(result.resources, hasLength(2));
      expect(
        result.issues.any(
          (i) => i['code'] == 'cycle' && i['resource_type'] == 'location',
        ),
        isTrue,
      );
      expect(result.hasErrors, isFalse);
      await (db.update(db.locations)..where((t) => t.id.equals('b'))).write(
        LocationsCompanion(deletedAt: Value(DateTime(2020))),
      );
      final deleted = await snapshot();
      final b = deleted.resources.singleWhere((r) => r['id'] == 'b');
      expect(b['title'], 'B');
      expect(b['status'], 'missing');
      expect(
        deleted.issues.any((i) => i['code'] == 'missing_dependency'),
        isTrue,
      );
    },
  );

  test(
    'fatal graph errors report IDs, while mixed directions diagnose topology without inventing narrative roots',
    () async {
      final a = await service.addNode(
        canvasId: canvas,
        type: 'sticky',
        content: 'a',
        x: 0,
        y: 0,
      );
      final b = await service.addNode(
        canvasId: canvas,
        type: 'sticky',
        content: 'b',
        x: 300,
        y: 0,
      );
      final c = await service.addNode(
        canvasId: canvas,
        type: 'sticky',
        content: 'c',
        x: 600,
        y: 0,
      );
      await service.addEdge(
        canvasId: canvas,
        sourceNodeId: a,
        targetNodeId: b,
        type: 'relationship',
      );
      var result = await snapshot();
      expect((result.json['analysis'] as Map)['root_node_ids'], isEmpty);
      expect((result.json['analysis'] as Map)['terminal_node_ids'], isEmpty);
      expect((result.json['analysis'] as Map)['isolated_node_ids'], [c]);
      await service.addEdge(
        canvasId: canvas,
        sourceNodeId: a,
        targetNodeId: b,
        type: 'timeline',
      );
      await service.addEdge(
        canvasId: canvas,
        sourceNodeId: b,
        targetNodeId: a,
        type: 'causal',
      );
      result = await snapshot();
      expect((result.json['analysis'] as Map)['cycle_groups'], hasLength(1));
      expect(result.hasErrors, isFalse);
      final row = (await db.canvasDao.getCanvasById(canvas))!;
      final nodes = await db.canvasDao.getNodesByCanvas(canvas),
          edges = await db.canvasDao.getEdgesByCanvas(canvas);
      final invalid = buildCanvasExportSnapshot(
        canvas: row,
        nodes: [
          ...nodes,
          nodes.first.copyWith(x: double.nan),
          nodes.last.copyWith(id: 'unknown', type: 'future'),
        ],
        edges: [
          ...edges,
          edges.first.copyWith(id: 'broken', targetNodeId: 'absent'),
          edges.first.copyWith(type: 'future'),
        ],
        resources: const CanvasResourceCollection({}, []),
        workId: 'work',
        contentKind: 'novel',
        exportedAt: exportTime,
      );
      expect(
        invalid.issues
            .where((i) => i['severity'] == 'error')
            .map((i) => i['code'])
            .toSet(),
        containsAll([
          'duplicate_id',
          'invalid_geometry',
          'unsupported_type',
          'missing_edge_endpoint',
        ]),
      );
      expect(
        invalid.issues.singleWhere(
          (i) => i['code'] == 'missing_edge_endpoint',
        )['edge_id'],
        'broken',
      );
      expect(
        () => canvasExportSvg(invalid, _preview(invalid)),
        throwsA(isA<CanvasExportException>()),
      );
    },
  );

  for (final (direction, offset, directed) in [
    ('down', const Offset(0, 500), true),
    ('up', const Offset(0, -500), true),
    ('right', const Offset(500, 0), true),
    ('left', const Offset(-500, 0), true),
    ('diagonal', const Offset(500, 500), true),
    ('self-loop', Offset.zero, true),
    ('undirected', const Offset(0, 500), false),
  ]) {
    test('SVG arrow direction follows the actual curve: $direction', () async {
      final a = await service.addNode(
        canvasId: canvas,
        type: 'sticky',
        content: 'A',
        x: 0,
        y: 0,
      );
      final b = await service.addNode(
        canvasId: canvas,
        type: 'sticky',
        content: 'B',
        x: offset.dx,
        y: offset.dy,
      );
      final edge = CanvasEdge(
        id: 'direction',
        canvasId: canvas,
        sourceNodeId: a,
        targetNodeId: direction == 'self-loop' ? a : b,
        type: directed ? 'timeline' : 'relationship',
        createdAt: exportTime,
        updatedAt: exportTime,
      );
      final result = buildCanvasExportSnapshot(
        canvas: (await db.canvasDao.getCanvasById(canvas))!,
        nodes: await db.canvasDao.getNodesByCanvas(canvas),
        edges: [edge],
        resources: const CanvasResourceCollection({}, []),
        workId: 'work',
        contentKind: 'novel',
        exportedAt: exportTime,
      );
      final paths = XmlDocument.parse(
        canvasExportSvg(result, _preview(result)),
      ).findAllElements('path').toList();
      final arrows = paths
          .where((path) => path.getAttribute('d')!.endsWith('Z'))
          .toList();
      expect(arrows, hasLength(directed ? 1 : 0));
      if (!directed) {
        return;
      }
      List<Offset> vertices(XmlElement path) {
        final values = RegExp(r'-?\d+(?:\.\d+)?(?:e[+-]?\d+)?')
            .allMatches(path.getAttribute('d')!)
            .map((match) => double.parse(match[0]!))
            .toList();
        return [
          for (var i = 0; i < values.length; i += 2)
            Offset(values[i], values[i + 1]),
        ];
      }

      final triangle = vertices(arrows.single);
      final base = (triangle[1] + triangle[2]) / 2;
      final arrow = triangle[0] - base;
      final curve = vertices(
        paths.singleWhere((path) => path.getAttribute('fill') == 'none'),
      );
      // 与画布一致：线停在箭头底边，箭头尖端再往前伸进留白。
      expect(base, curve.last);
      // 末段的最后一个控制点（或直线段起点）到终点即入射切线方向。
      final incoming =
          curve.last - curve.lastWhere((point) => point != curve.last);
      final alignment =
          (arrow.dx * incoming.dx + arrow.dy * incoming.dy) /
          (arrow.distance * incoming.distance);
      expect(
        alignment,
        greaterThan(0.999),
        reason: '$direction arrow must point along the SVG curve',
      );
      switch (direction) {
        case 'down':
          expect(arrow.dx, closeTo(0, 0.0001));
          expect(arrow.dy, greaterThan(0));
        case 'up':
          expect(arrow.dx, closeTo(0, 0.0001));
          expect(arrow.dy, lessThan(0));
        case 'right':
          expect(arrow.dx, greaterThan(0));
          expect(arrow.dy, closeTo(0, 0.0001));
        case 'left':
          expect(arrow.dx, lessThan(0));
          expect(arrow.dy, closeTo(0, 0.0001));
      }
    });
  }

  test(
    'SVG follows tree_tb routing: axis ports and lanes for long edges',
    () async {
      var column = 0;
      Future<String> sticky(String text) => service.addNode(
        canvasId: canvas,
        type: 'sticky',
        content: text,
        x: 400.0 * column++,
        y: 0,
      );
      final a = await sticky('A'), b = await sticky('B');
      final c = await sticky('C'), d = await sticky('D');
      for (final (source, target) in [(a, b), (b, c), (c, d), (a, d)]) {
        await service.addEdge(
          canvasId: canvas,
          sourceNodeId: source,
          targetNodeId: target,
          type: 'timeline',
        );
      }
      await service.applyLayout(canvas, 'tree_tb');
      final rows = await db.canvasDao.getNodesByCanvas(canvas);
      final result = buildCanvasExportSnapshot(
        canvas: (await db.canvasDao.getCanvasById(canvas))!,
        nodes: rows,
        edges: await db.canvasDao.getEdgesByCanvas(canvas),
        resources: const CanvasResourceCollection({}, []),
        workId: 'work',
        contentKind: 'novel',
        exportedAt: exportTime,
      );
      final curves =
          XmlDocument.parse(canvasExportSvg(result, _preview(result)))
              .findAllElements('path')
              .where((path) => path.getAttribute('fill') == 'none')
              .map((path) => path.getAttribute('d')!)
              .toList();
      expect(curves, hasLength(4));
      final byId = {for (final row in rows) row.id: row};
      Offset bottom(String id) => Offset(
        byId[id]!.x + (byId[id]!.width ?? canvasStickyDefaultWidth) / 2,
        byId[id]!.y + (byId[id]!.height ?? canvasStickyDefaultHeight) + 4,
      );
      final chained = curves.where((d) => 'C'.allMatches(d).length > 1);
      expect(chained, hasLength(1), reason: 'A→D skips two layers');
      expect(chained.single, startsWith('M ${bottom(a).dx} ${bottom(a).dy} C'));
      for (final d in curves) {
        final start = RegExp(r'^M (\S+) (\S+)').firstMatch(d)!;
        expect(
          [a, b, c].map(bottom),
          contains(Offset(double.parse(start[1]!), double.parse(start[2]!))),
          reason: 'directed edges leave from the bottom edge in tree_tb',
        );
      }
    },
  );

  test(
    'SVG viewBox includes negative nodes, self-loop controls and complete multiline labels',
    () async {
      final a = await service.addNode(
        canvasId: canvas,
        type: 'sticky',
        title: '多行\n标题',
        content: '预览正文',
        x: -700,
        y: -400,
      );
      final b = await service.addNode(
        canvasId: canvas,
        type: 'sticky',
        content: 'B',
        x: 400,
        y: 300,
      );
      await service.addEdge(
        canvasId: canvas,
        sourceNodeId: a,
        targetNodeId: b,
        type: 'timeline',
        label: '${'很长的连线说明' * 40}\n第二行',
      );
      final rows = await db.canvasDao.getNodesByCanvas(canvas);
      final edges = await db.canvasDao.getEdgesByCanvas(canvas);
      final result = buildCanvasExportSnapshot(
        canvas: (await db.canvasDao.getCanvasById(canvas))!,
        nodes: rows,
        edges: [
          ...edges,
          edges.single.copyWith(id: 'self', targetNodeId: a),
        ],
        resources: const CanvasResourceCollection({}, []),
        workId: 'work',
        contentKind: 'novel',
        exportedAt: exportTime,
      );
      final document = XmlDocument.parse(
        canvasExportSvg(result, _preview(result)),
      );
      final view = document.rootElement
          .getAttribute('viewBox')!
          .split(' ')
          .map(double.parse)
          .toList();
      final right = view[0] + view[2], bottom = view[1] + view[3];
      // 图标内联的 rect 处在自己的 viewBox 坐标里，只核对画布坐标下的矩形。
      for (final rect
          in document
              .findAllElements('rect')
              .where(
                (rect) => rect.ancestorElements.every(
                  (e) => e.name.local != 'svg' || e == document.rootElement,
                ),
              )) {
        final x = double.parse(rect.getAttribute('x')!),
            y = double.parse(rect.getAttribute('y')!);
        expect(x, greaterThanOrEqualTo(view[0]));
        expect(y, greaterThanOrEqualTo(view[1]));
        expect(
          x + double.parse(rect.getAttribute('width')!),
          lessThanOrEqualTo(right),
        );
        expect(
          y + double.parse(rect.getAttribute('height')!),
          lessThanOrEqualTo(bottom),
        );
      }
      expect(
        document.findAllElements('text').where((e) => e.innerText == '第二行'),
        hasLength(2),
      );
      // 最长一行标签（按 _preview 的字宽）完整落在 viewBox 内。
      expect(view[2], greaterThan('很长的连线说明'.length * 40 * 11.0));
      expect(view[0], lessThan(-700));
    },
  );

  test(
    'single read transaction cannot mix graph snapshot and a concurrent source update',
    () async {
      final database = _BarrierDatabase();
      addTearDown(database.close);
      final writer = CanvasService(database);
      final id = await writer.createCanvas(name: 'Snapshot');
      await database
          .into(database.documents)
          .insert(
            DocumentsCompanion.insert(
              id: 'doc',
              type: 'material',
              title: 'Before',
              content: const Value('Before content'),
            ),
          );
      await writer.addNode(
        canvasId: id,
        type: 'reference',
        refType: 'document',
        refId: 'doc',
        x: 0,
        y: 0,
      );
      database.pause = true;
      final collecting = exporter.snapshot(
        database: database,
        canvasId: id,
        workId: 'work',
        contentKind: 'novel',
      );
      await database.entered.future;
      var wrote = false;
      final writing =
          (database.update(database.documents)
                ..where((t) => t.id.equals('doc')))
              .write(
                const DocumentsCompanion(
                  title: Value('After'),
                  content: Value('After content'),
                ),
              )
              .then((_) => wrote = true);
      await Future<void>.delayed(Duration.zero);
      expect(wrote, isFalse);
      database.release.complete();
      final result = await collecting;
      await writing;
      expect(result.resources.single['title'], 'Before');
      expect(
        (result.resources.single['payload'] as Map)['content'],
        'Before content',
      );
      expect((await database.documentDao.getById('doc'))!.title, 'After');
    },
  );

  test(
    'scene moves read current season, episode and number; deleted parents block direct references',
    () async {
      final scene = await _seedAll(db, service, canvas);
      final writer = ScreenplayService(db);
      final root = (await db.screenplayDao.getRoot())!.id;
      final target = await writer.createSeason(screenplayId: root);
      await writer.createScene(
        screenplayId: root,
        episodeId: target.episodeId,
        title: 'Anchor',
      );
      await writer.moveSceneToEpisodeEnd(scene, target.episodeId);
      await writer.updateScene(sceneId: scene, title: 'Moved scene');
      final result = await snapshot(kind: 'screenplay');
      final sceneResource = result.resources.singleWhere(
        (r) => r['id'] == scene,
      );
      final payload = sceneResource['payload'] as Map;
      expect(sceneResource['title'], 'Moved scene');
      expect((payload['season'] as Map)['id'], target.seasonId);
      expect((payload['episode'] as Map)['id'], target.episodeId);
      expect(payload['scene_number'], 2);
      expect(result.nodes.where((n) => n['ref_id'] == scene), hasLength(2));
      await (db.update(db.screenplaySeasons)
            ..where((t) => t.id.equals(target.seasonId)))
          .write(ScreenplaySeasonsCompanion(deletedAt: Value(DateTime(2020))));
      final invalid = await snapshot(kind: 'screenplay');
      expect(
        invalid.issues.where(
          (i) =>
              i['code'] == 'invalid_direct_reference' &&
              i['resource_id'] == scene,
        ),
        hasLength(2),
      );
    },
  );

  for (final corruption in ['missing_heading', 'wrong_episode']) {
    test(
      '$corruption blocks direct scenes and marks dependencies missing',
      () async {
        final scene = await _seedAll(db, service, canvas);
        await (db.update(db.screenplaySceneElements)..where(
              (t) => t.sceneId.equals(scene) & t.type.equals('scene_heading'),
            ))
            .write(
              corruption == 'missing_heading'
                  ? ScreenplaySceneElementsCompanion(
                      deletedAt: Value(exportTime),
                    )
                  : const ScreenplaySceneElementsCompanion(
                      episodeId: Value('missing-episode'),
                    ),
            );
        final direct = await snapshot(kind: 'screenplay');
        expect(
          direct.issues.where(
            (issue) =>
                issue['code'] == 'invalid_direct_reference' &&
                issue['resource_id'] == scene,
          ),
          hasLength(2),
        );
        final nodes = await db.canvasDao.getNodesByCanvas(canvas);
        final indirect = await collectCanvasResources(
          db,
          nodes
              .where((node) => node.refType == entityTypeForeshadowing)
              .toList(),
        );
        expect(
          indirect.resources['screenplay_scene:$scene']!['status'],
          'missing',
        );
        expect(
          indirect.issues.where(
            (issue) =>
                issue['code'] == 'missing_dependency' &&
                issue['resource_id'] == scene,
          ),
          hasLength(1),
        );
      },
    );
  }

  for (final count in [500, 5000]) {
    test(
      '$count nodes and ${count * 2} edges export completely without recursion or truncation',
      () async {
        final row = (await db.canvasDao.getCanvasById(canvas))!;
        final nodes = [
          for (var i = 0; i < count; i++)
            CanvasNode(
              id: 'n$i',
              canvasId: canvas,
              type: 'sticky',
              title: 'Node $i',
              content: 'Body $i',
              x: (i % 20) * 400.0,
              y: (i ~/ 20) * 248.0,
              zIndex: 0,
              sortOrder: i,
              createdAt: exportTime,
              updatedAt: exportTime,
              deletedAt: notDeletedSentinel,
            ),
        ];
        final edges = [
          for (var i = 0; i < count * 2; i++)
            CanvasEdge(
              id: 'e$i',
              canvasId: canvas,
              sourceNodeId: 'n${i % count}',
              targetNodeId: 'n${(i + 1 + i ~/ count) % count}',
              type: i < count ? 'timeline' : 'relationship',
              label: 'Edge $i',
              createdAt: exportTime,
              updatedAt: exportTime,
            ),
        ];
        final result = buildCanvasExportSnapshot(
          canvas: row,
          nodes: nodes,
          edges: edges,
          resources: const CanvasResourceCollection({}, []),
          workId: 'work',
          contentKind: 'novel',
          exportedAt: exportTime,
        );
        final artifact = await exporter.encode(result, CanvasExportFormat.json);
        final decoded = jsonDecode(utf8.decode(artifact.bytes)) as Map;
        expect(
          (decoded['nodes'] as List).map((n) => n['id']).toSet(),
          nodes.map((n) => n.id).toSet(),
        );
        expect(
          (decoded['edges'] as List).map((e) => e['id']).toSet(),
          edges.map((e) => e.id).toSet(),
        );
        expect((decoded['analysis'] as Map)['cycle_groups'], hasLength(1));
      },
    );
  }

  test(
    '10 MiB Chinese body survives isolate encoding while the event loop and later edits continue',
    () async {
      final text = '中' * (10 * 1024 * 1024 ~/ 3) + '结尾';
      final node = await service.addNode(
        canvasId: canvas,
        type: 'sticky',
        content: text,
        x: 0,
        y: 0,
      );
      final result = await snapshot();
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );
      final watch = Stopwatch()..start();
      final encoding = exporter.encode(
        result,
        CanvasExportFormat.zip,
        preview: _preview(result),
      );
      await service.updateNodeContent(nodeId: node, content: 'After snapshot');
      final artifact = await encoding;
      timer.cancel();
      watch.stop();
      final files = ZipDecoder().decodeBytes(artifact.bytes);
      final json =
          jsonDecode(
                utf8.decode(
                  files.findFile('canvas.json')!.content as List<int>,
                ),
              )
              as Map;
      expect((json['nodes'] as List).single['content'], text);
      expect(
        utf8.decode(files.findFile('review.md')!.content as List<int>),
        contains(text),
      );
      expect((await db.canvasDao.getNodeById(node))!.content, 'After snapshot');
      expect(ticks, greaterThan(0));
      // ignore: avoid_print
      print(
        '10 MiB Chinese ZIP encode: ${watch.elapsedMilliseconds} ms; event-loop ticks=$ticks; bytes=${artifact.bytes.length}',
      );
    },
  );
}

Future<String> _seedAll(
  NovelContentDatabase db,
  CanvasService service,
  String canvas,
) async {
  for (final (id, parent) in [
    ('root-volume', null),
    ('volume', 'root-volume'),
  ]) {
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            id: id,
            type: nodeTypeVolume,
            siblingOrder: 0,
            title: Value(id),
            parentId: Value(parent),
          ),
        );
  }
  for (final id in ['first', 'secret-first', 'unselected-child']) {
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            id: id,
            type: nodeTypeChapter,
            siblingOrder: 0,
            title: Value(id),
            parentId: const Value('volume'),
            content: const Value('not selected'),
          ),
        );
  }
  await db
      .into(db.chapters)
      .insert(
        ChaptersCompanion.insert(
          id: 'chapter',
          type: nodeTypeChapter,
          siblingOrder: 3,
          title: const Value('章节'),
          parentId: const Value('volume'),
          content: const Value(special),
          outline: const Value('写前'),
          brief: const Value('写后'),
          wordCount: const Value(77),
        ),
      );
  await db
      .into(db.outlines)
      .insert(
        OutlinesCompanion.insert(
          documentId: 'outline-document-id',
          title: const Value('大纲'),
          content: const Value('大纲正文'),
          startChapterNum: const Value(5),
        ),
      );
  for (final i in [2, 1]) {
    await db
        .into(db.outlineBeats)
        .insert(
          OutlineBeatsCompanion.insert(
            id: 'beat-$i',
            outlineDocumentId: 'outline-document-id',
            title: Value(i == 1 ? '节拍一' : '节拍二'),
            content: Value(i == 1 ? '节拍正文一' : '节拍正文二'),
            chapterCount: Value(i + 1),
            sortOrder: Value(i),
          ),
        );
  }
  await db
      .into(db.characterProfiles)
      .insert(
        CharacterProfilesCompanion.insert(
          id: 'character',
          name: '人物',
          aliases: const Value(['旧名', '称号']),
          tags: const Value(['人物标签']),
          biography: const Value('小传'),
          appearance: const Value('外貌'),
          description: const Value('描述'),
          currentState: const Value('近况'),
          identity: const Value('身份'),
          age: const Value('二十'),
          motivation: const Value('动机'),
          arc: const Value('弧光'),
          personality: const Value('性格'),
          behaviorTags: const Value([
            CharacterBehaviorTag(tag: '行为', context: '情境'),
          ]),
          firstAppearChapterId: const Value('first'),
          avatarAssetId: const Value('/private-avatar'),
          photos: const Value([SubjectPhoto(assetId: '/private-photo')]),
        ),
      );
  await db
      .into(db.characterProfiles)
      .insert(
        CharacterProfilesCompanion.insert(
          id: 'guest',
          name: '配角',
          firstAppearChapterId: const Value('secret-first'),
          biography: const Value('not selected'),
        ),
      );
  await db
      .into(db.locations)
      .insert(LocationsCompanion.insert(id: 'country', name: '国家'));
  await db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: 'location',
          name: '地点',
          description: const Value('地点正文'),
          tags: const Value('地点,标签'),
          parentId: const Value('country'),
          meta: const Value({'secret': 'SECRET_META'}),
        ),
      );
  for (final type in ['item', 'faction', 'skill', 'creature']) {
    await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            id: type,
            type: type,
            title: type,
            content: Value('$type 正文'),
            category: Value('$type 分类'),
            photos: const Value([SubjectPhoto(assetId: 'private-photo')]),
          ),
        );
  }
  await db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          id: 'folder',
          type: 'material',
          title: '目录',
          isFolder: const Value(true),
        ),
      );
  await db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          id: 'document',
          type: 'historical-custom-type',
          title: '文档',
          content: const Value('文档正文'),
          category: const Value('文档分类'),
          tags: const Value('文档,标签'),
          parentId: const Value('folder'),
        ),
      );
  final screenplay = ScreenplayService(db);
  final initial = await screenplay.createInitialStructure();
  final root = (await db.screenplayDao.getRoot())!.id;
  final scene = await screenplay.createScene(
    screenplayId: root,
    episodeId: initial.episodeId,
    title: '场次',
  );
  await screenplay.updateScene(
    sceneId: scene,
    locationId: const Value('location'),
    interiorExterior: const Value('interior'),
    timeLabel: '夜',
    synopsis: '场次梗概',
  );
  final heading = (await db.screenplayDao.getScene(scene))!.heading;
  for (final (index, type) in [
    'action',
    'character',
    'parenthetical',
    'dialogue',
    'transition',
    'subtitle',
    'note',
  ].indexed) {
    await db
        .into(db.screenplaySceneElements)
        .insert(
          ScreenplaySceneElementsCompanion.insert(
            id: 'element-$type',
            sceneId: scene,
            episodeId: initial.episodeId,
            sortOrder: heading.sortOrder + index + 1,
            type: type,
            textContent: Value(
              type == 'character'
                  ? ''
                  : type == 'note'
                  ? '作者 note\n完整注释'
                  : type == 'dialogue'
                  ? '第一行对白\n第二行对白'
                  : '$type 正文',
            ),
            characterId: Value(type == 'character' ? 'guest' : null),
            extension: Value(type == 'character' ? 'O.S.' : ''),
          ),
        );
  }
  await db
      .into(db.foreshadowings)
      .insert(
        ForeshadowingsCompanion.insert(
          id: 'foreshadowing',
          title: '伏笔',
          setup: const Value('铺垫'),
          payoff: const Value('兑现'),
          setupChapterId: const Value('chapter'),
          payoffChapterId: const Value('missing-chapter'),
          setupSceneId: Value(scene),
        ),
      );
  for (final type in canvasNodeRefTypes) {
    await service.addNode(
      canvasId: canvas,
      type: 'reference',
      refType: type,
      refId: type == 'outline'
          ? 'outline-document-id'
          : type == 'screenplay_scene'
          ? scene
          : type,
      x: 10,
      y: 20,
    );
  }
  await service.addNode(
    canvasId: canvas,
    type: 'reference',
    refType: 'screenplay_scene',
    refId: scene,
    x: 400,
    y: 200,
  );
  await service.addNode(
    canvasId: canvas,
    type: 'sticky',
    title: '标题 <&>',
    content: special,
    x: -200,
    y: -100,
  );
  final nodes = await db.canvasDao.getNodesByCanvas(canvas);
  await service.addEdge(
    canvasId: canvas,
    sourceNodeId: nodes.first.id,
    targetNodeId: nodes.last.id,
    type: 'timeline',
    label: '第一行 <&>\n第二行',
  );
  await service.applyLayout(canvas, 'grid');
  return scene;
}

Future<void> _fixture(String name, CanvasExportSnapshot snapshot) async {
  final path = Platform.environment['CANVAS_EXPORT_FIXTURE_DIR'];
  if (path == null) {
    return;
  }
  final dir = await Directory(path).create(recursive: true);
  await File(
    '${dir.path}/$name.json',
  ).writeAsString(canvasExportJson(snapshot));
  await File(
    '${dir.path}/canvas.schema.json',
  ).writeAsString(jsonEncode(canvasExportSchema()));
}

class _BarrierDatabase extends NovelContentDatabase {
  _BarrierDatabase() : super.forTest(NativeDatabase.memory());
  bool pause = false;
  final entered = Completer<void>(), release = Completer<void>();
  late final CanvasDao _dao = _BarrierDao(this);
  @override
  CanvasDao get canvasDao => _dao;
}

class _BarrierDao extends CanvasDao {
  _BarrierDao(this.owner) : super(owner);
  final _BarrierDatabase owner;
  @override
  Future<List<CanvasEdge>> getEdgesByCanvas(String id) async {
    final rows = await super.getEdgesByCanvas(id);
    if (owner.pause) {
      owner.pause = false;
      owner.entered.complete();
      await owner.release.future;
    }
    return rows;
  }
}

/// 纯值预览：每张卡片、每条连线一份外观，文字按原文单行。桌面端的真实解析见
/// test/desktop/features/canvas/export_preview_test.dart。
CanvasExportPreview _preview(CanvasExportSnapshot snapshot) {
  const style = CanvasExportTextStyle(
    fontSize: 13,
    fontWeight: 400,
    color: Color(0xFF30343B),
    lineHeight: 18,
    ascent: 14,
  );
  CanvasExportText text(String value) =>
      CanvasExportText(lines: value.split('\n'), style: style);
  return CanvasExportPreview(
    background: const Color(0xFFF7F7F4),
    strokeWidth: 1.8,
    labelBackground: const Color(0xFFF7F7F4),
    labelRadius: 4,
    labelPaddingX: 6,
    labelPaddingY: 1,
    shadows: const [],
    icons: const {
      'icon':
          '<svg viewBox="0 0 256 256"><rect width="256" height="256"/></svg>',
    },
    nodes: {
      for (final node in snapshot.nodes)
        node['id'] as String? ?? '': node['type'] == 'sticky'
            ? CanvasExportStickyFace(
                fill: const Color(0xFFF4ECD8),
                border: const Color(0x1F000000),
                icon: 'icon',
                iconColor: const Color(0x85000000),
                label: text(node['title'] as String? ?? ''),
                body: text(node['content'] as String? ?? ''),
              )
            : CanvasExportReferenceFace(
                fill: const Color(0xFFFFFFFF),
                border: const Color(0xFFC9CCC5),
                chipFill: const Color(0x21000000),
                icon: 'icon',
                iconColor: const Color(0xFF000000),
                title: text(node['title'] as String? ?? ''),
                subtitle: text(node['ref_type'] as String? ?? ''),
              ),
    },
    edges: {
      for (final edge in snapshot.edges)
        edge['id'] as String? ?? '': CanvasExportEdgeFace(
          color: const Color(0xFF78808A),
          label: (edge['label'] as String? ?? '').isEmpty
              ? null
              : text(edge['label'] as String),
          labelWidth: (edge['label'] as String? ?? '')
              .split('\n')
              .map((line) => line.runes.length * 11.0)
              .fold(0, math.max),
        ),
    },
  );
}
