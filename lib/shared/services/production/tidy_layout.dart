// 职责: 计算制作画布「整理画布」的落点：参考在左、各场按成片顺序各占一列、产物贴在来源场次右侧，无连线的单位在下方网格排开。
// 关联文件:
//   lib/shared/services/production/derived_placement.dart
//   lib/desktop/features/production/board.dart

import 'dart:math' as math;
import 'dart:ui';
import '../../models/production/group_layout.dart';
import '../../theme/theme.dart';
import 'derived_placement.dart';

/// 相邻两层之间的距离；一层连向下一层的线可能很多，要留出让连线散开的空间。
const double productionTidyLayerGap = 240;

/// 同一列里上下两个单位、折列后相邻两列、网格里相邻单位之间的空隙。
const double _gap = RevericSpacing.x6l;

/// 两个连通块之间、连线区与下方网格之间的空隙。
const double _blockGap = 160;

/// 并排的两场色带之间的空隙。
const double _sceneGap = 96;

/// [nodes] 是画布上所有节点当前的卡片矩形（渲染坐标，不含卡片外的标题）；
/// [sceneOf]、[groupOf] 与 [productionDerivedPlacement] 相同，场次和分组各作为一个整体移动。
/// [sceneOrder] 是场次 id 的成片顺序。
/// [scope] 选中了两个以上单位时只整理它们，否则整理整张画布；整理后的左上角对齐原来的左上角。
///
/// 有连线的单位按连通块自上而下排；块内按连线方向分列（输入在左），同列按上一列的连线位置排序。
/// 所有场次归入同一块、落在同一层，每场单独一列按成片顺序从左往右并排，参考在它们左边。
/// 只来自一场的产物（尾帧、音频等）贴在这一场右侧，下一场顺延；来自多场的产物排在所有场次右边。
/// 同一层单位太多时折成几列，有场次时不高过最高的一场。
/// 没有连线的单位按原来的先后在下方逐行排开。返回需要移动的节点及新位置。
Map<String, Offset> productionTidyLayout({
  required Map<String, Rect> nodes,
  required Map<String, String> sceneOf,
  Map<String, String> groupOf = const {},
  required Iterable<(String, String)> edges,
  List<String> sceneOrder = const [],
  Set<String> scope = const {},
}) {
  final members = <String, List<String>>{};
  String unitOf(String id) => groupOf[id] != null
      ? 'group/${groupOf[id]}'
      : sceneOf[id] == null
      ? 'node/$id'
      : 'scene/${sceneOf[id]}';
  for (final id in nodes.keys) {
    (members[unitOf(id)] ??= []).add(id);
  }
  final rects = <String, Rect>{
    for (final MapEntry(key: unit, value: ids) in members.entries)
      unit: _unitRect(
        unit,
        ids.map((id) => nodes[id]!).reduce((a, b) => a.expandToInclude(b)),
      ),
  };
  final scoped = {
    for (final id in scope)
      if (nodes.containsKey(id)) unitOf(id),
  };
  final units = scoped.length > 1 ? scoped : rects.keys.toSet();
  if (units.isEmpty) {
    return const {};
  }
  final origin = units
      .map((unit) => rects[unit]!.topLeft)
      .reduce((a, b) => Offset(math.min(a.dx, b.dx), math.min(a.dy, b.dy)));
  int byPlace(String a, String b) {
    final byY = rects[a]!.top.compareTo(rects[b]!.top);
    return byY != 0 ? byY : rects[a]!.left.compareTo(rects[b]!.left);
  }

  bool isScene(String unit) => unit.startsWith('scene/');
  final scenes = units.where(isScene).toSet();
  int sceneIndex(String unit) {
    final index = sceneOrder.indexOf(unit.substring('scene/'.length));
    return index < 0 ? sceneOrder.length : index;
  }

  final next = <String, Set<String>>{};
  final prev = <String, Set<String>>{};
  for (final (source, target) in edges) {
    if (!nodes.containsKey(source) || !nodes.containsKey(target)) {
      continue;
    }
    final from = unitOf(source);
    final to = unitOf(target);
    if (from == to || !units.contains(from) || !units.contains(to)) {
      continue;
    }
    (next[from] ??= {}).add(to);
    (prev[to] ??= {}).add(from);
  }

  // 连通块按块内最靠上的单位排序；没有连线的场次也和其他场并在一起。
  final seen = <String>{};
  final blocks = <List<String>>[];
  for (final start in units
      .where(next.containsKey)
      .followedBy(units.where(prev.containsKey))
      .followedBy(scenes)) {
    if (!seen.add(start)) {
      continue;
    }
    final block = <String>[start];
    for (var i = 0; i < block.length; i++) {
      for (final other in {
        ...?next[block[i]],
        ...?prev[block[i]],
        if (isScene(block[i])) ...scenes,
      }) {
        if (seen.add(other)) {
          block.add(other);
        }
      }
    }
    blocks.add(block..sort(byPlace));
  }
  blocks.sort((a, b) => byPlace(a.first, b.first));

  final targets = <String, Offset>{};
  var top = origin.dy;
  var width = 0.0;
  for (final block in blocks) {
    final (:column, :sceneColumn) = _columns(block, next, prev, isScene);
    final owner = _owners(block, column, prev, isScene);
    final sceneHeights = block
        .where(isScene)
        .map((unit) => rects[unit]!.height);
    final sceneHeight = sceneHeights.isEmpty
        ? null
        : sceneHeights.reduce(math.max);
    var bottom = top;

    // 从 x 起竖着排一列，按已排好的上游中心排序以减少交叉；太高就折成几列。返回占用宽度。
    double stack(List<String> units, double x) {
      double key(String unit) {
        final placed = [
          for (final from in prev[unit] ?? const <String>{})
            if (targets[from] case final at?) at.dy + rects[from]!.height / 2,
        ];
        return placed.isEmpty
            ? rects[unit]!.center.dy - rects[block.first]!.top + top
            : placed.reduce((a, b) => a + b) / placed.length;
      }

      final keys = {for (final unit in units) unit: key(unit)};
      units.sort((a, b) {
        final byKey = keys[a]!.compareTo(keys[b]!);
        return byKey != 0 ? byKey : byPlace(a, b);
      });
      // 有场次时不高过最高的一场，否则按总面积排成接近方形。
      final limit = math.max(
        units.map((unit) => rects[unit]!.height).reduce(math.max),
        sceneHeight ??
            math.sqrt(
              units
                  .map((unit) => rects[unit]!.width * rects[unit]!.height)
                  .reduce((a, b) => a + b),
            ),
      );
      final left = x;
      var y = top;
      var columnWidth = 0.0;
      for (final unit in units) {
        final rect = rects[unit]!;
        if (y > top && y + rect.height - top > limit) {
          x += columnWidth + _gap;
          y = top;
          columnWidth = 0;
        }
        targets[unit] = Offset(x, y);
        y += rect.height + _gap;
        bottom = math.max(bottom, y - _gap);
        columnWidth = math.max(columnWidth, rect.width);
      }
      return x + columnWidth - left;
    }

    // 只来自某一场的产物按列分组，排在这一场右侧。
    final attached = <String, Map<int, List<String>>>{};
    for (final unit in block) {
      if (owner[unit] case final scene?) {
        ((attached[scene] ??= {})[column[unit]!] ??= []).add(unit);
      }
    }
    final layers = <int, List<String>>{};
    for (final unit in block) {
      if (!owner.containsKey(unit)) {
        (layers[column[unit]!] ??= []).add(unit);
      }
    }

    var x = origin.dx;
    for (final index in layers.keys.toList()..sort()) {
      final layer = layers[index]!;
      final rest = layer.where((unit) => !isScene(unit)).toList();
      if (index == sceneColumn) {
        final sceneUnits = layer.where(isScene).toList()
          ..sort((a, b) {
            final byOrder = sceneIndex(a).compareTo(sceneIndex(b));
            return byOrder != 0 ? byOrder : byPlace(a, b);
          });
        for (final (i, scene) in sceneUnits.indexed) {
          if (i > 0) {
            x += _sceneGap;
          }
          targets[scene] = Offset(x, top);
          bottom = math.max(bottom, top + rects[scene]!.height);
          x += rects[scene]!.width;
          final outputs = attached[scene] ?? const <int, List<String>>{};
          for (final output in outputs.keys.toList()..sort()) {
            x += productionDerivedGap;
            x += stack(outputs[output]!, x);
          }
        }
        if (rest.isNotEmpty) {
          x += _sceneGap;
        }
      }
      if (rest.isNotEmpty) {
        x += stack(rest, x);
      }
      x += productionTidyLayerGap;
    }
    width = math.max(width, x - productionTidyLayerGap - origin.dx);
    top = bottom + _blockGap;
  }

  final loose = units.where((unit) => !seen.contains(unit)).toList()
    ..sort(byPlace);
  if (loose.isNotEmpty) {
    final area = loose
        .map((unit) => rects[unit]!.width * rects[unit]!.height)
        .reduce((a, b) => a + b);
    final rowWidth = math.max(width, math.sqrt(area) * 2);
    var x = origin.dx;
    var rowHeight = 0.0;
    for (final unit in loose) {
      final rect = rects[unit]!;
      if (x > origin.dx && x + rect.width - origin.dx > rowWidth) {
        x = origin.dx;
        top += rowHeight + _gap;
        rowHeight = 0;
      }
      targets[unit] = Offset(x, top);
      x += rect.width + _gap;
      rowHeight = math.max(rowHeight, rect.height);
    }
  }

  return {
    for (final MapEntry(key: unit, value: at) in targets.entries)
      if (at != rects[unit]!.topLeft)
        for (final id in members[unit]!)
          id: nodes[id]!.topLeft + (at - rects[unit]!.topLeft),
  };
}

