// 职责: 封面档案模型 — 读稿产出的视觉方向，以及判断它是否已经跟不上稿子的快照。
// 关联文件:
//   lib/shared/services/ai/cover_brief_service.dart
//   lib/shared/services/cover_prompt_builder.dart

/// 一个候选意象。必须带出处章节，作者才能回去核对。
class CoverBriefMotif {
  const CoverBriefMotif({required this.text, required this.from});

  final String text;
  final String from;

  Map<String, dynamic> toJson() => {'text': text, 'from': from};

  static CoverBriefMotif? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text']?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return CoverBriefMotif(
      text: text,
      from: json['from']?.toString().trim() ?? '',
    );
  }
}

/// 档案读的是哪一版章节。判断过时靠它 —— 只比体量会漏掉「章节数没变但正文改了」。
class CoverBriefSource {
  const CoverBriefSource({required this.chapterId, required this.updatedAt});

  final String chapterId;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'chapter_id': chapterId,
    'updated_at': updatedAt.toIso8601String(),
  };

  static CoverBriefSource? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final chapterId = json['chapter_id']?.toString();
    final updatedAt = DateTime.tryParse(json['updated_at']?.toString() ?? '');
    if (chapterId == null || chapterId.isEmpty || updatedAt == null) {
      return null;
    }
    return CoverBriefSource(chapterId: chapterId, updatedAt: updatedAt);
  }
}

class CoverBrief {
  const CoverBrief({
    required this.category,
    required this.style,
    required this.palette,
    required this.temperature,
    required this.figure,
    required this.era,
    required this.motifs,
    required this.readAt,
    required this.sources,
    required this.chapterCount,
    required this.wordCount,
  });

  /// 品类，如「历史 · 群像」。
  final String category;

  /// 风格；读稿前靠芯片预设，读完后档案里是这部稿的判断。
  final String style;

  /// 色调；读稿前靠芯片预设，读完后档案里是这部稿的判断。
  final String palette;

  /// 色温倾向。
  final String temperature;

  /// 主角怎么画（或建议不画具体人物）。
  final String figure;

  /// 时代与要避开的器物 / 字体。
  final String era;
  final List<CoverBriefMotif> motifs;

  final DateTime readAt;

  /// 读的那几章（只读开头三章）及其当时的 updatedAt。
  final List<CoverBriefSource> sources;

  /// 读的时候全稿的体量快照。
  final int chapterCount;
  final int wordCount;

  Map<String, dynamic> toJson() => {
    'category': category,
    'style': style,
    'palette': palette,
    'temperature': temperature,
    'figure': figure,
    'era': era,
    'motifs': motifs.map((motif) => motif.toJson()).toList(),
    'read_at': readAt.toIso8601String(),
    'sources': sources.map((source) => source.toJson()).toList(),
    'chapter_count': chapterCount,
    'word_count': wordCount,
  };

  static CoverBrief? fromJson(Object? json) {
    if (json is! Map) return null;
    final readAt = DateTime.tryParse(json['read_at']?.toString() ?? '');
    if (readAt == null) return null;
    return CoverBrief(
      category: json['category']?.toString() ?? '',
      style: json['style']?.toString() ?? '',
      palette: json['palette']?.toString() ?? '',
      temperature: json['temperature']?.toString() ?? '',
      figure: json['figure']?.toString() ?? '',
      era: json['era']?.toString() ?? '',
      motifs: [
        if (json['motifs'] case final List<dynamic> raw)
          ...raw.map(CoverBriefMotif.fromJson).nonNulls,
      ],
      readAt: readAt,
      sources: [
        if (json['sources'] case final List<dynamic> raw)
          ...raw.map(CoverBriefSource.fromJson).nonNulls,
      ],
      chapterCount: (json['chapter_count'] as num?)?.toInt() ?? 0,
      wordCount: (json['word_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 稿子当前的体量，用来和档案的快照比。
class CoverBriefStats {
  const CoverBriefStats({
    required this.chapterCount,
    required this.wordCount,
    this.sourceUpdatedAt = const {},
  });

  final int chapterCount;
  final int wordCount;

  /// 档案来源章节的当前 updatedAt，按 chapterId 索引。
  final Map<String, DateTime> sourceUpdatedAt;
}

/// 多写这么多章就提示一次。
const coverBriefStaleChapters = 5;

/// 字数涨了这个比例就提示一次。
const coverBriefStaleWordRatio = 0.2;

/// 档案是否已经跟不上稿子。
///
/// 只读开头三章，所以判据有两条，任一命中即为过时：
/// 1. 读过的那几章本身被改了 —— 档案的依据变了；
/// 2. 后面又写了一大段 —— 依据没变，但作品可能已经不是当初那个样子。
bool isCoverBriefStale(CoverBrief brief, CoverBriefStats stats) {
  for (final source in brief.sources) {
    final current = stats.sourceUpdatedAt[source.chapterId];
    if (current != null && current.isAfter(source.updatedAt)) {
      return true;
    }
  }
  if (stats.chapterCount - brief.chapterCount >= coverBriefStaleChapters) {
    return true;
  }
  if (brief.wordCount > 0 &&
      stats.wordCount / brief.wordCount - 1 >= coverBriefStaleWordRatio) {
    return true;
  }
  return false;
}
