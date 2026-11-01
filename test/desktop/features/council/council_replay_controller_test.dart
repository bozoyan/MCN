// 职责: 验证圆周会议定速重放控制器 — 消息流式推进、用户消息瞬显、停止与总结。
// 关联文件:
//   lib/desktop/features/council/replay_controller.dart
//   lib/shared/models/agent_council_models.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/features/council/replay_controller.dart';
import 'package:reveric/shared/models/agent_council_models.dart';

AgentCouncilSession _session({
  required List<CouncilMessage> messages,
  CouncilSummary? summary,
  bool roundComplete = true,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return AgentCouncilSession(
    id: 'council_1',
    novelId: 'novel_1',
    topic: 'Opening scene',
    participants: const [
      CouncilParticipant(
        id: 'p1',
        name: 'Plot Architect',
        description: '',
        prompt: '',
      ),
      CouncilParticipant(
        id: 'p2',
        name: 'Character Analyst',
        description: '',
        prompt: '',
      ),
    ],
    rounds: [
      CouncilRound(
        roundNumber: 1,
        messages: messages,
        isComplete: roundComplete,
      ),
    ],
    summary: summary,
    phase: CouncilPhase.completed,
    createdAt: now,
    updatedAt: now,
  );
}

CouncilMessage _msg({
  required String id,
  required String participantId,
  required String name,
  required String content,
  int round = 1,
}) {
  return CouncilMessage(
    id: id,
    participantId: participantId,
    participantName: name,
    content: content,
    timestamp: DateTime.utc(2026, 1, 1),
    round: round,
  );
}

void main() {
  test('canReplay is true only when discussion has non-empty content', () {
    final empty = _session(messages: const []);
    expect(CouncilReplayController.canReplay(empty), isFalse);

    final blank = _session(
      messages: [
        _msg(
          id: 'm0',
          participantId: 'p1',
          name: 'Plot Architect',
          content: '   ',
        ),
      ],
    );
    expect(CouncilReplayController.canReplay(blank), isFalse);

    final ready = _session(
      messages: [
        _msg(
          id: 'm1',
          participantId: 'p1',
          name: 'Plot Architect',
          content: 'Hello',
        ),
      ],
    );
    expect(CouncilReplayController.canReplay(ready), isTrue);
  });

  test('streams agent text then commits message at uniform pace', () {
    fakeAsync((async) {
      final controller = CouncilReplayController(
        charsPerTick: 2,
        tickInterval: const Duration(milliseconds: 20),
        messageGap: const Duration(milliseconds: 100),
        summarizingHold: const Duration(milliseconds: 50),
      );
      addTearDown(controller.dispose);

      final source = _session(
        messages: [
          _msg(
            id: 'm1',
            participantId: 'p1',
            name: 'Plot Architect',
            content: 'ABCD',
          ),
        ],
      );

      controller.start(source);
      expect(controller.isReplaying, isTrue);
      expect(controller.snapshot!.session.rounds, isEmpty);

      // messageGap before streaming starts
      async.elapse(const Duration(milliseconds: 100));
      expect(controller.snapshot!.activeRun, isNotNull);
      expect(controller.snapshot!.activeRun!.accumulatedText, isEmpty);

      // 2 ticks → "ABCD"
      async.elapse(const Duration(milliseconds: 20));
      expect(controller.snapshot!.activeRun!.accumulatedText, 'AB');
      async.elapse(const Duration(milliseconds: 20));
      expect(controller.snapshot!.activeRun!.accumulatedText, 'ABCD');

      // next tick commits
      async.elapse(const Duration(milliseconds: 20));
      expect(controller.snapshot!.activeRun, isNull);
      expect(
        controller.snapshot!.session.rounds.single.messages.single.content,
        'ABCD',
      );

      // no summary → finish after gap
      async.elapse(const Duration(milliseconds: 100));
      expect(controller.isReplaying, isFalse);
      expect(controller.snapshot, isNull);
    });
  });

  test('user messages appear instantly without streaming', () {
    fakeAsync((async) {
      final controller = CouncilReplayController(
        charsPerTick: 2,
        tickInterval: const Duration(milliseconds: 20),
        messageGap: const Duration(milliseconds: 50),
        summarizingHold: const Duration(milliseconds: 50),
      );
      addTearDown(controller.dispose);

      final source = _session(
        messages: [
          _msg(
            id: 'u1',
            participantId: '__user__',
            name: 'You',
            content: 'My take',
          ),
          _msg(
            id: 'm1',
            participantId: 'p1',
            name: 'Plot Architect',
            content: 'OK',
          ),
        ],
      );

      controller.start(source);
      // user message commits immediately on begin
      expect(
        controller.snapshot!.session.rounds.single.messages.single.content,
        'My take',
      );
      expect(controller.snapshot!.activeRun, isNull);

      async.elapse(const Duration(milliseconds: 50));
      // agent typing gap then stream
      expect(controller.snapshot!.currentSpeaker?.id, 'p1');
    });
  });

  test('stop clears overlay mid-replay', () {
    fakeAsync((async) {
      final controller = CouncilReplayController(
        charsPerTick: 1,
        tickInterval: const Duration(milliseconds: 20),
        messageGap: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.start(
        _session(
          messages: [
            _msg(
              id: 'm1',
              participantId: 'p1',
              name: 'Plot Architect',
              content: 'Long enough text',
            ),
          ],
        ),
      );
      async.elapse(const Duration(milliseconds: 100));
      expect(controller.isReplaying, isTrue);

      controller.stop();
      expect(controller.isReplaying, isFalse);
      expect(controller.snapshot, isNull);
    });
  });

  test('shows summarizing hold then reveals summary before finish', () {
    fakeAsync((async) {
      final controller = CouncilReplayController(
        charsPerTick: 4,
        tickInterval: const Duration(milliseconds: 10),
        messageGap: const Duration(milliseconds: 20),
        summarizingHold: const Duration(milliseconds: 40),
      );
      addTearDown(controller.dispose);

      final summary = CouncilSummary(
        content: 'Wrap-up',
        timestamp: DateTime.utc(2026, 1, 1),
        coveredThroughRound: 1,
      );
      controller.start(
        _session(
          messages: [
            _msg(
              id: 'm1',
              participantId: 'p1',
              name: 'Plot Architect',
              content: 'Hi',
            ),
          ],
          summary: summary,
        ),
      );

      // gap + one stream tick (full text) + commit tick + gap → summarizing
      async.elapse(const Duration(milliseconds: 20)); // typing gap
      async.elapse(const Duration(milliseconds: 10)); // stream "Hi"
      async.elapse(const Duration(milliseconds: 10)); // commit
      async.elapse(
        const Duration(milliseconds: 20),
      ); // begin next → summarizing

      expect(controller.isReplaying, isTrue);
      expect(controller.snapshot!.isSummarizing, isTrue);
      expect(controller.snapshot!.session.summary, isNull);

      async.elapse(const Duration(milliseconds: 40));
      expect(controller.snapshot!.isSummarizing, isFalse);
      expect(controller.snapshot!.session.summary?.content, 'Wrap-up');

      async.elapse(const Duration(milliseconds: 20));
      expect(controller.isReplaying, isFalse);
      expect(controller.snapshot, isNull);
    });
  });
}
