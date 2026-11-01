// 职责: Timeline 大纲编辑态模型 — 承载 outline 主内容与 beat 列表。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/models/outline.dart

const String outlineStatusPending = 'pending';
const String outlineStatusInProgress = 'in_progress';
const String outlineStatusFinished = 'finished';

const List<String> outlineStatuses = <String>[
  outlineStatusPending,
  outlineStatusInProgress,
  outlineStatusFinished,
];

class OutlineDraft {
  const OutlineDraft({
    required this.documentId,
    this.title = '',
    this.content = '',
    this.status = outlineStatusPending,
    this.startChapterNum = 1,
    this.beats = const <OutlineBeatDraft>[],
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String documentId;
  final String title;
  final String content;
  final String status;
  final int startChapterNum;
  final List<OutlineBeatDraft> beats;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime deletedAt;

  OutlineDraft copyWith({
    String? documentId,
    String? title,
    String? content,
    String? status,
    int? startChapterNum,
    List<OutlineBeatDraft>? beats,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return OutlineDraft(
      documentId: documentId ?? this.documentId,
      title: title ?? this.title,
      content: content ?? this.content,
      status: status ?? this.status,
      startChapterNum: startChapterNum ?? this.startChapterNum,
      beats: beats ?? this.beats,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

class OutlineBeatDraft {
  OutlineBeatDraft({
    required String id,
    bool isNew = false,
    this.title = '',
    this.content = '',
    this.status = outlineStatusPending,
    this.chapterCount = 1,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) : _identity = _OutlineBeatIdentity(id, isNew),
       createdAt = createdAt ?? _emptyDate,
       updatedAt = updatedAt ?? _emptyDate,
       deletedAt = deletedAt ?? _emptyDate;

  late _OutlineBeatIdentity _identity;
  String get id => _identity.id;

  /// 由 Create/列表新增入口显式设置；持久化读取与历史快照默认都是 false。
  bool get isNew => _identity.isNew;

  /// 同一待保存节拍的编辑副本共享身份；事务成功后一次性确认最终 ID。
  /// 这样排队中的自动保存和保存期间的后续编辑不会再次创建同一个节拍。
  void acceptPersistedIdentity(String id) {
    _identity.id = id;
    _identity.isNew = false;
  }

  final String title;
  final String content;
  final String status;
  final int chapterCount;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime deletedAt;

  OutlineBeatDraft copyWith({
    String? id,
    bool? isNew,
    String? title,
    String? content,
    String? status,
    int? chapterCount,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    final result = OutlineBeatDraft(
      id: id ?? this.id,
      isNew: isNew ?? this.isNew,
      title: title ?? this.title,
      content: content ?? this.content,
      status: status ?? this.status,
      chapterCount: chapterCount ?? this.chapterCount,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
    if (id == null && isNew == null) {
      result._identity = _identity;
    }
    return result;
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      if (isNew) 'isNew': true,
      'title': title,
      'content': content,
      'status': status,
      'chapterCount': chapterCount,
      'sortOrder': sortOrder,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'deletedAt': deletedAt.millisecondsSinceEpoch,
    };
  }

  factory OutlineBeatDraft.fromJson(Map<String, Object?> json) {
    return OutlineBeatDraft(
      id: json['id'] as String? ?? '',
      isNew: json['isNew'] == true,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      status: json['status'] as String? ?? outlineStatusPending,
      chapterCount: _readInt(json['chapterCount']) ?? 1,
      sortOrder: _readInt(json['sortOrder']) ?? 0,
      createdAt: _readDateTime(json['createdAt']),
      updatedAt: _readDateTime(json['updatedAt']),
      deletedAt: _readDateTime(json['deletedAt']),
    );
  }
}

class _OutlineBeatIdentity {
  _OutlineBeatIdentity(this.id, this.isNew);
  String id;
  bool isNew;
}

final DateTime _emptyDate = DateTime.fromMillisecondsSinceEpoch(0);

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

DateTime? _readDateTime(Object? value) {
  final milliseconds = _readInt(value);
  if (milliseconds == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(milliseconds);
}

/// 去掉卷次前缀与括号章数说明，供卡片/对话框展示短标题。
String shortOutlineBeatTitle(String title) {
  var result = title.trim();
  if (result.isEmpty) {
    return result;
  }
  result = result.replaceFirst(RegExp(r'[（(][^）)]*[）)]\s*$'), '').trim();
  result = result
      .replaceFirst(RegExp(r'^第[一二三四五六七八九十百千\d]+卷[：:\s]*'), '')
      .trim();
  return result;
}

/// Compare identity, business values and order, ignoring storage timestamps.
bool outlineBeatsHaveSameContent(
  List<OutlineBeatDraft> left,
  List<OutlineBeatDraft> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    final a = left[i];
    final b = right[i];
    if (a.id != b.id ||
        a.title.trim() != b.title.trim() ||
        a.content.trimRight() != b.content.trimRight() ||
        a.status != b.status ||
        a.chapterCount != b.chapterCount) {
      return false;
    }
  }
  return true;
}
