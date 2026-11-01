// 职责: Memory 消化服务 — 周期性整理记忆：去重合并、升级优先级、淘汰过期、冲突检测
// 关联文件:
//   lib/shared/services/ai/chat.dart
//   lib/shared/services/ai/memory_service.dart
//   lib/shared/database/daos/memory_dao.dart

import 'dart:async';
import 'dart:convert';

import '../../database/app_database.dart';
import '../../models/ai_chat_models.dart';
import '../../logger/app_logger.dart';
import '../../utils/random_id.dart';
import 'chat.dart';

final _log = AppLogger.forModule('MemoryDreaming');

/// 拿 client 或每一批消化补全的上限。超时后跳过本批，不要把调度器卡住。
const Duration memoryDreamingTimeout = Duration(seconds: 60);

const _dreamingSystemPrompt = '''
你是一个记忆整理助手。你的任务是审阅一组已记录的长期记忆，进行整理和优化。

## 你需要做的事情
1. **合并重复记忆**：如果多条记忆表达相同或高度相似的信息，合并为一条最清晰的表述
2. **解决矛盾**：如果记忆之间存在矛盾，以较新的记忆为准，删除旧记忆，并在 merged_content 中说明矛盾点
3. **升级核心记忆**：如果某条记忆已经被多次确认或非常重要，应标注为需要升级为核心优先级
4. **补充缺失**：如果从已有的记忆中可以合理推断出缺失的关键信息，可以补充（谨慎使用，仅限明显可推断的信息）
5. **标记过时**：如果某条记忆可能已经过时或不准确，标记为建议删除

## 矛盾检测规则
- 同一主题的偏好变化（如"喜欢第一人称" vs "改用第三人称"）→ 保留较新的
- 事实冲突（如"角色A是主角" vs "角色B是主角"）→ 保留较新的，删除旧的
- 互补信息（如"角色A是战士" + "角色A擅长剑术"）→ 合并为一条

## 输出格式
返回 JSON 对象：
```json
{
  "to_merge": [
    {"keep_index": 0, "merge_indices": [1, 3], "merged_content": "合并后的内容", "reason": "重复信息"}
  ],
  "to_upgrade_core": [2],
  "to_delete": [4],
  "to_add": [{"category": "fact", "content": "新内容", "priority": "context"}]
}
```

其中 index 对应输入记忆列表中每条记忆的序号（从0开始）。
只对确实需要操作的项目进行输出；如果不需要操作，对应字段设为空数组。
每条 to_merge 必须提供 reason 说明合并原因。''';

String _buildDreamingUserPrompt(List<Memory> memories) {
  final buffer = StringBuffer();
  buffer.writeln('## 当前记忆列表');
  buffer.writeln();
  for (var i = 0; i < memories.length; i++) {
    final m = memories[i];
    final sourceLabel = switch (m.source) {
      memorySourceManual => '手动',
      memorySourceAutoExtracted => '自动',
      memorySourceConversation => '对话',
      _ => m.source,
    };
    buffer.writeln(
      '[$i] category=${m.category} priority=${m.priority} source=$sourceLabel content="${m.content}"',
    );
  }
  buffer.writeln();
  buffer.writeln('请审阅以上记忆并进行整理。注意：');
  buffer.writeln('- 仔细检查是否存在语义矛盾或重复，不要遗漏');
  buffer.writeln('- 合并时保留最完整、最准确的表述');
  buffer.writeln('- 只有确实过时或矛盾的记忆才标记删除，不要随意删除');
  buffer.writeln('- 补充新记忆要非常谨慎，仅限从已有记忆中明显可推断的信息');
  return buffer.toString().trim();
}

class _DreamingResult {
  final List<_MergeOp> toMerge;
  final Set<int> toUpgradeCore;
  final Set<int> toDelete;
  final List<_AddOp> toAdd;

  const _DreamingResult({
    this.toMerge = const [],
    this.toUpgradeCore = const {},
    this.toDelete = const {},
    this.toAdd = const [],
  });
}

class _MergeOp {
  final int keepIndex;
  final List<int> mergeIndices;
  final String mergedContent;
  final String reason;
  const _MergeOp({
    required this.keepIndex,
    required this.mergeIndices,
    required this.mergedContent,
    this.reason = '',
  });
}

