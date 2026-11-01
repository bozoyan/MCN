// 职责: 画布重载闸门测试 — 坐标/正文/边类型只改字段不改 id 时必须判定为「变了」
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/shared/services/canvas_service.dart
//   lib/shared/models/canvas_auto_layout.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/canvas_palette.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_board.dart';
import 'package:reveric/shared/database/novel_content_database.dart';

CanvasNode _node({
  String id = 'n1',
  String type = canvasNodeTypeReference,
  String refId = 'ch_1',
  String title = '第一章',
  String content = '',
  double x = 0,
  double y = 0,
  Map<String, dynamic>? style,
}) {
  return CanvasNode(
    id: id,
    canvasId: 'canvas_1',
    type: type,
    refType: entityTypeChapter,
    refId: refId,
    title: title,
    content: content,
    x: x,
    y: y,
    width: null,
    height: null,
    style: style,
    zIndex: 0,
    sortOrder: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    deletedAt: notDeletedSentinel,
  );
}

CanvasEdge _edge({
  String id = 'e1',
  String type = canvasEdgeTypeAssociation,
  String? label,
}) {
  return CanvasEdge(
    id: id,
    canvasId: 'canvas_1',
    sourceNodeId: 'n1',
    targetNodeId: 'n2',
    type: type,
    label: label,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

({List<CanvasNode> nodes, List<CanvasEdge> edges}) _content({
  List<CanvasNode>? nodes,
  List<CanvasEdge>? edges,
}) {
  return (nodes: nodes ?? [_node()], edges: edges ?? [_edge()]);
}

void main() {
  group('sameCanvasContentSignature', () {
    test('同一份快照重发不触发重载', () {
      expect(sameCanvasContentSignature(_content(), _content()), isTrue);
    });

    test('首次加载(previous 为 null)必须加载', () {
      expect(sameCanvasContentSignature(null, _content()), isFalse);
    });

    test('原地改类型或换到同名资源必须更新已有节点', () {
      for (final changed in [
        _node(type: canvasNodeTypeSticky),
        _node(refId: 'ch_2'),
      ]) {
        final before = _content();
        final after = _content(nodes: [changed]);
        expect(sameCanvasContentSignature(before, after), isFalse);
        final diff = diffCanvasContent(before, after);
        expect(diff.hasModifications, isTrue);
        expect(diff.addedNodes, isEmpty);
        expect(diff.removedNodeIds, isEmpty);
        expect(diff.addedEdges, isEmpty);
        expect(diff.removedEdgeIds, isEmpty);
      }
    });

    test('只改坐标也算变了 —— 自动重排/AI 改坐标全靠这一条刷新', () {
      expect(
        sameCanvasContentSignature(
          _content(),
          _content(nodes: [_node(x: 400, y: 248)]),
        ),
        isFalse,
      );
    });

    test('便签正文、标题、纸色变化都要刷新', () {
      expect(
        sameCanvasContentSignature(
          _content(),
          _content(nodes: [_node(content: '改过的正文')]),
        ),
        isFalse,
      );
      expect(
        sameCanvasContentSignature(
          _content(),
          _content(nodes: [_node(title: '改过的标题')]),
        ),
        isFalse,
      );
      expect(
        sameCanvasContentSignature(
          _content(),
          _content(
            nodes: [
              _node(
                style: const {canvasNodeColorStyleKey: canvasStickyColorSage},
              ),
            ],
          ),
        ),
        isFalse,
      );
    });

    test('边的类型与标签变化要刷新（线色/线型/字条都跟着变）', () {
      expect(
        sameCanvasContentSignature(
          _content(),
          _content(edges: [_edge(type: canvasEdgeTypeCausal)]),
        ),
        isFalse,
      );
      expect(
        sameCanvasContentSignature(
          _content(),
          _content(edges: [_edge(label: '埋设')]),
        ),
        isFalse,
      );
    });

    test('增删节点/边仍然触发重载', () {
      expect(
        sameCanvasContentSignature(
          _content(),
          _content(
            nodes: [
              _node(),
              _node(id: 'n2'),
            ],
          ),
        ),
        isFalse,
      );
      expect(
        sameCanvasContentSignature(_content(), _content(edges: const [])),
        isFalse,
      );
    });

    test('id 换了但字段相同也算变了', () {
      expect(
        sameCanvasContentSignature(
          _content(),
          _content(nodes: [_node(id: 'n9')]),
        ),
        isFalse,
      );
    });
  });

  group('diffCanvasContent', () {
    test('纯新增节点/边:进 added 列表,不带修改标记 —— 增量挂载的主场景', () {
      final diff = diffCanvasContent(
        _content(nodes: [_node()], edges: const []),
        _content(
          nodes: [
            _node(),
            _node(id: 'n2'),
          ],
          edges: [_edge()],
        ),
      );

      expect(diff.addedNodes.map((n) => n.id), ['n2']);
      expect(diff.addedEdges.map((e) => e.id), ['e1']);
      expect(diff.removedNodeIds, isEmpty);
      expect(diff.removedEdgeIds, isEmpty);
      expect(diff.hasModifications, isFalse);
    });

    test('纯删除:进 removed 集合,不带修改标记', () {
      final diff = diffCanvasContent(
        _content(
          nodes: [
            _node(),
            _node(id: 'n2'),
          ],
        ),
        _content(nodes: [_node()], edges: const []),
      );

      expect(diff.removedNodeIds, {'n2'});
      expect(diff.removedEdgeIds, {'e1'});
      expect(diff.addedNodes, isEmpty);
      expect(diff.addedEdges, isEmpty);
      expect(diff.hasModifications, isFalse);
    });

    test('增删混合同样走增量', () {
      final diff = diffCanvasContent(
        _content(nodes: [_node()]),
        _content(nodes: [_node(id: 'n2')]),
      );

      expect(diff.addedNodes.map((n) => n.id), ['n2']);
      expect(diff.removedNodeIds, {'n1'});
      expect(diff.hasModifications, isFalse);
    });

    test('改坐标/正文/纸色都算修改 —— 必须回退整图重载', () {
      for (final mutated in <CanvasNode>[
        _node(x: 400),
        _node(content: '改过的正文'),
        _node(style: const {canvasNodeColorStyleKey: canvasStickyColorSage}),
      ]) {
        final diff = diffCanvasContent(_content(), _content(nodes: [mutated]));
        expect(diff.hasModifications, isTrue);
        expect(diff.addedNodes, isEmpty);
        expect(diff.removedNodeIds, isEmpty);
      }
    });

    test('改边类型/标签也算修改', () {
      for (final mutated in <CanvasEdge>[
        _edge(type: canvasEdgeTypeCausal),
        _edge(label: '埋设'),
      ]) {
        final diff = diffCanvasContent(_content(), _content(edges: [mutated]));
        expect(diff.hasModifications, isTrue);
      }
    });

    test('同一份快照:空差集', () {
      final diff = diffCanvasContent(_content(), _content());

      expect(diff.addedNodes, isEmpty);
      expect(diff.removedNodeIds, isEmpty);
      expect(diff.addedEdges, isEmpty);
      expect(diff.removedEdgeIds, isEmpty);
      expect(diff.hasModifications, isFalse);
    });
  });
}
