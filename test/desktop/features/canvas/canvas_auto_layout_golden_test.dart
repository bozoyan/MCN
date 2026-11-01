// 职责: 自动重排前后对比 golden — 用真实伏笔地图数据确认长横线被压短、连线不再糊成一团
// 关联文件:
//   lib/shared/models/canvas_auto_layout.dart
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart
//   lib/desktop/features/canvas/widgets/canvas_node_widget.dart

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/canvas_palette.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_flow_adapter.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_node_widget.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/canvas_auto_layout.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;
import 'package:shared_preferences/shared_preferences.dart';

/// 真实数据(canvas「全书伏笔地图」)：14 个章节排 row 0、14 个伏笔排 row 1，
/// 伏笔在行内的顺序与其指向的章节无关 —— 于是 21 条边全成了横穿画布的长线。
const _chapters = <String>[
  '核心代码泄露',
  '绝地反击',
  '团队扩张',
  '技术突破',
  '团建爬山',
  '2.0版本开发',
  '庆功宴表白',
  '公开恋情',
  '黑稿突袭',
  '见家长',
  '七十二小时',
  '查人',
  '摊牌',
  '锚点',
];

const _foreshadowings = <String>[
  '穿越的秘密',
  '苏瑶的身世',
  '陈峰的间谍网络',
  '张总的投资背景',
  '李明的背景',
  '性能优化技术',
  '黑客"鸭舌帽"的攻击',
  '李明的良心挣扎',
  '论坛用户"星河2025"',
  '团队CP猜测',
  '移动端技术架构',
  '地下恋的甜蜜与风险',
  '陈峰的产品攻击',
  '未来考古学家的私信',
];

/// (伏笔序号, 章节序号, 边类型, 标签)
const _links = <(int, int, String, String)>[
  (0, 4, canvasEdgeTypeAssociation, '埋设'),
  (0, 13, canvasEdgeTypeForeshadowPayoff, '兑现'),
  (1, 13, canvasEdgeTypeForeshadowPayoff, '兑现'),
  (1, 9, canvasEdgeTypeAssociation, '埋设'),
  (2, 1, canvasEdgeTypeAssociation, '埋设'),
  (3, 1, canvasEdgeTypeAssociation, '埋设'),
  (4, 12, canvasEdgeTypeForeshadowPayoff, '兑现'),
  (4, 2, canvasEdgeTypeAssociation, '埋设'),
  (5, 3, canvasEdgeTypeAssociation, '埋设'),
  (6, 11, canvasEdgeTypeAssociation, '推进'),
  (6, 8, canvasEdgeTypeAssociation, '埋设'),
  (7, 12, canvasEdgeTypeForeshadowPayoff, '兑现'),
  (7, 9, canvasEdgeTypeAssociation, '埋设'),
  (8, 11, canvasEdgeTypeAssociation, '埋设'),
  (9, 4, canvasEdgeTypeAssociation, '埋设'),
  (9, 7, canvasEdgeTypeForeshadowPayoff, '兑现'),
  (10, 5, canvasEdgeTypeAssociation, '埋设'),
  (11, 7, canvasEdgeTypeForeshadowPayoff, '兑现'),
  (11, 6, canvasEdgeTypeAssociation, '埋设'),
  (12, 7, canvasEdgeTypeAssociation, '埋设'),
  (13, 11, canvasEdgeTypeAssociation, '埋设'),
];

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

