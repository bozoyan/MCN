// 职责: 图片地图画布 — 地图缩放平移与透明地点命中区
// 关联文件:
//   lib/shared/models/map_studio_models.dart
//   lib/desktop/features/map/map_studio_page.dart
//   lib/shared/database/novel_content_database.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/performance.md
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../database/novel_content_database.dart';
import '../../theme/theme.dart';
import '../../models/map_studio_models.dart';

/// 把逻辑画布按比例缩进当前视口；不放大小于视口的图片。
@visibleForTesting
Size fitImageMapCanvasSize({
  required Size viewport,
  required Size logicalCanvas,
}) {
  if (viewport.width <= 0 ||
      viewport.height <= 0 ||
      !viewport.width.isFinite ||
      !viewport.height.isFinite ||
      logicalCanvas.width <= 0 ||
      logicalCanvas.height <= 0) {
    return logicalCanvas;
  }
  final scale = math.min(
    1.0,
    math.min(
      viewport.width / logicalCanvas.width,
      viewport.height / logicalCanvas.height,
    ),
  );
  return Size(logicalCanvas.width * scale, logicalCanvas.height * scale);
}

/// DB 中的逻辑画布坐标投影到当前缩放后的展示坐标。
@visibleForTesting
Offset projectImageMapCanvasPosition({
  required Offset position,
  required Size logicalCanvas,
  required Size displaySize,
}) {
  return Offset(
    position.dx / logicalCanvas.width * displaySize.width,
    position.dy / logicalCanvas.height * displaySize.height,
  );
}

/// 桌面鼠标的命中区边长。
const double imageMapDefaultTargetSize = 32;

/// 地点透明命中区在当前画布缩放下的布局矩形，视口尺寸固定为 [targetSize]。
@visibleForTesting
Rect imageMapLocationTargetRect({
  required Offset position,
  required double scale,
  double targetSize = imageMapDefaultTargetSize,
}) {
  final inverse = scale > 0 ? 1 / scale : 1.0;
  return Rect.fromLTWH(
    position.dx - targetSize * inverse / 2,
    position.dy - targetSize * inverse / 2,
    targetSize * inverse,
    targetSize * inverse,
  );
}

@visibleForTesting
({double diameter, double opacity}) imageMapSelectionPulse(
  double progress, {
  bool animationsDisabled = false,
}) {
  if (animationsDisabled) {
    return (diameter: 22, opacity: 0.68);
  }
  final normalized = progress.clamp(0.0, 1.0);
  final breath = (1 - math.cos(normalized * math.pi * 2)) / 2;
  return (diameter: 22 + breath * 10, opacity: 0.68 - breath * 0.52);
}

class ImageMapCanvas extends HookWidget {
  const ImageMapCanvas({
    super.key,
    required this.map,
    required this.settings,
    required this.imageBytes,
    required this.mapLocations,
    required this.locationById,
    required this.selectedLocationId,
    this.hoveredLocationId,
    required this.onSelectionChanged,
    this.onHoverLocation,
    this.targetSize = imageMapDefaultTargetSize,
  });

  final NovelMap map;
  final MapStudioSettings settings;
  final Uint8List? imageBytes;
  final List<MapLocation> mapLocations;
  final Map<String, Location> locationById;
  final String? selectedLocationId;
  final String? hoveredLocationId;
  final ValueChanged<String?> onSelectionChanged;

  /// 触屏没有 hover，移动端不传。
  final ValueChanged<String?>? onHoverLocation;

