// 职责: 在主 isolate 按画布卡片与 flow 主题的同一套取值，把导出快照的每张卡片、每条连线
//       解析成预览 SVG 的纯值输入：颜色、图标源码、按 Flutter 排版断好行的文字。
// 关联文件:
//   lib/desktop/features/canvas/export_button.dart
//   lib/desktop/features/canvas/widgets/canvas_node_widget.dart
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/shared/models/canvas_export_preview.dart
//   lib/shared/services/canvas_export/svg.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/database/novel_content_database.dart';
import '../../../shared/models/canvas_export.dart';
import '../../../shared/models/canvas_export_preview.dart';
import '../../../shared/models/canvas_scene_reference.dart';
import '../../../shared/theme/canvas_card_metrics.dart';
import '../../../shared/theme/theme.dart';
import 'canvas_palette.dart';
import 'widgets/canvas_node_widget.dart';

/// 卡片文字的省略号，与 [TextOverflow.ellipsis] 一致。
const _ellipsis = '…';

/// flow 边标签的省略号（见 connection_labels_layer 的 TextPainter）。
const _labelEllipsis = '...';

/// [invalidNodeIds] 与 [scenes] 取画布当前用的同一份 provider 值，卡片灰态与
/// 场次标题因此与画布一致。上下文相关的取值都在第一个 await 之前完成。
Future<CanvasExportPreview> buildCanvasExportPreview(
  BuildContext context, {
  required CanvasExportSnapshot snapshot,
  required Set<String> invalidNodeIds,
  required Map<String, CanvasSceneReference> scenes,
}) async {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);
  // 卡片在 Material 里，继承的默认文字样式就是 bodyMedium；不取导出按钮处的
  // DefaultTextStyle，免得按钮挂在别处时字体跟着变。
  final base =
      Theme.of(context).textTheme.bodyMedium ??
      DefaultTextStyle.of(context).style;
  final fontFamily = base.fontFamily;
  final scaler = MediaQuery.textScalerOf(context);
  final flowTheme = canvasFlowTheme(
    colors,
    typo,
    false,
    fontFamily: fontFamily,
  );
  final labelTheme = flowTheme.labelTheme;

  _Text text(
    String value,
    TextStyle style, {
    required double maxWidth,
    int? maxLines,
    String? ellipsis,
    double? maxHeight,
    TextAlign align = TextAlign.start,
  }) => _layoutText(
    value,
    base.merge(style),
    scaler: scaler,
    maxWidth: maxWidth,
    maxLines: maxLines,
    ellipsis: ellipsis,
    maxHeight: maxHeight,
    align: align,
  );

  final nodes = <String, CanvasExportNodeFace>{};
  for (final node in snapshot.nodes) {
    final id = node['id'] as String;
    final width = (node['width'] as num).toDouble();
    final height = (node['height'] as num).toDouble();
    final title = node['title'] as String;
    if (node['type'] == 'sticky') {
      final content = node['content'] as String;
      final look = canvasStickyCardLook(
        colors,
        typo,
        node['color_key'] as String?,
        isEmpty: content.isEmpty,
      );
      final (:label, :body) = canvasStickyCardText(
        context,
        title: title,
        content: content,
      );
      final inner =
          width -
          CanvasStickyCardMetrics.paddingLeft -
          CanvasStickyCardMetrics.paddingRight;
      final labelText = text(
        label,
        look.labelStyle,
        maxWidth:
            inner -
            CanvasStickyCardMetrics.iconSize -
            CanvasStickyCardMetrics.iconGap,
        maxLines: 1,
        ellipsis: _ellipsis,
      );
      final row = math.max(
        CanvasStickyCardMetrics.iconSize,
        labelText.value.height,
      );
      nodes[id] = CanvasExportStickyFace(
        fill: look.paper,
        border: look.border,
        icon: look.icon,
        iconColor: look.iconColor,
        label: labelText.value,
        body: text(
          body,
          look.bodyStyle,
          maxWidth: inner,
          maxHeight:
              height -
              CanvasStickyCardMetrics.paddingTop -
              CanvasStickyCardMetrics.paddingBottom -
              row -
              CanvasStickyCardMetrics.bodyGap,
        ).value,
      );
      continue;
    }
    final refType = node['ref_type'] as String?;
    final invalid = invalidNodeIds.contains(id);
    final look = canvasReferenceCardLook(
      colors,
      typo,
      refType,
      isInvalid: invalid,
      colorValue: node['color_key'] as String?,
    );
    final (title: shown, :subtitle) = canvasReferenceCardText(
      context,
      title: title,
      refType: refType,
      isInvalid: invalid,
      scene: refType == canvasNodeRefTypeScreenplayScene
          ? scenes[node['ref_id']]
          : null,
    );
    final column =
        width -
        CanvasReferenceCardMetrics.paddingX * 2 -
        CanvasReferenceCardMetrics.chipSize -
        CanvasReferenceCardMetrics.chipGap;
    nodes[id] = CanvasExportReferenceFace(
      fill: look.fill,
      border: look.border,
      chipFill: look.chipFill,
      chipBorder: look.chipBorder,
      icon: look.icon,
      iconColor: look.iconColor,
      title: text(
        shown,
        look.titleStyle,
        maxWidth: column,
        maxLines: CanvasReferenceCardMetrics.titleMaxLines,
        ellipsis: _ellipsis,
      ).value,
      subtitle: text(
        subtitle,
        look.subtitleStyle,
        maxWidth: column,
        maxLines: 1,
        ellipsis: _ellipsis,
      ).value,
    );
  }

  final edges = <String, CanvasExportEdgeFace>{};
  for (final edge in snapshot.edges) {
    final type = edge['type'] as String;
    final label = edge['label'] as String;
    final laid = label.isEmpty
        ? null
        : text(
            label,
            labelTheme.textStyle,
            maxWidth: labelTheme.maxWidth,
            maxLines: labelTheme.maxLines,
            ellipsis: _labelEllipsis,
            align: TextAlign.center,
          );
    edges[edge['id'] as String] = CanvasExportEdgeFace(
      color: canvasEdgeColor(colors, type),
      dash: canvasEdgeDashPattern(type),
      label: laid?.value,
      labelWidth: laid?.width ?? 0,
    );
  }

  final icons = <String, String>{
    for (final face in nodes.values)
      switch (face) {
        CanvasExportReferenceFace(:final icon) => icon,
        CanvasExportStickyFace(:final icon) => icon,
      }: '',
  };
  for (final key in icons.keys.toList()) {
    icons[key] = await rootBundle.loadString(key);
  }

  return CanvasExportPreview(
    background: flowTheme.backgroundColor,
    strokeWidth: flowTheme.connectionTheme.strokeWidth,
    labelBackground: labelTheme.backgroundColor ?? flowTheme.backgroundColor,
    labelRadius: labelTheme.borderRadius.topLeft.x,
    labelPaddingX: labelTheme.padding.left,
    labelPaddingY: labelTheme.padding.top,
    shadows: [
      for (final shadow in canvasNodeShadows(colors))
        CanvasExportShadow(
          color: shadow.color,
          blur: shadow.blurRadius,
          offset: shadow.offset,
        ),
    ],
    icons: icons,
    nodes: nodes,
    edges: edges,
  );
}

