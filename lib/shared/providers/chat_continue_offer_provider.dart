// 职责: 记录「刚点新对话时替换掉的那个会话」，供新会话里的延续提议条读取与清除
// 关联文件:
//   lib/shared/widgets/ai/chat/continue_session_offer_bar.dart
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/providers/novel_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/error-handling.md
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../logger/app_logger.dart';
import 'novel_providers.dart';

part 'chat_continue_offer_provider.g.dart';

final _log = AppLogger.forModule('ChatContinueOffer');

/// 点「新对话」时被替换下去的那个会话；新会话据此提议「延续为新对话」。
class ChatContinueOffer {
  const ChatContinueOffer({
    required this.novelId,
    required this.sourceSessionId,
    required this.title,
  });

  final String novelId;
  final String sourceSessionId;
  final String title;
}

/// keepAlive 而非 autoDispose：移动端「新对话」走 `pushReplacement`，旧页面先
/// dispose、新页面后 build，两者之间没有任何 listener，autoDispose 会正好在这个
/// 空档把提议清掉。全局单实例（不是 family），只持有三个字符串，不持有
/// controller / stream / client，提议条显示一次后即 [clear]。
@Riverpod(keepAlive: true)
class ChatContinueOfferNotifier extends _$ChatContinueOfferNotifier {
  @override
  ChatContinueOffer? build() => null;

  void offer(ChatContinueOffer offer) {
    state = offer;
  }

  void clear() {
    state = null;
  }

  /// 点「新对话」后记一次延续提议。
  ///
  /// 来源没有落库消息时不提议——提议条点下去只会拿到「来源对话已不可用」。
  /// 草稿会话（`__new__` / `__handoff_draft__`）还没有真实会话行，同样不提议。
  Future<void> offerAfterNewSession({
    required String novelId,
    required String? sourceSessionId,
    required String sourceTitle,
    required String? databasePath,
  }) async {
    final id = sourceSessionId;
    if (id == null || id.startsWith('__') || databasePath == null) {
      return;
    }
    bool hasMessages;
    try {
      hasMessages = await ref
          .read(novelContentDatabaseProvider(databasePath))
          .aiChatMessageDao
          .hasSavedMessages(id);
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=ai_chat_messages operation=SELECT session=$id error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    if (!ref.mounted || !hasMessages) {
      return;
    }
    offer(
      ChatContinueOffer(
        novelId: novelId,
        sourceSessionId: id,
        title: sourceTitle,
      ),
    );
  }
}
