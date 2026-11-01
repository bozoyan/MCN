// 职责: 验证 Codemode 根据明确更新标志记录改动，成功的简短回执不产生不确定写入。
// 关联文件:
//   lib/shared/services/ai/codemode/orchestrator.dart
//   lib/shared/services/ai/codemode/runtime.dart
//   lib/shared/agent/agent_tool_dispatcher.dart
//   lib/shared/models/ai_nested_tool_call.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/models/ai_nested_tool_call.dart';
import 'package:reveric/shared/services/ai/codemode/orchestrator.dart';
import 'package:reveric/shared/services/ai/codemode/runtime.dart';
import 'package:reveric/shared/services/ai/codemode/scheduler.dart';

void main() {
  for (final sample in [
    (result: <String, dynamic>{'ok': true}, effect: AiToolEffectStatus.none),
    (
      result: <String, dynamic>{'ok': true, 'updated': false},
      effect: AiToolEffectStatus.none,
    ),
    (
      result: <String, dynamic>{'ok': true, 'updated': true},
      effect: AiToolEffectStatus.confirmed,
    ),
    (
      result: <String, dynamic>{'ok': false, 'error_code': 'write_failed'},
      effect: AiToolEffectStatus.unknown,
    ),
    (
      result: <String, dynamic>{
        'ok': true,
        'updated': true,
        'failed': {
          'write_failed': {'count': 1},
        },
      },
      effect: AiToolEffectStatus.unknown,
    ),
  ]) {
    test(
      'write outcome ${sample.result} preserves success and mutation facts',
      () async {
        final scheduler = CodemodeScheduler(maxActive: 1);
        addTearDown(scheduler.dispose);
        final dispatcher = _Dispatcher();
        AiNestedToolCall? record;
        final result = await CodemodeOrchestrator().execute(
          input: {'code': 'script'},
          context: ToolExecutionContext(
            sessionId: 'session',
            sourceSessionId: 'session',
            sourceTurnId: 'turn',
          ),
          parentToolCallId: 'parent',
          tools: dispatcher,
          runTool: (call, context) async {
            context.lifecycleObserver!.onStarted!(null);
            context.lifecycleObserver!.onFinished!(sample.result, null);
            return sample.result;
          },
          onRecord: (next) => record = next,
          scheduler: scheduler,
          isAllowed: () => true,
          allowedToolNames: dispatcher.allToolNames,
          runtimeFactory: _Runtime.new,
        );
        expect(record!.effectStatus, sample.effect);
        expect(
          record!.status,
          sample.result['ok'] == true
              ? AiNestedToolStatus.success
              : AiNestedToolStatus.error,
        );
        expect(result['completed_count'], sample.result['ok'] == true ? 1 : 0);
        expect(
          result['completed_operations'],
          hasLength(sample.result['updated'] == true ? 1 : 0),
        );
        expect(
          result['uncertain_operations'],
          hasLength(sample.effect == AiToolEffectStatus.unknown ? 1 : 0),
        );
        expect(
          result.containsKey('verification_required'),
          sample.effect == AiToolEffectStatus.unknown,
        );
      },
    );
  }
}

class _Dispatcher implements AgentToolDispatcher {
  @override
  List<String> allToolNames() => ['Write'];

  @override
  List<ToolDef> allToolDefs() => const [
    ToolDef(name: 'Write', description: '', inputSchema: {'type': 'object'}),
  ];

  @override
  List<ToolDef> toolDefsForNames(List<String> names) =>
      allToolDefs().where((tool) => names.contains(tool.name)).toList();

  @override
  Future<Map<String, dynamic>> executeTool({
    required String name,
    required Map<String, dynamic> input,
    String? callId,
    bool emitEvents = true,
    ToolExecutionContext? context,
  }) => throw UnimplementedError();
}

// 只替换 JS 宿主，实际排队、生命周期、结果归类及摘要均经过生产 Orchestrator。
class _Runtime extends FjsRuntime {
  @override
  Future<void> get settled => Future.value();

  @override
  Future<CodemodeRuntimeResult> run({
    required String code,
    required List<ToolDef> tools,
    required Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> input,
    )
    executeTool,
    Future<Map<String, dynamic>> Function(
      String method,
      Map<String, dynamic> input,
    )?
    discover,
    bool Function(String name)? isDynamicTool,
    AgentCancellationToken? cancellationToken,
    String Function()? cancellationErrorCode,
    void Function(String? errorCode)? onTerminate,
    void Function(String name, Map<String, dynamic> input, String errorCode)?
    onRejectedTool,
    CodemodeRuntimeLimits limits = const CodemodeRuntimeLimits(),
  }) async {
    final result = await executeTool('Write', {
      'path': 'profile/title',
      'value': 'title',
    });
    return CodemodeRuntimeResult(
      output: [result],
      callCount: 1,
      completedCount: result['ok'] == true ? 1 : 0,
      failedCount: result['ok'] == true ? 0 : 1,
    );
  }
}
