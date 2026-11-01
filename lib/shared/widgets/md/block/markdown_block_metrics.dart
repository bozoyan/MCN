// 职责: Markdown 块高度度量 — 用字符估算未挂载块并缓存已布局块的真实高度
// 关联文件:
//   lib/shared/widgets/md/block/markdown_block_document.dart
//   lib/shared/widgets/md/block/markdown_block_list_view.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md
//   .agents/rules/performance.md

import 'dart:math' as math;

import 'markdown_block_document.dart';

/// 为虚拟列表的屏外定位提供高度估算。
class MarkdownBlockMetrics {
  final Map<int, double> _measuredHeights = <int, double>{};

  double _availableWidth = 600;
  double _fontSize = 16;
  double _lineHeight = 1.5;
  double _letterSpacing = 0;

  void configure({
    required double availableWidth,
    required double fontSize,
    required double lineHeight,
    required double letterSpacing,
  }) {
    _availableWidth = math.max(1, availableWidth);
    _fontSize = math.max(1, fontSize);
    _lineHeight = math.max(0.5, lineHeight);
    _letterSpacing = letterSpacing;
  }

  void recordMeasured(int blockId, double height) {
    if (height.isFinite && height > 0) {
      _measuredHeights[blockId] = height;
    }
  }

  double heightOf(MarkdownBlock block, String source) {
    return _measuredHeights[block.id] ?? _estimate(block, source);
  }

  double estimatedOffsetOf(MarkdownBlockDocument document, int blockIndex) {
    final safeIndex = blockIndex.clamp(0, document.length);
    var offset = 0.0;
    for (var index = 0; index < safeIndex; index++) {
      offset += heightOf(document[index], document.source);
    }
    return offset;
  }

  void retainOnly(Iterable<int> blockIds) {
    final retained = blockIds.toSet();
    _measuredHeights.removeWhere((id, _) => !retained.contains(id));
  }

  double _estimate(MarkdownBlock block, String source) {
    final text = source.substring(block.start, block.separatorEnd);
    final averageGlyphWidth = math.max(
      1,
      _fontSize * 0.72 + math.max(0, _letterSpacing),
    );
    final charsPerLine = math.max(
      1,
      (_availableWidth / averageGlyphWidth).floor(),
    );
    var visualLines = 0;
    for (final line in text.split('\n')) {
      visualLines += math.max(1, (line.length / charsPerLine).ceil());
    }
    if (block.separatorEnd > block.end && visualLines > 1) {
      visualLines -= 1;
    }
    return visualLines * _fontSize * _lineHeight;
  }
}
