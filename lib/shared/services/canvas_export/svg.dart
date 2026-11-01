// 职责: 以快照几何绘制静态 SVG，并把节点、连接曲线和多行标签纳入包围盒。
//       连线直接取画布同一条管线算出的路径段（见 canvas_connection_path.dart）；
//       卡片、连线颜色与文字取主 isolate 按画布主题预先解析的 [CanvasExportPreview]，
//       卡片内的摆位按画布卡片共用的几何 token。
// 关联文件:
//   lib/shared/models/canvas_export.dart
//   lib/shared/models/canvas_export_preview.dart
//   lib/shared/theme/canvas_card_metrics.dart
//   lib/desktop/features/canvas/export_preview.dart
//   lib/shared/models/canvas_connection_path.dart
//   lib/shared/models/canvas_tree_layout.dart
//   lib/shared/services/canvas_export/format.dart
//   lib/desktop/features/canvas/widgets/canvas_flow_adapter.dart

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:xml/xml.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/connections/styles/path_segments.dart';
import '../../../third/flow/vyuh_node_flow.dart' as flow;
import '../../models/canvas_connection_path.dart';
import '../../models/canvas_export.dart';
import '../../models/canvas_export_preview.dart';
import '../../models/canvas_layout.dart';
import '../../models/canvas_tree_layout.dart';
import '../../theme/canvas_card_metrics.dart';

String _safe(String text) => String.fromCharCodes(
  text.runes.map(
    (r) =>
        r == 9 ||
            r == 10 ||
            r == 13 ||
            (r >= 32 && r <= 0xD7FF) ||
            (r >= 0xE000 && r <= 0xFFFD) ||
            (r >= 0x10000 && r <= 0x10FFFF)
        ? r
        : 0xFFFD,
  ),
);
Rect _rect(CanvasExportObject node) => Rect.fromLTWH(
  (node['x'] as num).toDouble(),
  (node['y'] as num).toDouble(),
  (node['width'] as num).toDouble(),
  (node['height'] as num).toDouble(),
);
Offset _cubic(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final u = 1 - t;
  return p0 * (u * u * u) +
      p1 * (3 * u * u * t) +
      p2 * (3 * u * t * t) +
      p3 * (t * t * t);
}

/// 路径的折线采样，用于包围盒与按长度取中点（画布的中心标签落在路径长度一半处）。
List<Offset> _sample(CanvasConnectionPath path) {
  final points = [path.start];
  var from = path.start;
  for (final segment in path.segments) {
    switch (segment) {
      case StraightSegment():
        points.add(segment.end);
      case QuadraticSegment(:final controlPoint, :final end):
        for (var i = 1; i <= 8; i++) {
          final t = i / 8;
          points.add(
            Offset.lerp(
              Offset.lerp(from, controlPoint, t)!,
              Offset.lerp(controlPoint, end, t)!,
              t,
            )!,
          );
        }
      case CubicSegment(:final controlPoint1, :final controlPoint2, :final end):
        for (var i = 1; i <= 24; i++) {
          points.add(_cubic(from, controlPoint1, controlPoint2, end, i / 24));
        }
    }
    from = segment.end;
  }
  return points;
}

Offset _midpoint(List<Offset> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += (points[i] - points[i - 1]).distance;
  }
  var remaining = total / 2;
  for (var i = 1; i < points.length; i++) {
    final step = (points[i] - points[i - 1]).distance;
    if (step >= remaining && step > 0) {
      return Offset.lerp(points[i - 1], points[i], remaining / step)!;
    }
    remaining -= step;
  }
  return points.last;
}

String _pathData(CanvasConnectionPath path) => [
  'M ${path.start.dx} ${path.start.dy}',
  for (final segment in path.segments)
    switch (segment) {
      StraightSegment(:final end) => 'L ${end.dx} ${end.dy}',
      QuadraticSegment(:final controlPoint, :final end) =>
        'Q ${controlPoint.dx} ${controlPoint.dy}, ${end.dx} ${end.dy}',
      CubicSegment(:final controlPoint1, :final controlPoint2, :final end) =>
        'C ${controlPoint1.dx} ${controlPoint1.dy}, ${controlPoint2.dx} ${controlPoint2.dy}, ${end.dx} ${end.dy}',
    },
].join(' ');

