// 职责: 关系图 PNG 合成回归测试 — 验证输出尺寸、编码有效性与分辨率钳制。
// 关联文件:
//   lib/shared/entity_graph/png_export.dart
//   lib/shared/entity_graph/constants.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/entity_graph/constants.dart';
import 'package:reveric/shared/entity_graph/png_export.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = EntityGraphPngStyle(
    background: Color(0xFFFFFBF5),
    dotColor: Color(0xFFE8E2D8),
    legendBackground: Color(0xFFF5F1EB),
    legendBorder: Color(0xFFE8E2D8),
    titleStyle: TextStyle(fontSize: 12, color: Color(0xFF8A7D6B)),
    legendTitleStyle: TextStyle(fontSize: 11, color: Color(0xFF8A7D6B)),
    legendItemStyle: TextStyle(fontSize: 11, color: Color(0xFF5B5347)),
  );

  test('composeEntityGraphPng 输出内容区 + 水印 + 图例的完整画面', () async {
    // 画布 600x400（逻辑），内容边界 200,200 起 200x100 —— 与 graph_widget 的
    // canvasOffset = kEntityGraphNodeSpacing - bounds.left 一致。
    const canvasSize = Size(600, 400);
    const contentRect = Rect.fromLTWH(200, 200, 200, 100);
    const pixelRatio = 2.0;
    final capture = EntityGraphCapture(
      image: await _solidImage(canvasSize, pixelRatio),
      contentRect: contentRect,
      pixelRatio: pixelRatio,
    );

    final bytes = await composeEntityGraphPng(
      capture: capture,
      style: style,
      titleText: '《测试》· 关系图谱 · 2026-08-17 10:00',
      legendTitle: '关系类型',
      legend: const [
        EntityGraphPngLegendEntry(label: '亲族', color: Color(0xFFD4845A)),
        EntityGraphPngLegendEntry(label: '敌对', color: Color(0xFFC25B5B)),
      ],
    );
    capture.image.dispose();

    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);

    final decoded = await _decode(bytes);
    final expectedWidth =
        (contentRect.width + kEntityGraphExportPadding * 2) * pixelRatio;
    expect(decoded.width, expectedWidth.round());
    // 高度 = 水印行 + 内容高（含留白）+ 单行图例带。
    final expectedHeight =
        (kEntityGraphExportTitleBandHeight +
            contentRect.height +
            kEntityGraphExportPadding * 2 +
            RevericSpacing.sm * 2 +
            kEntityGraphExportLegendRowHeight) *
        pixelRatio;
    expect(decoded.height, expectedHeight.round());
    decoded.dispose();
  });

  test('composeEntityGraphPng 无图例时不画图例带', () async {
    const canvasSize = Size(600, 400);
    const contentRect = Rect.fromLTWH(200, 200, 200, 100);
    final capture = EntityGraphCapture(
      image: await _solidImage(canvasSize, 1.0),
      contentRect: contentRect,
      pixelRatio: 1.0,
    );

    final bytes = await composeEntityGraphPng(
      capture: capture,
      style: style,
      titleText: '关系图谱',
      legendTitle: '关系类型',
      legend: const [],
    );
    capture.image.dispose();

    final decoded = await _decode(bytes);
    expect(
      decoded.height,
      (kEntityGraphExportTitleBandHeight +
              contentRect.height +
              kEntityGraphExportPadding * 2)
          .round(),
    );
    decoded.dispose();
  });

  test('entityGraphExportPixelRatio 在长边超限时降级，且不低于 1', () {
    expect(entityGraphExportPixelRatio(const Size(800, 600)), 2.0);
    expect(
      entityGraphExportPixelRatio(const Size(6000, 1000)),
      moreOrLessEquals(1.0, epsilon: 0.0001),
    );
    expect(entityGraphExportPixelRatio(const Size(20000, 1000)), 1.0);
    expect(
      entityGraphExportPixelRatio(const Size(4000, 1000)),
      moreOrLessEquals(1.5, epsilon: 0.0001),
    );
  });
}

Future<ui.Image> _solidImage(Size logicalSize, double pixelRatio) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  canvas.drawRect(
    Offset.zero & logicalSize,
    Paint()..color = const Color(0xFF3366FF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (logicalSize.width * pixelRatio).round(),
    (logicalSize.height * pixelRatio).round(),
  );
  picture.dispose();
  return image;
}

Future<ui.Image> _decode(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}
