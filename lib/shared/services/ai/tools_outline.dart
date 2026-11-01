// 职责: 定位 AI 大纲与节拍操作的目标，并执行创建、写入、编辑和单拍删除。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_read.dart
//   lib/shared/services/ai/tools_write.dart
//   lib/shared/services/working_overlay.dart
//   lib/shared/models/outline.dart
// ignore_for_file: use_null_aware_elements
part of 'tools.dart';

/// 将稳定 beat ID 绑定到当前大纲中的实际拍及显示顺序。
class _LocatedOutlineTarget {
  const _LocatedOutlineTarget(
    this.parsed,
    this.outline, {
    this.beat,
    required this.beatIndex,
  });
  final ParsedPath parsed;
  final OutlineDraft outline;
  final OutlineBeatDraft? beat;
  final int? beatIndex;
}

class _ParsedOutlineBeats {
  const _ParsedOutlineBeats._({required this.value, this.error});

  factory _ParsedOutlineBeats.value(List<OutlineBeatDraft> value) {
    return _ParsedOutlineBeats._(value: value);
  }

  factory _ParsedOutlineBeats.error(String error) {
    return _ParsedOutlineBeats._(
      value: const <OutlineBeatDraft>[],
      error: error,
    );
  }

  final List<OutlineBeatDraft> value;
  final String? error;
}

