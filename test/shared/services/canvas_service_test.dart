// 职责: 测试 CanvasService — 校验/级联/引用标题刷新/不污染 entity_graph
// 关联文件:
//   lib/shared/services/canvas_service.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/database/novel_content_daos/canvas_dao.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/database/novel_content_daos/canvas_dao.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/shared/services/canvas_service.dart';
import 'package:reveric/shared/utils/short_entity_id.dart';

void main() {
  late NovelContentDatabase db;
  late CanvasService service;

  setUp(() {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    service = CanvasService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('atomic layout', () {
    Future<(String, String, String)> seed(CanvasService subject) async {
      final canvasId = await subject.createCanvas(name: 'Layout');
      final a = await subject.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeSticky,
        content: 'A',
        x: 999,
        y: 555,
      );
      final b = await subject.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeSticky,
        content: 'B',
        x: 100,
        y: 700,
      );
      await subject.addEdge(
        canvasId: canvasId,
        sourceNodeId: a,
        targetNodeId: b,
        type: canvasEdgeTypeTimeline,
        label: 'Choice',
      );
      return (canvasId, a, b);
    }

    test(
      'arrange modes persist, tidy keeps mode, edits retain last mode',
      () async {
        final (canvasId, a, b) = await seed(service);
        for (final mode in canvasLayoutSavedModes) {
          await service.applyLayout(canvasId, mode);
          expect((await db.canvasDao.getCanvasById(canvasId))!.layout, mode);
        }
        final old = DateTime.fromMillisecondsSinceEpoch(100000);
        await (db.update(db.canvases)..where((c) => c.id.equals(canvasId)))
            .write(CanvasesCompanion(updatedAt: Value(old)));
        final unchanged = await service.applyLayout(canvasId, canvasLayoutGrid);
        expect(unchanged.moved, 0);
        expect(unchanged.modeChanged, isFalse);
        expect((await db.canvasDao.getCanvasById(canvasId))!.updatedAt, old);
        final tidy = await service.applyLayout(canvasId, canvasLayoutTidy);
        expect(tidy.moved, 0);
        expect(tidy.modeChanged, isFalse);
        expect((await db.canvasDao.getCanvasById(canvasId))!.updatedAt, old);
        await service.updateNodePosition(nodeId: a, x: 123, y: 456);
        await service.updateNodeContent(nodeId: b, content: 'Edited');
        await service.renameCanvas(canvasId: canvasId, name: 'Renamed');
        expect(
          (await db.canvasDao.getCanvasById(canvasId))!.layout,
          canvasLayoutGrid,
        );
        expect((await db.canvasDao.getNodeById(a))!.x, 123);
        expect((await db.canvasDao.getNodeById(b))!.content, 'Edited');
      },
    );
    test('tidy reruns the saved layout and never saves itself', () async {
      final (canvasId, a, _) = await seed(service);
      expect(
        (await service.applyLayout(canvasId, canvasLayoutTidy)).modeChanged,
        isFalse,
      );
      expect((await db.canvasDao.getCanvasById(canvasId))!.layout, isNull);

      await service.applyLayout(canvasId, canvasLayoutTreeTb);
      final arranged = await db.canvasDao.getNodeById(a);
      await service.updateNodePosition(nodeId: a, x: 3000, y: 3000);
      final tidy = await service.applyLayout(canvasId, canvasLayoutTidy);
      expect(tidy.moved, 1);
      expect(tidy.modeChanged, isFalse);
      final node = await db.canvasDao.getNodeById(a);
      expect((node!.x, node.y), (arranged!.x, arranged.y));
      expect(
        (await db.canvasDao.getCanvasById(canvasId))!.layout,
        canvasLayoutTreeTb,
      );
    });
    test(
      'zero or one node saves mode; undirected multi-node graph rejects tree',
      () async {
        final id = await service.createCanvas(name: 'Empty');
        expect((await service.applyLayout(id, canvasLayoutTreeLr)).moved, 0);
        expect(
          (await db.canvasDao.getCanvasById(id))!.layout,
          canvasLayoutTreeLr,
        );
        final a = await service.addNode(
          canvasId: id,
          type: canvasNodeTypeSticky,
          content: 'A',
          x: 15,
          y: 15,
        );
        expect((await service.applyLayout(id, canvasLayoutGrid)).moved, 0);
        final b = await service.addNode(
          canvasId: id,
          type: canvasNodeTypeSticky,
          content: 'B',
          x: 25,
          y: 25,
        );
        await service.addEdge(
          canvasId: id,
          sourceNodeId: a,
          targetNodeId: b,
          type: canvasEdgeTypeRelationship,
        );
        final before = await db.canvasDao.getNodesByCanvas(id);
        await expectLater(
          service.applyLayout(id, canvasLayoutTreeTb),
          throwsA(
            isA<CanvasServiceException>().having(
              (e) => e.errorCode,
              'code',
              'layout_requires_directed_edges',
            ),
          ),
        );
        expect(await db.canvasDao.getNodesByCanvas(id), before);
        expect(
          (await db.canvasDao.getCanvasById(id))!.layout,
          canvasLayoutGrid,
        );
      },
    );
    for (final change in [
      'position',
      'size',
      'content',
      'nodes',
      'edges',
      'layout',
    ]) {
      test(
        '$change during calculation conflicts without partial writes',
        () async {
          final (id, a, b) = await seed(service);
          late List<CanvasNode> expectedNodes;
          late List<CanvasEdge> expectedEdges;
          late CanvasEntry expectedCanvas;
          final concurrent = CanvasService(
            db,
            layoutComputer: (request) async {
              switch (change) {
                case 'position':
                  await service.updateNodePosition(nodeId: a, x: 77, y: 88);
                case 'size':
                  await service.updateNodeGeometry(
                    nodeId: a,
                    position: const Offset(999, 555),
                    size: const Size(330, 210),
                  );
                case 'content':
                  await service.updateNodeContent(
                    nodeId: a,
                    content: 'New draft',
                  );
                case 'nodes':
                  await service.addNode(
                    canvasId: id,
                    type: canvasNodeTypeSticky,
                    content: 'New node',
                    x: 0,
                    y: 0,
                  );
                case 'edges':
                  await service.addEdge(
                    canvasId: id,
                    sourceNodeId: b,
                    targetNodeId: a,
                    type: canvasEdgeTypeCausal,
                  );
                case 'layout':
                  await db.canvasDao.updateLayout(id, canvasLayoutAuto);
              }
              expectedNodes = await db.canvasDao.getNodesByCanvas(id);
              expectedEdges = await db.canvasDao.getEdgesByCanvas(id);
              expectedCanvas = (await db.canvasDao.getCanvasById(id))!;
              return resolveCanvasGridLayout(request.nodes);
            },
          );
          await expectLater(
            concurrent.applyLayout(id, canvasLayoutGrid),
            throwsA(
              isA<CanvasServiceException>().having(
                (e) => e.errorCode,
                'code',
                'layout_conflict',
              ),
            ),
          );
          expect(await db.canvasDao.getNodesByCanvas(id), expectedNodes);
          expect(await db.canvasDao.getEdgesByCanvas(id), expectedEdges);
          expect(await db.canvasDao.getCanvasById(id), expectedCanvas);
        },
      );
    }
    for (final field in ['content', 'title', 'style', 'position']) {
      test(
        '$field read before layout cannot restore unrelated stale fields',
        () async {
          final racingDb = _NodeReadBarrierDatabase();
          addTearDown(racingDb.close);
          final writer = CanvasService(racingDb);
          final arranger = CanvasService(racingDb);
          final (canvasId, a, _) = await seed(writer);
          final before = (await racingDb.canvasDao.getNodeById(a))!;
          racingDb.blockNodeId = a;
          final write = switch (field) {
            'content' => writer.updateNodeContent(
              nodeId: a,
              content: 'Updated body',
            ),
            'title' => writer.updateNodeTitle(
              nodeId: a,
              title: 'Updated title',
            ),
            'style' => writer.updateNodeStyle(
              nodeId: a,
              style: {'sticky_color': 'sage'},
            ),
            _ => writer.updateNodePosition(nodeId: a, x: 123, y: 456),
          };
          await racingDb.didRead.future;
          expect(
            (await arranger.applyLayout(canvasId, canvasLayoutGrid)).moved,
            2,
          );
          if (field == 'position') {
            await arranger.updateNodeContent(
              nodeId: a,
              content: 'Concurrent body',
            );
          }
          final arranged = (await racingDb.canvasDao.getNodeById(a))!;
          expect((arranged.x, arranged.y), isNot((before.x, before.y)));
          racingDb.releaseRead.complete();
          await write;
          final saved = (await racingDb.canvasDao.getNodeById(a))!;
          expect((
            saved.x,
            saved.y,
          ), field == 'position' ? (123.0, 456.0) : (arranged.x, arranged.y));
          expect(
            (saved.width, saved.height),
            (arranged.width, arranged.height),
          );
          expect(
            saved.content,
            field == 'content' ? 'Updated body' : arranged.content,
          );
          expect(
            saved.title,
            field == 'title' ? 'Updated title' : arranged.title,
          );
          expect(
            saved.style,
            field == 'style' ? {'sticky_color': 'sage'} : arranged.style,
          );
          expect(
            (await racingDb.canvasDao.getCanvasById(canvasId))!.layout,
            canvasLayoutGrid,
          );
        },
      );
    }

    test('concurrent rename and description survive layout commit', () async {
      final (id, _, _) = await seed(service);
      final concurrent = CanvasService(
        db,
        layoutComputer: (request) async {
          await service.renameCanvas(canvasId: id, name: 'New name');
          await service.updateCanvasDescription(
            canvasId: id,
            description: 'New description',
          );
          return resolveCanvasGridLayout(request.nodes);
        },
      );
      expect((await concurrent.applyLayout(id, canvasLayoutGrid)).moved, 2);
      final saved = (await db.canvasDao.getCanvasById(id))!;
      expect(
        (saved.name, saved.description, saved.layout),
        ('New name', 'New description', canvasLayoutGrid),
      );
    });
    for (final failure in ['nodes', 'layout']) {
      test(
        '$failure write failure rolls back coordinates and layout',
        () async {
          final faultDb = _LayoutFailureDatabase();
          try {
            final faultService = CanvasService(faultDb);
            final (id, _, _) = await seed(faultService);
            final beforeNodes = await faultDb.canvasDao.getNodesByCanvas(id);
            final beforeCanvas = await faultDb.canvasDao.getCanvasById(id);
            faultDb.failAt = failure;
            await expectLater(
              faultService.applyLayout(id, canvasLayoutGrid),
              throwsStateError,
            );
            expect(await faultDb.canvasDao.getNodesByCanvas(id), beforeNodes);
            expect(await faultDb.canvasDao.getCanvasById(id), beforeCanvas);
          } finally {
            await faultDb.close();
          }
        },
      );
    }
    test('reopening restores chosen mode and final coordinates', () async {
      final dir = await Directory.systemTemp.createTemp(
        'canvas-layout-reopen-',
      );
      final file = File('${dir.path}/content.sqlite');
      final first = NovelContentDatabase.forTest(NativeDatabase(file));
      final initialService = CanvasService(first);
      final (id, _, _) = await seed(initialService);
      await initialService.applyLayout(id, canvasLayoutTreeTb);
      final nodes = await first.canvasDao.getNodesByCanvas(id);
      await first.close();
      final reopened = NovelContentDatabase.forTest(NativeDatabase(file));
      try {
        expect(
          (await reopened.canvasDao.getCanvasById(id))!.layout,
          canvasLayoutTreeTb,
        );
        expect(await reopened.canvasDao.getNodesByCanvas(id), nodes);
      } finally {
        await reopened.close();
        await dir.delete(recursive: true);
      }
    });
  });

  // ---- 资源造数 helpers ----

  Future<void> insertCharacter(String id, String name) async {
    final now = DateTime.now();
    await db
        .into(db.characterProfiles)
        .insert(
          CharacterProfilesCompanion.insert(
            id: id,
            name: name,
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> renameCharacter(String id, String name) async {
    await (db.update(
      db.characterProfiles,
    )..where((t) => t.id.equals(id))).write(
      CharacterProfilesCompanion(
        name: Value(name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> insertChapter(String id, String title) async {
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            id: id,
            type: nodeTypeChapter,
            siblingOrder: 1,
            title: Value(title),
          ),
        );
  }

  Future<void> insertForeshadowing(String id, String title) async {
    await db
        .into(db.foreshadowings)
        .insert(ForeshadowingsCompanion.insert(id: id, title: title));
  }

  Future<void> insertLocation(String id, String name) async {
    await db
        .into(db.locations)
        .insert(LocationsCompanion.insert(id: id, name: name));
  }

  Future<void> insertItem(String id, String type, String title) async {
    await db
        .into(db.items)
        .insert(ItemsCompanion.insert(id: id, type: type, title: title));
  }

  // ---- Canvas ----

  group('createCanvas + watchCanvases', () {
    test('creates canvas and watchCanvases returns it', () async {
      final id = await service.createCanvas(name: '角色关系', description: 'desc');
      expect(id, isNotEmpty);

      final all = await service.watchCanvases().first;
      expect(all, hasLength(1));
      expect(all.first.id, id);
      expect(all.first.name, '角色关系');
      expect(all.first.description, 'desc');
    });

    test('sortOrder increments across canvases', () async {
      await service.createCanvas(name: '一');
      await service.createCanvas(name: '二');
      final all = await service.watchCanvases().first;
      expect(all.map((c) => c.sortOrder), [0, 1]);
    });

    test(
      'uses distinct short IDs and skips a soft-deleted canvas ID',
      () async {
        final now = DateTime.now();
        await db.canvasDao.insertCanvas(
          CanvasEntry(
            id: 'can_AAAAAA',
            name: 'deleted',
            description: '',
            kind: canvasKindUser,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            deletedAt: now,
          ),
        );
        final candidates = {
          ShortEntityIdType.canvas: ['can_AAAAAA', 'can_BBBBBB'],
          ShortEntityIdType.canvasNode: ['cnd_AAAAAA', 'cnd_BBBBBB'],
          ShortEntityIdType.canvasEdge: ['ced_AAAAAA'],
        };
        service = CanvasService(
          db,
          idBuilder: (type) => candidates[type]!.removeAt(0),
        );

        final canvasId = await service.createCanvas(name: 'active');
        final firstNodeId = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeSticky,
          content: 'A',
          x: 0,
          y: 0,
        );
        final secondNodeId = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeSticky,
          content: 'B',
          x: 10,
          y: 10,
        );
        final edgeId = await service.addEdge(
          canvasId: canvasId,
          sourceNodeId: firstNodeId,
          targetNodeId: secondNodeId,
          type: canvasEdgeTypeAssociation,
        );

        expect(canvasId, 'can_BBBBBB');
        expect(firstNodeId, 'cnd_AAAAAA');
        expect(secondNodeId, 'cnd_BBBBBB');
        expect(edgeId, 'ced_AAAAAA');
        final tombstone = await (db.select(
          db.canvases,
        )..where((table) => table.id.equals('can_AAAAAA'))).getSingle();
        expect(tombstone.name, 'deleted');
        expect(tombstone.deletedAt, isNot(notDeletedSentinel));
      },
    );

    test('createCanvas rejects path-structural chars in name', () async {
      for (final bad in const ['Who?', 'a/b']) {
        await expectLater(
          service.createCanvas(name: bad),
          throwsA(
            isA<CanvasServiceException>().having(
              (e) => e.errorCode,
              'errorCode',
              'invalid_name',
            ),
          ),
          reason: '$bad 是 AI 路径结构符，含它的画布名无法寻址',
        );
      }
    });
  });

  group('renameCanvas / softDeleteCanvas', () {
    test('renameCanvas updates name', () async {
      final id = await service.createCanvas(name: '旧名');
      await service.renameCanvas(canvasId: id, name: '新名');
      final canvas = await db.canvasDao.getCanvasById(id);
      expect(canvas!.name, '新名');
    });

    test('renameCanvas throws canvas_not_found when missing', () async {
      await expectLater(
        service.renameCanvas(canvasId: 'nope', name: 'x'),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'canvas_not_found',
          ),
        ),
      );
    });

    test('renameCanvas rejects path-structural chars in name', () async {
      final id = await service.createCanvas(name: '原名');
      await expectLater(
        service.renameCanvas(canvasId: id, name: '改成什么?'),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'invalid_name',
          ),
        ),
      );
    });

    test(
      'softDeleteCanvas cascades: nodes soft-deleted, edges hard-deleted',
      () async {
        final canvasId = await service.createCanvas(name: 'c');
        await insertCharacter('char_1', '主角');
        final n1 = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: entityTypeCharacter,
          refId: 'char_1',
          x: 0,
          y: 0,
        );
        final n2 = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeSticky,
          content: '便签',
          x: 10,
          y: 10,
        );
        await service.addEdge(
          canvasId: canvasId,
          sourceNodeId: n1,
          targetNodeId: n2,
          type: canvasEdgeTypeAssociation,
        );

        await service.softDeleteCanvas(canvasId);

        expect(await db.canvasDao.getCanvasById(canvasId), isNull);
        expect(await db.canvasDao.getNodeById(n1), isNull);
        expect(await db.canvasDao.getNodeById(n2), isNull);
        expect(await db.canvasDao.getEdgesByCanvas(canvasId), isEmpty);
      },
    );
  });

  // ---- addNode: reference ----

  group('addNode reference', () {
    test('creates reference node and caches resolved title', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertCharacter('char_1', '主角');

      final nodeId = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_1',
        x: 100,
        y: 200,
        width: 120,
        height: 80,
      );

      final node = await db.canvasDao.getNodeById(nodeId);
      expect(node, isNotNull);
      expect(node!.type, canvasNodeTypeReference);
      expect(node.refType, entityTypeCharacter);
      expect(node.refId, 'char_1');
      expect(node.title, '主角'); // 缓存资源标题
      expect(node.content, '');
      expect(node.x, 100);
      expect(node.y, 200);
      expect(node.width, 120);
      expect(node.height, 80);
    });

    test('throws invalid_reference when refId does not exist', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await expectLater(
        service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: entityTypeCharacter,
          refId: 'ghost',
          x: 0,
          y: 0,
        ),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'invalid_reference',
          ),
        ),
      );
    });

    test('throws missing_required_fields when refType missing', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await expectLater(
        service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refId: 'char_1',
          x: 0,
          y: 0,
        ),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'missing_required_fields',
          ),
        ),
      );
    });

    test('throws invalid_ref_type for unknown refType', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await expectLater(
        service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: 'alien',
          refId: 'x',
          x: 0,
          y: 0,
        ),
        throwsA(
          isA<CanvasServiceException>()
              .having((e) => e.errorCode, 'errorCode', 'invalid_ref_type')
              .having((e) => e.message, 'message', contains('character')),
        ),
      );
    });

    test('resolves title for various refTypes', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertChapter('ch_1', '第一章');
      await insertForeshadowing('fs_1', '伏笔一');
      await insertLocation('loc_1', '京都');
      await insertItem('itm_1', entityTypeItem, '宝剑');
      await insertItem('fac_1', entityTypeFaction, '光明教');

      final nCh = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeChapter,
        refId: 'ch_1',
        x: 0,
        y: 0,
      );
      final nFs = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeForeshadowing,
        refId: 'fs_1',
        x: 0,
        y: 0,
      );
      final nLoc = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeLocation,
        refId: 'loc_1',
        x: 0,
        y: 0,
      );
      final nItm = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeItem,
        refId: 'itm_1',
        x: 0,
        y: 0,
      );
      final nFac = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeFaction,
        refId: 'fac_1',
        x: 0,
        y: 0,
      );

      expect((await db.canvasDao.getNodeById(nCh))!.title, '第一章');
      expect((await db.canvasDao.getNodeById(nFs))!.title, '伏笔一');
      expect((await db.canvasDao.getNodeById(nLoc))!.title, '京都');
      expect((await db.canvasDao.getNodeById(nItm))!.title, '宝剑');
      expect((await db.canvasDao.getNodeById(nFac))!.title, '光明教');
    });

    test('item refId with mismatched type is invalid_reference', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertItem('itm_1', entityTypeItem, '宝剑');
      // refType=faction 但 id 实际指向 item 类型资源
      await expectLater(
        service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: entityTypeFaction,
          refId: 'itm_1',
          x: 0,
          y: 0,
        ),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'invalid_reference',
          ),
        ),
      );
    });
  });

  // ---- addNode: sticky ----

  group('addNode sticky', () {
    test('creates sticky node with content and title', () async {
      final canvasId = await service.createCanvas(name: 'c');
      final nodeId = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeSticky,
        title: '灵感',
        content: '把主角和反派放一起看看',
        x: 5,
        y: 5,
      );
      final node = await db.canvasDao.getNodeById(nodeId);
      expect(node, isNotNull);
      expect(node!.type, canvasNodeTypeSticky);
      expect(node.title, '灵感');
      expect(node.content, '把主角和反派放一起看看');
      expect(node.refType, isNull);
      expect(node.refId, isNull);
    });

    test('throws missing_required_fields when content missing', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await expectLater(
        service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeSticky,
          x: 0,
          y: 0,
        ),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'missing_required_fields',
          ),
        ),
      );
    });
  });

  // ---- addEdge ----

  group('addEdge', () {
    test('creates edge between nodes of same canvas', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertCharacter('char_1', '主角');
      await insertCharacter('char_2', '反派');
      final n1 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_1',
        x: 0,
        y: 0,
      );
      final n2 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_2',
        x: 0,
        y: 0,
      );

      final edgeId = await service.addEdge(
        canvasId: canvasId,
        sourceNodeId: n1,
        targetNodeId: n2,
        type: canvasEdgeTypeRelationship,
        label: '宿敌',
      );

      final edges = await db.canvasDao.getEdgesByCanvas(canvasId);
      expect(edges, hasLength(1));
      expect(edges.single.id, edgeId);
      expect(edges.single.type, canvasEdgeTypeRelationship);
      expect(edges.single.label, '宿敌');
    });

    test(
      'throws invalid_edge_semantics when endpoint belongs to other canvas',
      () async {
        final c1 = await service.createCanvas(name: 'c1');
        final c2 = await service.createCanvas(name: 'c2');
        await insertCharacter('char_1', '主角');
        final n1 = await service.addNode(
          canvasId: c1,
          type: canvasNodeTypeReference,
          refType: entityTypeCharacter,
          refId: 'char_1',
          x: 0,
          y: 0,
        );
        final n2 = await service.addNode(
          canvasId: c2,
          type: canvasNodeTypeReference,
          refType: entityTypeCharacter,
          refId: 'char_1',
          x: 0,
          y: 0,
        );

        await expectLater(
          service.addEdge(
            canvasId: c1,
            sourceNodeId: n1,
            targetNodeId: n2,
            type: canvasEdgeTypeRelationship,
          ),
          throwsA(
            isA<CanvasServiceException>().having(
              (e) => e.errorCode,
              'errorCode',
              'invalid_edge_semantics',
            ),
          ),
        );
      },
    );

    test(
      'foreshadow_payoff requires source=foreshadowing, target=chapter',
      () async {
        final canvasId = await service.createCanvas(name: 'c');
        await insertCharacter('char_1', '主角');
        await insertForeshadowing('fs_1', '伏笔一');
        await insertChapter('ch_1', '第一章');

        final charNode = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: entityTypeCharacter,
          refId: 'char_1',
          x: 0,
          y: 0,
        );
        final fsNode = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: entityTypeForeshadowing,
          refId: 'fs_1',
          x: 0,
          y: 0,
        );
        final chNode = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: entityTypeChapter,
          refId: 'ch_1',
          x: 0,
          y: 0,
        );

        // source 非 foreshadowing → 抛错
        await expectLater(
          service.addEdge(
            canvasId: canvasId,
            sourceNodeId: charNode,
            targetNodeId: chNode,
            type: canvasEdgeTypeForeshadowPayoff,
          ),
          throwsA(
            isA<CanvasServiceException>().having(
              (e) => e.errorCode,
              'errorCode',
              'invalid_edge_semantics',
            ),
          ),
        );

        // 正确语义(伏笔 → 章节)成功
        final edgeId = await service.addEdge(
          canvasId: canvasId,
          sourceNodeId: fsNode,
          targetNodeId: chNode,
          type: canvasEdgeTypeForeshadowPayoff,
        );
        expect(edgeId, isNotEmpty);
      },
    );

    test('throws duplicate_edge for same (source, target, type)', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertCharacter('char_1', '主角');
      await insertCharacter('char_2', '反派');
      final n1 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_1',
        x: 0,
        y: 0,
      );
      final n2 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_2',
        x: 0,
        y: 0,
      );
      await service.addEdge(
        canvasId: canvasId,
        sourceNodeId: n1,
        targetNodeId: n2,
        type: canvasEdgeTypeCausal,
      );

      await expectLater(
        service.addEdge(
          canvasId: canvasId,
          sourceNodeId: n1,
          targetNodeId: n2,
          type: canvasEdgeTypeCausal,
        ),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'duplicate_edge',
          ),
        ),
      );

      // 不同 type 的同端点边允许
      await service.addEdge(
        canvasId: canvasId,
        sourceNodeId: n1,
        targetNodeId: n2,
        type: canvasEdgeTypeTimeline,
      );
      expect(await db.canvasDao.getEdgesByCanvas(canvasId), hasLength(2));
    });

    test('throws invalid_type for unknown edge type', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await expectLater(
        service.addEdge(
          canvasId: canvasId,
          sourceNodeId: 'a',
          targetNodeId: 'b',
          type: 'unknown',
        ),
        throwsA(
          isA<CanvasServiceException>()
              .having((e) => e.errorCode, 'errorCode', 'invalid_type')
              .having(
                (e) => e.message,
                'message',
                contains(canvasEdgeTypeTimeline),
              ),
        ),
      );
    });

    test('hardDeleteEdge removes edge', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertCharacter('char_1', '主角');
      await insertCharacter('char_2', '反派');
      final n1 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_1',
        x: 0,
        y: 0,
      );
      final n2 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_2',
        x: 0,
        y: 0,
      );
      final edgeId = await service.addEdge(
        canvasId: canvasId,
        sourceNodeId: n1,
        targetNodeId: n2,
        type: canvasEdgeTypeRelationship,
      );

      await service.hardDeleteEdge(edgeId);
      expect(await db.canvasDao.getEdgeById(edgeId), isNull);
    });
  });

  // ---- updateNode ----

  group('updateNodePosition / updateNodeContent', () {
    test('updates position and content', () async {
      final canvasId = await service.createCanvas(name: 'c');
      final nodeId = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeSticky,
        content: '旧',
        x: 0,
        y: 0,
      );

      await service.updateNodePosition(nodeId: nodeId, x: 42, y: 17);
      await service.updateNodeContent(nodeId: nodeId, content: '新');

      final node = await db.canvasDao.getNodeById(nodeId);
      expect(node!.x, 42);
      expect(node.y, 17);
      expect(node.content, '新');
    });

    test('throws node_not_found when node missing', () async {
      await expectLater(
        service.updateNodePosition(nodeId: 'ghost', x: 0, y: 0),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'node_not_found',
          ),
        ),
      );
      await expectLater(
        service.updateNodeContent(nodeId: 'ghost', content: 'x'),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'node_not_found',
          ),
        ),
      );
    });
  });

  // ---- 便签标题 / 纸色 ----

  group('updateNodeTitle / updateNodeStyle', () {
    test('updates sticky title and paper color style', () async {
      final canvasId = await service.createCanvas(name: 'c');
      final nodeId = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeSticky,
        content: '正文',
        x: 0,
        y: 0,
      );

      await service.updateNodeTitle(nodeId: nodeId, title: '留白提醒');
      await service.updateNodeStyle(
        nodeId: nodeId,
        style: {'sticky_color': 'sage'},
      );

      final node = await db.canvasDao.getNodeById(nodeId);
      expect(node!.title, '留白提醒');
      expect(node.style?['sticky_color'], 'sage');
      // 纸色是纯视觉,不应动到正文。
      expect(node.content, '正文');
    });

    test('rejects title writes on reference nodes', () async {
      // 引用型 title 是资源标题的缓存,由 refreshReferenceTitle 维护。
      // 允许外部改写会让画布显示与资源本体永久不一致。
      final canvasId = await service.createCanvas(name: 'c');
      await insertCharacter('char_1', '主角');
      final nodeId = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_1',
        x: 0,
        y: 0,
      );

      await expectLater(
        service.updateNodeTitle(nodeId: nodeId, title: '手改标题'),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'missing_required_fields',
          ),
        ),
      );
      final node = await db.canvasDao.getNodeById(nodeId);
      expect(node!.title, '主角');
    });
  });

  // ---- 连线原地编辑 ----

  group('updateEdge', () {
    Future<({String canvasId, String n1, String n2})> setupPair() async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertCharacter('char_1', '主角');
      await insertCharacter('char_2', '反派');
      final n1 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_1',
        x: 0,
        y: 0,
      );
      final n2 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_2',
        x: 0,
        y: 0,
      );
      return (canvasId: canvasId, n1: n1, n2: n2);
    }

    test('changes type and label in place', () async {
      final s = await setupPair();
      final edgeId = await service.addEdge(
        canvasId: s.canvasId,
        sourceNodeId: s.n1,
        targetNodeId: s.n2,
        type: canvasEdgeTypeAssociation,
      );

      await service.updateEdge(
        edgeId: edgeId,
        type: canvasEdgeTypeRelationship,
        label: '旧友 · 互相隐瞒',
      );

      final edge = await db.canvasDao.getEdgeById(edgeId);
      expect(edge!.type, canvasEdgeTypeRelationship);
      expect(edge.label, '旧友 · 互相隐瞒');
    });

    test('changing label alone keeps the existing type', () async {
      final s = await setupPair();
      final edgeId = await service.addEdge(
        canvasId: s.canvasId,
        sourceNodeId: s.n1,
        targetNodeId: s.n2,
        type: canvasEdgeTypeCausal,
      );

      await service.updateEdge(edgeId: edgeId, label: '促成重逢');

      final edge = await db.canvasDao.getEdgeById(edgeId);
      expect(edge!.type, canvasEdgeTypeCausal);
      expect(edge.label, '促成重逢');
    });

    test(
      'rejects a type change that would duplicate an existing edge',
      () async {
        // 同 (canvas,source,target,type) 有 unique 约束;若不提前拦,
        // upsert 会抛 SQLite 原始异常而非可读错误码。
        final s = await setupPair();
        await service.addEdge(
          canvasId: s.canvasId,
          sourceNodeId: s.n1,
          targetNodeId: s.n2,
          type: canvasEdgeTypeRelationship,
        );
        final second = await service.addEdge(
          canvasId: s.canvasId,
          sourceNodeId: s.n1,
          targetNodeId: s.n2,
          type: canvasEdgeTypeCausal,
        );

        await expectLater(
          service.updateEdge(edgeId: second, type: canvasEdgeTypeRelationship),
          throwsA(
            isA<CanvasServiceException>().having(
              (e) => e.errorCode,
              'errorCode',
              'duplicate_edge',
            ),
          ),
        );
        // 失败后原类型保持不变。
        final edge = await db.canvasDao.getEdgeById(second);
        expect(edge!.type, canvasEdgeTypeCausal);
      },
    );

    test('enforces foreshadow_payoff semantics on type change', () async {
      // 伏笔兑现要求 起点=伏笔、终点=章节;人物→人物不该被改成这个类型。
      final s = await setupPair();
      final edgeId = await service.addEdge(
        canvasId: s.canvasId,
        sourceNodeId: s.n1,
        targetNodeId: s.n2,
        type: canvasEdgeTypeAssociation,
      );

      await expectLater(
        service.updateEdge(
          edgeId: edgeId,
          type: canvasEdgeTypeForeshadowPayoff,
        ),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'invalid_edge_semantics',
          ),
        ),
      );
    });

    test('throws edge_not_found when edge missing', () async {
      await expectLater(
        service.updateEdge(edgeId: 'ghost', label: 'x'),
        throwsA(
          isA<CanvasServiceException>().having(
            (e) => e.errorCode,
            'errorCode',
            'edge_not_found',
          ),
        ),
      );
    });
  });

  // ---- softDeleteNode cascade ----

  group('softDeleteNode', () {
    test('cascades: edges hard-deleted', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertCharacter('char_1', '主角');
      await insertCharacter('char_2', '反派');
      await insertCharacter('char_3', '配角');
      final n1 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_1',
        x: 0,
        y: 0,
      );
      final n2 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_2',
        x: 0,
        y: 0,
      );
      final n3 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_3',
        x: 0,
        y: 0,
      );
      final e1 = await service.addEdge(
        canvasId: canvasId,
        sourceNodeId: n1,
        targetNodeId: n2,
        type: canvasEdgeTypeRelationship,
      );
      final e2 = await service.addEdge(
        canvasId: canvasId,
        sourceNodeId: n3,
        targetNodeId: n2,
        type: canvasEdgeTypeRelationship,
      );

      await service.softDeleteNode(n2);

      expect(await db.canvasDao.getNodeById(n2), isNull);
      expect(await db.canvasDao.getEdgeById(e1), isNull);
      expect(await db.canvasDao.getEdgeById(e2), isNull);
      expect(await db.canvasDao.getNodesByCanvas(canvasId), hasLength(2));
    });
  });

  // ---- refreshReferenceTitle ----

  group('refreshReferenceTitle', () {
    test('refreshes cached title after resource renamed', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertCharacter('char_1', '旧名');
      final nodeId = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_1',
        x: 0,
        y: 0,
      );
      expect((await db.canvasDao.getNodeById(nodeId))!.title, '旧名');

      await renameCharacter('char_1', '新名');
      await service.refreshReferenceTitle(
        refType: entityTypeCharacter,
        refId: 'char_1',
      );

      expect((await db.canvasDao.getNodeById(nodeId))!.title, '新名');
    });

    test('skips silently when resource deleted (no error)', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertCharacter('char_1', '原名');
      final nodeId = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_1',
        x: 0,
        y: 0,
      );

      // 软删角色(画布引用节点保留,失效态由 UI 渲染时检测)
      await (db.update(
        db.characterProfiles,
      )..where((t) => t.id.equals('char_1'))).write(
        CharacterProfilesCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // 不抛错,跳过;title 保持旧值
      await service.refreshReferenceTitle(
        refType: entityTypeCharacter,
        refId: 'char_1',
      );
      expect((await db.canvasDao.getNodeById(nodeId))!.title, '原名');
    });

    test(
      'refreshReferenceTitlesForCanvas refreshes all reference nodes',
      () async {
        final canvasId = await service.createCanvas(name: 'c');
        await insertCharacter('char_1', '旧名A');
        await insertForeshadowing('fs_1', '旧伏笔');
        final nChar = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: entityTypeCharacter,
          refId: 'char_1',
          x: 0,
          y: 0,
        );
        final nFs = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: entityTypeForeshadowing,
          refId: 'fs_1',
          x: 0,
          y: 0,
        );
        final nSticky = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeSticky,
          content: '便签',
          x: 0,
          y: 0,
        );

        await renameCharacter('char_1', '新名A');
        await (db.update(db.foreshadowings)..where((t) => t.id.equals('fs_1')))
            .write(ForeshadowingsCompanion(title: Value('新伏笔')));

        await service.refreshReferenceTitlesForCanvas(canvasId);

        expect((await db.canvasDao.getNodeById(nChar))!.title, '新名A');
        expect((await db.canvasDao.getNodeById(nFs))!.title, '新伏笔');
        // 便签不受影响
        expect((await db.canvasDao.getNodeById(nSticky))!.content, '便签');
      },
    );
  });

  // ---- canvas edge 不进入 entity_graph ----

  group('boundary with entity_graph', () {
    test('canvas edge does not appear in EntityRelations', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertCharacter('char_1', '主角');
      await insertCharacter('char_2', '反派');
      final n1 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_1',
        x: 0,
        y: 0,
      );
      final n2 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_2',
        x: 0,
        y: 0,
      );
      await service.addEdge(
        canvasId: canvasId,
        sourceNodeId: n1,
        targetNodeId: n2,
        type: canvasEdgeTypeRelationship,
        label: '宿敌',
      );

      final relations = await (db.select(db.entityRelations)).get();
      expect(relations, isEmpty);
    });
  });

  // ---- watchCanvasContent 合并流 ----

  group('autoLayout', () {
    /// 章节排 row 0、伏笔排 row 1，但伏笔的列与它指向的章节无关 —— 截图里那张
    /// 画布的最小复现。
    Future<({String canvasId, Map<String, String> nodeIds})>
    buildCrossed() async {
      final canvasId = await service.createCanvas(name: '伏笔地图');
      final nodeIds = <String, String>{};
      for (var i = 0; i < 3; i++) {
        await insertChapter('ch_$i', '第 $i 章');
        nodeIds['c$i'] = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: entityTypeChapter,
          refId: 'ch_$i',
          x: canvasGridOrigin(i, 0).dx,
          y: canvasGridOrigin(i, 0).dy,
        );
      }
      for (var i = 0; i < 2; i++) {
        await insertForeshadowing('fs_$i', '伏笔 $i');
        nodeIds['f$i'] = await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: entityTypeForeshadowing,
          refId: 'fs_$i',
          x: canvasGridOrigin(i, 1).dx,
          y: canvasGridOrigin(i, 1).dy,
        );
      }
      // f0(第 0 列)兑现在第 2 章、f1(第 1 列)兑现在第 0 章 —— 两条边交叉。
      await service.addEdge(
        canvasId: canvasId,
        sourceNodeId: nodeIds['f0']!,
        targetNodeId: nodeIds['c2']!,
        type: canvasEdgeTypeForeshadowPayoff,
      );
      await service.addEdge(
        canvasId: canvasId,
        sourceNodeId: nodeIds['f1']!,
        targetNodeId: nodeIds['c0']!,
        type: canvasEdgeTypeForeshadowPayoff,
      );
      return (canvasId: canvasId, nodeIds: nodeIds);
    }

    test('把伏笔挪到其兑现章节所在列，章节保持不动', () async {
      final built = await buildCrossed();

      final moved = await service.autoLayout(built.canvasId);
      expect(moved, 2);

      final nodes = await db.canvasDao.getNodesByCanvas(built.canvasId);
      final byId = {for (final n in nodes) n.id: n};
      expect(byId[built.nodeIds['f0']]!.x, canvasGridOrigin(2, 1).dx);
      expect(byId[built.nodeIds['f1']]!.x, canvasGridOrigin(0, 1).dx);
      for (var i = 0; i < 3; i++) {
        expect(byId[built.nodeIds['c$i']]!.x, canvasGridOrigin(i, 0).dx);
        expect(byId[built.nodeIds['c$i']]!.y, 0);
      }
    });

    test('已经排好的画布再跑一次不动任何节点', () async {
      final built = await buildCrossed();
      await service.autoLayout(built.canvasId);
      expect(await service.autoLayout(built.canvasId), 0);
    });

    test('批量改坐标只让内容流发一次，画布不会连闪几十次', () async {
      final built = await buildCrossed();
      final snapshots = <int>[];
      final sub = service
          .watchCanvasContent(built.canvasId)
          .listen((content) => snapshots.add(content.nodes.length));
      // 等首帧快照落地
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final baseline = snapshots.length;

      await service.autoLayout(built.canvasId);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(snapshots.length - baseline, 1);
    });

    test('画布不存在 / 空画布返回 0', () async {
      expect(await service.autoLayout('canvas_missing'), 0);
      final empty = await service.createCanvas(name: '空');
      expect(await service.autoLayout(empty), 0);
    });
  });

  group('watchCanvasContent', () {
    test('emits combined nodes + edges snapshot', () async {
      final canvasId = await service.createCanvas(name: 'c');
      await insertCharacter('char_1', '主角');
      final n1 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeReference,
        refType: entityTypeCharacter,
        refId: 'char_1',
        x: 0,
        y: 0,
      );
      final n2 = await service.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeSticky,
        content: '便签',
        x: 0,
        y: 0,
      );
      await service.addEdge(
        canvasId: canvasId,
        sourceNodeId: n1,
        targetNodeId: n2,
        type: canvasEdgeTypeAssociation,
      );

      final snapshot = await service.watchCanvasContent(canvasId).first;
      expect(snapshot.nodes, hasLength(2));
      expect(snapshot.edges, hasLength(1));
    });
  });
}

