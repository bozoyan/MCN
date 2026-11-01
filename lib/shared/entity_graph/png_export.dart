// 职责: 实体关系图 PNG 导出 — 承接画布图层捕获、合成背景/水印/图例并保存或分享。
// 关联文件:
//   lib/shared/entity_graph/graph_widget.dart
//   lib/shared/entity_graph/constants.dart
//   lib/desktop/widgets/entity_graph_panel.dart
//   lib/mobile/widgets/entity_graph_panel.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/error-handling.md

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../logger/app_logger.dart';
import '../theme/theme.dart';
import 'constants.dart';

final _log = AppLogger.forModule('EntityGraphExport');

/// 画布图层的一次捕获结果。[contentRect] 是画布逻辑坐标系中的内容边界，
/// [image] 覆盖整块画布（含力导向布局的外围留白），像素尺寸 = 画布逻辑尺寸 × [pixelRatio]。
class EntityGraphCapture {
  const EntityGraphCapture({
    required this.image,
    required this.contentRect,
    required this.pixelRatio,
  });

  final ui.Image image;
  final Rect contentRect;
  final double pixelRatio;
}

/// 由面板持有、由 `EntityGraphWidget` 挂载捕获实现的导出句柄。
class EntityGraphExportController {
  Future<EntityGraphCapture> Function()? _capture;

  bool get isAttached => _capture != null;

  void attach(Future<EntityGraphCapture> Function() capture) {
    _capture = capture;
  }

  void detach(Future<EntityGraphCapture> Function() capture) {
    if (identical(_capture, capture)) {
      _capture = null;
    }
  }

  Future<EntityGraphCapture> capture() {
    final capture = _capture;
    if (capture == null) {
      throw StateError('EntityGraphExportController 尚未挂载到 EntityGraphWidget');
    }
    return capture();
  }
}

/// 导出图片的配色与文字样式，由 widget 层从主题解析后传入（本文件不读 BuildContext）。
class EntityGraphPngStyle {
  const EntityGraphPngStyle({
    required this.background,
    required this.dotColor,
    required this.legendBackground,
    required this.legendBorder,
    required this.titleStyle,
    required this.legendTitleStyle,
    required this.legendItemStyle,
  });

  final Color background;
  final Color dotColor;
  final Color legendBackground;
  final Color legendBorder;
  final TextStyle titleStyle;
  final TextStyle legendTitleStyle;
  final TextStyle legendItemStyle;
}

/// 图例中的一个关系分类条目（文案已本地化）。
class EntityGraphPngLegendEntry {
  const EntityGraphPngLegendEntry({required this.label, required this.color});

  final String label;
  final Color color;
}

enum EntityGraphPngSaveStatus { saved, shared, cancelled }

class EntityGraphPngSaveResult {
  const EntityGraphPngSaveResult(this.status, {this.path});

  final EntityGraphPngSaveStatus status;
  final String? path;
}

/// 捕获 → 合成 → 保存/分享的完整流程；异常向上抛出，由调用方记日志并提示。
Future<EntityGraphPngSaveResult> exportEntityGraphPng({
  required EntityGraphExportController controller,
  required EntityGraphPngStyle style,
  required String titleText,
  required String legendTitle,
  required List<EntityGraphPngLegendEntry> legend,
  required String fileName,
}) async {
  final capture = await controller.capture();
  try {
    final bytes = await composeEntityGraphPng(
      capture: capture,
      style: style,
      titleText: titleText,
      legendTitle: legendTitle,
      legend: legend,
    );
    return await saveEntityGraphPng(bytes, fileName: fileName);
  } finally {
    capture.image.dispose();
  }
}

/// 导出分辨率：默认 [kEntityGraphExportMaxPixelRatio]，长边超过
/// [kEntityGraphExportMaxDimension] 时按比例下调，下限 1.0（超大图谱宁可超出上限也保持可读）。
double entityGraphExportPixelRatio(Size logicalSize) {
  final longest = max(logicalSize.width, logicalSize.height);
  if (longest <= 0) {
    return kEntityGraphExportMaxPixelRatio;
  }
  final fitted = kEntityGraphExportMaxDimension / longest;
  if (fitted >= kEntityGraphExportMaxPixelRatio) {
    return kEntityGraphExportMaxPixelRatio;
  }
  final ratio = max(1.0, fitted);
  _log.warning(
    'pixelRatio 降级 ratio=${ratio.toStringAsFixed(2)} '
    'logical=${logicalSize.width.round()}x${logicalSize.height.round()} '
    'maxDimension=${kEntityGraphExportMaxDimension.round()}',
  );
  return ratio;
}

