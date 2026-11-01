// 职责: 实体关系图边绘制 — 曲线多边、方向箭头、高亮边标签与碰撞避让。
// 关联文件:
//   lib/shared/entity_graph/constants.dart
//   lib/shared/entity_graph/layout.dart
//   lib/shared/entity_graph/models.dart
//   lib/shared/entity_graph/graph_widget.dart

import 'dart:math';

import 'package:flutter/material.dart';

import 'layout.dart';
import 'models.dart';

class EntityGraphEdgePainter extends CustomPainter {
  EntityGraphEdgePainter({
    required this.edges,
    required this.positions,
    required this.offset,
    required this.showLabels,
    required this.showDirection,
    required this.highlightedNodeKey,
    required this.labelBgColor,
    required this.includeNodeLabels,
  });

  final List<EntityEdgeData> edges;
  final Map<String, Offset> positions;
  final Offset offset;
  final bool showLabels;
  final bool showDirection;
  final String? highlightedNodeKey;
  final Color labelBgColor;
  final bool includeNodeLabels;

  static const double _multiEdgeCurvatureStep = 56.0;

  @override
  void paint(Canvas canvas, Size size) {
    final edgesByPair = <String, int>{};
    for (final edge in edges) {
      final pairKey = _pairKey(edge.sourceKey, edge.targetKey);
      edgesByPair[pairKey] = (edgesByPair[pairKey] ?? 0) + 1;
    }

    final pairIndex = <String, int>{};
    final occupiedLabelRects = <Rect>[];

    for (final edge in edges) {
      final srcPos = positions[edge.sourceKey];
      final tgtPos = positions[edge.targetKey];
      if (srcPos == null || tgtPos == null) {
        continue;
      }

      final src = srcPos + offset;
      final tgt = tgtPos + offset;

      final pairKey = _pairKey(edge.sourceKey, edge.targetKey);
      final count = edgesByPair[pairKey] ?? 1;
      final idx = pairIndex[pairKey] ?? 0;
      pairIndex[pairKey] = idx + 1;

      final touchesHighlight =
          highlightedNodeKey == null ||
          edge.sourceKey == highlightedNodeKey ||
          edge.targetKey == highlightedNodeKey;
      final dimmed = !touchesHighlight;
      final edgeAlpha = dimmed ? 0.12 : 1.0;

      final paint = Paint()
        ..color = edge.color.withValues(alpha: edgeAlpha)
        ..strokeWidth = touchesHighlight ? 2.4 : 1.6
        ..style = PaintingStyle.stroke;

      final curvature = count > 1
          ? (idx - (count - 1) / 2) * _multiEdgeCurvatureStep
          : 0.0;
      final clipRadius = entityGraphNodeClipRadius(
        includeLabels: includeNodeLabels,
      );

      _drawEdge(canvas, src, tgt, paint, curvature, clipRadius);

      if (showDirection && edge.directed) {
        _drawArrow(
          canvas,
          src,
          tgt,
          edge.color.withValues(alpha: edgeAlpha),
          curvature,
          clipRadius,
        );
      }

      final shouldDrawLabel = showLabels && edge.label.isNotEmpty && !dimmed;

      if (shouldDrawLabel) {
        _drawLabel(
          canvas,
          src,
          tgt,
          edge.label,
          edge.color,
          curvature,
          occupiedLabelRects,
        );
      }
    }
  }

  String _pairKey(String a, String b) {
    return a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
  }

