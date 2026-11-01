// 职责: 画布 AI 跟随镜头决策 — 按焦点/内容/可视区几何算出「要不要动镜头、动到哪」
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/shared/models/canvas_ai_activity.dart

import 'dart:math' as math;
import 'dart:ui';

/// 焦点被认为「已经看得见」时,离可视区边缘至少要留的比例。
///
/// 贴着视口边缘的节点技术上可见,但用户扫视时几乎注意不到,还容易被左下角的
/// 工具簇压住 —— 所以判定用内缩后的安全区,而不是整个可视区。
const double _safeInsetRatio = 0.08;

/// 认为「当前缩放足够看清、不必动镜头」的区间。
///
/// 下限 0.35:六列的时间线在典型画布区里 fit 出来就是 0.4 上下,门槛再高会让
/// 每次新增节点都重新适配一次,反而更晃;
/// 上限 1.6:再大就只剩两三张卡片,AI 在别处加的东西完全落在视野外。
const double _readableZoomMin = 0.35;
const double _readableZoomMax = 1.6;

/// 看全图时的留白与缩放上限。上限压在 1.2 是为了避免节点很少时镜头怼到脸上。
const double _overviewPadding = 64;
const double _overviewMaxZoom = 1.2;

/// 全图 fit 后的缩放低于这个值(约十列以上)才说明图真的太大,改为局部跟随。
///
/// 用户点「适配视图」得到的就是这个 fit 值,所以门槛不该比手动适配更挑剔 ——
/// 定高了会让「内容变多自动缩小」几乎不触发。
const double _overviewMinZoom = 0.35;

/// 局部跟随:焦点四周额外展开的画布距离(约半格),让相邻节点也进画面,
/// 用户才知道 AI 把新节点接到了哪里。
const double _focusInflate = 160;
const double _focusPadding = 48;
const double _focusZoomMin = 0.6;
const double _focusZoomMax = 1.1;

/// 内容整个都在安全区内时,只有还能明显放大(适配缩放是当前的这么多倍)才值得
/// 重新适配 —— 否则「收尾」会在用户眼皮底下做一次毫无意义的微调。
const double _refitZoomGain = 1.6;

/// 镜头决策结果。
sealed class CanvasCameraCommand {
  const CanvasCameraCommand();
}

/// 保持不动 —— 用户视角里画布是稳的，这是默认答案。
class CanvasCameraHold extends CanvasCameraCommand {
  const CanvasCameraHold();
}

/// 把 [center] 移到屏幕中心并缩放到 [zoom]。
class CanvasCameraMove extends CanvasCameraCommand {
  const CanvasCameraMove({required this.center, required this.zoom});

  /// 目标中心(画布坐标)。
  final Offset center;

  /// 目标缩放(已按 min/max 夹紧)。
  final double zoom;

  @override
  bool operator ==(Object other) =>
      other is CanvasCameraMove &&
      other.center == center &&
      (other.zoom - zoom).abs() < 1e-6;

  @override
  int get hashCode => Object.hash(center, zoom);

  @override
  String toString() => 'CanvasCameraMove(center: $center, zoom: $zoom)';
}

/// 决定 AI 编辑画布后镜头怎么动。
///
/// 判定顺序(先出结果者胜):
/// 1. 一轮活动收尾(或本次操作没有焦点,如删除/整理布局)→ 只有内容跑出安全区、
///    或视口空得能明显放大时才重新适配;全图大到适配后看不清时保持不动,
///    不在收尾时把画面缩成一片。
/// 1'. 传入 [lockedZoom](一轮跟随里缩放已经定下)→ 焦点在安全区内不动,
///    否则以锁定缩放平移到焦点。一轮里只平移不缩放,画面不会忽大忽小。
/// 2. 焦点已在安全区内且缩放可读 → 不动。**这条是「别晃镜头」的闸门**:AI 连着
///    在同一片区域加节点时,镜头应该是静止的。
/// 3. 全图还能以可读的缩放装下 → 直接给全貌。节点变多时缩放自然变小,
///    「UI 自动适应数据」由这条实现。
/// 4. 图已经大到装不下 → 退化成局部跟随,把焦点连同周边一格拉进画面。
///
/// [visibleBounds] / [contentBounds] 均为画布坐标;[focusBounds] 是本轮 AI 触碰
/// 节点的并集,删除类操作传 null。
CanvasCameraCommand decideCanvasCamera({
  required Size screenSize,
  required double currentZoom,
  required Rect visibleBounds,
  required Rect contentBounds,
  required bool settled,
  required double minZoom,
  required double maxZoom,
  Rect? focusBounds,
  double? lockedZoom,
}) {
  if (screenSize.isEmpty || contentBounds.isEmpty || visibleBounds.isEmpty) {
    return const CanvasCameraHold();
  }

  final overviewZoom = _clamp(
    _fitZoom(contentBounds, screenSize, _overviewPadding),
    minZoom,
    math.min(maxZoom, _overviewMaxZoom),
  );
  final safeArea = _deflateByRatio(visibleBounds, _safeInsetRatio);

  if (settled || focusBounds == null || focusBounds.isEmpty) {
    if (_fitZoom(contentBounds, screenSize, _overviewPadding) <
        _overviewMinZoom) {
      return const CanvasCameraHold();
    }
    final contentVisible = _contains(safeArea, contentBounds);
    if (contentVisible && overviewZoom <= currentZoom * _refitZoomGain) {
      return const CanvasCameraHold();
    }
    return CanvasCameraMove(center: contentBounds.center, zoom: overviewZoom);
  }

  final focusVisible = _contains(safeArea, focusBounds);
  if (lockedZoom != null) {
    if (focusVisible) {
      return const CanvasCameraHold();
    }
    final zoom = _clamp(lockedZoom, minZoom, maxZoom);
    final view = visibleBounds.center;
    return CanvasCameraMove(
      center: Offset(
        _leadAxis(
          view: view.dx,
          focusMin: focusBounds.left,
          focusMax: focusBounds.right,
          safeMin: safeArea.left,
          safeMax: safeArea.right,
          half: screenSize.width / zoom / 2,
        ),
        _leadAxis(
          view: view.dy,
          focusMin: focusBounds.top,
          focusMax: focusBounds.bottom,
          safeMin: safeArea.top,
          safeMax: safeArea.bottom,
          half: screenSize.height / zoom / 2,
        ),
      ),
      zoom: zoom,
    );
  }
  if (focusVisible &&
      currentZoom >= _readableZoomMin &&
      currentZoom <= _readableZoomMax) {
    return const CanvasCameraHold();
  }

  if (_fitZoom(contentBounds, screenSize, _overviewPadding) >=
      _overviewMinZoom) {
    return CanvasCameraMove(center: contentBounds.center, zoom: overviewZoom);
  }

  final focusRect = focusBounds.inflate(_focusInflate);
  final focusZoom = _clamp(
    _fitZoom(focusRect, screenSize, _focusPadding),
    math.max(minZoom, _focusZoomMin),
    math.min(maxZoom, _focusZoomMax),
  );
  return CanvasCameraMove(center: focusRect.center, zoom: focusZoom);
}

