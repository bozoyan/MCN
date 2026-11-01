// 职责: 定义剧本领域常量、只读投影与服务错误契约。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/database/novel_content_daos/screenplay_dao.dart
//   lib/shared/services/screenplay_service.dart

import 'screenplay_element.dart';
import '../database/novel_content_database.dart';

const String screenplayKindSeries = 'series';
const String screenplayFormatAsian = 'asian';
const String screenplayStageDraft = 'draft';
const String screenplayStageFinal = 'final';
const String screenplayInterior = 'interior';
const String screenplayExterior = 'exterior';
const String screenplayInteriorExterior = 'interior_exterior';

const Set<String> screenplayStages = <String>{
  screenplayStageDraft,
  screenplayStageFinal,
};
const Set<String> screenplayInteriorExteriorValues = <String>{
  screenplayInterior,
  screenplayExterior,
  screenplayInteriorExterior,
};

class ScreenplayServiceException implements Exception {
  const ScreenplayServiceException(
    this.errorCode,
    this.message, {
    this.details,
  });

  final String errorCode;
  final String message;
  final Object? details;

  @override
  String toString() => '$errorCode: $message';
}

/// 仍引用某人物 / 地点的场次，删除前用于拦截并列出。
class ScreenplaySceneReference {
  const ScreenplaySceneReference({
    required this.sceneId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.sceneNumber,
    required this.title,
    required this.sources,
  });

  final String sceneId;
  final int? seasonNumber;
  final int? episodeNumber;
  final int sceneNumber;
  final String title;

  /// 引用来源：人物为 `cast`（出场名单）/ `dialogue`（对白），地点为 `heading`。
  final List<String> sources;
}

class CreatedSeason {
  const CreatedSeason({required this.seasonId, required this.episodeId});

  final String seasonId;
  final String episodeId;
}

class ScreenplaySceneSummary {
  const ScreenplaySceneSummary({
    required this.id,
    required this.episodeId,
    required this.sceneNumber,
    required this.synopsis,
    required this.stage,
    required this.pageEighths,
    required this.dialogueLineCount,
    required this.wordCount,
    this.beatId,
    this.locationId,
    this.interiorExterior,
    this.timeLabel = '',
    this.title = '',
    this.emotion = const [],
  });

  final String id;
  final String episodeId;
  final int sceneNumber;
  final String? beatId;
  final String? locationId;
  final String? interiorExterior;
  final String timeLabel;
  final String title;
  final List<String> emotion;
  final String synopsis;
  final String stage;
  final int pageEighths;
  final int dialogueLineCount;
  final int wordCount;
}

class ScreenplayBeatSummary {
  const ScreenplayBeatSummary({
    required this.id,
    required this.episodeId,
    required this.actNumber,
    required this.beatNumber,
    required this.title,
    required this.description,
    required this.sceneCount,
    required this.pageEighths,
  });

  final String id;
  final String episodeId;
  final int actNumber;
  final int beatNumber;
  final String title;
  final String description;
  final int sceneCount;
  final int pageEighths;
}

class ScreenplayOutlineEntry {
  ScreenplayOutlineEntry({
    required this.scene,
    required this.beatTitle,
    required Iterable<String> characterIds,
  }) : characterIds = List<String>.unmodifiable(characterIds);

  final ScreenplaySceneSummary scene;
  final String? beatTitle;
  final List<String> characterIds;
}

class ScreenplayOverview {
  const ScreenplayOverview({
    required this.sceneCount,
    required this.pageEighths,
    required this.dialogueLineCount,
    required this.wordCount,
    required this.characterCount,
    required this.locationCount,
    required this.beatCount,
  });

  final int sceneCount;
  final int pageEighths;
  final int dialogueLineCount;
  final int wordCount;
  final int characterCount;
  final int locationCount;
  final int beatCount;
}

class ScreenplayAppearanceMatrixRow {
  ScreenplayAppearanceMatrixRow({
    required this.sceneId,
    required this.sceneNumber,
    required Iterable<String> characterIds,
  }) : characterIds = List<String>.unmodifiable(characterIds);

  final String sceneId;
  final int sceneNumber;
  final List<String> characterIds;
}

class EpisodeScriptScenePreview {
  const EpisodeScriptScenePreview({
    required this.scene,
    required this.elements,
  });

  final ScreenplaySceneSummary scene;
  final List<ScreenplayElement> elements;
}

/// 继续写作的落点：选中的场次优先，其次本集第一场草稿，最后第一场。
/// [quote] 是这一场最后一句非空的对白或动作，让作者认出自己停在哪。
({EpisodeScriptScenePreview? preview, String? quote}) screenplayContinuePoint(
  List<EpisodeScriptScenePreview> previews,
  String? selectedSceneId,
) {
  final preview =
      previews.where((p) => p.scene.id == selectedSceneId).firstOrNull ??
      previews
          .where((p) => p.scene.stage != screenplayStageFinal)
          .firstOrNull ??
      previews.firstOrNull;
  final quote = preview?.elements.reversed
      .where(
        (e) =>
            (e.type == ScreenplayElementType.dialogue ||
                e.type == ScreenplayElementType.action) &&
            e.text.trim().isNotEmpty,
      )
      .firstOrNull
      ?.text
      .trim();
  return (preview: preview, quote: quote);
}

/// 场次资料与唯一标题元素的只读关联；标题字段和顺序不存入场次表。
class ScreenplaySceneRecord {
  const ScreenplaySceneRecord(this.row, this.heading);
  final ScreenplaySceneRow row;
  final ScreenplaySceneElementRow heading;
  String get id => row.id;
  String get screenplayId => row.screenplayId;
  String get episodeId => row.episodeId;
  String? get beatId => row.beatId;
  String? get locationId => heading.locationId;
  String? get interiorExterior => heading.interiorExterior;
  String get timeLabel => heading.timeLabel!;
  String get title => row.title;
  List<String>? get emotion => row.emotion;
  List<Map<String, dynamic>>? get events => row.events;
  String get synopsis => row.synopsis;
  String get stage => row.stage;
  int get pageEighths => row.pageEighths;
  int get dialogueLineCount => row.dialogueLineCount;
  int get wordCount => row.wordCount;
  DateTime get createdAt => row.createdAt;
  DateTime get updatedAt => row.updatedAt;
  DateTime get deletedAt => row.deletedAt;
}