  void _drawEdge(
    Canvas canvas,
    Offset src,
    Offset tgt,
    Paint paint,
    double curvature,
    double clipRadius,
  ) {
    final srcClipped = _clipToCircle(src, tgt, clipRadius);
    final tgtClipped = _clipToCircle(tgt, src, clipRadius);

    if (curvature.abs() < 1.0) {
      canvas.drawLine(srcClipped, tgtClipped, paint);
    } else {
      final mid = (srcClipped + tgtClipped) / 2;
      final dx = tgtClipped.dx - srcClipped.dx;
      final dy = tgtClipped.dy - srcClipped.dy;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1.0) {
        return;
      }
      final nx = -dy / len;
      final ny = dx / len;
      final ctrl = Offset(mid.dx + nx * curvature, mid.dy + ny * curvature);

      final path = Path()
        ..moveTo(srcClipped.dx, srcClipped.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, tgtClipped.dx, tgtClipped.dy);
      canvas.drawPath(path, paint);
    }
  }

  void _drawArrow(
    Canvas canvas,
    Offset src,
    Offset tgt,
    Color color,
    double curvature,
    double clipRadius,
  ) {
    final tgtClipped = _clipToCircle(tgt, src, clipRadius);
    final srcClipped = _clipToCircle(src, tgt, clipRadius);

    Offset direction;
    if (curvature.abs() < 1.0) {
      direction = tgtClipped - srcClipped;
    } else {
      final mid = (srcClipped + tgtClipped) / 2;
      final dx = tgtClipped.dx - srcClipped.dx;
      final dy = tgtClipped.dy - srcClipped.dy;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1.0) {
        return;
      }
      final nx = -dy / len;
      final ny = dx / len;
      final ctrl = Offset(mid.dx + nx * curvature, mid.dy + ny * curvature);
      direction = tgtClipped - ctrl;
    }

    final len = sqrt(direction.dx * direction.dx + direction.dy * direction.dy);
    if (len < 1.0) {
      return;
    }
    final unit = Offset(direction.dx / len, direction.dy / len);

    const arrowLen = 8.0;
    const arrowAngle = 0.5;
    final p1 = Offset(
      tgtClipped.dx - arrowLen * cos(atan2(unit.dy, unit.dx) - arrowAngle),
      tgtClipped.dy - arrowLen * sin(atan2(unit.dy, unit.dx) - arrowAngle),
    );
    final p2 = Offset(
      tgtClipped.dx - arrowLen * cos(atan2(unit.dy, unit.dx) + arrowAngle),
      tgtClipped.dy - arrowLen * sin(atan2(unit.dy, unit.dx) + arrowAngle),
    );

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final arrowPath = Path()
      ..moveTo(tgtClipped.dx, tgtClipped.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);
  }

  void _drawLabel(
    Canvas canvas,
    Offset src,
    Offset tgt,
    String label,
    Color color,
    double curvature,
    List<Rect> occupiedLabelRects,
  ) {
    final mid = (src + tgt) / 2;
    Offset labelPos;
    if (curvature.abs() < 1.0) {
      labelPos = mid;
    } else {
      final dx = tgt.dx - src.dx;
      final dy = tgt.dy - src.dy;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1.0) {
        return;
      }
      final nx = -dy / len;
      final ny = dx / len;
      labelPos = Offset(
        mid.dx + nx * curvature * 0.55,
        mid.dy + ny * curvature * 0.55,
      );
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    var bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: labelPos,
        width: textPainter.width + 8,
        height: textPainter.height + 4,
      ),
      const Radius.circular(4),
    );

    for (var attempt = 0; attempt < 6; attempt++) {
      final rect = bgRect.outerRect;
      final collides = occupiedLabelRects.any((r) => r.overlaps(rect));
      if (!collides) {
        break;
      }
      final dx = tgt.dx - src.dx;
      final dy = tgt.dy - src.dy;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1.0) {
        break;
      }
      final nx = -dy / len;
      final ny = dx / len;
      final shift = (attempt + 1) * 12.0;
      labelPos = Offset(labelPos.dx + nx * shift, labelPos.dy + ny * shift);
      bgRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: labelPos,
          width: textPainter.width + 8,
          height: textPainter.height + 4,
        ),
        const Radius.circular(4),
      );
    }

    occupiedLabelRects.add(bgRect.outerRect.inflate(2));

    canvas.drawRRect(
      bgRect,
      Paint()..color = labelBgColor.withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    textPainter.paint(
      canvas,
      Offset(
        labelPos.dx - textPainter.width / 2,
        labelPos.dy - textPainter.height / 2,
      ),
    );
  }

  Offset _clipToCircle(Offset center, Offset other, double radius) {
    final dx = other.dx - center.dx;
    final dy = other.dy - center.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 1.0) {
      return center;
    }
    return Offset(center.dx + dx / len * radius, center.dy + dy / len * radius);
  }

  @override
  bool shouldRepaint(EntityGraphEdgePainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.positions != positions ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.showDirection != showDirection ||
        oldDelegate.highlightedNodeKey != highlightedNodeKey ||
        oldDelegate.includeNodeLabels != includeNodeLabels;
  }
}
