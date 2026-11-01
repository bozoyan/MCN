// 职责: 章节批注锚点校准的回归测试 — 正文编辑后的重定位、失锚与命中测试。
// 关联文件:
//   lib/shared/utils/chapter_comment_anchor.dart
//   lib/shared/models/chapter_comment.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/chapter_comment.dart';
import 'package:reveric/shared/utils/chapter_comment_anchor.dart';

ChapterComment _comment({
  String id = 'c1',
  required int start,
  required int end,
  required String quote,
  String content = '批注内容',
  String status = chapterCommentStatusOpen,
  DateTime? deletedAt,
  DateTime? createdAt,
}) {
  final now = createdAt ?? DateTime(2026, 8, 17, 14, 2);
  return ChapterComment(
    id: id,
    start: start,
    end: end,
    quote: quote,
    content: content,
    status: status,
    createdAt: now,
    updatedAt: now,
    deletedAt: deletedAt,
  );
}

void main() {
  const body = '船家的灯笼挂在桅杆上，照见雨水沿着甲板的纹路缓缓淌下去。';

  group('resolveChapterCommentAnchor', () {
    test('原位置仍是那段引文时原样返回', () {
      const quote = '照见雨水沿着甲板';
      final start = body.indexOf(quote);
      final anchor = resolveChapterCommentAnchor(
        content: body,
        comment: _comment(
          start: start,
          end: start + quote.length,
          quote: quote,
        ),
      );

      expect(anchor, ChapterCommentAnchor(start: start, end: start + 8));
    });

    test('前文被插入内容导致偏移时按引文重定位', () {
      const quote = '缓缓淌下去';
      final original = body.indexOf(quote);
      const inserted = '雨下了一夜。';
      final edited = inserted + body;

      final anchor = resolveChapterCommentAnchor(
        content: edited,
        comment: _comment(
          start: original,
          end: original + quote.length,
          quote: quote,
        ),
      );

      expect(anchor, isNotNull);
      expect(anchor!.start, original + inserted.length);
      expect(edited.substring(anchor.start, anchor.end), quote);
    });

    test('引文出现多次时取离原锚点最近的一处', () {
      const quote = '灯笼';
      const repeated = '灯笼在船头。灯笼在船尾。灯笼在舱里。';
      final thirdStart = repeated.lastIndexOf(quote);

      final anchor = resolveChapterCommentAnchor(
        content: repeated,
        comment: _comment(
          start: thirdStart + 1, // 稍微漂了一个字符
          end: thirdStart + 1 + quote.length,
          quote: quote,
        ),
      );

      expect(anchor, isNotNull);
      expect(anchor!.start, thirdStart);
    });

    test('引文已被改写则失锚', () {
      final anchor = resolveChapterCommentAnchor(
        content: body,
        comment: _comment(start: 0, end: 5, quote: '这句话已经不在了'),
      );

      expect(anchor, isNull);
    });

    test('空引文或空正文失锚', () {
      expect(
        resolveChapterCommentAnchor(
          content: body,
          comment: _comment(start: 0, end: 0, quote: ''),
        ),
        isNull,
      );
      expect(
        resolveChapterCommentAnchor(
          content: '',
          comment: _comment(start: 0, end: 2, quote: '灯笼'),
        ),
        isNull,
      );
    });

    test('越界的存储偏移不抛异常，走重定位', () {
      const quote = '桅杆';
      final anchor = resolveChapterCommentAnchor(
        content: body,
        comment: _comment(start: 9000, end: 9002, quote: quote),
      );

      expect(anchor, isNotNull);
      expect(body.substring(anchor!.start, anchor.end), quote);
    });
  });

  group('resolveChapterComments', () {
    test('按正文顺序排序，失锚的排在最后，软删的被过滤', () {
      final resolved = resolveChapterComments(
        content: body,
        comments: [
          _comment(id: 'orphan', start: 0, end: 4, quote: '早已删掉的句子'),
          _comment(
            id: 'late',
            start: body.indexOf('缓缓淌下去'),
            end: body.indexOf('缓缓淌下去') + 5,
            quote: '缓缓淌下去',
          ),
          _comment(id: 'early', start: 0, end: 2, quote: '船家'),
          _comment(
            id: 'deleted',
            start: 0,
            end: 2,
            quote: '船家',
            deletedAt: DateTime(2026, 8, 17),
          ),
        ],
      );

      expect(resolved.map((r) => r.comment.id).toList(), [
        'early',
        'late',
        'orphan',
      ]);
      expect(resolved.last.isOrphaned, isTrue);
      expect(resolved.first.anchor, isNotNull);
    });
  });

  group('chapterCommentAtTextOffset', () {
    test('命中区间内的偏移，重叠时取更短的一条', () {
      final outerStart = body.indexOf('照见雨水沿着甲板');
      final innerStart = body.indexOf('雨水');
      final resolved = resolveChapterComments(
        content: body,
        comments: [
          _comment(
            id: 'outer',
            start: outerStart,
            end: outerStart + 8,
            quote: '照见雨水沿着甲板',
          ),
          _comment(
            id: 'inner',
            start: innerStart,
            end: innerStart + 2,
            quote: '雨水',
          ),
        ],
      );

      expect(
        chapterCommentAtTextOffset(
          offset: innerStart,
          comments: resolved,
        )?.comment.id,
        'inner',
      );
      expect(
        chapterCommentAtTextOffset(
          offset: outerStart,
          comments: resolved,
        )?.comment.id,
        'outer',
      );
      expect(chapterCommentAtTextOffset(offset: 0, comments: resolved), isNull);
    });

    test('区间末尾偏移不算命中（左闭右开）', () {
      const quote = '船家';
      final resolved = resolveChapterComments(
        content: body,
        comments: [_comment(start: 0, end: quote.length, quote: quote)],
      );

      expect(
        chapterCommentAtTextOffset(
          offset: quote.length - 1,
          comments: resolved,
        ),
        isNotNull,
      );
      expect(
        chapterCommentAtTextOffset(offset: quote.length, comments: resolved),
        isNull,
      );
    });
  });
}