  /// 地点命中区的视口边长；触屏用 44 保证手指点得中。
  final double targetSize;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final transformation = useMemoized(
      () => TransformationController(),
      const [],
    );
    final currentScale = useValueListenable(transformation).getMaxScaleOnAxis();
    final bytes = imageBytes;
    if (bytes == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalCanvas = Size(map.width, map.height);
        final displaySize = fitImageMapCanvasSize(
          viewport: constraints.biggest,
          logicalCanvas: logicalCanvas,
        );
        return InteractiveViewer(
          transformationController: transformation,
          boundaryMargin: const EdgeInsets.all(240),
          minScale: 0.5,
          maxScale: 4,
          panEnabled: true,
          scaleEnabled: true,
          child: Center(
            child: MouseRegion(
              onExit: (_) => onHoverLocation?.call(null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelectionChanged(null),
                child: SizedBox(
                  width: displaySize.width,
                  height: displaySize.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                      for (final row in mapLocations)
                        if (!settings.unmatchedLocationIds.contains(
                              row.locationId,
                            ) &&
                            locationById[row.locationId] != null)
                          _LocationTarget(
                            key: ValueKey('map-location-${row.id}'),
                            row: row,
                            location: locationById[row.locationId]!,
                            logicalCanvasSize: logicalCanvas,
                            displaySize: displaySize,
                            selected: selectedLocationId == row.locationId,
                            hovered: hoveredLocationId == row.locationId,
                            scale: currentScale,
                            targetSize: targetSize,
                            colors: colors,
                            onSelect: () => onSelectionChanged(row.locationId),
                            onHover: onHoverLocation,
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 固定视口尺寸的透明命中区。静止时不绘制，hover 显示细环，选中显示呼吸圆环。
class _LocationTarget extends StatelessWidget {
  const _LocationTarget({
    super.key,
    required this.row,
    required this.location,
    required this.logicalCanvasSize,
    required this.displaySize,
    required this.selected,
    required this.hovered,
    required this.scale,
    required this.targetSize,
    required this.colors,
    required this.onSelect,
    required this.onHover,
  });

  final MapLocation row;
  final Location location;
  final Size logicalCanvasSize;
  final Size displaySize;
  final bool selected;
  final bool hovered;
  final double scale;
  final double targetSize;
  final RevericColors colors;
  final VoidCallback onSelect;
  final ValueChanged<String?>? onHover;

  @override
  Widget build(BuildContext context) {
    // 命中区不随画布缩放变大，避免放大后覆盖邻近地名。
    final inverse = scale > 0 ? 1 / scale : 1.0;
    final position = projectImageMapCanvasPosition(
      position: Offset(row.x, row.y),
      logicalCanvas: logicalCanvasSize,
      displaySize: displaySize,
    );
    final targetRect = imageMapLocationTargetRect(
      position: position,
      scale: scale,
      targetSize: targetSize,
    );
    return Positioned(
      left: targetRect.left,
      top: targetRect.top,
      child: Transform.scale(
        scale: inverse,
        alignment: Alignment.topLeft,
        child: Semantics(
          label: location.name,
          button: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => onHover?.call(row.locationId),
            onExit: (_) => onHover?.call(null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSelect,
              child: SizedBox.square(
                dimension: targetSize,
                child: Center(
                  child: selected
                      ? _SelectedLocationMarker(colors: colors)
                      : hovered
                      ? _HoveredLocationMarker(colors: colors)
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedLocationMarker extends HookWidget {
  const _SelectedLocationMarker({required this.colors});

  final RevericColors colors;

  @override
  Widget build(BuildContext context) {
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final pulse = useAnimationController(
      duration: const Duration(milliseconds: 1400),
    );
    useEffect(() {
      if (animationsDisabled) {
        pulse.stop();
        pulse.value = 0;
        return null;
      }
      pulse.repeat();
      return pulse.stop;
    }, [animationsDisabled]);
    final pulseStyle = imageMapSelectionPulse(
      useAnimation(pulse),
      animationsDisabled: animationsDisabled,
    );

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: pulseStyle.diameter,
              height: pulseStyle.diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.accent.withValues(alpha: pulseStyle.opacity),
                  width: 2,
                ),
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent.withValues(alpha: 0.08),
                border: Border.all(color: colors.surface, width: 3),
              ),
            ),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.accent, width: 2),
              ),
            ),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoveredLocationMarker extends StatelessWidget {
  const _HoveredLocationMarker({required this.colors});

  final RevericColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.surface, width: 2),
            ),
          ),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
