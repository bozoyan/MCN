// 职责: 测试 CanvasDao — 验证 canvases/canvas_nodes/canvas_edges 的 CRUD、watch、级联软删/硬删、引用标题刷新
// 关联文件:
//   lib/shared/database/novel_content_daos/canvas_dao.dart
//   lib/shared/database/novel_content_database.dart
// 遵循的 Rules:
//   .agents/rules/db-migration.md

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';

void main() {
  late NovelContentDatabase db;

  setUp(() {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  CanvasEntry _canvas({
    required String id,
    String name = '角色关系',
    String description = '',
    int sortOrder = 0,
  }) {
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    return CanvasEntry(
      id: id,
      name: name,
      description: description,
      kind: canvasKindUser,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
      deletedAt: notDeletedSentinel,
    );
  }

  CanvasNode _referenceNode({
    required String id,
    required String canvasId,
    required String refType,
    required String refId,
    String title = '',
    double x = 0,
    double y = 0,
  }) {
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    return CanvasNode(
      sortOrder: 0,
      id: id,
      canvasId: canvasId,
      type: canvasNodeTypeReference,
      refType: refType,
      refId: refId,
      title: title,
      content: '',
      x: x,
      y: y,
      zIndex: 0,
      createdAt: now,
      updatedAt: now,
      deletedAt: notDeletedSentinel,
    );
  }

  CanvasNode _stickyNode({
    required String id,
    required String canvasId,
    required String content,
    String title = '',
    double x = 0,
    double y = 0,
  }) {
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    return CanvasNode(
      sortOrder: 0,
      id: id,
      canvasId: canvasId,
      type: canvasNodeTypeSticky,
      title: title,
      content: content,
      x: x,
      y: y,
      zIndex: 0,
      createdAt: now,
      updatedAt: now,
      deletedAt: notDeletedSentinel,
    );
  }

  CanvasEdge _edge({
    required String id,
    required String canvasId,
    required String sourceNodeId,
    required String targetNodeId,
    String type = canvasEdgeTypeRelationship,
    String? label,
  }) {
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    return CanvasEdge(
      id: id,
      canvasId: canvasId,
      sourceNodeId: sourceNodeId,
      targetNodeId: targetNodeId,
      type: type,
      label: label,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('CanvasDao - Canvas', () {
    test('upsert and get canvas', () async {
      await db.canvasDao.upsertCanvas(_canvas(id: 'canvas_1', name: '角色关系'));
      final canvas = await db.canvasDao.getCanvasById('canvas_1');
      expect(canvas, isNotNull);
      expect(canvas!.name, '角色关系');
      expect(canvas.deletedAt, notDeletedSentinel);
    });

    test(
      'getAllCanvases excludes soft-deleted and orders by sortOrder',
      () async {
        await db.canvasDao.upsertCanvas(
          _canvas(id: 'canvas_2', name: '第二张', sortOrder: 2),
        );
        await db.canvasDao.upsertCanvas(
          _canvas(id: 'canvas_1', name: '第一张', sortOrder: 1),
        );
        await db.canvasDao.upsertCanvas(
          _canvas(id: 'canvas_3', name: '已删', sortOrder: 0),
        );
        await db.canvasDao.softDeleteCanvas('canvas_3');

        final all = await db.canvasDao.getAllCanvases();
        expect(all.map((c) => c.id), ['canvas_1', 'canvas_2']);
      },
    );

    test(
      'softDeleteCanvas cascades: nodes soft-deleted, edges hard-deleted',
      () async {
        await db.canvasDao.upsertCanvas(_canvas(id: 'canvas_1'));
        await db.canvasDao.upsertNode(
          _referenceNode(
            id: 'n1',
            canvasId: 'canvas_1',
            refType: entityTypeCharacter,
            refId: 'char_1',
          ),
        );
        await db.canvasDao.upsertNode(
          _referenceNode(
            id: 'n2',
            canvasId: 'canvas_1',
            refType: entityTypeCharacter,
            refId: 'char_2',
          ),
        );
        await db.canvasDao.upsertEdge(
          _edge(
            id: 'e1',
            canvasId: 'canvas_1',
            sourceNodeId: 'n1',
            targetNodeId: 'n2',
          ),
        );

        await db.canvasDao.softDeleteCanvas('canvas_1');

        expect(await db.canvasDao.getCanvasById('canvas_1'), isNull);
        expect(await db.canvasDao.getNodeById('n1'), isNull);
        expect(await db.canvasDao.getEdgeById('e1'), isNull);
        // 边表行确实被硬删(不只是查询过滤)
        final rawEdges = await db.canvasDao.getEdgesByCanvas('canvas_1');
        expect(rawEdges, isEmpty);
      },
    );
  });

  group('CanvasDao - Node', () {
    test('getNodesByCanvas excludes soft-deleted nodes', () async {
      await db.canvasDao.upsertCanvas(_canvas(id: 'canvas_1'));
      await db.canvasDao.upsertNode(
        _stickyNode(id: 's1', canvasId: 'canvas_1', content: '便签一'),
      );
      await db.canvasDao.upsertNode(
        _stickyNode(id: 's2', canvasId: 'canvas_1', content: '便签二'),
      );
      await db.canvasDao.softDeleteNode('s2');

      final nodes = await db.canvasDao.getNodesByCanvas('canvas_1');
      expect(nodes.map((n) => n.id), ['s1']);
      expect(nodes.single.content, '便签一');
    });

    test('softDeleteNode cascades: edges hard-deleted', () async {
      await db.canvasDao.upsertCanvas(_canvas(id: 'canvas_1'));
      await db.canvasDao.upsertNode(
        _referenceNode(
          id: 'n1',
          canvasId: 'canvas_1',
          refType: entityTypeCharacter,
          refId: 'char_1',
        ),
      );
      await db.canvasDao.upsertNode(
        _referenceNode(
          id: 'n2',
          canvasId: 'canvas_1',
          refType: entityTypeCharacter,
          refId: 'char_2',
        ),
      );
      await db.canvasDao.upsertNode(
        _referenceNode(
          id: 'n3',
          canvasId: 'canvas_1',
          refType: entityTypeCharacter,
          refId: 'char_3',
        ),
      );
      await db.canvasDao.upsertEdge(
        _edge(
          id: 'e1',
          canvasId: 'canvas_1',
          sourceNodeId: 'n1',
          targetNodeId: 'n2',
        ),
      );
      await db.canvasDao.upsertEdge(
        _edge(
          id: 'e2',
          canvasId: 'canvas_1',
          sourceNodeId: 'n3',
          targetNodeId: 'n2',
        ),
      );

      await db.canvasDao.softDeleteNode('n2');

      // n2 软删,以其为端点的两条边都硬删
      expect(await db.canvasDao.getNodeById('n2'), isNull);
      expect(await db.canvasDao.getEdgeById('e1'), isNull);
      expect(await db.canvasDao.getEdgeById('e2'), isNull);
      expect(await db.canvasDao.getNodesByCanvas('canvas_1'), hasLength(2));
    });

    test(
      'updateReferenceTitles updates only matching non-deleted reference nodes',
      () async {
        await db.canvasDao.upsertCanvas(_canvas(id: 'canvas_1'));
        // 画布名有部分唯一索引（canvases_by_name_u，跳过软删记录），
        // 同时存在的两张画布不能重名。
        await db.canvasDao.upsertCanvas(_canvas(id: 'canvas_2', name: '势力关系'));
        await db.canvasDao.upsertNode(
          _referenceNode(
            id: 'n1',
            canvasId: 'canvas_1',
            refType: entityTypeCharacter,
            refId: 'char_1',
            title: '旧名',
          ),
        );
        await db.canvasDao.upsertNode(
          _referenceNode(
            id: 'n2',
            canvasId: 'canvas_2',
            refType: entityTypeCharacter,
            refId: 'char_1',
            title: '旧名',
          ),
        );
        // 不同 refId 不更新
        await db.canvasDao.upsertNode(
          _referenceNode(
            id: 'n3',
            canvasId: 'canvas_1',
            refType: entityTypeCharacter,
            refId: 'char_2',
            title: '不变',
          ),
        );
        // 软删的不更新
        await db.canvasDao.upsertNode(
          _referenceNode(
            id: 'n4',
            canvasId: 'canvas_1',
            refType: entityTypeCharacter,
            refId: 'char_1',
            title: '已删',
          ),
        );
        await db.canvasDao.softDeleteNode('n4');

        final updated = await db.canvasDao.updateReferenceTitles(
          refType: entityTypeCharacter,
          refId: 'char_1',
          title: '新名',
        );
        expect(updated, 2);

        expect((await db.canvasDao.getNodeById('n1'))!.title, '新名');
        expect((await db.canvasDao.getNodeById('n2'))!.title, '新名');
        expect((await db.canvasDao.getNodeById('n3'))!.title, '不变');
      },
    );
  });

  group('CanvasDao - Edge', () {
    test('getEdgesByCanvas returns edges ordered by createdAt', () async {
      await db.canvasDao.upsertCanvas(_canvas(id: 'canvas_1'));
      await db.canvasDao.upsertNode(
        _referenceNode(
          id: 'n1',
          canvasId: 'canvas_1',
          refType: entityTypeCharacter,
          refId: 'char_1',
        ),
      );
      await db.canvasDao.upsertNode(
        _referenceNode(
          id: 'n2',
          canvasId: 'canvas_1',
          refType: entityTypeCharacter,
          refId: 'char_2',
        ),
      );
      await db.canvasDao.upsertEdge(
        _edge(
          id: 'e1',
          canvasId: 'canvas_1',
          sourceNodeId: 'n1',
          targetNodeId: 'n2',
          type: canvasEdgeTypeRelationship,
        ),
      );

      final edges = await db.canvasDao.getEdgesByCanvas('canvas_1');
      expect(edges, hasLength(1));
      expect(edges.single.type, canvasEdgeTypeRelationship);
      expect(edges.single.label, isNull);
    });

    test('hardDeleteEdge removes edge only', () async {
      await db.canvasDao.upsertCanvas(_canvas(id: 'canvas_1'));
      await db.canvasDao.upsertNode(
        _referenceNode(
          id: 'n1',
          canvasId: 'canvas_1',
          refType: entityTypeCharacter,
          refId: 'char_1',
        ),
      );
      await db.canvasDao.upsertNode(
        _referenceNode(
          id: 'n2',
          canvasId: 'canvas_1',
          refType: entityTypeCharacter,
          refId: 'char_2',
        ),
      );
      await db.canvasDao.upsertEdge(
        _edge(
          id: 'e1',
          canvasId: 'canvas_1',
          sourceNodeId: 'n1',
          targetNodeId: 'n2',
        ),
      );

      await db.canvasDao.hardDeleteEdge('e1');
      expect(await db.canvasDao.getEdgeById('e1'), isNull);
      // 节点不受影响
      expect(await db.canvasDao.getNodesByCanvas('canvas_1'), hasLength(2));
    });

    test('duplicate same-type edge is rejected by unique constraint', () async {
      await db.canvasDao.upsertCanvas(_canvas(id: 'canvas_1'));
      await db.canvasDao.upsertNode(
        _referenceNode(
          id: 'n1',
          canvasId: 'canvas_1',
          refType: entityTypeCharacter,
          refId: 'char_1',
        ),
      );
      await db.canvasDao.upsertNode(
        _referenceNode(
          id: 'n2',
          canvasId: 'canvas_1',
          refType: entityTypeCharacter,
          refId: 'char_2',
        ),
      );
      await db.canvasDao.upsertEdge(
        _edge(
          id: 'e1',
          canvasId: 'canvas_1',
          sourceNodeId: 'n1',
          targetNodeId: 'n2',
          type: canvasEdgeTypeCausal,
        ),
      );

      // 相同 (canvas_id, source, target, type) 的重复边应抛错
      await expectLater(
        db.canvasDao.upsertEdge(
          _edge(
            id: 'e2',
            canvasId: 'canvas_1',
            sourceNodeId: 'n1',
            targetNodeId: 'n2',
            type: canvasEdgeTypeCausal,
          ),
        ),
        throwsA(isA<Object>()),
      );

      // 不同 type 的同端点边允许
      await db.canvasDao.upsertEdge(
        _edge(
          id: 'e3',
          canvasId: 'canvas_1',
          sourceNodeId: 'n1',
          targetNodeId: 'n2',
          type: canvasEdgeTypeTimeline,
        ),
      );
      expect(await db.canvasDao.getEdgesByCanvas('canvas_1'), hasLength(2));
    });
  });

  group('CanvasDao - queries do not depend on metadata JSON', () {
    test('node position is a column, not parsed from metadata', () async {
      await db.canvasDao.upsertCanvas(_canvas(id: 'canvas_1'));
      await db.canvasDao.upsertNode(
        _referenceNode(
          id: 'n1',
          canvasId: 'canvas_1',
          refType: entityTypeCharacter,
          refId: 'char_1',
          x: 120.5,
          y: 80.0,
        ),
      );
      final node = await db.canvasDao.getNodeById('n1');
      expect(node!.x, 120.5);
      expect(node.y, 80.0);
      // refType/refId 是列,不是 metadata
      expect(node.refType, entityTypeCharacter);
      expect(node.refId, 'char_1');
    });
  });
}
