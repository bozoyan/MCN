// 职责: Memory 自动提取服务 — 从对话记录中提取用户偏好、事实、决策、风格、世界观、角色信息
// 关联文件:
//   lib/shared/services/ai/chat.dart
//   lib/shared/services/ai/memory_service.dart
//   lib/shared/database/daos/memory_dao.dart
//   lib/shared/database/novel_content_daos/ai_chat_message_dao.dart

import 'dart:async';
import 'dart:convert';

import '../../database/app_database.dart';
import '../../database/novel_content_database.dart';
import '../../models/ai_chat_models.dart';
import '../../logger/app_logger.dart';
import '../../utils/random_id.dart';
import 'chat.dart';

final _log = AppLogger.forModule('MemoryExtraction');

/// 一次提取（拿 client + 补全）的上限。后台任务超时后跳过本轮，不要把调度器卡住。
const Duration memoryExtractionTimeout = Duration(seconds: 60);

class ExtractedMemoryItem {
  final String category;
  final String content;
  final double confidence;

  const ExtractedMemoryItem({
    required this.category,
    required this.content,
    this.confidence = 0.8,
  });
}

const _extractionSystemPrompt = '''
你是一个记忆提取助手。你的任务是从用户和AI助手的对话中提取重要信息，形成结构化的记忆条目。

## 记忆分类
- preference: 用户的偏好、习惯、审美取向
- fact: 关于小说世界观、设定、角色、剧情的确定事实
- decision: 用户做出的创作决策、方向选择
- style: 用户期望的写作风格、语气、叙事方式
- worldview: 世界观设定、规则体系、魔法/科技体系
- character: 角色设定、性格、关系、背景

## 提取规则
1. 只提取明确、确定的信息，不要推测或编造
2. 每条记忆应简洁明了，一句话表达，避免冗余修饰
3. 优先提取用户主动表达的偏好和决策，其次提取从对话中明确推断出的事实
4. 如果已有类似记忆，只补充新的或不同的信息，不要重复
5. 忽略闲聊、问候、技术故障排查、临时性表达（如"今天累了"）等无长期价值的内容
6. 每条记忆用中文书写
7. 对于可能随时间变化的信息（如"正在考虑..."），标记为低置信度
8. 同一条信息不要拆分为多条记忆，保持原子性

## 置信度
- high (0.9): 用户明确、反复强调的信息
- medium (0.7): 用户提及一次但态度明确的信息
- low (0.5): 用户提及但态度模糊或可能变化的信息

## 输出格式
返回 JSON 数组，每个元素包含 category、content 和 confidence：
```json
[
  {"category": "preference", "content": "用户喜欢第一人称视角叙事", "confidence": 0.9},
  {"category": "fact", "content": "主角林风是一名退役特种兵", "confidence": 0.7}
]
```
如果没有值得提取的信息，返回空数组 []。''';

String _buildExtractionUserPrompt(
  String conversationText,
  String existingMemoryText,
) {
  final buffer = StringBuffer();
  buffer.writeln('## 对话记录');
  buffer.writeln(conversationText);

  if (existingMemoryText.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('## 已有记忆（避免重复提取相同或相似信息）');
    buffer.writeln(existingMemoryText);
  }

  buffer.writeln();
  buffer.writeln('请从上述对话中提取值得长期保存的记忆条目。注意：');
  buffer.writeln('- 不要提取与已有记忆重复或高度相似的信息');
  buffer.writeln('- 每条记忆必须是独立、完整、可理解的事实或偏好');
  buffer.writeln('- 优先提取对后续创作有指导意义的信息');
  return buffer.toString().trim();
}

String _formatConversation(List<_ConversationMessage> messages) {
  final buffer = StringBuffer();
  for (final msg in messages) {
    final roleLabel = switch (msg.role) {
      'user' => '用户',
      'assistant' => 'AI',
      _ => msg.role,
    };
    buffer.writeln('[$roleLabel]: ${msg.content}');
    buffer.writeln();
  }
  return buffer.toString().trim();
}

class _ConversationMessage {
  final String role;
  final String content;
  const _ConversationMessage({required this.role, required this.content});
}

class MemoryExtractionService {
  MemoryExtractionService({
    required this._appDb,
    required this._clientFactory,
    this._timeout = memoryExtractionTimeout,
  });

  final AppDatabase _appDb;
  final Future<AiClient?> Function() _clientFactory;
  final Duration _timeout;

