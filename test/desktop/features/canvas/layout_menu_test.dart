// 职责: 验证排列菜单按图结构禁用无效排列，并防止忙碌期间重复操作。
// 关联文件:
//   lib/desktop/features/canvas/layout_menu.dart
//   lib/desktop/features/canvas/edit_session.dart
//   lib/shared/providers/canvas_providers.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/i18n.md

import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/canvas/layout_menu.dart';
import 'package:reveric/desktop/features/canvas/edit_session.dart';
import 'package:reveric/desktop/features/canvas/widgets/floating_cluster.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/shared/providers/canvas_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());
  for (final kind in ['none', 'relationship', 'timeline', 'cycle']) {
    testWidgets('$kind allows only applicable layout actions', (tester) async {
      final session = CanvasEditSession();
      addTearDown(session.dispose);
      final nodes = [_node('a'), _node('b')];
      final edges = [
        if (kind != 'none')
          _edge('ab', 'a', 'b', kind == 'cycle' ? 'timeline' : kind),
        if (kind == 'cycle') _edge('ba', 'b', 'a', 'timeline'),
      ];
      String? picked;
      await tester.pumpWidget(
        _wrap(nodes, edges, session, (mode) async {
          picked = mode;
        }),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Arrange'));
      await tester.pumpAndSettle();
      expect(find.text('Last used'), findsNothing);
      expect(find.text('Recommended'), findsNothing);
      if (kind == 'none' || kind == 'relationship') {
        expect(
          find.byTooltip('Requires directed connections. You can use Grid.'),
          findsNWidgets(2),
        );
      }
      for (final (label, mode) in [
        ('Hierarchy · Left to right', canvasLayoutTreeLr),
        ('Hierarchy · Top to bottom', canvasLayoutTreeTb),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        if (kind == 'timeline' || kind == 'cycle') {
          expect(picked, mode);
          await tester.tap(find.byTooltip('Arrange'));
          await tester.pumpAndSettle();
        } else {
          expect(picked, isNull);
        }
      }
      await tester.tap(find.text('Grid'));
      await tester.pumpAndSettle();
      expect(picked, canvasLayoutGrid);
      final gate = Completer<void>();
      final running = session.runExclusive(() => gate.future);
      await tester.pump();
      expect(
        tester
            .widget<CanvasFloatingButton>(find.byType(CanvasFloatingButton))
            .onTap,
        isNull,
      );
      gate.complete();
      await running;
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
  for (final count in [0, 1]) {
    testWidgets('$count nodes disables arrangement', (tester) async {
      final session = CanvasEditSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        _wrap([if (count == 1) _node('a')], [], session, (_) async {}),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CanvasFloatingButton>(find.byType(CanvasFloatingButton))
            .onTap,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

CanvasNode _node(String id) => CanvasNode(
  id: id,
  canvasId: 'canvas',
  type: canvasNodeTypeSticky,
  title: id,
  content: id,
  x: 0,
  y: 0,
  zIndex: 0,
  sortOrder: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  deletedAt: notDeletedSentinel,
);
CanvasEdge _edge(String id, String a, String b, String type) => CanvasEdge(
  id: id,
  canvasId: 'canvas',
  sourceNodeId: a,
  targetNodeId: b,
  type: type,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
Widget _wrap(
  List<CanvasNode> nodes,
  List<CanvasEdge> edges,
  CanvasEditSession session,
  Future<void> Function(String) onSelected,
) => ProviderScope(
  overrides: [
    canvasContentStreamProvider((
      canvasId: 'canvas',
      databasePath: 'memory:menu',
    )).overrideWith((ref) => Stream.value((nodes: nodes, edges: edges))),
  ],
  child: EasyLocalization(
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
        home: Scaffold(
          body: CanvasLayoutMenu(
            canvasId: 'canvas',
            databasePath: 'memory:menu',
            session: session,
            onSelected: onSelected,
          ),
        ),
      ),
    ),
  ),
);
