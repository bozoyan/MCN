// 职责: 验证 AskUser 截止、提醒和回答竞争的业务边界。
// 关联文件:
//   lib/shared/services/ai/pending_ask_user.dart
//   lib/shared/models/ask_user_models.dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ask_user_models.dart';
import 'package:reveric/shared/services/ai/pending_ask_user.dart';

const request = AskUserRequest(
  callId: 'same',
  questions: [
    AskUserQuestion(
      id: 'single',
      question: 'Single',
      options: [
        AskUserOption(label: 'ordinary'),
        AskUserOption(label: 'first', recommended: true),
        AskUserOption(label: 'second', recommended: true),
      ],
    ),
    AskUserQuestion(
      id: 'multi',
      question: 'Multi',
      multiSelect: true,
      options: [
        AskUserOption(label: 'first', recommended: true),
        AskUserOption(label: 'ordinary'),
        AskUserOption(label: 'second', recommended: true),
      ],
    ),
    AskUserQuestion(id: 'text', question: 'Text'),
    AskUserQuestion(
      id: 'none',
      question: 'None',
      options: [AskUserOption(label: 'ordinary')],
    ),
  ],
);

void main() {
  for (final minutes in [5, 15]) {
    test('manual answer at minute $minutes wins and cancels further work', () {
      fakeAsync((async) {
        var reminders = 0;
        final pending = PendingAskUser(
          request: request,
          runId: 1,
          now: async.getClock(DateTime(2026)).now,
          onReminder: (_) {
            reminders++;
          },
        )..start();
        async.elapse(Duration(minutes: minutes));
        pending.complete(
          const AskUserResult(
            ok: true,
            answers: [AskUserAnswer(questionId: 'text', answer: 'manual')],
          ),
        );
        pending.cancel();
        async.elapse(const Duration(hours: 1));
        pending.future.then((result) {
          expect(result.resolution, isNull);
          expect(result.answers!.single.answer, 'manual');
        });
        async.flushMicrotasks();
        expect(reminders, minutes < 10 ? 0 : 1);
        expect(async.pendingTimers, isEmpty);
      });
    });
  }

  test(
    'reminds once and completes mixed questions without inventing answers',
    () {
      fakeAsync((async) {
        var reminders = 0;
        AskUserResult? result;
        final pending = PendingAskUser(
          request: request,
          runId: 1,
          now: async.getClock(DateTime(2026)).now,
          onReminder: (_) {
            reminders++;
          },
        );
        pending.future.then((value) => result = value);
        pending.start();
        async.elapse(const Duration(minutes: 10));
        pending.checkDeadline();
        expect(reminders, 1);
        async.elapse(const Duration(minutes: 20));
        expect(result!.toJson(), containsPair('resolution', 'timeout'));
        expect(result!.ok, isTrue);
        expect(result!.cancelled, isFalse);
        expect(result!.answers!.map((a) => a.selectedOptions), [
          ['first'],
          ['first', 'second'],
        ]);
        expect(result!.unansweredQuestionIds, ['text', 'none']);
        expect(async.pendingTimers, isEmpty);
      });
    },
  );

  test('late submit checks wall deadline before accepting a draft', () {
    fakeAsync((async) {
      var now = DateTime(2026);
      var reminders = 0;
      final pending = PendingAskUser(
        request: request,
        runId: 1,
        now: () => now,
        onReminder: (_) {
          reminders++;
        },
      )..start();
      now = now.add(const Duration(minutes: 30));
      pending.complete(
        const AskUserResult(
          ok: true,
          answers: [AskUserAnswer(questionId: 'text', answer: 'draft')],
        ),
      );
      pending.future.then(
        (result) => expect(result.resolution, AskUserResolution.timeout),
      );
      async.flushMicrotasks();
      expect(reminders, 0);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('resume catches up once and cancellation releases both timers', () {
    fakeAsync((async) {
      var now = DateTime(2026);
      var reminders = 0;
      final pending = PendingAskUser(
        request: request,
        runId: 1,
        now: () => now,
        onReminder: (_) {
          reminders++;
        },
      )..start();
      now = now.add(const Duration(minutes: 9));
      pending.checkDeadline();
      expect(reminders, 0);
      now = now.add(const Duration(minutes: 2));
      pending.checkDeadline();
      pending.checkDeadline();
      expect(reminders, 1);
      pending.cancel();
      pending.complete(const AskUserResult(ok: true));
      pending.future.then((result) => expect(result.cancelled, isTrue));
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });
  });
}
