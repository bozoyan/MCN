// 职责: 移动端「助手」Tab 只读会话浏览的 Provider — 跨作品的各模式（chat/council/monologue/theater/roleplay）会话列表 + 单会话消息加载（薄包装 shared 持久化层）。
// 关联文件:
//   lib/mobile/pages/chat_page.dart
//   lib/mobile/pages/chat_session_page.dart
//   lib/mobile/features/council/page.dart
//   lib/mobile/features/monologue/page.dart
//   lib/mobile/features/theater/page.dart
//   lib/mobile/features/roleplay/page.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/services/ai/session_persistence.dart
//   lib/shared/models/ai_chat_models.dart
//   lib/mobile/widgets/ai_session_history_sheet.dart
//   lib/shared/database/daos/ai_chat_session_dao.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/database/app_database.dart' show AiChatSession;
import '../../shared/models/ai_chat_models.dart';
import '../../shared/models/ai_session_mode.dart';
import '../../shared/providers/novel_providers.dart';
import '../../shared/services/ai/session_persistence.dart'
    show finalizeAiMessagesToolCallsForPersistence;

/// 作品内某 AI 模式的历史会话，SQL 按 novelId + mode 过滤，[updatedAt] 降序。
typedef MobileNovelModeSessionsRef = ({String novelId, AiSessionMode mode});

final mobileNovelModeSessionsProvider = StreamProvider.autoDispose
    .family<List<AiChatSession>, MobileNovelModeSessionsRef>((ref, arg) {
      final database = ref.watch(appDatabaseProvider);
      return database.aiChatSessionDao.watchHistoryByNovelAndMode(
        arg.novelId,
        arg.mode.value,
      );
    });

/// 跨所有作品的 chat 模式会话，按最近更新排序（只读浏览，不含子会话/特殊模式）。
final mobileChatSessionsProvider =
    StreamProvider.autoDispose<List<AiChatSession>>((ref) {
      final database = ref.watch(appDatabaseProvider);
      return database.aiChatSessionDao.watchRecent(
        limit: 5,
        mode: AiSessionMode.chat.value,
      );
    });

/// 跨所有作品的 council（圆桌会议）会话，按最近更新排序。供各模式页 header 历史入口重开。
final mobileCouncilSessionsProvider =
    StreamProvider.autoDispose<List<AiChatSession>>((ref) {
      final database = ref.watch(appDatabaseProvider);
      return database.aiChatSessionDao.watchRecent(
        limit: 200,
        mode: AiSessionMode.council.value,
      );
    });

/// 跨所有作品的 monologue（独白）会话，按最近更新排序。供独白页 header 历史入口重开。
final mobileMonologueSessionsProvider =
    StreamProvider.autoDispose<List<AiChatSession>>((ref) {
      final database = ref.watch(appDatabaseProvider);
      return database.aiChatSessionDao.watchRecent(
        limit: 200,
        mode: AiSessionMode.monologue.value,
      );
    });

/// 跨所有作品的 theater（小剧场）会话，按最近更新排序。供小剧场页 header 历史入口重开。
final mobileTheaterSessionsProvider =
    StreamProvider.autoDispose<List<AiChatSession>>((ref) {
      final database = ref.watch(appDatabaseProvider);
      return database.aiChatSessionDao.watchRecent(
        limit: 200,
        mode: AiSessionMode.theater.value,
      );
    });

/// 跨所有作品的 roleplay（角色扮演）会话，按最近更新排序。供角色扮演页 header 历史入口重开。
final mobileRoleplaySessionsProvider =
    StreamProvider.autoDispose<List<AiChatSession>>((ref) {
      final database = ref.watch(appDatabaseProvider);
      return database.aiChatSessionDao.watchRecent(
        limit: 200,
        mode: AiSessionMode.roleplay.value,
      );
    });

/// 定位一个会话所需的最小信息：会话 id + 所属作品 id + 作品内容库路径。
typedef MobileChatSessionRef = ({
  String sessionId,
  String novelId,
  String? databasePath,
});

/// 加载单个会话的消息（只读）。消息存于作品内容库，缺少 [databasePath] 时无法加载。
///
/// 加载后调用 [finalizeAiMessagesToolCallsForPersistence] 将独立的 tool_result
/// 合并回 assistant 的工具块，并过滤掉 system 消息，得到适合展示的消息列表。
final mobileSessionMessagesProvider = FutureProvider.autoDispose
    .family<List<AiMessage>, MobileChatSessionRef>((ref, arg) async {
      final databasePath = arg.databasePath;
      if (databasePath == null || databasePath.isEmpty) {
        return const <AiMessage>[];
      }
      final service = ref.watch(
        aiSessionPersistenceServiceProvider(
          novelId: arg.novelId,
          databasePath: databasePath,
        ),
      );
      final novelDatabase = ref.watch(
        novelContentDatabaseProvider(databasePath),
      );
      final data = await service.loadSessionMessages(
        sessionId: arg.sessionId,
        novelDatabase: novelDatabase,
      );
      return finalizeAiMessagesToolCallsForPersistence(
        data.messages,
      ).where((message) => message.role != AiMessageRole.system).toList();
    });
