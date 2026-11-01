// 职责: Markdown 正文的分块视图 — 按空行把全文切成段落块，维护「块内位置 ↔ 全文偏移」映射与增量编辑
// 关联文件:
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/widgets/md/block/markdown_edit_patch_stack.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md

const int _lineFeed = 0x0A;
const int _carriageReturn = 0x0D;
const int _space = 0x20;
const int _tab = 0x09;

/// 一个段落块在全文中的位置。
///
/// `[start, end)` 是块正文，`[end, separatorEnd)` 是块后的空行分隔符。
/// 相邻块满足 `blocks[i].separatorEnd == blocks[i + 1].start`，因此所有块的区间
/// 连续覆盖 `[0, source.length)` —— 无损性由结构保证，而不是靠重新拼接。
class MarkdownBlock {
  const MarkdownBlock({
    required this.id,
    required this.start,
    required this.end,
    required this.separatorEnd,
  });

  /// 跨编辑稳定的标识：未受编辑影响的块保持同一个 id。
  ///
  /// 高度缓存与 `GlobalKey` 注册表必须以此为键——用数组下标会在块分裂 / 合并后
  /// 整体错位，把缓存挂到语义上完全不同的块上。
  final int id;
  final int start;
  final int end;
  final int separatorEnd;

  int get length => end - start;

  bool get isEmpty => end == start;

  String textIn(String source) => source.substring(start, end);

  MarkdownBlock shifted(int delta) {
    return MarkdownBlock(
      id: id,
      start: start + delta,
      end: end + delta,
      separatorEnd: separatorEnd + delta,
    );
  }

  @override
  String toString() => 'MarkdownBlock#$id($start, $end, $separatorEnd)';
}

/// 全文的分块快照。不可变：每次编辑返回新实例。
///
/// 块只存偏移不存字符串副本，48 万字符文档切出的 3555 个块因此只占几十 KB。
class MarkdownBlockDocument {
  MarkdownBlockDocument._(this.source, this.blocks, this._nextId);

  factory MarkdownBlockDocument.split(String source) {
    final blocks = _splitBlocks(source, 0, 0);
    return MarkdownBlockDocument._(source, blocks, blocks.length);
  }

  final String source;
  final List<MarkdownBlock> blocks;

  /// 下一个可分配的块 id。只有被重切的块会拿新 id，其余块 id 不变。
  final int _nextId;

  int get length => blocks.length;

  MarkdownBlock operator [](int index) => blocks[index];

  /// 全文偏移落在哪个块（含块后分隔符区间）。
  int blockIndexAt(int offset) {
    final target = offset.clamp(0, source.length);
    var low = 0;
    var high = blocks.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (target < blocks[mid].separatorEnd) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }

  /// 全文偏移 → (块索引, 块内偏移)。落在分隔符区间时夹到该块末尾。
  ({int block, int local}) locate(int offset) {
    final index = blockIndexAt(offset);
    final block = blocks[index];
    return (block: index, local: (offset - block.start).clamp(0, block.length));
  }

  /// (块索引, 块内偏移) → 全文偏移。
  int offsetOf(int blockIndex, int localOffset) {
    final block = blocks[blockIndex.clamp(0, blocks.length - 1)];
    return block.start + localOffset.clamp(0, block.length);
  }

  /// 用 [replacement] 替换第 [index] 块的正文（不动块后分隔符）。
  MarkdownBlockDocument replaceBlock(int index, String replacement) {
    final block = blocks[index];
    return replaceRange(block.start, block.end, replacement);
  }