class _LayoutFailureDatabase extends NovelContentDatabase {
  _LayoutFailureDatabase() : super.forTest(NativeDatabase.memory());
  String? failAt;
  late final CanvasDao _failureDao = _LayoutFailureDao(this);
  @override
  CanvasDao get canvasDao => _failureDao;
}

class _LayoutFailureDao extends CanvasDao {
  _LayoutFailureDao(this.owner) : super(owner);
  final _LayoutFailureDatabase owner;
  @override
  Future<void> updateLayout(String id, String mode) async {
    await super.updateLayout(id, mode);
    if (owner.failAt == 'layout') {
      throw StateError('injected layout write failure');
    }
  }

  @override
  Future<void> updateNodePositions(
    Map<String, ({double x, double y})> positions,
  ) async {
    await super.updateNodePositions(positions);
    if (owner.failAt == 'nodes') {
      throw StateError('injected node write failure');
    }
  }
}

class _NodeReadBarrierDatabase extends NovelContentDatabase {
  _NodeReadBarrierDatabase() : super.forTest(NativeDatabase.memory());
  String? blockNodeId;
  final didRead = Completer<void>();
  final releaseRead = Completer<void>();
  late final CanvasDao _barrierDao = _NodeReadBarrierDao(this);
  @override
  CanvasDao get canvasDao => _barrierDao;
}

class _NodeReadBarrierDao extends CanvasDao {
  _NodeReadBarrierDao(this.owner) : super(owner);
  final _NodeReadBarrierDatabase owner;
  @override
  Future<CanvasNode?> getNodeById(String id) async {
    final row = await super.getNodeById(id);
    if (owner.blockNodeId == id) {
      owner.blockNodeId = null;
      owner.didRead.complete();
      await owner.releaseRead.future;
    }
    return row;
  }
}
