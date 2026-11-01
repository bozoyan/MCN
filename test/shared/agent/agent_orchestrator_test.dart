// 职责: 验证通用 Agent 编排器的多轮编号与回调契约
// 关联文件:
//   lib/shared/agent/agent_orchestrator.dart
//   lib/shared/agent/fake_agent.dart
//   lib/shared/models/ai_run_failure.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_hook.dart';
import 'package:reveric/shared/agent/agent_orchestrator.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/models/ai_run_failure.dart';

class _AbortOnStartHook extends AgentHook {
  const _AbortOnStartHook(this.failure);

  final AiRunFailure failure;

  @override
  HookAction<String> onStart(String task) => HookAction.abort(failure);
}

void main() {
  test('startRound is used consistently by every round callback', () async {
    final taskRounds = <int>[];
    final parsedRounds = <int>[];
    final startedRounds = <int>[];
    final outputRounds = <int>[];

    final result = await AgentOrchestrator().runRounds<String, String>(
      participants: const ['agent'],
      buildAgent: (_) async => FakeAgent.create(
        responses: const [
          FakeProviderClientResponse.text('round four'),
          FakeProviderClientResponse.text('round five'),
        ],
      ),
      maxRounds: 2,
      startRound: 4,
      buildRoundTask: (_, round) {
        taskRounds.add(round);
        return 'task $round';
      },
      parseOutput: (_, output, round) {
        parsedRounds.add(round);
        return '$round:$output';
      },
      onRoundBegin: (_, round) {
        startedRounds.add(round);
      },
      onAgentOutput: (round, _, _) {
        outputRounds.add(round);
      },
    );

    expect(taskRounds, [4, 5]);
    expect(parsedRounds, [4, 5]);
    expect(startedRounds, [4, 5]);
    expect(outputRounds, [4, 5]);
    expect(result, [
      ['4:round four'],
      ['5:round five'],
    ]);
  });

  test('AgentError stops the remaining council-style rounds', () async {
    var secondAgentCalls = 0;
    var parseCalls = 0;

    final run = AgentOrchestrator().runRounds<String, String>(
      participants: const ['first', 'second'],
      buildAgent: (participant) async {
        if (participant == 'first') {
          return FakeAgent.create(
            hooks: const [_AbortOnStartHook(AiRunFailure.requestFailed())],
          );
        }
        return FakeAgent.create(
          responder: (_) {
            secondAgentCalls += 1;
            return const FakeProviderClientResponse.text('should not run');
          },
        );
      },
      maxRounds: 2,
      buildRoundTask: (_, round) => 'task $round',
      parseOutput: (_, output, _) {
        parseCalls += 1;
        return output;
      },
      stopOnAgentError: true,
    );

    await expectLater(
      run,
      throwsA(
        isA<AgentOrchestratorFailure>().having(
          (error) => error.failure.kind,
          'failure kind',
          AiRunFailureKind.requestFailed,
        ),
      ),
    );
    expect(secondAgentCalls, 0);
    expect(parseCalls, 0);
  });
}