/// 画布的终点箭头：以 [center] 为中心、尖端朝目标节点内侧的三角形，尖端在前。
List<Offset> _arrow(Offset center, flow.PortPosition port) {
  final inward = switch (port) {
    flow.PortPosition.left => const Offset(1, 0),
    flow.PortPosition.right => const Offset(-1, 0),
    flow.PortPosition.top => const Offset(0, 1),
    flow.PortPosition.bottom => const Offset(0, -1),
  };
  final normal = Offset(-inward.dy, inward.dx);
  final half = canvasConnectionArrowSize.width / 2;
  return [
    center + inward * half,
    center - inward * half + normal * half,
    center - inward * half - normal * half,
  ];
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String _opacity(Color color) => '${(color.a * 1000).round() / 1000}';

Map<String, String> _fill(Color color) => {
  'fill': _hex(color),
  if (color.a < 1) 'fill-opacity': _opacity(color),
};

Map<String, String> _stroke(Color color) => {
  'stroke': _hex(color),
  if (color.a < 1) 'stroke-opacity': _opacity(color),
};

/// 与 Flutter 的 BoxShadow.convertRadiusToSigma 一致。
double _sigma(double blur) => blur > 0 ? blur * 0.57735 + 0.5 : 0;

String canvasExportSvg(
  CanvasExportSnapshot snapshot,
  CanvasExportPreview preview,
) {
  if (snapshot.hasErrors) {
    throw const CanvasExportException('invalid_snapshot');
  }
  final nodes = {for (final node in snapshot.nodes) node['id'] as String: node};
  Rect? bounds;
  void include(Rect rect) {
    bounds = bounds?.expandToInclude(rect) ?? rect;
  }

  for (final node in nodes.values) {
    include(_rect(node));
  }
  final layout =
      (snapshot.json['canvas'] as CanvasExportObject)['layout'] as String?;
  final waypoints = resolveCanvasTreeEdgeWaypoints(
    nodes: [
      for (final node in nodes.values)
        CanvasArrangeNode(
          id: node['id'] as String,
          sortOrder: node['sort_order'] as int,
          size: _rect(node).size,
          position: _rect(node).topLeft,
        ),
    ],
    edges: [
      for (final edge in snapshot.edges)
        CanvasArrangeEdge(
          sourceNodeId: edge['source_node_id'] as String,
          targetNodeId: edge['target_node_id'] as String,
          type: edge['type'] as String,
        ),
    ],
    layout: layout,
  );
  final lines = <(CanvasExportEdgeFace, CanvasConnectionPath, Rect?)>[];
  for (final edge in snapshot.edges) {
    final source = edge['source_node_id'] as String,
        target = edge['target_node_id'] as String;
    final face = preview.edges[edge['id']]!;
    final curve = canvasConnectionPath(
      source: _rect(nodes[source]!),
      target: _rect(nodes[target]!),
      directed: edge['directed'] == true,
      layout: layout,
      waypoints: waypoints[(source, target)],
    );
    final points = _sample(curve);
    final label = face.label == null
        ? null
        : Rect.fromCenter(
            center: _midpoint(points),
            width: face.labelWidth + preview.labelPaddingX * 2,
            height: face.label!.height + preview.labelPaddingY * 2,
          );
    for (final point in [
      ...points,
      if (curve.arrow case final arrow?) ...[arrow.center],
    ]) {
      include(Rect.fromCircle(center: point, radius: 10));
    }
    if (label != null) {
      include(label);
    }
    lines.add((face, curve, label));
  }
  final view = (bounds ?? const Rect.fromLTWH(0, 0, 1, 1)).inflate(48);
  final xml = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8"');

  void text(
    CanvasExportText block,
    double x,
    double top, {
    String anchor = 'start',
  }) {
    final style = block.style;
    for (final (index, line) in block.lines.indexed) {
      xml.element(
        'text',
        attributes: {
          'x': '$x',
          'y': '${top + style.ascent + index * style.lineHeight}',
          ..._fill(style.color),
          'font-size': '${style.fontSize}',
          'font-weight': '${style.fontWeight}',
          'font-family': [
            if (style.fontFamily case final family? when family.isNotEmpty)
              family,
            'system-ui',
            'sans-serif',
          ].join(', '),
          if (style.letterSpacing != 0)
            'letter-spacing': '${style.letterSpacing}',
          if (style.lineThroughColor != null) 'text-decoration': 'line-through',
          if (anchor != 'start') 'text-anchor': anchor,
          'xml:space': 'preserve',
        },
        nest: () => xml.text(_safe(line)),
      );
    }
  }

  // 图标整段内联成嵌套 svg：预览不含任何 href，离线打开与安全扫描都不依赖引用。
  final iconSources = {
    for (final MapEntry(:key, :value) in preview.icons.entries)
      key: XmlDocument.parse(value).rootElement,
  };
  void icon(String key, Color color, double x, double y, double size) {
    final source = iconSources[key]!;
    xml.element(
      'svg',
      attributes: {
        'x': '$x',
        'y': '$y',
        'width': '$size',
        'height': '$size',
        'viewBox': source.getAttribute('viewBox') ?? '0 0 256 256',
        'color': _hex(color),
        if (color.a < 1) 'opacity': _opacity(color),
      },
      nest: () {
        for (final child in source.childElements) {
          xml.xml(child.toXmlString());
        }
      },
    );
  }

  /// Flutter 的 Border 画在盒内；SVG 描边居中，内缩半个线宽对齐。
  void box(
    Rect rect,
    double radius,
    Color fill,
    Color? border, {
    bool shadow = false,
  }) {
    final inner = border == null ? rect : rect.deflate(0.5);
    xml.element(
      'rect',
      attributes: {
        'x': '${inner.left}',
        'y': '${inner.top}',
        'width': '${inner.width}',
        'height': '${inner.height}',
        'rx': '$radius',
        ..._fill(fill),
        if (border != null) ..._stroke(border),
        if (shadow && preview.shadows.isNotEmpty) 'filter': 'url(#card-shadow)',
      },
    );
  }

  xml.element(
    'svg',
    attributes: {
      'xmlns': 'http://www.w3.org/2000/svg',
      'viewBox': '${view.left} ${view.top} ${view.width} ${view.height}',
      'width': '${view.width}',
      'height': '${view.height}',
    },
    nest: () {
      xml.element('title', nest: () => xml.text(_safe(snapshot.title)));
      xml.element(
        'defs',
        nest: () {
          if (preview.shadows.isNotEmpty) {
            xml.element(
              'filter',
              attributes: {
                'id': 'card-shadow',
                'x': '-20%',
                'y': '-20%',
                'width': '140%',
                'height': '140%',
              },
              nest: () {
                for (final shadow in preview.shadows) {
                  xml.element(
                    'feDropShadow',
                    attributes: {
                      'dx': '${shadow.offset.dx}',
                      'dy': '${shadow.offset.dy}',
                      'stdDeviation': '${_sigma(shadow.blur)}',
                      'flood-color': _hex(shadow.color),
                      'flood-opacity': _opacity(shadow.color),
                    },
                  );
                }
              },
            );
          }
        },
      );
      box(view, 0, preview.background, null);
      for (final (face, curve, _) in lines) {
        xml.element(
          'path',
          attributes: {
            'd': _pathData(curve),
            'fill': 'none',
            ..._stroke(face.color),
            'stroke-width': '${preview.strokeWidth}',
            if (face.dash case final dash?) 'stroke-dasharray': dash.join(' '),
          },
        );
        if (curve.arrow case final arrow?) {
          final [tip, left, right] = _arrow(arrow.center, arrow.port);
          xml.element(
            'path',
            attributes: {
              'd':
                  'M ${tip.dx} ${tip.dy} L ${left.dx} ${left.dy} L ${right.dx} ${right.dy} Z',
              ..._fill(face.color),
            },
          );
        }
      }
      for (final node in snapshot.nodes) {
        final rect = _rect(node);
        final face = preview.nodes[node['id']]!;
        xml.element(
          'g',
          nest: () {
            xml.element(
              'title',
              nest: () => xml.text(_safe(node['title'] as String)),
            );
            switch (face) {
              case CanvasExportReferenceFace():
                _referenceCard(face, rect, box, icon, text);
              case CanvasExportStickyFace():
                _stickyCard(
                  xml,
                  node['id'] as String,
                  face,
                  rect,
                  box,
                  icon,
                  text,
                );
            }
          },
        );
      }
      for (final (face, _, label) in lines) {
        if (label == null) {
          continue;
        }
        box(label, preview.labelRadius, preview.labelBackground, null);
        text(
          face.label!,
          label.center.dx,
          label.top + preview.labelPaddingY,
          anchor: 'middle',
        );
      }
    },
  );
  return '${xml.buildDocument().toXmlString()}\n';
}

typedef _Box =
    void Function(
      Rect rect,
      double radius,
      Color fill,
      Color? border, {
      bool shadow,
    });
typedef _Icon =
    void Function(String key, Color color, double x, double y, double size);
typedef _TextBlock =
    void Function(
      CanvasExportText block,
      double x,
      double top, {
      String anchor,
    });

/// 同 CanvasReferenceNodeCard：chip 与文字列都在卡片内垂直居中。
void _referenceCard(
  CanvasExportReferenceFace face,
  Rect rect,
  _Box box,
  _Icon icon,
  _TextBlock text,
) {
  box(
    rect,
    CanvasReferenceCardMetrics.radius,
    face.fill,
    face.border,
    shadow: true,
  );
  final chip = Rect.fromLTWH(
    rect.left + CanvasReferenceCardMetrics.paddingX,
    rect.center.dy - CanvasReferenceCardMetrics.chipSize / 2,
    CanvasReferenceCardMetrics.chipSize,
    CanvasReferenceCardMetrics.chipSize,
  );
  box(
    chip,
    CanvasReferenceCardMetrics.chipRadius,
    face.chipFill,
    face.chipBorder,
  );
  icon(
    face.icon,
    face.iconColor,
    chip.center.dx - CanvasReferenceCardMetrics.iconSize / 2,
    chip.center.dy - CanvasReferenceCardMetrics.iconSize / 2,
    CanvasReferenceCardMetrics.iconSize,
  );
  final left = chip.right + CanvasReferenceCardMetrics.chipGap;
  final top = rect.center.dy - (face.title.height + face.subtitle.height) / 2;
  text(face.title, left, top);
  text(face.subtitle, left, top + face.title.height);
}

/// 同 CanvasStickyNodeCard：图标 + 标签行，其下正文吃掉剩余高度，超出部分裁掉。
void _stickyCard(
  XmlBuilder xml,
  String id,
  CanvasExportStickyFace face,
  Rect rect,
  _Box box,
  _Icon icon,
  _TextBlock text,
) {
  box(
    rect,
    CanvasStickyCardMetrics.radius,
    face.fill,
    face.border,
    shadow: true,
  );
  final left = rect.left + CanvasStickyCardMetrics.paddingLeft;
  final top = rect.top + CanvasStickyCardMetrics.paddingTop;
  final row = math.max(CanvasStickyCardMetrics.iconSize, face.label.height);
  icon(
    face.icon,
    face.iconColor,
    left,
    top + (row - CanvasStickyCardMetrics.iconSize) / 2,
    CanvasStickyCardMetrics.iconSize,
  );
  text(
    face.label,
    left + CanvasStickyCardMetrics.iconSize + CanvasStickyCardMetrics.iconGap,
    top + (row - face.label.height) / 2,
  );
  final body = Rect.fromLTRB(
    left,
    top + row + CanvasStickyCardMetrics.bodyGap,
    rect.right - CanvasStickyCardMetrics.paddingRight,
    rect.bottom - CanvasStickyCardMetrics.paddingBottom,
  );
  if (body.height <= 0) {
    return;
  }
  final clip = 'clip-${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';
  xml.element(
    'clipPath',
    attributes: {'id': clip},
    nest: () => xml.element(
      'rect',
      attributes: {
        'x': '${body.left}',
        'y': '${body.top}',
        'width': '${body.width}',
        'height': '${body.height}',
      },
    ),
  );
  xml.element(
    'g',
    attributes: {'clip-path': 'url(#$clip)'},
    nest: () => text(face.body, body.left, body.top),
  );
}