class _AddOp {
  final String category;
  final String content;
  final String priority;
  const _AddOp({
    required this.category,
    required this.content,
    this.priority = memoryPriorityContext,
  });
}

class MemoryDreamingService {
  MemoryDreamingService({
    required this._appDb,
    required this._clientFactory,
    this._timeout = memoryDreamingTimeout,
  });

  final AppDatabase _appDb;
  final Future<AiClient?> Function() _clientFactory;
  final Duration _timeout;

  static const int _batchSize = 20;

  Future<int> dream({required String novelId}) async {
    final memories = await _appDb.memoryDao.getMemoriesForPrompt(
      novelId: novelId,
    );
    if (memories.length < 2) {
      if (_log.isDebugEnabled) {
        _log.debug('too few memories (${memories.length}), skipping');
      }
      return 0;
    }

    final AiClient client;
    try {
      final resolved = await _clientFactory().timeout(_timeout);
      if (resolved == null) {
        _log.debug('no AI client available');
        return 0;
      }
      client = resolved;
    } on TimeoutException catch (e, stack) {
      _log.error('client init timed out', error: e, stackTrace: stack);
      return 0;
    }

    var totalChanges = 0;

    if (memories.length <= _batchSize) {
      totalChanges = await _dreamBatch(client, memories, novelId);
    } else {
      final coreMemories = memories
          .where((m) => m.priority == memoryPriorityCore)
          .toList();
      final contextMemories = memories
          .where((m) => m.priority == memoryPriorityContext)
          .toList();

      if (coreMemories.length >= 2) {
        totalChanges += await _dreamBatch(client, coreMemories, novelId);
      }

      for (var i = 0; i < contextMemories.length; i += _batchSize) {
        final end = (i + _batchSize > contextMemories.length)
            ? contextMemories.length
            : i + _batchSize;
        final batch = contextMemories.sublist(i, end);
        totalChanges += await _dreamBatch(client, batch, novelId);
      }
    }

    _log.info('done for novelId=$novelId, totalChanges=$totalChanges');
    return totalChanges;
  }

  Future<int> _dreamBatch(
    AiClient client,
    List<Memory> memories,
    String novelId,
  ) async {
    if (memories.length < 2) return 0;

    final userPrompt = _buildDreamingUserPrompt(memories);

    _DreamingResult result;
    try {
      final response = await client.chatCompletionDetached([
        AiMessage.system(id: 'drm_sys', content: _dreamingSystemPrompt),
        AiMessage.user(id: 'drm_usr', content: userPrompt),
      ], timeout: _timeout);
      result = _parseResponse(response, memories);
    } on TimeoutException catch (e, stack) {
      _log.error('LLM timed out', error: e, stackTrace: stack);
      return 0;
    } catch (e, stack) {
      _log.error('LLM error: $e', error: e, stackTrace: stack);
      return 0;
    }

    var changes = 0;
    final deletedIndices = <int>{};

    for (final op in result.toMerge) {
      if (op.keepIndex < 0 || op.keepIndex >= memories.length) continue;
      if (deletedIndices.contains(op.keepIndex)) continue;
      final keep = memories[op.keepIndex];
      try {
        await _appDb.memoryDao.updateContent(
          id: keep.id,
          content: op.mergedContent,
          category: keep.category,
          priority: keep.priority,
        );
        for (final idx in op.mergeIndices) {
          if (idx != op.keepIndex &&
              idx < memories.length &&
              !deletedIndices.contains(idx)) {
            await _appDb.memoryDao.softDelete(memories[idx].id);
            deletedIndices.add(idx);
          }
        }
        changes++;
        if (_log.isDebugEnabled) {
          _log.debug(
            'merged ${op.mergeIndices.length + 1} memories -> ${keep.id}'
            '${op.reason.isNotEmpty ? ' reason=${op.reason}' : ''}',
          );
        }
      } catch (e) {
        _log.error('merge error: $e', error: e);
      }
    }

    for (final idx in result.toUpgradeCore) {
      if (idx < 0 || idx >= memories.length) continue;
      if (deletedIndices.contains(idx)) continue;
      final mem = memories[idx];
      if (mem.priority == memoryPriorityCore) continue;
      try {
        await _appDb.memoryDao.updateContent(
          id: mem.id,
          content: mem.content,
          priority: memoryPriorityCore,
        );
        changes++;
        if (_log.isDebugEnabled) {
          _log.debug('upgraded ${mem.id} to core');
        }
      } catch (e) {
        _log.error('upgrade error: $e', error: e);
      }
    }

    for (final idx in result.toDelete) {
      if (idx < 0 || idx >= memories.length) continue;
      if (deletedIndices.contains(idx)) continue;
      try {
        await _appDb.memoryDao.softDelete(memories[idx].id);
        deletedIndices.add(idx);
        changes++;
        if (_log.isDebugEnabled) {
          _log.debug('deleted ${memories[idx].id}');
        }
      } catch (e) {
        _log.error('delete error: $e', error: e);
      }
    }

    for (final op in result.toAdd) {
      if (op.content.trim().isEmpty) continue;
      try {
        await _appDb.memoryDao.create(
          id: buildRandomId('mem_drm'),
          category: op.category.isNotEmpty ? op.category : memoryCategoryFact,
          content: op.content.trim(),
          novelId: novelId,
          priority: op.priority,
          source: memorySourceAutoExtracted,
          enabled: true,
          sortOrder: 0,
        );
        changes++;
      } catch (e) {
        _log.error('add error: $e', error: e);
      }
    }

    return changes;
  }

