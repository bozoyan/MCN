// 职责: 实体关系图 Widget 回归测试 — 验证聚焦点击与相机矩阵稳定性。
// 关联文件:
//   lib/shared/entity_graph/graph_widget.dart
//   lib/shared/entity_graph/layout.dart
//   lib/shared/entity_graph/models.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/i18n.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/entity_graph/colors.dart';
import 'package:reveric/shared/entity_graph/constants.dart';
import 'package:reveric/shared/entity_graph/graph_widget.dart';
import 'package:reveric/shared/entity_graph/layout.dart';
import 'package:reveric/shared/entity_graph/models.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('focus interactions clear empty taps and keep camera stable', (
    tester,
  ) async {
    final harness = _GraphHarnessController();

    await tester.pumpWidget(_wrapGraph(_GraphHarness(controller: harness)));
    await tester.pumpAndSettle();

    final graphController = _graphTransformController(tester);
    final initialCamera = _matrixStorage(graphController);

    expect(harness.selectedNodeKey, 'character_a');

    await tester.tapAt(
      _nodeScreenCenter(
        tester: tester,
        controller: graphController,
        nodeKey: 'character_b',
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.clearCount, 0);
    expect(harness.tappedNodeKeys, ['character_b']);
    expect(harness.selectedNodeKey, 'character_b');
    _expectMatrixStorage(graphController, initialCamera);

    final viewportRect = tester.getRect(
      find.byKey(const ValueKey('entity_graph_viewport')),
    );
    await tester.tapAt(viewportRect.topLeft + const Offset(12, 12));
    await tester.pumpAndSettle();

    expect(harness.clearCount, 1);
    expect(harness.tappedNodeKeys, ['character_b']);
    expect(harness.selectedNodeKey, isNull);
    _expectMatrixStorage(graphController, initialCamera);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _GraphHarnessController {
  final tappedNodeKeys = <String>[];
  int clearCount = 0;
  String? selectedNodeKey = 'character_a';
}

class _GraphHarness extends StatefulWidget {
  const _GraphHarness({required this.controller});

  final _GraphHarnessController controller;

  @override
  State<_GraphHarness> createState() => _GraphHarnessState();
}

class _GraphHarnessState extends State<_GraphHarness> {
  @override
  Widget build(BuildContext context) {
    return EntityGraphWidget(
      databasePath: 'test.sqlite',
      nodes: _nodes,
      edges: _edges,
      selectedNodeKey: widget.controller.selectedNodeKey,
      defaultCenterNodeKey: 'character_a',
      onNodeTap: (key) {
        setState(() {
          widget.controller.tappedNodeKeys.add(key);
          widget.controller.selectedNodeKey =
              widget.controller.selectedNodeKey == key ? null : key;
        });
      },
      onClearSelection: () {
        setState(() {
          widget.controller.clearCount++;
          widget.controller.selectedNodeKey = null;
        });
      },
    );
  }
}

const _nodes = <EntityNodeData>[
  EntityNodeData(
    key: 'character_a',
    entityType: 'character',
    entityId: 'a',
    name: 'Alpha',
  ),
  EntityNodeData(
    key: 'character_b',
    entityType: 'character',
    entityId: 'b',
    name: 'Beta',
  ),
  EntityNodeData(
    key: 'faction_c',
    entityType: 'faction',
    entityId: 'c',
    name: 'Circle',
  ),
];

const _edges = <EntityEdgeData>[
  EntityEdgeData(
    id: 'edge_ab',
    sourceKey: 'character_a',
    targetKey: 'character_b',
    relationType: 'friend',
    label: 'friend',
    color: Colors.green,
    category: RelationCategory.bond,
    directed: false,
  ),
  EntityEdgeData(
    id: 'edge_ac',
    sourceKey: 'character_a',
    targetKey: 'faction_c',
    relationType: 'member',
    label: 'member',
    color: Colors.blue,
    category: RelationCategory.faction,
    directed: false,
  ),
];

Widget _wrapGraph(Widget child) {
  return ProviderScope(
    child: EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: Center(
                  child: SizedBox(width: 960, height: 640, child: child),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

TransformationController _graphTransformController(WidgetTester tester) {
  final viewer = tester.widget<InteractiveViewer>(
    find.byType(InteractiveViewer),
  );
  final controller = viewer.transformationController;
  expect(controller, isNotNull);
  return controller!;
}

List<double> _matrixStorage(TransformationController controller) {
  return List<double>.from(controller.value.storage);
}

void _expectMatrixStorage(
  TransformationController controller,
  List<double> expected,
) {
  final actual = controller.value.storage;
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], moreOrLessEquals(expected[i], epsilon: 0.0001));
  }
}

Offset _nodeScreenCenter({
  required WidgetTester tester,
  required TransformationController controller,
  required String nodeKey,
}) {
  final positions = computeEntityGraphLayout(
    nodes: _nodes,
    edges: _edges,
    centerNodeKey: 'character_a',
  );
  final bounds = computeEntityGraphContentBounds(
    positions,
    includeLabels: true,
  );
  final canvasOffset = Offset(
    kEntityGraphNodeSpacing - bounds.left,
    kEntityGraphNodeSpacing - bounds.top,
  );
  final canvasPoint = positions[nodeKey]! + canvasOffset;
  final transformedPoint = MatrixUtils.transformPoint(
    controller.value,
    canvasPoint,
  );
  final viewportRect = tester.getRect(
    find.byKey(const ValueKey('entity_graph_viewport')),
  );
  return viewportRect.topLeft + transformedPoint;
}