/// 场次按色带算，其余向上带出卡片标题。
Rect _unitRect(String unit, Rect cards) => unit.startsWith('scene/')
    ? productionSceneBand(cards)
    : Rect.fromLTRB(
        cards.left,
        cards.top - productionCardHeaderExtent,
        cards.right,
        cards.bottom,
      );

/// 按连线方向分列：每个单位落在所有上游的右边一列。环路里先处理原位置最靠上的单位，
/// 指回它的连线不再参与分列。
///
/// 场次全部落在同一列 [sceneColumn]：场次自己的产物和别的场次连进场次的线不参与分列，
/// 否则用上一场尾帧做参考的场次会被挤到右边一层。
({Map<String, int> column, int? sceneColumn}) _columns(
  List<String> block,
  Map<String, Set<String>> next,
  Map<String, Set<String>> prev,
  bool Function(String unit) isScene,
) {
  final downstream = <String>{};
  final queue = [...block.where(isScene)];
  while (queue.isNotEmpty) {
    for (final to in next[queue.removeLast()] ?? const <String>{}) {
      if (!isScene(to) && downstream.add(to)) {
        queue.add(to);
      }
    }
  }
  Set<String> inputs(String unit) => {
    for (final from in prev[unit] ?? const <String>{})
      if (!isScene(unit) || (!isScene(from) && !downstream.contains(from)))
        from,
  };

  Map<String, int> assign(int sceneColumn) {
    final pending = {for (final unit in block) unit: inputs(unit).length};
    final column = <String, int>{};
    final ready = [
      for (final unit in block)
        if (pending[unit] == 0) unit,
    ];
    while (column.length < block.length) {
      if (ready.isEmpty) {
        // block 已按原位置排好，第一个未处理的就是最靠上的；环路断在这里。
        ready.add(block.firstWhere((unit) => !column.containsKey(unit)));
      }
      final unit = ready.removeAt(0);
      if (column.containsKey(unit)) {
        continue;
      }
      column[unit] = [
        if (isScene(unit)) sceneColumn,
        for (final from in inputs(unit))
          if (column[from] case final at?) at + 1,
      ].fold(0, math.max);
      for (final to in next[unit] ?? const <String>{}) {
        if (inputs(to).contains(unit)) {
          pending[to] = pending[to]! - 1;
          if (pending[to] == 0) {
            ready.add(to);
          }
        }
      }
    }
    return column;
  }

  var column = assign(0);
  if (!block.any(isScene)) {
    return (column: column, sceneColumn: null);
  }
  final sceneColumn = block
      .where(isScene)
      .map((unit) => column[unit]!)
      .reduce(math.max);
  if (sceneColumn > 0) {
    column = assign(sceneColumn);
  }
  return (column: column, sceneColumn: sceneColumn);
}

/// 场次右侧单位的归属：上游只有一场（直接或经由同一场的其他产物）时归这一场，
/// 来自多场或接着别的共享产物的不归属。场次左侧的参考不影响归属。
Map<String, String> _owners(
  List<String> block,
  Map<String, int> column,
  Map<String, Set<String>> prev,
  bool Function(String unit) isScene,
) {
  final sceneColumn = [
    for (final unit in block)
      if (isScene(unit)) column[unit]!,
  ].firstOrNull;
  if (sceneColumn == null) {
    return const {};
  }
  final owner = <String, String>{};
  final after =
      block
          .where((unit) => !isScene(unit) && column[unit]! > sceneColumn)
          .toList()
        ..sort((a, b) => column[a]!.compareTo(column[b]!));
  for (final unit in after) {
    final sources = <String?>{
      for (final from in prev[unit] ?? const <String>{})
        if (isScene(from))
          from
        else if (column[from]! > sceneColumn)
          owner[from],
    };
    if (sources.length == 1 && sources.single != null) {
      owner[unit] = sources.single!;
    }
  }
  return owner;
}
