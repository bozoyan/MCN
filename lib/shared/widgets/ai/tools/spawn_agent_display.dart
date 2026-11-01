// 职责: 从子运行实时状态与已保存的展示快照派生工具卡片状态，保留原模型工具结果。
// 关联文件:
//   lib/shared/providers/spawn_agent_run_providers.dart
//   lib/shared/providers/ai_providers.dart
//   lib/shared/widgets/ai/tool_activity_group.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../models/ai_message_block.dart';
import '../../../providers/spawn_agent_run_providers.dart';

bool isUntrackedBackgroundSpawn(AiToolCallBlock block) =>
    block.toolName == 'SpawnAgent' &&
    block.result?['status'] == 'running' &&
    block.status == AiToolCallStatus.pending;

AiToolCallBlock spawnAgentDisplayBlock(WidgetRef ref, AiToolCallBlock block) {
  if (block.toolName != 'SpawnAgent') {
    return block;
  }
  final display = block.metadata?['background_run'];
  if (block.arguments['background'] == false &&
      block.result?['status'] != 'running' &&
      display is! Map) {
    return block;
  }
  final activeId = ref.watch(
    spawnAgentActiveRunProvider(block.callId).select((run) => run?.agentId),
  );
  final runId =
      block.result?['run_id'] ??
      (display is Map ? display['run_id'] : null) ??
      activeId;
  if (runId == null) {
    // 未登记 run 的参数/启动拒绝保留原始工具错误。
    return block;
  }
  final subSessionId =
      block.result?['session_id'] ??
      (display is Map ? display['session_id'] : null);
  final receipt = <String, dynamic>{
    'status': 'running',
    'run_id': runId,
    'session_id': ?subSessionId,
  };
  if (activeId == runId) {
    return block.copyWith(
      status: AiToolCallStatus.running,
      result: receipt,
      errorMessage: '',
    );
  }
  if (display is Map &&
      display['run_id'] == runId &&
      display['result'] is Map) {
    final result = Map<String, dynamic>.from(display['result'] as Map);
    return block.copyWith(
      status: result['cancelled'] == true
          ? AiToolCallStatus.cancelled
          : result['ok'] == true
          ? AiToolCallStatus.success
          : AiToolCallStatus.error,
      result: result,
      errorMessage: result['error'] as String? ?? '',
    );
  }
  // 重启、卸载后缺少实时实例只表示未在运行，不能推断成功或继续显示转圈。
  return block.copyWith(
    status: AiToolCallStatus.pending,
    result: receipt,
    errorMessage: '',
  );
}