  static _DreamingResult _parseResponse(
    String response,
    List<Memory> memories,
  ) {
    final trimmed = response.trim();
    if (trimmed.isEmpty) return const _DreamingResult();

    try {
      var jsonStr = trimmed;
      final codeBlockMatch = RegExp(
        r'```(?:json)?\s*([\s\S]*?)\s*```',
      ).firstMatch(trimmed);
      if (codeBlockMatch != null) {
        jsonStr = codeBlockMatch.group(1)!.trim();
      }

      final objMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
      if (objMatch != null) {
        jsonStr = objMatch.group(0)!;
      }

      final Map<String, dynamic> parsed =
          jsonDecode(jsonStr) as Map<String, dynamic>;

      final toMerge = <_MergeOp>[];
      final mergeList = parsed['to_merge'] as List<dynamic>? ?? [];
      for (final item in mergeList) {
        final map = item as Map<String, dynamic>;
        final keepIndex = map['keep_index'] as int?;
        final mergeIndices =
            (map['merge_indices'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            [];
        final mergedContent = (map['merged_content'] as String? ?? '').trim();
        final reason = (map['reason'] as String? ?? '').trim();
        if (keepIndex != null &&
            mergeIndices.isNotEmpty &&
            mergedContent.isNotEmpty) {
          toMerge.add(
            _MergeOp(
              keepIndex: keepIndex,
              mergeIndices: mergeIndices,
              mergedContent: mergedContent,
              reason: reason,
            ),
          );
        }
      }

      final toUpgradeRaw = parsed['to_upgrade_core'] as List<dynamic>? ?? [];
      final toUpgradeCore = toUpgradeRaw.map((e) => e as int).toSet();

      final toDeleteRaw = parsed['to_delete'] as List<dynamic>? ?? [];
      final toDelete = toDeleteRaw.map((e) => e as int).toSet();

      final toAdd = <_AddOp>[];
      final addList = parsed['to_add'] as List<dynamic>? ?? [];
      for (final item in addList) {
        final map = item as Map<String, dynamic>;
        final category = (map['category'] as String? ?? memoryCategoryFact)
            .toLowerCase();
        final content = (map['content'] as String? ?? '').trim();
        final priority = map['priority'] as String? ?? memoryPriorityContext;
        if (content.isNotEmpty) {
          toAdd.add(
            _AddOp(category: category, content: content, priority: priority),
          );
        }
      }

      return _DreamingResult(
        toMerge: toMerge,
        toUpgradeCore: toUpgradeCore,
        toDelete: toDelete,
        toAdd: toAdd,
      );
    } catch (e) {
      _log.error('failed to parse response: $e', error: e);
      return const _DreamingResult();
    }
  }
}
