// 职责: 把章节批注的存储锚点校准到当前正文 — 正文被编辑后按引文快照重新定位。
// 关联文件:
//   lib/shared/models/chapter_comment.dart
//   lib/desktop/widgets/workspace/chapter_editor.dart

import '../models/chapter_comment.dart';

/// 一条批注在当前正文中的实际区间。
class ChapterCommentAnchor {
  const ChapterCommentAnchor({required this.start, required this.end});

  final int start;
  final int end;

  bool get isEmpty => end <= start;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ChapterCommentAnchor &&
            other.start == start &&
            other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ChapterCommentAnchor($start, $end)';
}

/// 一条批注 + 它在当前正文中的位置。[anchor] 为 null 表示**失锚**：
/// 被批注的原文已被改写，批注内容仍在，但不再往正文上画痕迹。
class ResolvedChapterComment {
  const ResolvedChapterComment({required this.comment, this.anchor});

  final ChapterComment comment;
  final ChapterCommentAnchor? anchor;

  bool get isOrphaned => anchor == null;
}

/// 把 [comment] 的锚点校准到 [content]。
///
/// 存储的 `start/end` 只是提示：正文一改就会漂。真源是 [ChapterComment.quote]：
///
/// 1. 原位置正好还是那段引文 → 原样返回（最常见，零成本）；
/// 2. 否则全文搜引文 —— 取**离原 start 最近**的那处，兼顾「同一句话出现多次」；
/// 3. 一处都搜不到 → 返回 null（失锚）。
///
/// 结果不回写数据库：引文是真源，每次加载重算即可，一章的批注量很小。
ChapterCommentAnchor? resolveChapterCommentAnchor({
  required String content,
  required ChapterComment comment,
}) {
  final quote = comment.quote;
  if (quote.isEmpty || content.isEmpty) {
    return null;
  }

  final start = comment.start;
  final end = comment.end;
  if (start >= 0 &&
      end <= content.length &&
      end - start == quote.length &&
      content.substring(start, end) == quote) {
    return ChapterCommentAnchor(start: start, end: end);
  }

  var bestStart = -1;
  var bestDistance = -1;
  var cursor = content.indexOf(quote);
  while (cursor >= 0) {
    final distance = (cursor - start).abs();
    if (bestStart < 0 || distance < bestDistance) {
      bestStart = cursor;
      bestDistance = distance;
    }
    cursor = content.indexOf(quote, cursor + 1);
  }
  if (bestStart < 0) {
    return null;
  }
  return ChapterCommentAnchor(start: bestStart, end: bestStart + quote.length);
}

/// 批量校准并按正文顺序排序；已软删除的批注在此过滤掉。
///
/// 失锚的批注仍会出现在结果里（`anchor == null`），排在有锚点的之后 ——
/// 它们的内容不该因为原文被改就消失。
List<ResolvedChapterComment> resolveChapterComments({
  required String content,
  required Iterable<ChapterComment> comments,
}) {
  final resolved = <ResolvedChapterComment>[];
  for (final comment in comments) {
    if (comment.isDeleted) {
      continue;
    }
    resolved.add(
      ResolvedChapterComment(
        comment: comment,
        anchor: resolveChapterCommentAnchor(content: content, comment: comment),
      ),
    );
  }
  resolved.sort((a, b) {
    final anchorA = a.anchor;
    final anchorB = b.anchor;
    if (anchorA == null && anchorB == null) {
      return a.comment.createdAt.compareTo(b.comment.createdAt);
    }
    if (anchorA == null) {
      return 1;
    }
    if (anchorB == null) {
      return -1;
    }
    final byStart = anchorA.start.compareTo(anchorB.start);
    if (byStart != 0) {
      return byStart;
    }
    return anchorA.end.compareTo(anchorB.end);
  });
  return resolved;
}

/// 命中测试：正文偏移 [offset] 落在哪条批注上。
///
/// 与 `chapterEntityAtTextOffset` 同构。多条批注重叠时返回**最短**的那条 ——
/// 精确的小区间通常是用户更想点到的那个。
ResolvedChapterComment? chapterCommentAtTextOffset({
  required int offset,
  required List<ResolvedChapterComment> comments,
}) {
  ResolvedChapterComment? hit;
  for (final resolved in comments) {
    final anchor = resolved.anchor;
    if (anchor == null || offset < anchor.start || offset >= anchor.end) {
      continue;
    }
    final current = hit?.anchor;
    if (current == null ||
        anchor.end - anchor.start < current.end - current.start) {
      hit = resolved;
    }
  }
  return hit;
}
