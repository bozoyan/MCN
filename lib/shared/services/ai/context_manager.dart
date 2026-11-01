// 职责: AiContextManager — 单发 chatCompletion 路径的上下文构建（历史窗口、摘要、引用截断）
// 关联文件:
//   lib/shared/models/ai_chat_models.dart
//   lib/shared/services/ai/context_models.dart
//   lib/shared/agent/token_estimator.dart
import '../../agent/token_estimator.dart';
import '../../models/ai_chat_models.dart';
import 'context_models.dart';

class AiContextManagerConfig {
  const AiContextManagerConfig({
    this.historyMessageLimit = 12,
    this.outlineCharLimit = 2200,
    this.chapterContentCharLimit = 4000,
    this.referenceSectionCharLimit = 1800,
  });

  final int historyMessageLimit;
  final int outlineCharLimit;
  final int chapterContentCharLimit;
  final int referenceSectionCharLimit;
}

class AiManagedConversation {
  const AiManagedConversation({required this.messages, required this.summary});

  final List<AiMessage> messages;
  final String? summary;
}

class AiContextManager {
  const AiContextManager({this.config = const AiContextManagerConfig()});

  final AiContextManagerConfig config;

  AiManagedConversation buildConversation(
    List<AiMessage> history, {
    required String systemPrompt,
  }) {
    final cleaned = history
        .where((message) => !message.isStreaming)
        .where((message) => message.content.trim().isNotEmpty)
        .toList();

    final retained = _retainRecentMessages(cleaned);
    final summary = _buildSummary(cleaned, retained);

    return AiManagedConversation(
      summary: summary,
      messages: [
        AiMessage.system(id: 'sys_ctx', content: systemPrompt),
        if (summary != null && summary.isNotEmpty)
          AiMessage.system(id: 'sys_history', content: summary),
        ...retained,
      ],
    );
  }

  AiSessionContext compactContext(AiSessionContext context) {
    return context.copyWith(
      chapterOutline: _truncate(
        context.chapterOutline,
        config.outlineCharLimit,
      ),
      chapterContent: _truncate(
        context.chapterContent,
        config.chapterContentCharLimit,
      ),
      outline: _truncate(context.outline, config.referenceSectionCharLimit),
      previousContent: _truncate(
        context.previousContent,
        config.referenceSectionCharLimit,
      ),
      characterProfiles: _truncateList(
        context.characterProfiles,
        config.referenceSectionCharLimit,
      ),
      worldbuildingNotes: _truncateList(
        context.worldbuildingNotes,
        config.referenceSectionCharLimit,
      ),
      materialNotes: _truncateList(
        context.materialNotes,
        config.referenceSectionCharLimit,
      ),
    );
  }

  List<AiMessage> _retainRecentMessages(List<AiMessage> messages) {
    // 不再截断消息内容——userPrompt 被 messageCharLimit=1600 砍掉会伤害记忆提取。
    final retained = <AiMessage>[];
    for (final message in messages.reversed) {
      if (retained.length >= config.historyMessageLimit) {
        break;
      }
      retained.add(message);
    }
    return retained.reversed.toList();
  }

  String? _buildSummary(List<AiMessage> all, List<AiMessage> retained) {
    if (all.isEmpty || retained.length >= all.length) {
      return null;
    }

    final cutoffIds = retained.map((message) => message.id).toSet();
    final older = all
        .where((message) => !cutoffIds.contains(message.id))
        .toList();
    if (older.isEmpty) {
      return null;
    }

    final lines = <String>[];
    var userCount = 0;
    var assistantCount = 0;

    for (final message in older) {
      final content = _truncate(message.content, 240);
      if (content == null || content.isEmpty) {
        continue;
      }
      if (message.role == AiMessageRole.user) {
        userCount++;
      } else if (message.role == AiMessageRole.assistant) {
        assistantCount++;
      }
      lines.add('${_roleLabel(message.role)}：$content');
    }

    if (lines.isEmpty) {
      return null;
    }

    final buffer = StringBuffer();
    buffer.writeln('以下是更早对话的压缩摘要，请延续其中已经确认的创作方向与约束。');
    buffer.writeln('早期对话统计：用户 $userCount 条，助手 $assistantCount 条。');
    buffer.writeln();
    for (final line in lines) {
      buffer.writeln('- $line');
    }

    final summary = buffer.toString().trim();
    return _truncate(summary, config.outlineCharLimit);
  }

  String _roleLabel(AiMessageRole role) {
    return switch (role) {
      AiMessageRole.user => '用户',
      AiMessageRole.assistant => '助手',
      AiMessageRole.system => '系统',
    };
  }

  List<String> _truncateList(List<String> values, int maxChars) {
    if (values.isEmpty || maxChars <= 0) {
      return values;
    }
    final retained = <String>[];
    var used = 0;
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final next = trimmed.length + (retained.isEmpty ? 0 : 1);
      if (retained.isNotEmpty && used + next > maxChars) {
        break;
      }
      if (retained.isEmpty && trimmed.length > maxChars) {
        retained.add(safeTruncate(trimmed, maxChars).trimRight());
        break;
      }
      retained.add(trimmed);
      used += next;
    }
    return retained;
  }

  /// 截断字符串到 maxChars，使用 rune 安全截断（不劈开 UTF-16 代理对）。
  String? _truncate(String? value, int maxChars) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || maxChars <= 0) {
      return trimmed;
    }
    if (trimmed.length <= maxChars) {
      return trimmed;
    }
    const suffix = '\n[已截断]';
    final safeLength = maxChars - suffix.length;
    if (safeLength <= 0) {
      return safeTruncate(trimmed, maxChars);
    }
    return '${safeTruncate(trimmed, safeLength).trimRight()}$suffix';
  }
}

extension AiContextManagerChapterSnapshotX on AiChapterContextSnapshot {
  AiChapterContextSnapshot compact(AiContextManager manager) {
    final compacted = manager.compactContext(toSessionContext());
    return copyWith(
      chapterOutline: compacted.chapterOutline ?? '',
      content: compacted.chapterContent ?? '',
      outline: compacted.outline ?? '',
      previousContent: compacted.previousContent,
      characterProfiles: compacted.characterProfiles,
      worldbuildingNotes: compacted.worldbuildingNotes,
      materialNotes: compacted.materialNotes,
    );
  }
}
