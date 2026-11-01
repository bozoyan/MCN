// 职责: 验证跨会话运行名额、排队取消及未收口原生实例不能释放名额。
// 关联文件:
//   lib/shared/services/ai/codemode/scheduler.dart
//   lib/shared/agent/agent_tool_dispatcher.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_tool_dispatcher.dart';
import 'package:reveric/shared/services/ai/codemode/scheduler.dart';

void main() {
  test(
    'two busy runs queue third; cancellation does not leak or create a lease',
    () async {
      final scheduler = CodemodeScheduler(maxActive: 2);
      final first = await scheduler.acquire();
      final second = await scheduler.acquire();
      final cancellation = AgentCancellationController();
      final queued = scheduler.acquire(cancellationToken: cancellation.token);
      final expectation = expectLater(
        queued,
        throwsA(
          isA<CodemodeAdmissionException>().having(
            (e) => e.errorCode,
            'code',
            'user_cancelled',
          ),
        ),
      );
      expect(scheduler.queuedCount, 1);
      cancellation.cancel();
      await expectation;
      expect(scheduler.queuedCount, 0);
      final unsettled = Completer<void>();
      final released = first.releaseAfter(unsettled.future);
      expect(scheduler.activeCount, 2);
      unsettled.complete();
      await released;
      expect(scheduler.activeCount, 1);
      await second.releaseAfter(Future.value());
      expect(scheduler.activeCount, 0);
      scheduler.dispose();
    },
  );

  test('queue is FIFO and full/expired queues return busy', () async {
    final scheduler = CodemodeScheduler(
      maxActive: 1,
      maxQueued: 1,
      waitTimeout: const Duration(milliseconds: 10),
    );
    final active = await scheduler.acquire();
    final queued = scheduler.acquire();
    final expired = expectLater(
      queued,
      throwsA(
        isA<CodemodeAdmissionException>().having(
          (e) => e.errorCode,
          'code',
          'codemode_busy',
        ),
      ),
    );
    await expectLater(
      scheduler.acquire(),
      throwsA(isA<CodemodeAdmissionException>()),
    );
    await expired;
    final next = scheduler.acquire();
    await active.releaseAfter(Future.value());
    final lease = await next;
    expect(scheduler.activeCount, 1);
    await lease.releaseAfter(Future.value());
    scheduler.dispose();
  });

  test(
    'dispose ends queued waiters without releasing unsettled active engines',
    () async {
      final scheduler = CodemodeScheduler(maxActive: 1);
      final lease = await scheduler.acquire();
      final pending = scheduler.acquire();
      final expected = expectLater(
        pending,
        throwsA(isA<CodemodeAdmissionException>()),
      );
      scheduler.dispose();
      await expected;
      expect(scheduler.activeCount, 1);
      await lease.releaseAfter(Future.value());
      expect(scheduler.activeCount, 0);
    },
  );
}
