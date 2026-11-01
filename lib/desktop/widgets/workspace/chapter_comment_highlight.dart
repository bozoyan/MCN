// 职责: 在已有正文 span 上叠加批注痕迹 — 多区间下划线，不抢背景色。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/shared/utils/chapter_comment_anchor.dart
//   lib/shared/theme/theme.dart

import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';
import '../../../shared/utils/chapter_comment_anchor.dart';

/// 一段要画痕迹的正文区间。
class ChapterCommentHighlightRange {
  const ChapterCommentHighlightRange({
    required this.start,
    required this.end,
    required this.resolved,
    required this.active,
  });

  final int start;
  final int end;

  /// 已解决的批注痕迹更淡（虚线），未解决的是实线。
  final bool resolved;

  /// 当前气泡打开的那一条，给一点背景把它拎出来。
  final bool active;
}

/// 把 [comments] 转成渲染用的区间；失锚的批注不画痕迹。
List<ChapterCommentHighlightRange> chapterCommentHighlightRanges({
  required List<ResolvedChapterComment> comments,
  String? activeId,
}) {
  final ranges = <ChapterCommentHighlightRange>[];
  for (final resolved in comments) {
    final anchor = resolved.anchor;
    if (anchor == null || anchor.isEmpty) {
      continue;
    }
    ranges.add(
      ChapterCommentHighlightRange(
        start: anchor.start,
        end: anchor.end,
        resolved: resolved.comment.isResolved,
        active: resolved.comment.id == activeId,
      ),
    );
  }
  return ranges;
}

/// 在 [spans] 上叠加批注痕迹。
///
/// 与 `applyChapterFindMatchHighlight` 同构（逐 span 按交集切段），差别有二：
///
/// 1. **多区间**：逐条区间反复叠加，重叠的批注天然合并样式，不需要先做区间归并；
/// 2. **只动 decoration 不动 backgroundColor**：正文已经有实体高亮和查找高亮两层
///    背景色，第三层会互相盖住。只有「当前打开的那一条」才补一点背景。
List<TextSpan> applyChapterCommentHighlight({
  required List<TextSpan> spans,
  required List<ChapterCommentHighlightRange> ranges,
  required RevericColors colors,
}) {
  if (ranges.isEmpty) {
    return spans;
  }

  var textLength = 0;
  for (final span in spans) {
    textLength += span.text?.length ?? 0;
  }

  var current = spans;
  for (final range in ranges) {
    if (range.start >= range.end || range.end > textLength || range.start < 0) {
      // 锚点与当前文本不吻合（正文刚变、还没重新解析）时整条跳过，不越界。
      continue;
    }
    current = _applyRange(current, range, colors);
  }
  return current;
}

List<TextSpan> _applyRange(
  List<TextSpan> spans,
  ChapterCommentHighlightRange range,
  RevericColors colors,
) {
  final highlighted = <TextSpan>[];
  var offset = 0;
  for (final span in spans) {
    final segment = span.text ?? '';
    final segmentStart = offset;
    final segmentEnd = segmentStart + segment.length;
    offset = segmentEnd;

    final overlapStart = range.start > segmentStart
        ? range.start
        : segmentStart;
    final overlapEnd = range.end < segmentEnd ? range.end : segmentEnd;
    if (overlapStart >= overlapEnd) {
      highlighted.add(span);
      continue;
    }

    final localStart = overlapStart - segmentStart;
    final localEnd = overlapEnd - segmentStart;
    if (localStart > 0) {
      highlighted.add(
        TextSpan(text: segment.substring(0, localStart), style: span.style),
      );
    }
    highlighted.add(
      TextSpan(
        text: segment.substring(localStart, localEnd),
        style: _commentStyle(span.style, range, colors),
      ),
    );
    if (localEnd < segment.length) {
      highlighted.add(
        TextSpan(text: segment.substring(localEnd), style: span.style),
      );
    }
  }
  return highlighted;
}

TextStyle _commentStyle(
  TextStyle? base,
  ChapterCommentHighlightRange range,
  RevericColors colors,
) {
  final style = base ?? const TextStyle();
  if (range.resolved) {
    return style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: colors.textSubtle,
      decorationStyle: TextDecorationStyle.dashed,
      decorationThickness: 1,
      backgroundColor: range.active
          ? colors.accent.withValues(alpha: 0.14)
          : style.backgroundColor,
    );
  }
  return style.copyWith(
    decoration: TextDecoration.underline,
    decorationColor: colors.accentWarm,
    decorationStyle: TextDecorationStyle.solid,
    decorationThickness: 2,
    backgroundColor: range.active
        ? colors.accent.withValues(alpha: 0.18)
        : style.backgroundColor,
  );
}