  Future<List<Memory>> extractFromChat({
    required String novelId,
    required NovelContentDatabase contentDb,
    int maxSessions = 3,
    int maxMessagesPerSession = 30,
  }) async {
    final sessions = await _appDb.aiChatSessionDao.getByNovel(
      novelId,
      limit: maxSessions,
    );
    if (sessions.isEmpty) {
      if (_log.isDebugEnabled) {
        _log.debug('no sessions for novelId=$novelId');
      }
      return const [];
    }

    final allMessages = <_ConversationMessage>[];
    for (final session in sessions) {
      final msgs = await contentDb.aiChatMessageDao.getBySession(session.id);
      final recent = msgs.length > maxMessagesPerSession
          ? msgs.sublist(msgs.length - maxMessagesPerSession)
          : msgs;
      for (final msg in recent) {
        final role = msg.role;
        final content = msg.content.trim();
        if (content.isEmpty) continue;
        if (role == 'system' || role == 'tool') continue;
        allMessages.add(
          _ConversationMessage(role: role, content: _truncate(content, 800)),
        );
      }
    }

    if (allMessages.isEmpty) {
      _log.debug('no messages to extract from');
      return const [];
    }

    final existingMemories = await _appDb.memoryDao.getMemoriesForPrompt(
      novelId: novelId,
    );
    final existingMemoryText = existingMemories
        .map((m) => '- [${m.category}] ${m.content}')
        .join('\n');

    final conversationText = _formatConversation(allMessages);
    final userPrompt = _buildExtractionUserPrompt(
      conversationText,
      existingMemoryText,
    );

    try {
      final clock = Stopwatch()..start();
      final client = await _clientFactory().timeout(_remaining(clock));
      if (client == null) {
        _log.debug('no AI client available');
        return const [];
      }

      final response = await client.chatCompletionDetached([
        AiMessage.system(id: 'ext_sys', content: _extractionSystemPrompt),
        AiMessage.user(id: 'ext_usr', content: userPrompt),
      ], timeout: _remaining(clock));

      final items = _parseResponse(response);
      if (items.isEmpty) {
        _log.debug('no new memories extracted');
        return const [];
      }

      return await _saveExtractedMemories(items, novelId, existingMemories);
    } on TimeoutException catch (e, stack) {
      _log.error('LLM timed out', error: e, stackTrace: stack);
      return const [];
    } catch (e, stack) {
      _log.error('LLM error: $e', error: e, stackTrace: stack);
      return const [];
    }
  }

  Duration _remaining(Stopwatch clock) {
    final left = _timeout - clock.elapsed;
    if (left <= Duration.zero) {
      throw TimeoutException('memoryExtraction', _timeout);
    }
    return left;
  }

  Future<List<Memory>> _saveExtractedMemories(
    List<ExtractedMemoryItem> items,
    String novelId,
    List<Memory> existing,
  ) async {
    final created = <Memory>[];
    for (final item in items) {
      if (item.content.trim().isEmpty) continue;

      final isDuplicate = existing.any((m) {
        return _similarity(m.content, item.content) > 0.6;
      });
      if (isDuplicate) continue;

      final isDuplicateInBatch = created.any((c) {
        return _similarity(c.content, item.content) > 0.6;
      });
      if (isDuplicateInBatch) continue;

      final id = buildRandomId('mem');
      final dateTimeNow = DateTime.now();
      await _appDb.memoryDao.create(
        id: id,
        category: item.category,
        content: item.content.trim(),
        novelId: novelId,
        priority: item.confidence >= 0.9
            ? memoryPriorityCore
            : memoryPriorityContext,
        source: memorySourceAutoExtracted,
        enabled: true,
        sortOrder: 0,
      );

      created.add(
        Memory(
          id: id,
          novelId: novelId,
          category: item.category,
          priority: item.confidence >= 0.9
              ? memoryPriorityCore
              : memoryPriorityContext,
          content: item.content.trim(),
          source: memorySourceAutoExtracted,
          sourceSessionId: null,
          enabled: true,
          sortOrder: 0,
          createdAt: dateTimeNow,
          updatedAt: dateTimeNow,
          deletedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      existing.add(created.last);
    }

    if (created.isNotEmpty) {
      _log.info('created ${created.length} new memories for novelId=$novelId');
    }
    return created;
  }

  static List<ExtractedMemoryItem> _parseResponse(String response) {
    final trimmed = response.trim();
    if (trimmed.isEmpty || trimmed == '[]') return const [];

    try {
      var jsonStr = trimmed;
      final codeBlockMatch = RegExp(
        r'```(?:json)?\s*([\s\S]*?)\s*```',
      ).firstMatch(trimmed);
      if (codeBlockMatch != null) {
        jsonStr = codeBlockMatch.group(1)!.trim();
      }

      final arrayMatch = RegExp(r'\[\s*\{[\s\S]*\}\s*\]').firstMatch(jsonStr);
      if (arrayMatch != null) {
        jsonStr = arrayMatch.group(0)!;
      }

      final List<dynamic> parsed = jsonDecode(jsonStr) as List<dynamic>;
      return parsed
          .map((item) {
            final map = item as Map<String, dynamic>;
            var category = (map['category'] as String? ?? '').toLowerCase();
            final content = (map['content'] as String? ?? '').trim();
            final confidence = (map['confidence'] as num?)?.toDouble() ?? 0.7;

            if (!_validCategories.contains(category)) {
              category = memoryCategoryFact;
            }

            return ExtractedMemoryItem(
              category: category,
              content: content,
              confidence: confidence.clamp(0.0, 1.0),
            );
          })
          .where((item) => item.content.isNotEmpty)
          .toList();
    } catch (e) {
      _log.error('failed to parse response: $e', error: e);
      return const [];
    }
  }

  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final aChars = a.runes.toList();
    final bChars = b.runes.toList();
    if (aChars.length < 2 || bChars.length < 2) {
      return a == b ? 1.0 : 0.0;
    }

    final aGrams = <String>{};
    for (var i = 0; i < aChars.length - 1; i++) {
      aGrams.add(String.fromCharCodes(aChars.sublist(i, i + 2)));
    }
    final bGrams = <String>{};
    for (var i = 0; i < bChars.length - 1; i++) {
      bGrams.add(String.fromCharCodes(bChars.sublist(i, i + 2)));
    }

    final intersection = aGrams.intersection(bGrams).length;
    final union = aGrams.union(bGrams).length;
    if (union == 0) return 0.0;
    return intersection / union;
  }

  static String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  static const _validCategories = {
    memoryCategoryPreference,
    memoryCategoryFact,
    memoryCategoryDecision,
    memoryCategoryStyle,
    memoryCategoryWorldview,
    memoryCategoryCharacter,
  };
}
