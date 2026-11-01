// 职责: AiChatSession 模型导出与扩展方法
// 关联文件:
//   lib/shared/database/app_database.dart

import '../database/app_database.dart';

export '../database/app_database.dart'
    show AiChatSession, AiChatSessions, AiChatSessionsCompanion;

extension AiChatSessionX on AiChatSession {
  bool get isEmpty => title.trim().isEmpty;

  bool get hasProvider => provider != null && provider!.isNotEmpty;

  bool get hasModel => model != null && model!.isNotEmpty;

  String get displayTitle {
    final trimmed = title.trim();
    return trimmed.isEmpty ? '未命名对话' : trimmed;
  }

  bool get isChatMode => mode == 'chat';

  bool get isCouncilMode => mode == 'council';

  bool get isMonologueMode => mode == 'monologue';

  bool get isTheaterMode => mode == 'theater';

  bool get isRoleplayMode => mode == 'roleplay';

  bool get hasAgent => agentSlug != null && agentSlug!.isNotEmpty;
}

extension AiChatSessionListX on List<AiChatSession> {
  List<AiChatSession> get sorted =>
      [...this]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<AiChatSession> get enabled =>
      where((s) => s.deletedAt == notDeletedSentinel).toList();
}
