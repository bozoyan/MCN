// 职责: 验证多选外框在负坐标、缩放和平移后的实际绘制范围。
// 关联文件:
//   lib/desktop/features/production/selection_layer.dart
//   lib/third/flow/vyuh_node_flow/lib/src/editor/unbounded_widgets.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/production/selection_layer.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/third/flow/vyuh_node_flow.dart' as flow;

void main() {
  testWidgets('selection outline paints outside the graph origin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = flow.NodeFlowController<String, String>(
      config: flow.NodeFlowConfig(
        showAttribution: false,
        plugins: [ProductionSelectionLayer()],
      ),
    );
    for (final entry in {
      'left': const Offset(-300, -150),
      'right': const Offset(80, 150),
    }.entries) {
      controller.addNode(
        flow.Node<String>(
          type: 'image',
          id: entry.key,
          position: entry.value,
          size: const Size(160, 100),
          data: entry.key,
        ),
      );
    }
    const captureKey = ValueKey('selection-capture');
    final colors = RevericThemeData.reveric.colors;
    await tester.pumpWidget(
      MaterialApp(
        home: RevericTheme(
          data: RevericThemeData.reveric,
          child: RepaintBoundary(
            key: captureKey,
            child: flow.NodeFlowEditor<String, String>(
              controller: controller,
              theme: flow.NodeFlowTheme.light.copyWith(
                backgroundColor: colors.canvas,
              ),
              nodeBuilder: (_, node) => ColoredBox(color: colors.surface),
            ),
          ),
        ),
      ),
    );
    controller.setViewport(const flow.GraphViewport(x: 450, y: 250, zoom: .8));
    controller.selectNodes(['left', 'right']);
    await tester.pumpAndSettle();
    final frame = tester.getRect(
      find.byKey(const ValueKey('production-selection-bounds')),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage();
      const capturePath = String.fromEnvironment('SELECTION_CAPTURE_PATH');
      if (capturePath.isNotEmpty) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(capturePath).writeAsBytes(png!.buffer.asUint8List());
      }
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return raw!;
    });
    // Read the actual painted left edge, not just the render object's correct bounds.
    var edgePixels = 0;
    for (var y = frame.top.ceil() + 20; y < frame.bottom.floor() - 20; y++) {
      for (var x = frame.left.floor() - 1; x <= frame.left.ceil() + 1; x++) {
        final at = (y * 900 + x) * 4;
        final r = pixels!.getUint8(at);
        final g = pixels.getUint8(at + 1);
        final b = pixels.getUint8(at + 2);
        if ((r - colors.canvas.r * 255).abs() +
                (g - colors.canvas.g * 255).abs() +
                (b - colors.canvas.b * 255).abs() >
            100) {
          edgePixels++;
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    expect(
      edgePixels,
      greaterThan(30),
      reason: 'The complete left outline must paint left of graph x=0.',
    );
  });
}
