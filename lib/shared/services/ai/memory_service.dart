// 职责: Memory 业务服务 — 记忆条目的 CRUD、格式化为 system prompt 片段、按 scope 查询、token 预算控制
// 关联文件:
//   lib/shared/database/daos/memory_dao.dart
//   lib/shared/database/app_database.dart
//   lib/shared/services/ai/prompts.dart
//   lib/shared/agent/agent.dart

import '../../database/app_database.dart';
import '../../database/daos/memory_dao.dart';
import '../../utils/random_id.dart';

export '../../database/app_database.dart'
    show
        Memory,
        MemoriesCompanion,
        memoryPriorityCore,
        memoryPriorityContext,
        memoryCategoryPreference,
        memoryCategoryFact,
        memoryCategoryDecision,
        memoryCategoryStyle,
        memoryCategoryWorldview,
        memoryCategoryCharacter,
        memorySourceManual,
        memorySourceAutoExtracted,
        memorySourceConversation;

const _categoryLabels = <String, String>{
  memoryCategoryPreference: '偏好',
  memoryCategoryFact: '事实',
  memoryCategoryDecision: '决策',
  memoryCategoryStyle: '风格',
  memoryCategoryWorldview: '世界观',
  memoryCategoryCharacter: '角色',
};

const _categoryOrder = <String>[
  memoryCategoryPreference,
  memoryCategoryDecision,
  memoryCategoryStyle,
  memoryCategoryWorldview,
  memoryCategoryCharacter,
  memoryCategoryFact,
];

const int _defaultMaxChars = 3000;

class MemoryService {
  MemoryService(this._db);

  final AppDatabase _db;

  MemoryDao get _dao => _db.memoryDao;

  Future<List<Memory>> getAll() => _dao.getAll();

  Stream<List<Memory>> watchAll() => _dao.watchAll();

  Stream<List<Memory>> watchGlobal() => _dao.watchGlobal();

  Stream<List<Memory>> watchByNovelId(String novelId) =>
      _dao.watchByNovelId(novelId);

  Future<List<Memory>> getMemoriesForPrompt({String? novelId}) =>
      _dao.getMemoriesForPrompt(novelId: novelId);

  Future<Memory?> get(String id) => _dao.get(id);

  Future<String> create({
    required String category,
    required String content,
    String? novelId,
    String priority = memoryPriorityContext,
    String source = memorySourceManual,
    String? sourceSessionId,
    bool enabled = true,
    int sortOrder = 0,
  }) {
    return _dao.create(
      id: buildRandomId('mem'),
      category: category,
      content: content,
      novelId: novelId,
      priority: priority,
      source: source,
      sourceSessionId: sourceSessionId,
      enabled: enabled,
      sortOrder: sortOrder,
    );
  }

  Future<int> updateContent({
    required String id,
    required String content,
    String? category,
    String? priority,
    bool? enabled,
    int? sortOrder,
  }) {
    return _dao.updateContent(
      id: id,
      content: content,
      category: category,
      priority: priority,
      enabled: enabled,
      sortOrder: sortOrder,
    );
  }

  Future<int> softDelete(String id) => _dao.softDelete(id);

  Future<int> hardDelete(String id) => _dao.hardDelete(id);

  Future<void> reorder(List<String> ids) => _dao.reorder(ids);

  static String buildMemoryPromptBlock(
    List<Memory> memories, {
    int maxChars = _defaultMaxChars,
  }) {
    if (memories.isEmpty) return '';

    final coreMemories = memories
        .where((m) => m.priority == memoryPriorityCore)
        .toList();
    final contextMemories = memories
        .where((m) => m.priority == memoryPriorityContext)
        .toList();

    final buffer = StringBuffer();
    buffer.writeln('## 记忆');
    buffer.writeln('以下是关于你和用户之间的重要记忆。请始终遵守这些记忆中的约束和偏好。');

    if (coreMemories.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('### 核心记忆（必须始终遵守）');
      _writeCategoryGrouped(buffer, coreMemories);
    }

    if (contextMemories.isNotEmpty) {
      final remainingChars = maxChars - buffer.length;
      final filtered = _applyTokenBudget(contextMemories, remainingChars);
      if (filtered.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('### 上下文记忆（参考）');
        _writeCategoryGrouped(buffer, filtered);
      }
    }

    final result = buffer.toString().trim();
    if (result.length > maxChars) {
      return result.substring(0, maxChars);
    }
    return result;
  }

  static void _writeCategoryGrouped(
    StringBuffer buffer,
    List<Memory> memories,
  ) {
    final grouped = <String, List<Memory>>{};
    for (final m in memories) {
      grouped.putIfAbsent(m.category, () => []).add(m);
    }

    for (final category in _categoryOrder) {
      final items = grouped[category];
      if (items == null || items.isEmpty) continue;

      final label = _categoryLabels[category] ?? category;
      buffer.writeln();
      buffer.writeln('**$label**');
      for (final m in items) {
        final scope = m.novelId == null ? '[全局]' : '[本小说]';
        buffer.writeln('- $scope ${m.content}');
      }
    }
  }

  static List<Memory> _applyTokenBudget(
    List<Memory> memories,
    int remainingChars,
  ) {
    if (remainingChars <= 0 || memories.isEmpty) return const [];

    final result = <Memory>[];
    var usedChars = 0;

    final grouped = <String, List<Memory>>{};
    for (final m in memories) {
      grouped.putIfAbsent(m.category, () => []).add(m);
    }

    for (final category in _categoryOrder) {
      final items = grouped[category];
      if (items == null) continue;

      for (final m in items) {
        final entrySize = m.content.length + 20;
        if (usedChars + entrySize > remainingChars) break;
        result.add(m);
        usedChars += entrySize;
      }
      if (usedChars >= remainingChars) break;
    }

    return result;
  }
}