mixin _AiToolManagerOutlineMixin on _AiToolManagerBase {
  Future<({_LocatedOutlineTarget? target, Map<String, dynamic>? error})>
  _locateOutline(ParsedPath parsed) async {
    final title = parsed.locator('title')!;
    final outline = await _contentService.outlineService.getByTitle(title);
    if (outline == null) {
      return (
        target: null,
        error: _resourceError(
          parsed.displayPath,
          ToolErrorCode.not_found,
          'Outline not found: outlines/$title',
        ),
      );
    }
    final working = await _readOutlineWithWorkingOverlay(outline);
    final beatId = parsed.outlineBeatId;
    final index = beatId == null
        ? null
        : working.beats.indexWhere((beat) => beat.id == beatId);
    if (index == -1) {
      return (
        target: null,
        error: _resourceError(
          parsed.displayPath,
          ToolErrorCode.not_found,
          'Beat $beatId was not found in this outline.',
          hint:
              'Read ${_resourceReferencePath('outlines/$title/beats')} and copy an existing ID path.',
        ),
      );
    }
    return (
      target: _LocatedOutlineTarget(
        parsed,
        working,
        beat: index == null ? null : working.beats[index],
        beatIndex: index,
      ),
      error: null,
    );
  }

  Future<OutlineDraft> _readOutlineWithWorkingOverlay(
    OutlineDraft outline,
  ) async {
    return outline;
  }

  // ---------------------------------------------------------------------------
  // CreateOutline
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _handleCreateOutline(
    Map<String, dynamic> input, {
    String toolName = 'CreateOutline',
  }) async {
    final title = input['title'] as String;
    final finalStatus = input['status'] as String? ?? outlineStatusPending;

    final content = input['content'] as String? ?? '';
    final startChapterNum = input['start_chapter_num'] as int? ?? 1;
    final rawBeats = input['beats'] as List<dynamic>? ?? const [];
    final beats = _parseOutlineBeats(rawBeats);
    if (beats.error != null) {
      return AiToolManager._structuredWriteError(
        path: 'outlines',
        errorCode: ToolErrorCode.invalid_argument,
        message: beats.error!,
        operation: 'create',
      );
    }
    final newDocId = await _contentService.outlineService.createOutline(
      defaultTitle: title,
      content: content,
      status: finalStatus,
      startChapterNum: startChapterNum,
      beats: beats.value,
    );
    final created = await _contentService.outlineService.getByDocumentId(
      newDocId,
    );
    if (created == null) {
      throw StateError('Created outline was not found: $newDocId');
    }
    final effectiveTitle = created.title;

    final previewText = [
      effectiveTitle,
      if (content.isNotEmpty) content,
      '状态：$finalStatus',
      '起始章节：$startChapterNum',
      if (rawBeats.isNotEmpty) '节拍数：${rawBeats.length}',
    ].join('\n\n');
    await _stageCreateChange(
      resourcePath: 'outlines/$newDocId',
      resourceType: 'outlines',
      resourceId: newDocId,
      previewText: previewText,
      source: workingChangeSourceAi,
      toolName: toolName,
      summary: 'AI created outline $effectiveTitle',
    );
    return {
      'path': 'outlines/$effectiveTitle',
      'id': newDocId,
      'created': true,
    };
  }

  // ---------------------------------------------------------------------------
  // Outline scalar fields and beat resource patches via Write
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _writeOutlineFields(
    ParsedPath parsed,
    Map<String, dynamic> fields,
  ) async {
    final located = await _locateOutline(parsed);
    if (located.error != null) {
      return located.error!;
    }
    return parsed.isOutlineBeat
        ? _writeOutlineBeatFields(located.target!, fields)
        : _writeOutlineDocumentFields(located.target!, fields);
  }

  /// 公共校验后的字段一次提交，沿用独立字段的审阅与历史恢复路径。
  Future<Map<String, dynamic>> _writeOutlineDocumentFields(
    _LocatedOutlineTarget target,
    Map<String, dynamic> fields,
  ) async {
    final outline = target.outline;
    final changes = <WorkingTextChangeRequest>[];
    for (final entry in fields.entries) {
      final oldText = switch (entry.key) {
        'title' => outline.title,
        'content' => outline.content,
        'status' => outline.status,
        'start_chapter_num' => outline.startChapterNum.toString(),
        _ => throw StateError(
          'Unsupported normalized outline field: ${entry.key}',
        ),
      };
      final newText = entry.value.toString();
      if (oldText == newText) {
        continue;
      }
      changes.add(
        WorkingTextChangeRequest(
          resourcePath: 'outlines/${outline.documentId}/${entry.key}',
          resourceType: 'outlines',
          resourceId: outline.documentId,
          field: entry.key,
          oldText: oldText,
          newText: newText,
          summary: 'AI updated outline ${entry.key}',
        ),
      );
    }
    await _stageTextChangesAtomically(
      changes: changes,
      source: workingChangeSourceAi,
      toolName: 'Write',
    );
    return {'path': target.parsed.displayPath, 'updated': changes.isNotEmpty};
  }

  Future<Map<String, dynamic>> _writeOutlineBeatFields(
    _LocatedOutlineTarget target,
    Map<String, dynamic> fields,
  ) async {
    final parsed = target.parsed;
    final beatIndex = target.beatIndex!;
    final outline = target.outline;
    final workingOutline = outline;
    final displayPath = parsed.displayPath;
    final beat = target.beat!;
    // 字段与值已由公共 schema 校验，资源补丁和单字段写入只组装一次目标快照。
    final updatedBeat = beat.copyWith(
      status: fields['status'] as String? ?? beat.status,
      chapterCount: fields['chapter_count'] as int? ?? beat.chapterCount,
    );
    if (updatedBeat.status == beat.status &&
        updatedBeat.chapterCount == beat.chapterCount) {
      return {'path': displayPath, 'updated': false};
    }

    final oldBeatsJson = workingOutline.encodeTimelineJson();
    final newBeats = workingOutline.beats.toList();
    newBeats[beatIndex] = updatedBeat;
    final newBeatsJson = workingOutline
        .copyWith(beats: newBeats)
        .encodeTimelineJson();

    await _stageTextChange(
      resourcePath: 'outlines/${outline.documentId}/beats',
      resourceType: 'outlines',
      resourceId: outline.documentId,
      field: 'beats',
      oldText: oldBeatsJson,
      newText: newBeatsJson,
      source: workingChangeSourceAi,
      toolName: 'Write',
      summary: 'AI updated outline beat $beatIndex ${fields.keys.join(', ')}',
    );
    return {'path': displayPath, 'updated': true};
  }

  /// `Write /outlines/{title}/beats` —— 整表替换节拍。
  ///
  /// 走 Write 而不是 Edit：Edit 的契约是 old_text/new_text 文本 diff，节拍是结构化
  /// 数组，没有可 diff 的文本；「整体覆盖」本来就是 Write 的语义。追加单拍走
  /// `Create /outlines/{title}/beats`。
  Future<Map<String, dynamic>> _writeOutlineBeats(
    ParsedPath parsed,
    Map<String, dynamic> fields,
  ) async {
    final located = await _locateOutline(parsed);
    if (located.error != null) {
      return located.error!;
    }
    return _replaceOutlineBeats(
      located.target!,
      fields['beats'] as List<dynamic>,
    );
  }

  // ---------------------------------------------------------------------------
  // Outline editing — dedicated outline editing with beat support
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _handleEditOutline(
    ParsedPath parsed,
    String oldText,
    String newText,
    bool replaceAll,
  ) async {
    final located = await _locateOutline(parsed);
    if (located.error != null) {
      return located.error!;
    }
    return parsed.isOutlineBeat
        ? _editOutlineBeat(located.target!, oldText, newText, replaceAll)
        : _editOutlineDocument(located.target!, oldText, newText, replaceAll);
  }

  _ParsedOutlineBeats _parseOutlineBeats(
    List<dynamic> rawBeats, {
    List<OutlineBeatDraft>? currentBeats,
  }) {
    final current = {
      for (final beat in currentBeats ?? <OutlineBeatDraft>[]) beat.id: beat,
    };
    final ids = <String>{};
    final beats = <OutlineBeatDraft>[];
    for (var i = 0; i < rawBeats.length; i++) {
      final raw = rawBeats[i] as Map<String, dynamic>;
      OutlineBeatDraft? existing;
      if (raw.containsKey('id')) {
        final id = raw['id'];
        if (currentBeats == null ||
            id is! String ||
            id.trim().isEmpty ||
            !ids.add(id) ||
            !current.containsKey(id)) {
          return _ParsedOutlineBeats.error(
            'Invalid beats[$i].id: use a unique ID from the current outline listing; omit id to create a beat.',
          );
        }
        existing = current[id];
      }
      final base = existing ?? _contentService.outlineService.createBeatDraft();
      beats.add(
        base.copyWith(
          title: raw['title'] as String? ?? '',
          content: raw['content'] as String? ?? '',
          status: raw['status'] as String? ?? outlineStatusPending,
          chapterCount: raw['chapter_count'] as int? ?? 1,
          sortOrder: i,
        ),
      );
    }
    return _ParsedOutlineBeats.value(beats);
  }

  Future<Map<String, dynamic>> _removeOutlineBeat(
    _LocatedOutlineTarget target,
  ) async {
    final outline = target.outline;
    final remaining = outline.beats
        .where((beat) => beat.id != target.beat!.id)
        .toList();
    final ordered = [
      for (var index = 0; index < remaining.length; index++)
        remaining[index].copyWith(sortOrder: index),
    ];
    await _stageTextChange(
      resourcePath: 'outlines/${outline.documentId}/beats',
      resourceType: 'outlines',
      resourceId: outline.documentId,
      field: 'beats',
      oldText: outline.encodeTimelineJson(),
      newText: outline.copyWith(beats: ordered).encodeTimelineJson(),
      source: workingChangeSourceAi,
      toolName: 'Remove',
      summary: 'AI removed outline beat',
    );
    return {
      'ok': true,
      'path': target.parsed.displayPath,
      'id': target.beat!.id,
      'removed': true,
      'parent_path': 'outlines/${target.parsed.locator('title')}/beats',
      'beat_count': ordered.length,
    };
  }

  Future<Map<String, dynamic>> _replaceOutlineBeats(
    _LocatedOutlineTarget target,
    List<dynamic> rawBeats,
  ) async {
    final outline = target.outline;
    final pathStr = target.parsed.locator('title')!;
    final parsedBeats = _parseOutlineBeats(
      rawBeats,
      currentBeats: outline.beats,
    );
    if (parsedBeats.error != null) {
      return AiToolManager._structuredWriteError(
        path: 'outlines/$pathStr/beats',
        errorCode: ToolErrorCode.invalid_argument,
        message: parsedBeats.error!,
        operation: 'write',
      );
    }

    final workingOutline = outline;
    if (outlineBeatsHaveSameContent(workingOutline.beats, parsedBeats.value)) {
      return {
        'path': 'outlines/$pathStr/beats',
        'updated': false,
        'beat_count': parsedBeats.value.length,
      };
    }
    final newBeatsJson = workingOutline
        .copyWith(beats: parsedBeats.value)
        .encodeTimelineJson();
    await _stageTextChange(
      resourcePath: 'outlines/${outline.documentId}/beats',
      resourceType: 'outlines',
      resourceId: outline.documentId,
      field: 'beats',
      oldText: workingOutline.encodeTimelineJson(),
      newText: newBeatsJson,
      source: workingChangeSourceAi,
      toolName: 'Write',
      summary: 'AI replaced outline beats',
    );
    return {
      'path': 'outlines/$pathStr/beats',
      'updated': true,
      'beat_count': parsedBeats.value.length,
      // 整表替换是破坏性的：模型可能想追加一拍却覆盖了全表，回报覆盖前的数量
      // 让它在下一轮看得见。
      'previous_beat_count': workingOutline.beats.length,
    };
  }

  Future<Map<String, dynamic>> _editOutlineDocument(
    _LocatedOutlineTarget target,
    String oldText,
    String newText,
    bool replaceAll,
  ) async {
    final outline = target.outline;
    final workingOutline = outline;
    final pathStr = target.parsed.locator('title')!;
    final field = target.parsed.field!;
    final current = field == 'title'
        ? workingOutline.title
        : workingOutline.content;

    final updated = AiToolManager._replaceExactText(
      current,
      oldText,
      newText,
      path: 'outlines/$pathStr/$field',
      replaceAll: replaceAll,
    );
    if (updated.error != null) {
      return AiToolManager._replaceTextErrorResult(updated);
    }

    await _stageTextChange(
      resourcePath: 'outlines/${outline.documentId}/$field',
      resourceType: 'outlines',
      resourceId: outline.documentId,
      field: field,
      oldText: current,
      newText: updated.value!,
      source: workingChangeSourceAi,
      toolName: 'Edit',
      summary: 'AI edited outline $field',
    );
    return {
      'path': 'outlines/$pathStr/$field',
      'edited': updated.changed,
      'match_count': updated.matchCount,
    };
  }

  Future<Map<String, dynamic>> _editOutlineBeat(
    _LocatedOutlineTarget target,
    String oldText,
    String newText,
    bool replaceAll,
  ) async {
    final outlinePath = target.parsed.locator('title')!;
    final field = target.parsed.field!;
    final beatIndex = target.beatIndex!;
    final draft = target.outline;
    final workingDraft = draft;
    final beat = target.beat!;
    final current = field == 'title' ? beat.title : beat.content;

    final updated = AiToolManager._replaceExactText(
      current,
      oldText,
      newText,
      path: 'outlines/$outlinePath/beats/${beat.id}/$field',
      replaceAll: replaceAll,
    );
    if (updated.error != null) {
      return AiToolManager._replaceTextErrorResult(updated);
    }

    final oldBeatsJson = workingDraft.encodeTimelineJson();
    final newBeats = workingDraft.beats.toList();
    newBeats[beatIndex] = newBeats[beatIndex].copyWith(
      title: field == 'title' ? (updated.value ?? current) : beat.title,
      content: field == 'content' ? (updated.value ?? current) : beat.content,
    );
    final newBeatsJson = workingDraft
        .copyWith(beats: newBeats)
        .encodeTimelineJson();

    await _stageTextChange(
      resourcePath: 'outlines/${draft.documentId}/beats',
      resourceType: 'outlines',
      resourceId: draft.documentId,
      field: 'beats',
      oldText: oldBeatsJson,
      newText: newBeatsJson,
      source: workingChangeSourceAi,
      toolName: 'Edit',
      summary: 'AI edited outline beat $beatIndex $field',
    );
    return {
      'path': 'outlines/$outlinePath/beats/${beat.id}/$field',
      'edited': updated.changed,
      'match_count': updated.matchCount,
    };
  }

  // ---------------------------------------------------------------------------
  // CreateBeat — add a new beat to an existing outline
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _handleCreateBeat(
    _LocatedOutlineTarget target,
    Map<String, dynamic> input, {
    String toolName = 'CreateBeat',
  }) async {
    final outlineTitle = target.parsed.locator('title')!;
    final outline = target.outline;
    final title = input['title'] as String;
    final workingOutline = outline;
    final content = input['content'] as String? ?? '';
    final chapterCount = input['chapter_count'] as int? ?? 1;
    final insertIndex = (input['index'] as int? ?? workingOutline.beats.length)
        .clamp(0, workingOutline.beats.length);
    final finalStatus = input['status'] as String? ?? outlineStatusPending;

    final newBeat = _contentService.outlineService.createBeatDraft(
      title: title,
      content: content,
      status: finalStatus,
      chapterCount: chapterCount,
      sortOrder: insertIndex,
    );

    // 插入后按位置重编号 sortOrder。落库的 replaceBeats 本来就按下标重写，这里
    // 对齐是为了内存态不留下重复的 sortOrder：新 beat 与原本占该位置的 beat 会拿到
    // 同一个值，一旦后续有人按 sortOrder 排一次序（List.sort 不保证稳定），插入
    // 位置就会变成不可复现的随机结果。
    final newBeats =
        (workingOutline.beats.toList()..insert(insertIndex, newBeat))
            .asMap()
            .entries
            .map((entry) => entry.value.copyWith(sortOrder: entry.key))
            .toList(growable: false);

    final change = await _stageTextChange(
      resourcePath: 'outlines/${outline.documentId}/beats',
      resourceType: 'outlines',
      resourceId: outline.documentId,
      field: 'beats',
      oldText: workingOutline.encodeTimelineJson(),
      newText: workingOutline.copyWith(beats: newBeats).encodeTimelineJson(),
      source: workingChangeSourceAi,
      toolName: toolName,
      summary: 'AI created beat $title in outline $outlineTitle',
    );

    final persistedBeat = decodeTimelineJson(change.newText!)[insertIndex];

    return {
      'ok': true,
      'path': 'outlines/$outlineTitle/beats/${persistedBeat.id}',
      'id': persistedBeat.id,
      'outline_title': outlineTitle,
      'beat_title': title,
      'beat_index': insertIndex,
      'created': true,
    };
  }
}