/// 新连线的镜头焦点:任一端点已经和可视区重叠就返回 null(不动镜头),
/// 否则只取终点。
///
/// 连线自己会生长,本身就是高亮;两端常常一个在时间线上、一个在角落的便签或
/// 人物卡上,拿两端的包围盒取景几乎每条线都要大幅平移,镜头来回乱跑。
/// [endpoints] 按「起点, 终点」顺序给出。
Rect? canvasEdgeFocus({
  required Rect visibleBounds,
  required List<Rect> endpoints,
}) {
  if (endpoints.isEmpty) {
    return null;
  }
  if (endpoints.any(visibleBounds.overlaps)) {
    return null;
  }
  return endpoints.last;
}

/// 把 [bounds] 连同 [padding] 留白装进 [screenSize] 所需的缩放。
double _fitZoom(Rect bounds, Size screenSize, double padding) {
  final availableWidth = screenSize.width - padding * 2;
  final availableHeight = screenSize.height - padding * 2;
  if (availableWidth <= 0 || availableHeight <= 0) {
    return 1;
  }
  return math.min(
    availableWidth / bounds.width,
    availableHeight / bounds.height,
  );
}

Rect _deflateByRatio(Rect rect, double ratio) {
  return Rect.fromLTRB(
    rect.left + rect.width * ratio,
    rect.top + rect.height * ratio,
    rect.right - rect.width * ratio,
    rect.bottom - rect.height * ratio,
  );
}

/// [outer] 是否完整包住 [inner](含边界,与 Rect.contains 的半开区间不同)。
bool _contains(Rect outer, Rect inner) {
  return inner.left >= outer.left &&
      inner.top >= outer.top &&
      inner.right <= outer.right &&
      inner.bottom <= outer.bottom;
}

/// 锁定缩放平移时,焦点停在离画面中心「半屏 × 该比例」处,背对前进方向。
///
/// 正中对焦的话,下一个相邻节点刚好又出安全区,几乎每个节点都要平移一次;
/// 给前进方向留出空间,一次平移能接住后面好几个节点。
const double _leadRatio = 0.4;

/// 单轴的平移目标:焦点在这一轴上没出安全区就不动,出了就带前进留白追过去。
double _leadAxis({
  required double view,
  required double focusMin,
  required double focusMax,
  required double safeMin,
  required double safeMax,
  required double half,
}) {
  if (focusMin >= safeMin && focusMax <= safeMax) {
    return view;
  }
  final focusCenter = (focusMin + focusMax) / 2;
  final focusHalf = (focusMax - focusMin) / 2;
  // 留白不能把焦点自己推出安全区。
  final lead = math.max(
    0.0,
    math.min(half * _leadRatio, half * (1 - _safeInsetRatio * 2) - focusHalf),
  );
  return focusCenter > view ? focusCenter + lead : focusCenter - lead;
}

/// 一轮跟随锁定的缩放上限：卡片标题仍清晰可读，
/// 画面里能并排放下三到四个节点，看得出结构。
const double _followZoomMax = 0.62;

/// 一轮跟随锁定的缩放：夹在「看得清」与 [_followZoomMax] 之间。
///
/// 首拍往往只有一个节点，全貌缩放会顶到 1.2；原样锁住，整轮都怼在单张卡片上，
/// 几乎每个新节点都要平移一次，收尾也只停在一角。用户自己缩得很小时也不原样锁，
/// 否则整轮都看不清。
double canvasFollowZoomFor(double zoom) {
  return _clamp(zoom, _readableZoomMin, _followZoomMax);
}

double _clamp(double value, double min, double max) {
  if (max < min) {
    return min;
  }
  return value.clamp(min, max);
}
