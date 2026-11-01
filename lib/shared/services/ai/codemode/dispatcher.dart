// 职责: 为子 Agent 注册 Codemode，并将脚本执行交给所属运行的编排入口。
// 关联文件:
//   lib/shared/services/ai/spawn_agent_handler.dart
//   lib/shared/services/ai/codemode/tool.dart
//   lib/shared/agent/agent_tool_dispatcher.dart
import '../../../agent/agent_tool_dispatcher.dart';
import 'runtime.dart' show codemodeErrorMessage;
import 'tool.dart';

class CodemodeToolDispatcher implements AgentToolDispatcher {
  const CodemodeToolDispatcher({
    required this.inner,
    required this.runCodemode,
    required this.isAllowed,
  });

  final AgentToolDispatcher inner;
  final bool Function() isAllowed;
  final Future<Map<String, dynamic>> Function(
    Map<String, dynamic> input,
    String callId,
    ToolExecutionContext context,
  )
  runCodemode;

  @override
  Future<Map<String, dynamic>> executeTool({
    required String name,
    required Map<String, dynamic> input,
    String? callId,
    bool emitEvents = true,
    ToolExecutionContext? context,
  }) {
    if (name != codemodeToolName) {
      return inner.executeTool(
        name: name,
        input: input,
        callId: callId,
        emitEvents: emitEvents,
        context: context,
      );
    }
    if (!isAllowed() ||
        callId == null ||
        context == null ||
        context.parentToolCallId != null) {
      return Future.value({
        'ok': false,
        'error_code': 'codemode_tool_forbidden',
        'error': codemodeErrorMessage('codemode_tool_forbidden'),
      });
    }
    return runCodemode(input, callId, context);
  }

  @override
  List<String> allToolNames() => [
    ...inner.allToolNames(),
    if (isAllowed()) codemodeToolName,
  ];

  @override
  List<ToolDef> allToolDefs() => [
    ...inner.allToolDefs(),
    if (isAllowed()) codemodeToolDef,
  ];

  @override
  List<ToolDef> toolDefsForNames(List<String> names) => [
    ...inner.toolDefsForNames(names),
    if (isAllowed() && names.contains(codemodeToolName)) codemodeToolDef,
  ];
}
