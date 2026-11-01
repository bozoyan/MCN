// 职责: 定义作者对章节正文选区写下的批注 — 锚点、引文快照、内容与解决状态。
// 关联文件:
//   lib/shared/database/type_converters.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/chapter.dart
//   lib/shared/services/novel_content.dart

const String chapterCommentStatusOpen = 'open';
const String chapterCommentStatusResolved = 'resolved';

/// 作者对一段正文写下的批注。
///
/// 落库形态是 `chapter_nodes.comments` 这一列里的 JSON 数组，不单独建表：
/// 一章的批注数量很小、永远随章节一起读、没有跨章查询场景。
///
/// [start] / [end] 只是**定位提示**，[quote] 才是真源：正文被编辑后偏移会漂，
/// 由 `chapter_comment_anchor.dart` 按 quote 重新校准，不回写数据库。
class ChapterComment {
  const ChapterComment({
    required this.id,
    required this.start,
    required this.end,
    required this.quote,
    required this.content,
    this.status = chapterCommentStatusOpen,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;

  /// 建批注时选区在正文中的起止偏移（提示值，见类文档）。
  final int start;
  final int end;

  /// 被批注的正文片段快照，用于正文变动后重新定位。
  final String quote;

  /// 批注正文，作者手写。
  final String content;

  /// [chapterCommentStatusOpen] / [chapterCommentStatusResolved]。
  final String status;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 软删除标记（`.agents/rules/data-deletion.md`）：删除只写这一项，
  /// 读取时过滤，不从 JSON 数组里真删。
  final DateTime? deletedAt;

  bool get isResolved => status == chapterCommentStatusResolved;
  bool get isDeleted => deletedAt != null;

  factory ChapterComment.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Chapter comment requires a non-empty id.');
    }
    return ChapterComment(
      id: id,
      start: _readInt(json['start']),
      end: _readInt(json['end']),
      quote: _readString(json['quote']),
      content: _readString(json['content']),
      status: switch (json['status']) {
        chapterCommentStatusResolved => chapterCommentStatusResolved,
        _ => chapterCommentStatusOpen,
      },
      createdAt: _readDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: _readDateTime(json['updated_at']) ?? DateTime.now(),
      deletedAt: _readDateTime(json['deleted_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'start': start,
      'end': end,
      'quote': quote,
      'content': content,
      'status': status,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      if (deletedAt != null)
        'deleted_at': deletedAt!.millisecondsSinceEpoch ~/ 1000,
    };
  }

  ChapterComment copyWith({
    int? start,
    int? end,
    String? quote,
    String? content,
    String? status,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return ChapterComment(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      quote: quote ?? this.quote,
      content: content ?? this.content,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ChapterComment &&
            other.id == id &&
            other.start == start &&
            other.end == end &&
            other.quote == quote &&
            other.content == content &&
            other.status == status &&
            other.createdAt == createdAt &&
            other.updatedAt == updatedAt &&
            other.deletedAt == deletedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    start,
    end,
    quote,
    content,
    status,
    createdAt,
    updatedAt,
    deletedAt,
  );
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

String _readString(Object? value) {
  return value is String ? value : '';
}

/// JSON 里时间统一存 Unix 秒（与 `db-timestamps.md` 的列存储口径一致）。
DateTime? _readDateTime(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
  }
  return null;
}
