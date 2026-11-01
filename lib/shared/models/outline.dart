// 职责: Timeline 大纲模型导出与文档内容渲染扩展。
// 关联文件:
//   lib/shared/database/novel_content_database.dart

import 'dart:convert';

import '../database/novel_content_database.dart';
import '../utils/utf16_safe_text.dart';
import 'outline_draft.dart';

export 'outline_draft.dart'
    show
        OutlineDraft,
        OutlineBeatDraft,
        outlineStatusPending,
        outlineStatusInProgress,
        outlineStatusFinished,
        outlineStatuses,
        shortOutlineBeatTitle,
        outlineBeatsHaveSameContent;

export '../database/novel_content_database.dart'
    show
        Outline,
        Outlines,
        OutlinesCompanion,
        OutlineBeat,
        OutlineBeats,
        OutlineBeatsCompanion;

extension OutlineDraftX on OutlineDraft {
  bool get isEmpty => title.trim().isEmpty && content.trim().isEmpty;

  bool get hasTimeline => beats.isNotEmpty;

  String get titleSummary => truncateUtf16Safe(title.trim(), 80);

  String encodeTimelineJson() {
    return jsonEncode(beats.map((beat) => beat.toJson()).toList());
  }

  String toDocumentContent() {
    final buffer = StringBuffer();
    void writeSection(String heading, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.writeln('## $heading');
      buffer.writeln(trimmed);
    }

    final effectiveTitle = title.trim();
    if (effectiveTitle.isNotEmpty) {
      buffer.writeln('# $effectiveTitle');
    }
    writeSection('Content', content);
    if (beats.isNotEmpty) {
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.writeln('## Timeline');
      for (var index = 0; index < beats.length; index++) {
        final beat = beats[index];
        final heading = beat.title.trim().isEmpty
            ? '${index + 1}. Beat'
            : '${index + 1}. ${beat.title.trim()}';
        buffer.writeln();
        buffer.writeln('### $heading');
        buffer.writeln('- Status: ${beat.status}');
        buffer.writeln('- Length: ${beat.chapterCount} chapter(s)');
        if (beat.content.trim().isNotEmpty) {
          buffer.writeln();
          buffer.writeln(beat.content.trim());
        }
      }
    }
    return buffer.toString().trimRight();
  }
}

extension OutlineListX on List<OutlineDraft> {
  List<OutlineDraft> get sorted =>
      [...this]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<OutlineDraft> get enabled =>
      where((t) => t.deletedAt == notDeletedSentinel).toList();
}

List<OutlineBeatDraft> decodeTimelineJson(String? source) {
  if (source == null || source.trim().isEmpty) {
    return const <OutlineBeatDraft>[];
  }
  try {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      return const <OutlineBeatDraft>[];
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => OutlineBeatDraft.fromJson(
            item.map(
              (key, value) => MapEntry(key.toString(), value as Object?),
            ),
          ),
        )
        .toList(growable: false);
  } catch (_) {
    return const <OutlineBeatDraft>[];
  }
}