/// 把一次捕获合成为 PNG 字节：主题底色 + 点阵 + 图谱 + 顶部水印 + 底部图例。
Future<Uint8List> composeEntityGraphPng({
  required EntityGraphCapture capture,
  required EntityGraphPngStyle style,
  required String titleText,
  required String legendTitle,
  required List<EntityGraphPngLegendEntry> legend,
}) async {
  final ratio = capture.pixelRatio;
  final imageLogicalSize = Size(
    capture.image.width / ratio,
    capture.image.height / ratio,
  );
  final crop = capture.contentRect
      .inflate(kEntityGraphExportPadding)
      .intersect(Offset.zero & imageLogicalSize);
  if (crop.isEmpty) {
    throw StateError(
      '导出内容区域为空 content=${capture.contentRect} image=$imageLogicalSize',
    );
  }

  final titlePainter = titleText.isEmpty
      ? null
      : _layoutText(
          titleText,
          style.titleStyle,
          maxWidth: max(0.0, crop.width - RevericSpacing.x2l * 2),
        );
  // 水印固定单行，带高取常量，保证导出尺寸只由内容区与图例决定。
  final titleBandHeight = titlePainter == null
      ? 0.0
      : kEntityGraphExportTitleBandHeight;
  final legendLayout = _layoutLegend(
    legendTitle: legendTitle,
    entries: legend,
    style: style,
    maxWidth: crop.width,
  );
  final legendBandHeight = legendLayout?.height ?? 0.0;

  final totalSize = Size(
    crop.width,
    titleBandHeight + crop.height + legendBandHeight,
  );

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio);

  canvas.drawRect(Offset.zero & totalSize, Paint()..color = style.background);
  _paintDotGrid(canvas, totalSize, style.dotColor);

  canvas.drawImageRect(
    capture.image,
    Rect.fromLTWH(
      crop.left * ratio,
      crop.top * ratio,
      crop.width * ratio,
      crop.height * ratio,
    ),
    Rect.fromLTWH(0, titleBandHeight, crop.width, crop.height),
    Paint()..filterQuality = FilterQuality.high,
  );

  if (titlePainter != null) {
    titlePainter.paint(
      canvas,
      Offset(RevericSpacing.x2l, (titleBandHeight - titlePainter.height) / 2),
    );
  }

  if (legendLayout != null) {
    _paintLegend(
      canvas,
      layout: legendLayout,
      style: style,
      top: titleBandHeight + crop.height,
      width: totalSize.width,
    );
  }

  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (totalSize.width * ratio).round(),
      (totalSize.height * ratio).round(),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('PNG 编码失败：toByteData 返回 null');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// 桌面弹系统保存对话框写文件；移动端写临时文件后走系统分享面板。
Future<EntityGraphPngSaveResult> saveEntityGraphPng(
  Uint8List bytes, {
  required String fileName,
}) async {
  final safeName = _sanitizeFileName(fileName);
  if (Platform.isIOS || Platform.isAndroid) {
    final cacheRoot = Directory(
      '${(await getTemporaryDirectory()).path}/$_exportCacheDirName',
    );
    await cacheRoot.create(recursive: true);
    await _cleanupExpiredExports(cacheRoot);
    final file = File('${cacheRoot.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    // Android 上取消分享也可能返回非 success，不能当作失败处理。
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        fileNameOverrides: [safeName],
      ),
    );
    return EntityGraphPngSaveResult(
      EntityGraphPngSaveStatus.shared,
      path: file.path,
    );
  }

  final location = await getSaveLocation(
    suggestedName: safeName,
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'PNG',
        extensions: ['png'],
        uniformTypeIdentifiers: ['public.png'],
      ),
    ],
  );
  if (location == null) {
    return const EntityGraphPngSaveResult(EntityGraphPngSaveStatus.cancelled);
  }
  final file = File(location.path);
  await file.writeAsBytes(bytes, flush: true);
  return EntityGraphPngSaveResult(
    EntityGraphPngSaveStatus.saved,
    path: file.path,
  );
}

const String _exportCacheDirName = 'reveric_graph_exports';

