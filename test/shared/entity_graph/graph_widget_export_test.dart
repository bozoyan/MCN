// 职责: 关系图画布导出捕获回归测试 — 验证捕获图层尺寸与缩放解耦。
// 关联文件:
//   lib/shared/entity_graph/graph_widget.dart
//   lib/shared/entity_graph/png_export.dart
//   lib/shared/entity_graph/layout.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/i18n.md
//   .agents/rules/testing.md
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/entity_graph/colors.dart';
import 'package:reveric/shared/entity_graph/constants.dart';
import 'package:reveric/shared/entity_graph/graph_widget.dart';
import 'package:reveric/shared/entity_graph/layout.dart';
import 'package:reveric/shared/entity_graph/models.dart';
import 'package:reveric/shared/entity_graph/png_export.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('导出捕获覆盖整块画布，尺寸与当前缩放无关', (tester) async {
    final controller = EntityGraphExportController();

    await tester.pumpWidget(
      _wrapGraph(
        EntityGraphWidget(
          databasePath: 'test.sqlite',
          nodes: _nodes,
          edges: _edges,
          defaultCenterNodeKey: 'character_a',
          exportController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.isAttached, isTrue);

    final positions = computeEntityGraphLayout(
      nodes: _nodes,
      edges: _edges,
      centerNodeKey: 'character_a',
    );
    final bounds = computeEntityGraphContentBounds(
      positions,
      includeLabels: true,
    );
    final canvasSize = Size(
      bounds.width + kEntityGraphNodeSpacing * 2,
      bounds.height + kEntityGraphNodeSpacing * 2,
    );

    final captureFuture = controller.capture();
    // 捕获会先切到导出态再等两帧，需要驱动帧循环。
    await tester.pumpAndSettle();
    final capture = await captureFuture;

    expect(capture.pixelRatio, entityGraphExportPixelRatio(canvasSize));
    expect(
      capture.image.width,
      (canvasSize.width * capture.pixelRatio).round(),
    );
    expect(
      capture.image.height,
      (canvasSize.height * capture.pixelRatio).round(),
    );
    expect(capture.contentRect.width, moreOrLessEquals(bounds.width));
    expect(capture.contentRect.height, moreOrLessEquals(bounds.height));
    final baseWidth = capture.image.width;
    final baseHeight = capture.image.height;
    capture.image.dispose();

    // 放大并平移后再捕获：导出画面必须仍是整块画布，与相机状态无关。
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-300.0, -200.0, 0.0, 1.0)
      ..scaleByDouble(2.4, 2.4, 1.0, 1.0);
    await tester.pumpAndSettle();

    final zoomedFuture = controller.capture();
    await tester.pumpAndSettle();
    final zoomed = await zoomedFuture;
    expect(zoomed.image.width, baseWidth);
    expect(zoomed.image.height, baseHeight);
    zoomed.image.dispose();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, timeout: const Timeout(Duration(seconds: 60)));
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