typedef _Text = ({CanvasExportText value, double width});

/// 用与 [Text] 相同的 [TextPainter] 排版，逐行取出实际显示的文字。
///
/// 超出 [maxLines] 时末行按省略号重新截断；给了 [maxHeight] 时只保留顶部落在
/// 可用高度内的行（画布用 fade 截断，SVG 再按区域裁切）。
_Text _layoutText(
  String value,
  TextStyle style, {
  required TextScaler scaler,
  required double maxWidth,
  int? maxLines,
  String? ellipsis,
  double? maxHeight,
  TextAlign align = TextAlign.start,
}) {
  final width = math.max(0.0, maxWidth);
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: TextDirection.ltr,
    textAlign: align,
    textScaler: scaler,
    maxLines: maxLines,
    ellipsis: ellipsis,
  )..layout(maxWidth: width);
  final metrics = painter.computeLineMetrics();
  final lines = <String>[];
  for (final line in metrics) {
    if (maxHeight != null && line.baseline - line.ascent >= maxHeight) {
      break;
    }
    final range = painter.getLineBoundary(
      painter.getPositionForOffset(Offset(line.left, line.baseline)),
    );
    lines.add(
      range.textInside(value).replaceAll('\n', '').replaceAll('\r', ''),
    );
  }
  if (painter.didExceedMaxLines && ellipsis != null && lines.isNotEmpty) {
    var runes = lines.last.runes.toList();
    double measure(String text) => (TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout()).width;
    while (runes.isNotEmpty &&
        measure('${String.fromCharCodes(runes)}$ellipsis') > width) {
      runes = runes.sublist(0, runes.length - 1);
    }
    lines[lines.length - 1] =
        '${String.fromCharCodes(runes).trimRight()}'
        '$ellipsis';
  }
  final first = metrics.isEmpty ? null : metrics.first;
  final fontSize = scaler.scale(style.fontSize ?? 14);
  return (
    value: CanvasExportText(
      lines: lines,
      style: CanvasExportTextStyle(
        fontFamily: [
          ?style.fontFamily,
          ...?style.fontFamilyFallback,
        ].join(', '),
        fontSize: fontSize,
        fontWeight: style.fontWeight?.value ?? 400,
        color: style.color ?? Colors.black,
        lineHeight: first?.height ?? fontSize,
        ascent: first?.baseline ?? fontSize,
        letterSpacing: style.letterSpacing ?? 0,
        lineThroughColor:
            style.decoration?.contains(TextDecoration.lineThrough) ?? false
            ? style.decorationColor ?? style.color
            : null,
      ),
    ),
    width: painter.width,
  );
}
