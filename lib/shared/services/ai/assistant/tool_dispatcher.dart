// 关联文件:
//   lib/shared/agent/agent_tool_dispatcher.dart
//   lib/shared/services/ai/headless_session_turn.dart
//   lib/shared/services/ai/chat_turn_runner.dart
//   lib/shared/services/remote/run_output_forwarder.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md

import '../../../agent/agent_tool_dispatcher.dart';
import '../../../logger/app_logger.dart';

/// 远程 / home page Assistant 查询小说列表的回调。
typedef AiListNovelsCallback = Future<List<Map<String, dynamic>>> Function();

/// 远程 / home page Assistant 启动后台 Job 的回调。
///
/// chatId / channelType 由 coordinator 从 inbound 上下文注入到业务回调实现，
/// 不在此 dispatcher 层回调签名内（LLM 不可知 chat 上下文）。
typedef AiStartJobCallback =
    Future<Map<String, dynamic>> Function(String novelId, String seed);

/// 远程 / home page Assistant 查询 Job 状态的回调。
typedef AiJobStatusCallback =
    Future<Map<String, dynamic>> Function(String jobId);

/// 远程 / home page Assistant 把用户消息转达给 Job 的回调。
typedef AiSendToJobCallback =
    Future<Map<String, dynamic>> Function(String jobId, String text);

/// Assistant 创建小说的回调。
///
/// `novel` 为扁平化字段映射（title/description/author_name/category/tags/type），
/// 由调用方（coordinator 注入的 NovelActionsService）落地；返回结果含 `novel_id`。
typedef AiCreateNovelCallback =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> novel);

/// Assistant 编辑小说元数据的回调。
///
/// `fields` 为仅含用户指定的可编辑字段（title/description/author_name/category/
/// type/tags），未指定的字段由调用方保留原值；返回结果含 `novel_id`。
typedef AiEditNovelCallback =
    Future<Map<String, dynamic>> Function(
      String novelId,
      Map<String, dynamic> fields,
    );

typedef AiListChaptersCallback =
    Future<Map<String, dynamic>> Function(String novelId);

final _log = AppLogger.forModule('AssistantTools');

const _listNovelsToolName = 'list_novels';
const _startJobToolName = 'start_job';
const _jobStatusToolName = 'job_status';
const _sendToJobToolName = 'send_to_job';
const _createNovelToolName = 'create_novel';
const _editNovelToolName = 'edit_novel';
const _listChaptersToolName = 'list_chapters';
const _listChaptersDefaultLimit = 20;
const _listChaptersMaxLimit = 50;

/// Assistant 专属的工具调度器。
///
/// 与 novel-scoped 的 [AiToolManager] 不同，此 dispatcher 不依赖
/// `NovelContentService` / `WorkingOverlayService`，只承载跨小说工具：
/// - `list_novels` — 列出用户小说库
/// - `start_job` — 为指定小说启动后台写作 Job（不是待办 Task）
/// - `job_status` — 查询 Job 的状态
/// - `send_to_job` — 把用户消息转发给进行中或 idle 的 Job
/// - `create_novel` — 创建一部新小说（含标题/简介/作者/分类/标签/类型）
/// - `edit_novel` — 编辑已存在小说的元数据字段
/// - `list_chapters` — 按过滤条件列出章节标题与字数（不含正文）
class AssistantToolDispatcher implements AgentToolDispatcher {
  AssistantToolDispatcher({
    required this.listNovelsCallback,
    required this.startJobCallback,
    required this.jobStatusCallback,
    required this.sendToJobCallback,
    required this.createNovelCallback,
    required this.editNovelCallback,
    AiListChaptersCallback? listChaptersCallback,
  }) : listChaptersCallback = listChaptersCallback ?? _unsupportedListChapters;

  final AiListNovelsCallback listNovelsCallback;
  final AiStartJobCallback startJobCallback;
  final AiJobStatusCallback jobStatusCallback;
  final AiSendToJobCallback sendToJobCallback;
  final AiCreateNovelCallback createNovelCallback;
  final AiEditNovelCallback editNovelCallback;
  final AiListChaptersCallback listChaptersCallback;

  static Future<Map<String, dynamic>> _unsupportedListChapters(
    String novelId,
  ) async => {'ok': false, 'error': 'list_chapters is not available'};

