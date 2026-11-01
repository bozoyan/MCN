// 职责: 解析与写回制作画布分组的 style.group，并算出卡片尺寸、分镜组格位坐标、外框和普通组重排。
// 关联文件:
//   lib/shared/services/production/group_service.dart
//   lib/shared/models/production/settings.dart
//   lib/desktop/features/production/node_card.dart
import 'dart:math' as math;
import 'dart:ui';

import 'settings.dart';

/// 画面卡片的长边；1:1 用略小的边长。短边不低于 [_minShortEdge]，空态的两个入口才放得下。
const double _longEdge = 260;
const double _squareEdge = 220;
const double _minShortEdge = 132;

/// 节点的类型与名称画在卡片外的左上方，占用卡片上沿之上的这段高度。
const double productionCardHeaderExtent = 22;

/// 「16:9」这类比例串的宽高比；解析不了时为 null。
double? productionAspect(String? ratio) {
  final parts = (ratio ?? '').split(':').map(double.tryParse).toList();
  if (parts.length != 2 || parts.any((p) => p == null || p <= 0)) {
    return null;
  }
  return parts[0]! / parts[1]!;
}

/// 画面卡片按宽高比的渲染尺寸。
Size productionCardSize(double aspect) {
  if ((aspect - 1).abs() < .01) {
    return const Size.square(_squareEdge);
  }
  return aspect > 1
      ? Size(_longEdge, math.max(_minShortEdge, _longEdge / aspect))
      : Size(math.max(_minShortEdge, _longEdge * aspect), _longEdge);
}

/// [ProductionSettings.ratios] 中最接近 [aspect] 的比例（按对数距离）。
String productionNearestRatio(double aspect) {
  final target = math.log(aspect);
  return ProductionSettings.ratios.reduce(
    (a, b) =>
        (math.log(productionAspect(a)!) - target).abs() <=
            (math.log(productionAspect(b)!) - target).abs()
        ? a
        : b,
  );
}

/// 分组节点 `style.group` 的布局；分镜组与普通组只差这一个键，转换不改节点 id、成员和连线。
sealed class ProductionGroupLayout {
  const ProductionGroupLayout();
  static const styleKey = 'group';

  /// 缺失时按普通组处理；取值非法时抛 [FormatException]。
  static ProductionGroupLayout fromStyle(Map<String, dynamic>? style) {
    final value = style?[styleKey];
    if (value == null) {
      return const FreeGroupLayout();
    }
    final map = value as Map;
    switch (map['layout']) {
      case 'free':
        return const FreeGroupLayout();
      case 'storyboard':
        final layout = StoryboardGroupLayout(
          cols: map['cols'] as int,
          rows: map['rows'] as int,
          ratio: map['ratio'] as String,
          numbered: map['numbered'] as bool? ?? false,
        );
        layout.validate();
        return layout;
    }
    throw const FormatException('Unsupported group layout');
  }

  Map<String, dynamic> toJson();

  /// 只改写 group 键，保留 style 里的其他键。
  Map<String, dynamic> writeTo(Map<String, dynamic>? style) => {
    ...?style,
    styleKey: toJson(),
  };
}

/// 分镜组：成员按格位紧凑平铺，格位下标即成员 sort_order。
final class StoryboardGroupLayout extends ProductionGroupLayout {
  const StoryboardGroupLayout({
    required this.cols,
    required this.rows,
    this.ratio = '16:9',
    this.numbered = false,
  });

  /// 能放下 [count] 格的最小方阵，如 3 → 2×2、7 → 3×3。
  factory StoryboardGroupLayout.fitting(int count, {required String ratio}) {
    final side = math.max(1, math.sqrt(count).ceil());
    final layout = StoryboardGroupLayout(cols: side, rows: side, ratio: ratio);
    layout.validate();
    return layout;
  }

  static const maxSide = 5;

  /// 格子之间的间隙。
  static const double gap = 2;

  final int cols, rows;
  final String ratio;
  final bool numbered;
  int get capacity => cols * rows;

  void validate() {
    if (cols < 1 ||
        rows < 1 ||
        cols > maxSide ||
        rows > maxSide ||
        !ProductionSettings.ratios.contains(ratio)) {
      throw const FormatException('Invalid storyboard group layout');
    }
  }

  /// 与同比例的普通图片卡片一样大。
  Size get cellSize => productionCardSize(productionAspect(ratio)!);

  Size get frameSize => Size(
    cols * cellSize.width + (cols - 1) * gap,
    rows * cellSize.height + (rows - 1) * gap,
  );

  /// 格位 [index] 的行列，均从 0 起。
  ({int row, int col}) cell(int index) =>
      (row: index ~/ cols, col: index % cols);

