// 职责: 用球面经纬线、源图与位置标记示意当前机位或光源方位。
// 关联文件:
//   lib/desktop/features/production/view/panel.dart
//   lib/shared/models/production/view_presets.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../shared/models/production/view_presets.dart';
import '../../../../shared/theme/theme.dart';

class ProductionSpherePreview extends StatelessWidget {
  const ProductionSpherePreview({
    super.key,
    required this.preset,
    required this.args,
    this.imagePath,
  });
  final ViewPreset preset;
  final ViewPresetArgs args;
  final String? imagePath;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final (yaw, pitch) = preset == ViewPreset.camera
        ? (args.yaw.toDouble(), args.pitch.toDouble())
        : switch (args.direction) {
            LightDirection.left => (-90.0, 0.0),
            LightDirection.right => (90.0, 0.0),
            LightDirection.top => (0.0, 80.0),
            LightDirection.bottom => (0.0, -80.0),
            LightDirection.front => (0.0, 0.0),
            LightDirection.back => (180.0, 0.0),
          };
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        foregroundPainter: _Sphere(
          yaw,
          pitch,
          colors.border,
          colors.accent,
          drawGrid: false,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _Sphere(yaw, pitch, colors.border, colors.accent),
              ),
            ),
            FractionallySizedBox(
              widthFactor: .28,
              heightFactor: .36,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(RevericRadius.medium),
                child: imagePath == null
                    ? RevericIcon(RevericIcons.image, color: colors.textMuted)
                    : Image.file(
                        File(imagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => RevericIcon(
                          RevericIcons.image,
                          color: colors.textMuted,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sphere extends CustomPainter {
  const _Sphere(
    this.yaw,
    this.pitch,
    this.grid,
    this.accent, {
    this.drawGrid = true,
  });
  final bool drawGrid;
  final double yaw, pitch;
  final Color grid, accent;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * .43;
    final paint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (drawGrid) {
      canvas.drawCircle(center, radius, paint);
      for (final factor in [.25, .6, 1.0]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: radius * 2 * factor,
            height: radius * 2,
          ),
          paint,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: radius * 2,
            height: radius * .65 * factor,
          ),
          paint,
        );
      }
    }
    final a = yaw * math.pi / 180;
    final p = pitch * math.pi / 180;
    final marker =
        center +
        Offset(
          math.sin(a) * math.cos(p) * radius,
          -math.sin(p) * radius + math.cos(a) * math.cos(p) * radius * .32,
        );
    canvas.drawLine(
      center,
      marker,
      paint
        ..color = accent
        ..strokeWidth = 2,
    );
    canvas.drawCircle(marker, 7, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_Sphere old) =>
      drawGrid != old.drawGrid ||
      yaw != old.yaw ||
      pitch != old.pitch ||
      grid != old.grid ||
      accent != old.accent;
}