CanvasNode _node(String id, String title, String refType, Offset position) {
  return CanvasNode(
    id: id,
    canvasId: 'canvas_golden',
    type: canvasNodeTypeReference,
    refType: refType,
    refId: 'ref_$id',
    title: title,
    content: '',
    x: position.dx,
    y: position.dy,
    width: null,
    height: null,
    zIndex: 0,
    sortOrder: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    deletedAt: notDeletedSentinel,
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await _loadFont('LXGWWenKai', 'assets/fonts/LXGWWenKai-Regular.ttf');
    // 卡片正文走主题字体族(Georgia/Literata)，不预载会渲染成一排方块。
    await _loadFont('Georgia', 'assets/fonts/LXGWWenKai-Regular.ttf');
    await _loadFont('Literata', 'assets/fonts/Literata-Regular.ttf');
  });

  // 前后两张图必须在同一个 testWidgets 里连续 pump：同一文件里第二个
  // testWidgets 重新包 EasyLocalization 会拿到空子树。
  testWidgets('golden: 伏笔地图重排前 vs 重排后', (tester) async {
    tester.view.physicalSize = const Size(2400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final colors = RevericThemeData.reveric.colors;

    final nodes = <CanvasNode>[
      for (var i = 0; i < _chapters.length; i++)
        _node('c$i', _chapters[i], entityTypeChapter, canvasGridOrigin(i, 0)),
      for (var i = 0; i < _foreshadowings.length; i++)
        _node(
          'f$i',
          _foreshadowings[i],
          entityTypeForeshadowing,
          canvasGridOrigin(i, 1),
        ),
    ];
    final edges = <CanvasEdge>[
      for (final (index, link) in _links.indexed)
        CanvasEdge(
          id: 'e$index',
          canvasId: 'canvas_golden',
          sourceNodeId: 'f${link.$1}',
          targetNodeId: 'c${link.$2}',
          type: link.$3,
          label: link.$4,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
    ];

    Future<void> render(List<CanvasNode> snapshot, String golden) async {
      final controller = flow.NodeFlowController<CanvasFlowNodeData, String>(
        config: flow.NodeFlowConfig(
          minZoom: 0.2,
          maxZoom: 3.0,
          showAttribution: false,
        ),
      );
      addTearDown(controller.dispose);
      controller.loadGraph(
        canvasContentToFlowGraph(
          snapshot,
          edges,
          colors: colors,
          // 整张画布 ~5900×500，缩到 0.38 才装得下，正好也是作者俯瞰全局的视角。
          viewport: const flow.GraphViewport(x: 40, y: 220, zoom: 0.38),
        ),
      );

      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('zh', 'CN')],
          path: 'assets/translations',
          assetLoader: const MergingAssetLoader(),
          fallbackLocale: const Locale('zh', 'CN'),
          startLocale: const Locale('zh', 'CN'),
          child: Builder(
            builder: (context) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                theme: RevericThemeData.reveric.toThemeData(
                  fontFamily: 'LXGWWenKai',
                ),
                home: RevericTheme(
                  data: RevericThemeData.reveric,
                  child: Scaffold(
                    body: SizedBox.expand(
                      child: flow.NodeFlowEditor<CanvasFlowNodeData, String>(
                        // 第二次 pump 换了 controller，不给新 key 的话 Flutter 会复用
                        // 同一个 element 并对未初始化的 controller 调 updateTheme。
                        key: ValueKey(golden),
                        controller: controller,
                        theme: canvasFlowTheme(
                          colors,
                          RevericThemeData.reveric.typography,
                          false,
                          fontFamily: 'LXGWWenKai',
                        ),
                        behavior: flow.NodeFlowBehavior.design,
                        nodeBuilder: (context, node) =>
                            CanvasNodeCard(node: node),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile(golden));
    }

    await render(nodes, 'goldens/canvas_auto_layout_before.png');

    final moved = resolveCanvasAutoLayout(
      nodes: [
        for (final node in nodes)
          (
            id: node.id,
            position: Offset(node.x, node.y),
            size: canvasReferenceDefaultSize,
          ),
      ],
      edges: [
        for (final edge in edges)
          (sourceNodeId: edge.sourceNodeId, targetNodeId: edge.targetNodeId),
      ],
    );
    expect(moved, isNotEmpty);

    await render([
      for (final node in nodes)
        if (moved[node.id] case final position?)
          node.copyWith(x: position.dx, y: position.dy)
        else
          node,
    ], 'goldens/canvas_auto_layout_after.png');
  });
}
