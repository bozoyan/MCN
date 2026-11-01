// 职责: 在子 Agent 声明和直接执行边界拒绝禁用的 Host 工具。
// 关联文件:
//   lib/shared/services/ai/spawn_agent_handler.dart
//   lib/shared/services/ai/builtin_agent_tools.dart
//   lib/shared/agent/agent_tool_dispatcher.dart
import '../../agent/agent_tool_dispatcher.dart';

class HostToolPolicyDispatcher implements AgentToolDispatcher {
  const HostToolPolicyDispatcher({required this.inner, required this.disabled});
  final AgentToolDispatcher inner;
  final Set<String> disabled;
  @override
  List<String> allToolNames() =>
      inner.allToolNames().where((name) => !disabled.contains(name)).toList();
  @override
  List<ToolDef> allToolDefs() => inner
      .allToolDefs()
      .where((tool) => !disabled.contains(tool.name))
      .toList();
  @override
  List<ToolDef> toolDefsForNames(List<String> names) => inner.toolDefsForNames(
    names.where((name) => !disabled.contains(name)).toList(),
  );
  @override
  Future<Map<String, dynamic>> executeTool({
    required String name,
    required Map<String, dynamic> input,
    String? callId,
    bool emitEvents = true,
    ToolExecutionContext? context,
  }) {
    if (disabled.contains(name)) {
      return Future.value({
        'ok': false,
        'error_code': 'permission_denied',
        'error': 'Host tool $name is disabled for this agent.',
      });
    }
    return inner.executeTool(
      name: name,
      input: input,
      callId: callId,
      emitEvents: emitEvents,
      context: context,
    );
  }
}
