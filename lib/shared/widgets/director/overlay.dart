// 职责: 在导演视角上投影绘制角色名、选中角色路径与关键帧、各机位视锥和注视连线。
// 关联文件:
//   lib/shared/widgets/director/viewport.dart
//   lib/shared/services/director/camera.dart
//   lib/shared/models/director/sampling.dart
import 'dart:math' as math;
import '../../models/director/rig.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as v;

import '../../models/director/document.dart';
import '../../models/director/sampling.dart';
import '../../services/director/camera.dart';
import '../../services/director/scene_builder.dart';
import '../../theme/theme.dart';

/// 某个机位在屏幕上的视锥：机身中心与远端四角。
class CameraGlyph {
  CameraGlyph(this.id, this.name, this.origin, this.corners, this.look);
  final String id, name;
  final Offset origin;
  final List<Offset> corners;
  final Offset? look;
}

/// 叠加层的投影结果；viewport 用它做机位点选。
class StageOverlay {
  StageOverlay({
    required DirectorDocument document,
    required FrameSample sample,
    required this.camera,
    required this.size,
    required this.selected,
    required this.frame,
  }) {
    final aspect = document.width / document.height;
    for (final entry in sample.cameras.entries) {
      final c = entry.value;
      final p = vec(c['position']), t = vec(c['target']);
      final forward = (t - p)..normalize();
      final right = forward.cross(vec(c['up']))..normalize();
      final up = right.cross(forward)..normalize();
      final half =
          (c['sensor_height_mm'] as num) / (2 * (c['focal_length_mm'] as num));
      const length = 1.1;
      final center = p + forward * length;
      final corners = <Offset>[];
      for (final (sx, sy) in [(-1, 1), (1, 1), (1, -1), (-1, -1)]) {
        final o = camera.worldToScreen(
          center +
              right * (sx * half * aspect * length) +
              up * (sy * half * length),
          size,
        );
        if (o != null) {
          corners.add(o);
        }
      }
      final origin = camera.worldToScreen(p, size);
      if (origin == null || corners.length < 4) {
        continue;
      }
      final look =
          entry.key == selected &&
              c['orientation_mode'] == 'look_at' &&
              c['camera_target']['type'] != 'point'
          ? camera.worldToScreen(t, size)
          : null;
      cameras.add(CameraGlyph(entry.key, c['name'], origin, corners, look));
    }
    for (final o in sample.objects.where(
      (o) => o['kind'] == 'actor' && o['visible'] == true,
    )) {
      final head = camera.worldToScreen(
        vec(boneWorldPoint(o, 'head', [0, 0.25, 0])),
        size,
      );
      if (head != null) {
        names.add((o['name'] as String, head, o['id'] == selected));
      }
    }
    final path = document.tracks
        .where((t) => t['target_id'] == selected && t['property'] == 'position')
        .firstOrNull;
    if (path != null && document.isCamera(selected) == false) {
      final keys = path['keys'] as List;
      final first = keys.first['frame'] as int,
          last = keys.last['frame'] as int;
      for (var f = first; f <= last; f += 2) {
        final p = camera.worldToScreen(
          vec(sampleTrack(path, f)) + v.Vector3(0, 0.02, 0),
          size,
        );
        if (p != null) {
          route.add(p);
        }
      }
      for (final k in keys) {
        final p = camera.worldToScreen(
          vec(k['value']) + v.Vector3(0, 0.02, 0),
          size,
        );
        if (p != null) {
          diamonds.add((p, k['frame'] as int));
        }
      }
    }
  }
  final DirectorCamera camera;
  final Size size;
  final String? selected;
  final int frame;
  final List<CameraGlyph> cameras = [];
  final List<(String, Offset, bool)> names = [];
  final List<Offset> route = [];
  final List<(Offset, int)> diamonds = [];

  /// 命中机位机身或视锥面，返回机位 id。
  String? hitCamera(Offset point, {double tolerance = 14}) {
    for (final c in cameras.reversed) {
      if ((c.origin - point).distance <= tolerance) {
        return c.id;
      }
      final path = Path()..addPolygon(c.corners, true);
      if (path.contains(point)) {
        return c.id;
      }
    }
    return null;
  }
}

class StageOverlayPainter extends CustomPainter {
  StageOverlayPainter(this.overlay, this.colors, this.label, this.fps);
  final StageOverlay overlay;
  final RevericColors colors;
  final TextStyle label;
  final int fps;

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    bool center = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: label.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center ? at - Offset(painter.width / 2, painter.height) : at,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    if (overlay.route.length > 1) {
      line.color = colors.accent.withValues(alpha: 0.8);
      final dash = Path()..addPolygon(overlay.route, false);
      for (final metric in dash.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 10) {
          canvas.drawPath(metric.extractPath(d, d + 6), line);
        }
      }
    }
    for (final (p, frame) in overlay.diamonds) {
      final diamond = Path()
        ..moveTo(p.dx, p.dy - 6)
        ..lineTo(p.dx + 6, p.dy)
        ..lineTo(p.dx, p.dy + 6)
        ..lineTo(p.dx - 6, p.dy)
        ..close();
      canvas.drawPath(
        diamond,
        Paint()
          ..color = colors.accent
          ..style = frame == overlay.frame
              ? PaintingStyle.fill
              : PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _text(
        canvas,
        '${(frame / fps).toStringAsFixed(1)}s',
        p + const Offset(10, 4),
        colors.textMuted,
      );
    }
    for (final c in overlay.cameras) {
      final on = c.id == overlay.selected;
      final color = on ? colors.accent : colors.textMuted;
      line
        ..color = color
        ..strokeWidth = on ? 1.5 : 1;
      for (final corner in c.corners) {
        canvas.drawLine(c.origin, corner, line);
      }
      canvas.drawPath(
        Path()..addPolygon(c.corners, true),
        Paint()..color = color.withValues(alpha: on ? 0.18 : 0.08),
      );
      canvas.drawPath(Path()..addPolygon(c.corners, true), line);
      if (c.look != null) {
        final dashLine = Paint()
          ..color = colors.accent
          ..strokeWidth = 1;
        final delta = c.look! - c.origin, length = delta.distance;
        for (var d = 0.0; d < length; d += 8) {
          canvas.drawLine(
            c.origin + delta * (d / length),
            c.origin + delta * (math.min(d + 4, length) / length),
            dashLine,
          );
        }
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c.origin, width: 18, height: 12),
          const Radius.circular(RevericRadius.small),
        ),
        Paint()..color = on ? colors.accent : colors.textSecondary,
      );
      _text(canvas, c.name, c.origin - const Offset(0, 9), color, center: true);
    }
    for (final (name, head, on) in overlay.names) {
      _text(
        canvas,
        name,
        head,
        on ? colors.accent : colors.textPrimary,
        center: true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StageOverlayPainter oldDelegate) => true;
}

/// 机位视角的画框：遮住画幅外区域并标注画幅、机位与时间。
class FramePainter extends CustomPainter {
  FramePainter(this.frame, this.colors, this.label, this.caption);
  final Rect frame;
  final RevericColors colors;
  final TextStyle label;
  final String caption;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..fillType = ui.PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(frame),
      Paint()..color = colors.canvas.withValues(alpha: 0.72),
    );
    canvas.drawRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = colors.accent.withValues(alpha: 0.7),
    );
    final painter = TextPainter(
      text: TextSpan(
        text: caption,
        style: label.copyWith(color: colors.textSecondary),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, frame.bottomLeft + Offset(8, -painter.height - 8));
  }

  @override
  bool shouldRepaint(covariant FramePainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.caption != caption;
}