Future<void> _cleanupExpiredExports(Directory cacheRoot) async {
  final expiredBefore = DateTime.now().subtract(const Duration(days: 1));
  await for (final entity in cacheRoot.list()) {
    if (entity is! File) {
      continue;
    }
    try {
      final stat = await entity.stat();
      if (stat.modified.isBefore(expiredBefore)) {
        await entity.delete();
      }
    } catch (error) {
      _log.warning('清理导出缓存失败 path=${entity.path} error=$error');
    }
  }
}

String _sanitizeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
  return cleaned.isEmpty ? 'entity_graph.png' : cleaned;
}

TextPainter _layoutText(String text, TextStyle style, {double? maxWidth}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  );
  painter.layout(maxWidth: maxWidth ?? double.infinity);
  return painter;
}

void _paintDotGrid(Canvas canvas, Size size, Color color) {
  final paint = Paint()..color = color;
  const spacing = kEntityGraphDotGridSpacing;
  for (var x = spacing / 2; x < size.width; x += spacing) {
    for (var y = spacing / 2; y < size.height; y += spacing) {
      canvas.drawCircle(Offset(x, y), kEntityGraphDotGridDotRadius, paint);
    }
  }
}

class _LegendItem {
  const _LegendItem({required this.painter, required this.color});

  final TextPainter painter;
  final Color color;

  double get width =>
      kEntityGraphExportLegendSwatchWidth + RevericSpacing.xxs + painter.width;
}

class _LegendLayout {
  const _LegendLayout({
    required this.titlePainter,
    required this.rows,
    required this.itemsLeft,
    required this.height,
  });

  final TextPainter titlePainter;
  final List<List<_LegendItem>> rows;
  final double itemsLeft;
  final double height;
}

_LegendLayout? _layoutLegend({
  required String legendTitle,
  required List<EntityGraphPngLegendEntry> entries,
  required EntityGraphPngStyle style,
  required double maxWidth,
}) {
  if (entries.isEmpty) {
    return null;
  }
  final titlePainter = _layoutText(legendTitle, style.legendTitleStyle);
  final itemsLeft =
      RevericSpacing.x2l + titlePainter.width + RevericSpacing.md;
  final available = max(
    kEntityGraphExportLegendSwatchWidth * 4,
    maxWidth - itemsLeft - RevericSpacing.x2l,
  );

  final rows = <List<_LegendItem>>[<_LegendItem>[]];
  var used = 0.0;
  for (final entry in entries) {
    final item = _LegendItem(
      painter: _layoutText(entry.label, style.legendItemStyle),
      color: entry.color,
    );
    final gap = rows.last.isEmpty ? 0.0 : RevericSpacing.md;
    if (rows.last.isNotEmpty && used + gap + item.width > available) {
      rows.add(<_LegendItem>[item]);
      used = item.width;
      continue;
    }
    rows.last.add(item);
    used += gap + item.width;
  }

  return _LegendLayout(
    titlePainter: titlePainter,
    rows: rows,
    itemsLeft: itemsLeft,
    height:
        RevericSpacing.sm * 2 +
        rows.length * kEntityGraphExportLegendRowHeight,
  );
}

void _paintLegend(
  Canvas canvas, {
  required _LegendLayout layout,
  required EntityGraphPngStyle style,
  required double top,
  required double width,
}) {
  canvas.drawRect(
    Rect.fromLTWH(0, top, width, layout.height),
    Paint()..color = style.legendBackground,
  );
  canvas.drawLine(
    Offset(0, top),
    Offset(width, top),
    Paint()
      ..color = style.legendBorder
      ..strokeWidth = 1,
  );

  final firstRowCenter =
      top + RevericSpacing.sm + kEntityGraphExportLegendRowHeight / 2;
  layout.titlePainter.paint(
    canvas,
    Offset(
      RevericSpacing.x2l,
      firstRowCenter - layout.titlePainter.height / 2,
    ),
  );

  for (var row = 0; row < layout.rows.length; row++) {
    final centerY = firstRowCenter + row * kEntityGraphExportLegendRowHeight;
    var dx = layout.itemsLeft;
    for (final item in layout.rows[row]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            dx,
            centerY - kEntityGraphExportLegendSwatchHeight / 2,
            kEntityGraphExportLegendSwatchWidth,
            kEntityGraphExportLegendSwatchHeight,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = item.color,
      );
      item.painter.paint(
        canvas,
        Offset(
          dx + kEntityGraphExportLegendSwatchWidth + RevericSpacing.xxs,
          centerY - item.painter.height / 2,
        ),
      );
      dx += item.width + RevericSpacing.md;
    }
  }
}