  /// 通用编辑入口：块的分裂、合并、跨块删除都走这里。
  ///
  /// 只对受影响区间重新切块，其余块整体平移偏移，复杂度 O(块数) 而非 O(全文)。
  MarkdownBlockDocument replaceRange(int start, int end, String replacement) {
    final safeStart = start.clamp(0, source.length);
    final safeEnd = end.clamp(safeStart, source.length);
    final nextSource = source.replaceRange(safeStart, safeEnd, replacement);
    final delta = replacement.length - (safeEnd - safeStart);

    // 编辑起点之前的文本没动，前一块的分隔符不可能被破坏，不需要往前扩。
    final firstIndex = blockIndexAt(safeStart);
    // 编辑碰到了块后分隔符时，该块可能与下一块合并，区间必须覆盖到下一块。
    var lastIndex = blockIndexAt(safeEnd);
    if (safeEnd > blocks[lastIndex].end && lastIndex + 1 < blocks.length) {
      lastIndex += 1;
    }

    final regionStart = blocks[firstIndex].start;
    final regionEnd = (blocks[lastIndex].separatorEnd + delta).clamp(
      regionStart,
      nextSource.length,
    );
    final rebuilt = _splitBlocks(
      nextSource.substring(regionStart, regionEnd),
      regionStart,
      _nextId,
    );

    // 区间末尾正好是分隔符之后，切块必然多出一个空的尾块；
    // 该位置由后面保留的块占据，去掉以免区间重复覆盖。
    final hasFollowing = lastIndex + 1 < blocks.length;
    if (hasFollowing) {
      assert(
        rebuilt.last.isEmpty && rebuilt.last.start == regionEnd,
        '区间末尾应当落在分隔符之后，实际得到 ${rebuilt.last}',
      );
      rebuilt.removeLast();
    }

    final next = <MarkdownBlock>[
      for (var i = 0; i < firstIndex; i++) blocks[i],
      ...rebuilt,
      for (var i = lastIndex + 1; i < blocks.length; i++)
        blocks[i].shifted(delta),
    ];
    return MarkdownBlockDocument._(nextSource, next, _nextId + rebuilt.length);
  }

  /// 外部整篇写入（AI 生成、humanize、撤销）后重切。
  ///
  /// 全部块都会拿到新 id：整篇替换后无法判断哪一块还是原来那一块。
  MarkdownBlockDocument resplit(String nextSource) {
    final next = _splitBlocks(nextSource, 0, _nextId);
    return MarkdownBlockDocument._(nextSource, next, _nextId + next.length);
  }

  /// 调试断言用：块区间是否连续覆盖全文。
  bool get isContiguous {
    if (blocks.isEmpty) {
      return false;
    }
    if (blocks.first.start != 0 || blocks.last.separatorEnd != source.length) {
      return false;
    }
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.start > block.end || block.end > block.separatorEnd) {
        return false;
      }
      if (i + 1 < blocks.length && block.separatorEnd != blocks[i + 1].start) {
        return false;
      }
    }
    return true;
  }
}

/// 按「空行」切块：一个换行后面还有换行（中间只允许空白）才算块分隔。
///
/// 分隔符区间到最后一个换行为止，之后的空格 / 制表符留给下一块，
/// 以免吃掉缩进列表项的层级。
List<MarkdownBlock> _splitBlocks(String source, int base, int idFrom) {
  final blocks = <MarkdownBlock>[];
  final length = source.length;
  var blockStart = 0;
  var index = 0;
  var nextId = idFrom;

  while (index < length) {
    if (source.codeUnitAt(index) != _lineFeed) {
      index++;
      continue;
    }

    var scan = index + 1;
    var newlineCount = 1;
    var lastNewline = index;
    while (scan < length) {
      final unit = source.codeUnitAt(scan);
      if (unit == _space || unit == _tab || unit == _carriageReturn) {
        scan++;
        continue;
      }
      if (unit == _lineFeed) {
        newlineCount++;
        lastNewline = scan;
        scan++;
        continue;
      }
      break;
    }

    if (newlineCount < 2) {
      index = scan;
      continue;
    }

    var blockEnd = index;
    if (blockEnd > blockStart &&
        source.codeUnitAt(blockEnd - 1) == _carriageReturn) {
      blockEnd--;
    }
    blocks.add(
      MarkdownBlock(
        id: nextId++,
        start: base + blockStart,
        end: base + blockEnd,
        separatorEnd: base + lastNewline + 1,
      ),
    );
    blockStart = lastNewline + 1;
    index = lastNewline + 1;
  }

  blocks.add(
    MarkdownBlock(
      id: nextId++,
      start: base + blockStart,
      end: base + length,
      separatorEnd: base + length,
    ),
  );
  return blocks;
}
