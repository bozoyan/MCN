// 职责: Patrol E2E — FakeAgent 调真实 canvas 工具时,画布镜头跟随、状态条与「用户接管后暂停跟随」的真实渲染验证
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/canvas/canvas_camera_policy.dart
//   lib/shared/services/ai/tools_canvas.dart
//   lib/shared/providers/canvas_providers.dart
//   lib/shared/agent/fake_agent.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
//   .agents/rules/state-management.md

import 'dart:io';

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_ai_focus_layer.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_board.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_detail_layer.dart';
import 'package:reveric/desktop/features/canvas/widgets/canvas_flow_adapter.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/canvas_layout.dart';
import 'package:reveric/shared/providers/canvas_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/app_background.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 画布区尺寸：与桌面窗口减去 chat panel 后的宽度同量级。
const Size _surface = Size(1100, 760);
const String _canvasName = 'E2E 时间线';

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => rootBundle.clear());

  // 在同一张画布连续验证 AI 跟随与用户接管后的暂停行为。
  patrolTest('AI 编辑画布时镜头跟随并提示状态，用户接管后停止跟随', ($) async {
    $.tester.view.devicePixelRatio = 1;
    $.tester.view.physicalSize = _surface;
    addTearDown(() {
      $.tester.view.resetPhysicalSize();
      $.tester.view.resetDevicePixelRatio();
    });

    // ---- 真实数据层：内存库 + 真实 CanvasService ----
    // ignore: invalid_use_of_visible_for_testing_member
    final db = NovelContentDatabase.forTest(NativeDatabase.memory());
    addTearDown(db.close);
    // ignore: invalid_use_of_visible_for_testing_member
    final appDb = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(appDb.close);
    final tempDir = await Directory.systemTemp.createTemp(
      'reveric_canvas_e2e_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final databasePath = '${tempDir.path}/content.sqlite';

    final contentService = NovelContentService(db);
    final canvasService = contentService.canvasService;
    final overlay = WorkingOverlayService(
      db,
      contentService,
      novelActionsService: NovelActionsService(appDb),
    );

    final canvasId = await canvasService.createCanvas(name: _canvasName);
    for (var col = 0; col < 3; col++) {
      final origin = canvasGridOrigin(col, 0);
      await canvasService.addNode(
        canvasId: canvasId,
        type: canvasNodeTypeSticky,
        content: '开场第 $col 拍',
        x: origin.dx,
        y: origin.dy,
      );
    }

    final container = ProviderContainer(
      overrides: [
        // UI 与工具层必须看同一个库，否则 AI 写入不会回流到画布。
        novelContentDatabaseProvider(databasePath).overrideWithValue(db),
        appBackgroundActiveProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    // ---- 工具层：真实 AiToolManager，reporter 接到真实 provider（与生产同形）----
    final toolManager = AiToolManager(
      contentService,
      workingOverlayService: overlay,
      canvasActivityReporter: (activity) =>
          container.read(canvasAiActivityProvider.notifier).report(activity),
    )..registerAllTools();

    // ---- UI ----
    final detailLayer = CanvasDetailLayer();
    final focusLayer = CanvasAiFocusLayer();
    final controller = CanvasFlowController(
      config: flow.NodeFlowConfig(
        minZoom: 0.2,
        maxZoom: 3.0,
        showAttribution: false,
        plugins: [...flow.NodeFlowConfig.defaultPlugins(), focusLayer],
      ),
    );
    addTearDown(controller.dispose);

    await $.pumpWidget(
      _CanvasHarness(
        container: container,
        canvasId: canvasId,
        databasePath: databasePath,
        controller: controller,
        detailLayer: detailLayer,
        focusLayer: focusLayer,
      ),
    );
    // flow 画布持续有动画 timer，pumpAndSettle 不会停 —— 用定量 pump。
    await _pumpFor($, const Duration(milliseconds: 900));

    expect(
      find.text('开场第 0 拍'),
      findsOneWidget,
      reason: '首次加载应 fitToView，把已有节点都摆进视野',
    );
    final viewportBeforeAi = _viewportOf(controller);

    // ---- 场景一：AI 在远处加节点，镜头应把它带进视野 ----
    final agent = FakeAgent.create(
      toolManager: toolManager,
      client: FakeProviderClient(
        responses: const [
          FakeProviderClientResponse.toolCalls([
            ToolCall(
              callId: 'call_add_far',
              toolName: 'Create',
              arguments: {
                'path': '/canvas/$_canvasName/nodes',
                'fields': {
                  'type': 'sticky',
                  'content': '远处的第 12 拍',
                  'color': 'rose',
                  'col': 12,
                  'row': 0,
                },
              },
            ),
          ]),
          FakeProviderClientResponse.text('已加上第 12 拍。'),
        ],
      ),
    );

    await agent.process('把第 12 拍加到时间线末尾').toList();
    // 工具会等待画布节拍器完成跟随后再返回；此时新节点应已进入视野。
    await $.tester.pump();
    final boardRect = $.tester.getRect(find.byType(CanvasBoard));
    expect(
      _viewportOf(controller),
      isNot(viewportBeforeAi),
      reason: '工具完成前镜头应已跟随远处的新节点',
    );
    expect(find.text('AI is adding a node'), findsOneWidget);
    expect(
      _isInside(boardRect, _rectOrNull($, find.text('远处的第 12 拍'))),
      isTrue,
      reason: 'AI 加在视野外的节点应被镜头带进画面',
    );

    // ---- 场景二：用户一动手就暂停跟随 ----
    await $.tester.dragFrom(boardRect.center, const Offset(-40, 0));
    await _pumpFor($, const Duration(milliseconds: 200));
    expect(find.textContaining('Following paused'), findsOneWidget);
    final viewportAfterUserPan = _viewportOf(controller);

    final pausedAgent = FakeAgent.create(
      toolManager: toolManager,
      client: FakeProviderClient(
        responses: const [
          FakeProviderClientResponse.toolCalls([
            ToolCall(
              callId: 'call_add_far_2',
              toolName: 'Create',
              arguments: {
                'path': '/canvas/$_canvasName/nodes',
                'fields': {
                  'type': 'sticky',
                  'content': '更远的第 24 拍',
                  'col': 24,
                  'row': 0,
                },
              },
            ),
          ]),
          FakeProviderClientResponse.text('已加上第 24 拍。'),
        ],
      ),
    );
    await pausedAgent.process('再加第 24 拍').toList();
    await _pumpFor($, const Duration(milliseconds: 1600));

    expect(
      _viewportOf(controller),
      viewportAfterUserPan,
      reason: '用户接管后镜头不该再被 AI 拽走',
    );
    expect(
      _isInside(boardRect, _rectOrNull($, find.text('更远的第 24 拍'))),
      isFalse,
      reason: '暂停跟随时新节点应停在视野外',
    );

    // 数据仍然照常落库 —— 暂停的是镜头，不是编辑。
    final snapshot = await canvasService.watchCanvasContent(canvasId).first;
    expect(snapshot.nodes.length, 5);
    expect(
      canvasNodeColorValueOf(
        snapshot.nodes.firstWhere((node) => node.content == '远处的第 12 拍').style,
      ),
      'rose',
      reason: 'AI 指定的纸色要真的落到 style 上',
    );
    await $.tester.pumpWidget(const SizedBox.shrink());
    await $.tester.pumpAndSettle();
  });
}

/// 取当前视口的可比较快照（GraphViewport 未实现 ==）。
({double x, double y, double zoom}) _viewportOf(
  CanvasFlowController controller,
) {
  final viewport = controller.viewport;
  return (x: viewport.x, y: viewport.y, zoom: viewport.zoom);
}

/// flow 画布的动画 timer 让 pumpAndSettle 永不返回，改为定量推进。
Future<void> _pumpFor(PatrolIntegrationTester $, Duration total) async {
  const step = Duration(milliseconds: 50);
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await $.tester.pump(step);
    elapsed += step;
  }
}

Rect? _rectOrNull(PatrolIntegrationTester $, Finder finder) {
  if (finder.evaluate().isEmpty) {
    return null;
  }
  return $.tester.getRect(finder);
}

/// 目标是否完整落在画布可视区内（找不到目标视为不可见）。
bool _isInside(Rect board, Rect? target) {
  if (target == null) {
    return false;
  }
  return target.left >= board.left &&
      target.top >= board.top &&
      target.right <= board.right &&
      target.bottom <= board.bottom;
}

class _CanvasHarness extends StatelessWidget {
  const _CanvasHarness({
    required this.container,
    required this.canvasId,
    required this.databasePath,
    required this.controller,
    required this.detailLayer,
    required this.focusLayer,
  });

  final ProviderContainer container;
  final String canvasId;
  final String databasePath;
  final CanvasFlowController controller;
  final CanvasDetailLayer detailLayer;
  final CanvasAiFocusLayer focusLayer;

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: CanvasBoard(
                  canvasId: canvasId,
                  databasePath: databasePath,
                  controller: controller,
                  detailLayer: detailLayer,
                  focusLayer: focusLayer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