  static final List<ToolDef> _toolDefs = [
    ToolDef(
      name: _listNovelsToolName,
      description:
          'List all novels in the user\'s library with their id, '
          'title, status, and word count. Use this before start_job to '
          'resolve a novel id.',
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    ),
    ToolDef(
      name: _startJobToolName,
      description:
          'Start a background writing Job for a novel with a seed prompt. '
          'A Job is not a Task (todo). The Job runs autonomously in the '
          'background; progress and questions are forwarded back to this '
          'chat automatically. Use this when the user wants to start '
          'writing or continue work on a novel.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'novel_id': {
            'type': 'string',
            'description': 'The novel id for the Job. Resolve via list_novels.',
          },
          'seed': {
            'type': 'string',
            'description':
                'The seed prompt describing what the Job should do '
                '(e.g. "写第3章" or "继续上一章的情节").',
          },
        },
        'required': ['novel_id', 'seed'],
        'additionalProperties': false,
      },
    ),
    ToolDef(
      name: _jobStatusToolName,
      description:
          'Query the current status of a Job by its job_id. Returns '
          'whether it is running or idle, plus any recent output. A Job '
          'is a background writing session, not a Task (todo).',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'job_id': {'type': 'string', 'description': 'The Job id to query.'},
        },
        'required': ['job_id'],
        'additionalProperties': false,
      },
    ),
    ToolDef(
      name: _sendToJobToolName,
      description:
          'Forward a user message to a Job so it can be incorporated '
          'into the next step. Use this for an in-progress Job or to '
          'resume an idle one. A Job is not a Task (todo).',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'job_id': {'type': 'string', 'description': 'The target Job id.'},
          'text': {
            'type': 'string',
            'description': 'The user message to forward.',
          },
        },
        'required': ['job_id', 'text'],
        'additionalProperties': false,
      },
    ),
    ToolDef(
      name: _createNovelToolName,
      description:
          'Create a new novel in the user\'s library with the given '
          'metadata. Only the title is required; description, author_name, '
          'category, tags, and type are optional. Returns the new novel id. '
          'Use this when the user wants to start a brand new novel.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'The novel title.'},
          'description': {
            'type': 'string',
            'description': 'A short synopsis or description.',
          },
          'author_name': {'type': 'string', 'description': 'The author name.'},
          'category': {
            'type': 'string',
            'description': 'The category / genre.',
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Optional tags.',
          },
          'type': {
            'type': 'string',
            'description': 'The novel type (e.g. original).',
          },
        },
        'required': ['title'],
        'additionalProperties': false,
      },
    ),
    ToolDef(
      name: _editNovelToolName,
      description:
          'Edit the metadata of an existing novel by its novel_id. '
          'Only the fields provided are updated; omitted fields keep their '
          'current values. Supports title, description, author_name, category, '
          'tags, and type. Use this after create_novel or list_novels to '
          'finalize or adjust a novel\'s details.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'novel_id': {
            'type': 'string',
            'description': 'The novel id to edit.',
          },
          'title': {'type': 'string', 'description': 'The new title.'},
          'description': {
            'type': 'string',
            'description': 'The new synopsis / description.',
          },
          'author_name': {
            'type': 'string',
            'description': 'The new author name.',
          },
          'category': {
            'type': 'string',
            'description': 'The new category / genre.',
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'The new tags.',
          },
          'type': {'type': 'string', 'description': 'The new novel type.'},
        },
        'required': ['novel_id'],
        'additionalProperties': false,
      },
    ),
    ToolDef(
      name: _listChaptersToolName,
      description:
          'List chapter titles, numbers, and word counts for a novel. '
          'Does not return chapter body. Filter with chapter_nums, '
          'from_chapter_num/to_chapter_num, or title when the user names '
          'chapters; omit filters to get the most recently updated chapters. '
          'Results are capped — never request the full catalog.',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'novel_id': {
            'type': 'string',
            'description': 'The novel id. Resolve via list_novels.',
          },
          'chapter_nums': {
            'type': 'array',
            'items': {'type': 'integer'},
            'description': 'Exact chapter numbers, e.g. [3, 4, 5].',
          },
          'from_chapter_num': {
            'type': 'integer',
            'description': 'Inclusive start of a chapter-number range.',
          },
          'to_chapter_num': {
            'type': 'integer',
            'description': 'Inclusive end of a chapter-number range.',
          },
          'title': {
            'type': 'string',
            'description': 'Case-insensitive substring match on chapter title.',
          },
          'limit': {
            'type': 'integer',
            'description':
                'Max chapters to return. Defaults to 20, maximum 50.',
          },
        },
        'required': ['novel_id'],
        'additionalProperties': false,
      },
    ),
  ];

  @override
  List<String> allToolNames() =>
      _toolDefs.map((def) => def.name).toList(growable: false);

  @override
  List<ToolDef> allToolDefs() => _toolDefs;

  @override
  List<ToolDef> toolDefsForNames(List<String> names) {
    final set = names.toSet();
    return _toolDefs
        .where((def) => set.contains(def.name))
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> executeTool({
    required String name,
    required Map<String, dynamic> input,
    String? callId,
    bool emitEvents = true,
    ToolExecutionContext? context,
  }) async {
    try {
      switch (name) {
        case _listNovelsToolName:
          return await _handleListNovels();
        case _startJobToolName:
          return await _handleStartJob(input);
        case _jobStatusToolName:
          return await _handleJobStatus(input);
        case _sendToJobToolName:
          return await _handleSendToJob(input);
        case _createNovelToolName:
          return await _handleCreateNovel(input);
        case _editNovelToolName:
          return await _handleEditNovel(input);
        case _listChaptersToolName:
          return await _handleListChapters(input);
        default:
          return {'ok': false, 'error': 'Unknown tool: $name'};
      }
    } catch (error, stackTrace) {
      _log.error(
        'remote assistant tool failed name=$name error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      return {'ok': false, 'error': error.toString()};
    }
  }

  String _parseString(
    Map<String, dynamic> input,
    String key, {
    String altKey = '',
  }) {
    final value = input[key] ?? (altKey.isNotEmpty ? input[altKey] : null);
    if (value == null) return '';
    return value.toString().trim();
  }

  int? _parseInt(Map<String, dynamic> input, String key) =>
      _coerceInt(input[key]);

  int? _coerceInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  List<int> _parseIntList(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final nums = <int>[];
    for (final item in raw) {
      final parsed = _coerceInt(item);
      if (parsed != null) {
        nums.add(parsed);
      }
    }
    return nums;
  }

  int _clampListChaptersLimit(int? raw) {
    if (raw == null || raw <= 0) {
      return _listChaptersDefaultLimit;
    }
    if (raw > _listChaptersMaxLimit) {
      return _listChaptersMaxLimit;
    }
    return raw;
  }

  Map<String, dynamic> _chapterListEntry(Map<String, dynamic> raw) {
    return <String, dynamic>{
      'id': raw['id'],
      'chapter_num': _coerceInt(raw['chapter_num']),
      'title': raw['title'],
      'word_count': _coerceInt(raw['word_count']) ?? 0,
      'updated_at': raw['updated_at'],
    };
  }

  ({List<Map<String, dynamic>> chapters, int matchedCount}) _filterChapters(
    List<Map<String, dynamic>> chapters, {
    required List<int> chapterNums,
    int? fromChapterNum,
    int? toChapterNum,
    String title = '',
    required int limit,
  }) {
    var filtered = chapters;
    if (chapterNums.isNotEmpty) {
      final wanted = chapterNums.toSet();
      filtered = [
        for (final chapter in filtered)
          if (wanted.contains(_coerceInt(chapter['chapter_num']))) chapter,
      ];
    } else if (fromChapterNum != null || toChapterNum != null) {
      final from = fromChapterNum ?? 1;
      final to = toChapterNum ?? 0x7fffffff;
      filtered = [
        for (final chapter in filtered)
          if (_inChapterRange(chapter, from, to)) chapter,
      ];
    } else if (title.isEmpty) {
      filtered = [...filtered]
        ..sort((a, b) {
          final aAt = _parseUpdatedAt(a['updated_at']);
          final bAt = _parseUpdatedAt(b['updated_at']);
          return bAt.compareTo(aAt);
        });
    }
    if (title.isNotEmpty) {
      final needle = title.toLowerCase();
      filtered = [
        for (final chapter in filtered)
          if (_titleContains(chapter, needle)) chapter,
      ];
    }
    final matchedCount = filtered.length;
    final sliced = [
      for (final chapter in filtered.take(limit)) _chapterListEntry(chapter),
    ];
    return (chapters: sliced, matchedCount: matchedCount);
  }

  bool _titleContains(Map<String, dynamic> chapter, String needle) {
    final value = chapter['title']?.toString() ?? '';
    return value.toLowerCase().contains(needle);
  }

  bool _inChapterRange(Map<String, dynamic> chapter, int from, int to) {
    final number = _coerceInt(chapter['chapter_num']);
    return number != null && number >= from && number <= to;
  }

  DateTime _parseUpdatedAt(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<Map<String, dynamic>> _handleListNovels() async {
    final novels = await listNovelsCallback();
    return {'ok': true, 'novels': novels, 'count': novels.length};
  }

  Future<Map<String, dynamic>> _handleStartJob(
    Map<String, dynamic> input,
  ) async {
    final novelId = _parseString(input, 'novel_id', altKey: 'novelId');
    final seed = _parseString(input, 'seed');
    if (novelId.isEmpty || seed.isEmpty) {
      return {'ok': false, 'error': 'novel_id and seed are required'};
    }
    final result = await startJobCallback(novelId, seed);
    return {'ok': true, ...result};
  }

  Future<Map<String, dynamic>> _handleJobStatus(
    Map<String, dynamic> input,
  ) async {
    final jobId = _parseString(input, 'job_id', altKey: 'jobId');
    if (jobId.isEmpty) {
      return {'ok': false, 'error': 'job_id is required'};
    }
    final status = await jobStatusCallback(jobId);
    return {'ok': true, ...status};
  }

  Future<Map<String, dynamic>> _handleSendToJob(
    Map<String, dynamic> input,
  ) async {
    final jobId = _parseString(input, 'job_id', altKey: 'jobId');
    final text = _parseString(input, 'text');
    if (jobId.isEmpty || text.isEmpty) {
      return {'ok': false, 'error': 'job_id and text are required'};
    }
    final result = await sendToJobCallback(jobId, text);
    return {'ok': true, ...result};
  }

  Future<Map<String, dynamic>> _handleCreateNovel(
    Map<String, dynamic> input,
  ) async {
    final title = _parseString(input, 'title');
    if (title.isEmpty) {
      return {'ok': false, 'error': 'title is required'};
    }
    final novelData = <String, dynamic>{
      'title': title,
      'description': _parseString(input, 'description'),
      'author_name': _parseString(input, 'author_name', altKey: 'authorName'),
      'category': _parseString(input, 'category'),
    };
    final type = _parseString(input, 'type');
    if (type.isNotEmpty) {
      novelData['type'] = type;
    }
    final tags = input['tags'];
    if (tags is List) {
      novelData['tags'] = tags.map((t) => t.toString()).toList();
    }
    final result = await createNovelCallback(novelData);
    return {'ok': result['ok'] != false, ...result};
  }

  Future<Map<String, dynamic>> _handleEditNovel(
    Map<String, dynamic> input,
  ) async {
    final novelId = _parseString(input, 'novel_id', altKey: 'novelId');
    if (novelId.isEmpty) {
      return {'ok': false, 'error': 'novel_id is required'};
    }
    final fields = <String, dynamic>{};
    for (final key in [
      'title',
      'description',
      'author_name',
      'category',
      'type',
    ]) {
      final value = _parseString(input, key);
      if (value.isNotEmpty) {
        fields[key] = value;
      }
    }
    final tags = input['tags'];
    if (tags is List) {
      fields['tags'] = tags.map((t) => t.toString()).toList();
    }
    final result = await editNovelCallback(novelId, fields);
    return {'ok': result['ok'] != false, ...result};
  }

  Future<Map<String, dynamic>> _handleListChapters(
    Map<String, dynamic> input,
  ) async {
    final novelId = _parseString(input, 'novel_id', altKey: 'novelId');
    if (novelId.isEmpty) {
      return {'ok': false, 'error': 'novel_id is required'};
    }
    final fromChapterNum = _parseInt(input, 'from_chapter_num');
    final toChapterNum = _parseInt(input, 'to_chapter_num');
    if (fromChapterNum != null && fromChapterNum < 1) {
      return {'ok': false, 'error': 'from_chapter_num must be >= 1'};
    }
    if (toChapterNum != null && toChapterNum < 1) {
      return {'ok': false, 'error': 'to_chapter_num must be >= 1'};
    }
    if (fromChapterNum != null &&
        toChapterNum != null &&
        fromChapterNum > toChapterNum) {
      return {
        'ok': false,
        'error': 'from_chapter_num must be <= to_chapter_num',
      };
    }
    final result = await listChaptersCallback(novelId);
    if (result['ok'] == false) {
      return {'ok': false, ...result};
    }
    final rawChapters = result['chapters'];
    if (rawChapters is! List) {
      return {'ok': false, 'error': 'list_chapters returned invalid chapters'};
    }
    final chapters = [
      for (final item in rawChapters)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
    final filtered = _filterChapters(
      chapters,
      chapterNums: _parseIntList(input['chapter_nums'] ?? input['chapterNums']),
      fromChapterNum: fromChapterNum,
      toChapterNum: toChapterNum,
      title: _parseString(input, 'title'),
      limit: _clampListChaptersLimit(_parseInt(input, 'limit')),
    );
    return {
      'ok': true,
      'novel_id': result['novel_id'] ?? novelId,
      if (result['title'] != null) 'title': result['title'],
      'chapters': filtered.chapters,
      'matched_count': filtered.matchedCount,
    };
  }
}
