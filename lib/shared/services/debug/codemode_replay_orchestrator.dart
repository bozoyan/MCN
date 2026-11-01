// 职责: 调试重放批量处理脚本 — 不经过模型，用独立工具管理器把一段 Codemode 源码在当前作品里再跑一遍
// 关联文件:
//   lib/shared/services/ai/codemode/orchestrator.dart
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/working_overlay.dart
//   lib/shared/widgets/ai/tools/codemode_detail_dialog.dart

import '../../models/ai_provider.dart';
import '../ai/codemode/orchestrator.dart';
import '../ai/codemode/scheduler.dart';
import '../ai/tools.dart';
import '../novel_content.dart';
import '../working_overlay.dart';

/// 调试用的批量处理重放。
///
/// 用来反复复现一次 AI 回合的写入效果（例如画布的逐个揭示动画），不用每次都
/// 重新问模型。写入照常走工作区，画布写入照常经 [canvasActivityReporter] 背压；
/// 不带会话归属，也不经过 Agent 的工具钩子。
class CodemodeReplayOrchestrator {
  Future<Map<String, dynamic>> run({
    required String code,
    required NovelContentService contentService,
    required WorkingOverlayService workingOverlayService,
    required CodemodeScheduler scheduler,
    required Future<List<AiProvider>> Function() providerReader,
    AiCanvasActivityReporter? canvasActivityReporter,
  }) {
    final toolManager = AiToolManager(
      contentService,
      workingOverlayService: workingOverlayService,
      providerReader: providerReader,

      canvasActivityReporter: canvasActivityReporter,
    )..registerAllTools();
    return CodemodeOrchestrator().execute(
      input: {'code': code},
      context: ToolExecutionContext(),
      parentToolCallId: 'debug_replay',
      tools: toolManager,
      runTool: (call, context) => toolManager.executeTool(
        name: call.toolName,
        input: call.arguments,
        callId: call.callId,
        context: context,
      ),
      onRecord: (_) {},
      scheduler: scheduler,
      isAllowed: () => true,
      allowedToolNames: toolManager.allToolNames,
    );
  }
}