  /// 格位左上角相对外框左上角的偏移。
  Offset cellOffset(int index) {
    final at = cell(index);
    return Offset(
      at.col * (cellSize.width + gap),
      at.row * (cellSize.height + gap),
    );
  }

  StoryboardGroupLayout copyWith({
    int? cols,
    int? rows,
    String? ratio,
    bool? numbered,
  }) => StoryboardGroupLayout(
    cols: cols ?? this.cols,
    rows: rows ?? this.rows,
    ratio: ratio ?? this.ratio,
    numbered: numbered ?? this.numbered,
  );

  @override
  Map<String, dynamic> toJson() {
    validate();
    return {
      'layout': 'storyboard',
      'cols': cols,
      'rows': rows,
      'ratio': ratio,
      'numbered': numbered,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is StoryboardGroupLayout &&
      cols == other.cols &&
      rows == other.rows &&
      ratio == other.ratio &&
      numbered == other.numbered;

  @override
  int get hashCode => Object.hash(cols, rows, ratio, numbered);
}

/// 普通组：成员按各自尺寸、各自位置显示，外框可手动调整。
final class FreeGroupLayout extends ProductionGroupLayout {
  const FreeGroupLayout();

  /// 外框比成员（含卡片外标题）外接矩形多出的边距。
  static const double padding = 24;

  /// 转普通组时成员之间的卡片间距。
  static const double spacing = 40;

  @override
  Map<String, dynamic> toJson() => {'layout': 'free'};

  @override
  bool operator ==(Object other) => other is FreeGroupLayout;

  @override
  int get hashCode => 0;
}

/// 普通组外框至少要包住的范围：成员卡片连同其外标题，再加边距。
Rect freeGroupMinFrame(Iterable<Rect> members) {
  Rect? bounds;
  for (final member in members) {
    final withHeader = Rect.fromLTRB(
      member.left,
      member.top - productionCardHeaderExtent,
      member.right,
      member.bottom,
    );
    bounds = bounds == null ? withHeader : bounds.expandToInclude(withHeader);
  }
  return bounds?.inflate(FreeGroupLayout.padding) ?? Rect.zero;
}

/// 转普通组：按顺序排成 [cols] 列，每列取该列最宽成员、每行取该行最高成员。
/// 外框左上角保持 [origin]，返回各成员左上角（画布坐标）与外框。
({List<Offset> positions, Rect frame}) arrangeFreeGroup(
  Offset origin,
  List<Size> sizes,
  int cols,
) {
  if (sizes.isEmpty) {
    return (positions: const [], frame: origin & Size.zero);
  }
  final columns = math.max(1, math.min(cols, sizes.length));
  final rows = (sizes.length / columns).ceil();
  final widths = List<double>.filled(columns, 0);
  final heights = List<double>.filled(rows, 0);
  for (var i = 0; i < sizes.length; i++) {
    widths[i % columns] = math.max(widths[i % columns], sizes[i].width);
    heights[i ~/ columns] = math.max(heights[i ~/ columns], sizes[i].height);
  }
  const rowGap = FreeGroupLayout.spacing + productionCardHeaderExtent;
  final start = origin.translate(
    FreeGroupLayout.padding,
    FreeGroupLayout.padding + productionCardHeaderExtent,
  );
  final positions = <Offset>[];
  for (var i = 0; i < sizes.length; i++) {
    final col = i % columns, row = i ~/ columns;
    var x = start.dx, y = start.dy;
    for (var c = 0; c < col; c++) {
      x += widths[c] + FreeGroupLayout.spacing;
    }
    for (var r = 0; r < row; r++) {
      y += heights[r] + rowGap;
    }
    positions.add(Offset(x, y));
  }
  return (
    positions: positions,
    frame: freeGroupMinFrame([
      for (var i = 0; i < sizes.length; i++) positions[i] & sizes[i],
    ]),
  );
}

/// 「先行后列」排序：上沿相差不到半个最矮成员高度的算同一行，行内按左沿。
List<String> readingOrder(Map<String, Rect> rects) {
  if (rects.isEmpty) {
    return const [];
  }
  final tolerance = rects.values.map((r) => r.height).reduce(math.min) / 2;
  final byTop = rects.keys.toList()
    ..sort((a, b) => rects[a]!.top.compareTo(rects[b]!.top));
  final rows = <List<String>>[];
  for (final id in byTop) {
    final row = rows.lastOrNull;
    if (row != null && rects[id]!.top - rects[row.first]!.top < tolerance) {
      row.add(id);
    } else {
      rows.add([id]);
    }
  }
  return [
    for (final row in rows)
      ...(row..sort((a, b) => rects[a]!.left.compareTo(rects[b]!.left))),
  ];
}
