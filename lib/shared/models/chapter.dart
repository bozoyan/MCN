// 职责: Chapter 手写模型（基于 VIEW 行）、表单字段枚举与扩展方法
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/database/novel_content_daos/chapter_dao.dart
//   lib/shared/models/chapter_comment.dart

import '../database/novel_content_database.dart';
import '../utils/utf16_safe_text.dart';
import '../database/type_converters.dart';
import '../../third/form/flutter_hook_form.dart';
import 'chapter_comment.dart';

export '../database/novel_content_database.dart'
    show
        ChapterData,
        ChaptersCompanion,
        Chapters,
        nodeTypeVolume,
        nodeTypeChapter,
        nodeTypeExtra,
        nodeTypes,
        chapterStatDraft,
        chapterStatPublished,
        chapterEmbeddingSyncStatusPending,
        notDeletedSentinel;

class Chapter {
  final String id;
  final String type;
  final String? parentId;
  final int siblingOrder;

  final String? title;
  final String outline;
  final String brief;
  final String content;
  final int wordCount;
  final String stat;
  final int? tension;
  final List<String>? emotion;

  /// 章内事件序列 `[{title, summary, state_change}]`，chronicler 提取。
  /// 不进章节树查询（重字段），只在单章详情可用。
  final List<Map<String, dynamic>>? events;

  /// 作者对正文选区写下的批注。含已软删除项，消费方按 `deletedAt` 过滤。
  final List<ChapterComment>? comments;
  final String embeddingSyncStatus;
  final DateTime? embeddingSyncedAt;
  final String? embeddingSyncModelId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime deletedAt;

  // VIEW computed columns
  final int? volumeNum;
  final int? chapterNum;
  final int? volumeChapterNum;

  const Chapter({
    required this.id,
    required this.type,
    this.parentId,
    required this.siblingOrder,
    this.title,
    this.outline = '',
    this.brief = '',
    this.content = '',
    this.wordCount = 0,
    this.stat = chapterStatDraft,
    this.tension,
    this.emotion,
    this.events,
    this.comments,
    this.embeddingSyncStatus = chapterEmbeddingSyncStatusPending,
    this.embeddingSyncedAt,
    this.embeddingSyncModelId,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    this.volumeNum,
    this.chapterNum,
    this.volumeChapterNum,
  });

  bool get isVolume => type == nodeTypeVolume;
  bool get isChapter => type == nodeTypeChapter || type == nodeTypeExtra;
  bool get isNumberedChapter => type == nodeTypeChapter;
  bool get isExtra => type == nodeTypeExtra;

  String get displayTitle {
    if (isVolume) {
      return '第 $volumeNum 卷${title != null ? ' · $title' : ''}';
    }
    if (isExtra) {
      return title ?? nodeTypeExtra;
    }
    return title ?? '第 $chapterNum 章';
  }

  /// 始终带上序号的标题，用于分享出去的快照。
  /// displayTitle 在章节有自定义标题时会丢掉序号；在章节树里有上下文可推断，
  /// 但审稿页只有孤立的几章，收件人没有参照物。
  String get numberedTitle {
    if (!isNumberedChapter) return displayTitle;
    final name = title;
    if (name == null || name.isEmpty) return '第 $chapterNum 章';
    return '第 $chapterNum 章 · $name';
  }

  factory Chapter.fromViewRow(Map<String, Object?> row) {
    DateTime parseDt(String key) {
      const maxSec = 10000000000; // 10 digits = seconds, 13 digits = ms
      final val = row[key];
      if (val == null) return notDeletedSentinel;
      if (val is DateTime) return val;
      if (val is int) {
        // Drift stores unix seconds; detect ms vs seconds
        if (val > maxSec) {
          return DateTime.fromMillisecondsSinceEpoch(val);
        }
        return DateTime.fromMillisecondsSinceEpoch(val * 1000);
      }
      if (val is String) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed;
        final numeric = int.tryParse(val);
        if (numeric != null) {
          if (numeric > maxSec) {
            return DateTime.fromMillisecondsSinceEpoch(numeric);
          }
          return DateTime.fromMillisecondsSinceEpoch(numeric * 1000);
        }
      }
      return notDeletedSentinel;
    }

    return Chapter(
      id: row['id'] as String,
      type: row['type'] as String,
      parentId: row['parent_id'] as String?,
      siblingOrder: (row['sibling_order'] as num).toInt(),
      title: row['title'] as String?,
      outline: (row['outline'] as String?) ?? '',
      brief: (row['brief'] as String?) ?? '',
      content: (row['content'] as String?) ?? '',
      wordCount: (row['word_count'] as int?) ?? 0,
      stat: (row['stat'] as String?) ?? chapterStatDraft,
      tension: row['tension'] as int?,
      emotion: switch (row['emotion']) {
        final String raw => const StringListConverter().fromSql(raw),
        _ => null,
      },
      events: switch (row['events']) {
        final String raw => const JsonMapListConverter().fromSql(raw),
        _ => null,
      },
      comments: switch (row['comments']) {
        final String raw => const ChapterCommentListConverter().fromSql(raw),
        _ => null,
      },
      embeddingSyncStatus:
          (row['embedding_sync_status'] as String?) ??
          chapterEmbeddingSyncStatusPending,
      embeddingSyncedAt: switch (row['embedding_synced_at']) {
        final int secs => DateTime.fromMillisecondsSinceEpoch(secs * 1000),
        _ => null,
      },
      embeddingSyncModelId: row['embedding_sync_model_id'] as String?,
      createdAt: parseDt('created_at'),
      updatedAt: parseDt('updated_at'),
      deletedAt: parseDt('deleted_at'),
      volumeNum: row['volume_num'] as int?,
      chapterNum: row['chapter_num'] as int?,
      volumeChapterNum: row['volume_chapter_num'] as int?,
    );
  }
}

enum ChapterEditFields implements FieldSchema {
  type(validators: [RequiredValidator()], initialValue: ''),
  title(initialValue: ''),
  outline(initialValue: ''),
  content(initialValue: '');

  const ChapterEditFields({this.validators, this.initialValue});

  final dynamic initialValue;

  @override
  final List<Validator<dynamic>>? validators;
}

extension ChapterX on Chapter {
  bool get isEmpty => content.trim().isEmpty;

  bool get hasTitle => title != null && title!.trim().isNotEmpty;

  String get outlineSummary => truncateUtf16Safe(outline.trim(), 200);

  String get contentSummary => truncateUtf16Safe(content.trim(), 100);

  bool get isDraft => stat == chapterStatDraft;

  bool get isPublished => stat == chapterStatPublished;
}

extension ChapterListX on List<Chapter> {
  List<Chapter> get sorted =>
      [...this]..sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));

  List<Chapter> get enabled =>
      where((c) => c.deletedAt == notDeletedSentinel).toList();
}
