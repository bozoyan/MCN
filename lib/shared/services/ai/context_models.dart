// 职责: AI 上下文快照模型，连接章节数据库记录与 AI 会话上下文
// 关联文件:
//   lib/shared/services/ai/context_manager.dart
//   lib/shared/models/ai_chat_models.dart
//   lib/shared/database/novel_content_database.dart
import '../../database/novel_content_database.dart';
import '../../models/ai_chat_models.dart';

class AiChapterContextSnapshot {
  const AiChapterContextSnapshot({
    required this.chapterId,
    required this.title,
    required this.chapterOutline,
    required this.content,
    this.chapterNum,
    this.outline = '',
    this.previousContent,
    this.characterProfiles = const [],
    this.worldbuildingNotes = const [],
    this.materialNotes = const [],
  });

  final String chapterId;
  final String title;
  final int? chapterNum;
  final String chapterOutline;
  final String content;
  final String outline;
  final String? previousContent;
  final List<String> characterProfiles;
  final List<String> worldbuildingNotes;
  final List<String> materialNotes;

  AiSessionContext toSessionContext({String? databasePath}) {
    return AiSessionContext(
      databasePath: databasePath,
      chapterId: chapterId,
      chapterTitle: title,
      chapterNum: chapterNum,
      chapterOutline: chapterOutline,
      chapterContent: content,
      outline: outline,
      previousContent: previousContent,
      characterProfiles: characterProfiles,
      worldbuildingNotes: worldbuildingNotes,
      materialNotes: materialNotes,
    );
  }

  AiChapterContextSnapshot copyWith({
    String? chapterId,
    String? title,
    int? chapterNum,
    String? chapterOutline,
    String? content,
    String? outline,
    String? previousContent,
    List<String>? characterProfiles,
    List<String>? worldbuildingNotes,
    List<String>? materialNotes,
  }) {
    return AiChapterContextSnapshot(
      chapterId: chapterId ?? this.chapterId,
      title: title ?? this.title,
      chapterNum: chapterNum ?? this.chapterNum,
      chapterOutline: chapterOutline ?? this.chapterOutline,
      content: content ?? this.content,
      outline: outline ?? this.outline,
      previousContent: previousContent ?? this.previousContent,
      characterProfiles: characterProfiles ?? this.characterProfiles,
      worldbuildingNotes: worldbuildingNotes ?? this.worldbuildingNotes,
      materialNotes: materialNotes ?? this.materialNotes,
    );
  }
}

extension ChapterContextSnapshotX on Chapter {
  AiChapterContextSnapshot toAiSnapshot({
    String novelOutline = '',
    String? previousContent,
    List<String> characterProfiles = const [],
    List<String> worldbuildingNotes = const [],
    List<String> materialNotes = const [],
  }) {
    return AiChapterContextSnapshot(
      chapterId: id,
      title: title?.trim().isNotEmpty == true ? title!.trim() : '未命名章节',
      chapterNum: chapterNum,
      chapterOutline: outline,
      content: content,
      outline: novelOutline,
      previousContent: previousContent,
      characterProfiles: characterProfiles,
      worldbuildingNotes: worldbuildingNotes,
      materialNotes: materialNotes,
    );
  }
}
