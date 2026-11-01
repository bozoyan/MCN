// 职责: 提供共享工具权限服务、规则流与会话待审批请求，并核对作品内的分集归属。
// 关联文件:
//   lib/shared/services/tool_permissions.dart
//   lib/shared/agent/tool_approval.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/providers/settings_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../agent/tool_approval.dart';
import '../services/tool_permissions.dart';
import '../database/app_database.dart';
import '../models/tool_permission.dart';
import 'ai_providers.dart';
import 'novel_providers.dart';

final toolPermissionServiceProvider = Provider<ToolPermissionService>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return ToolPermissionService(
    database,
    episodeExists: (workId, episodeId) async {
      final work = await database.novelDao.get(workId);
      final path = work?.contentDatabasePath;
      if (path == null || path.isEmpty) {
        return false;
      }
      final content = ref.read(novelContentDatabaseProvider(path));
      return await content.screenplayDao.getEpisode(episodeId) != null;
    },
  );
});

final toolPermissionRulesProvider = StreamProvider.autoDispose
    .family<List<ToolPermissionRule>, ToolPermissionScope>((ref, scope) {
      return ref
          .watch(toolPermissionServiceProvider)
          .database
          .toolPermissionDao
          .watch(scope);
    });

/// 某会话等待用户决定的审批请求；审批卡、运行条和悬浮球共用这一份。
final pendingToolApprovalsProvider = StreamProvider.autoDispose
    .family<List<AiToolApprovalRequest>, String>((ref, sessionId) async* {
      final approvals = ref.watch(aiToolApprovalControllerProvider);
      yield approvals.pendingFor(sessionId);
      yield* approvals.stream.map((_) => approvals.pendingFor(sessionId));
    });
