// 职责: 验证智能体模式从持久化恢复时不会覆盖仍在后台运行的内存状态。
// 关联文件:
//   lib/shared/providers/monologue_providers.dart
//   lib/shared/providers/theater_providers.dart
//   lib/shared/providers/roleplay_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_run_state.dart';
import 'package:reveric/shared/models/monologue_models.dart';
import 'package:reveric/shared/models/roleplay_models.dart';
import 'package:reveric/shared/models/theater_models.dart';
import 'package:reveric/shared/providers/monologue_providers.dart';
import 'package:reveric/shared/providers/roleplay_providers.dart';
import 'package:reveric/shared/providers/theater_providers.dart';

const _liveRun = AgentRunState(
  agentId: 'character',
  agentName: 'Character',
  round: 2,
  accumulatedText: 'Live run detail',
  isComplete: true,
);

const _persistedRun = AgentRunState(
  agentId: 'character',
  agentName: 'Character',
  round: 1,
  accumulatedText: 'Persisted run detail',
  isComplete: true,
);

void _expectHistory(
  Map<String, AgentRunState> history, {
  required String key,
  required AgentRunState run,
}) {
  expect(history.keys, [key]);
  expect(history[key]?.accumulatedText, run.accumulatedText);
  expect(history[key]?.round, run.round);
}

void main() {
  final now = DateTime(2026, 8, 4, 15, 42);

  test(
    'monologue hydration preserves live state and initializes absent state',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const participant = MonologueParticipant(
        characterId: 'character',
        name: 'Character',
        role: 'protagonist',
        biography: 'Biography',
      );
      const liveSessionId = 'monologue_live';
      final liveProvider = monologueSessionProvider(liveSessionId);
      final liveNotifier = container.read(liveProvider.notifier);
      final liveSession = MonologueSession(
        id: liveSessionId,
        novelId: 'novel',
        title: 'Live title',
        topic: 'Live topic',
        character: participant,
        phase: MonologuePhase.generating,
        createdAt: now,
        updatedAt: now,
      );
      liveNotifier.setSession(liveSession);
      liveNotifier.restoreRunHistory(const {'live_message': _liveRun});
      container
          .read(monologueRuntimeProvider(liveSessionId).notifier)
          .setProcessing(true);

      final didOverwrite = liveNotifier.restorePersistedSessionIfAbsent(
        session: MonologueSession(
          id: liveSessionId,
          novelId: 'novel',
          title: 'Stale title',
          topic: 'Stale topic',
          character: participant,
          phase: MonologuePhase.generating,
          createdAt: now,
          updatedAt: now,
        ),
        runHistory: const {'stale_message': _persistedRun},
      );

      expect(didOverwrite, isFalse);
      expect(container.read(liveProvider), same(liveSession));
      _expectHistory(
        container.read(monologueRunHistoryStoreProvider(liveSessionId)),
        key: 'live_message',
        run: _liveRun,
      );

      const absentSessionId = 'monologue_absent';
      final absentProvider = monologueSessionProvider(absentSessionId);
      final persistedSession = MonologueSession(
        id: absentSessionId,
        novelId: 'novel',
        topic: 'Persisted topic',
        character: participant,
        phase: MonologuePhase.completed,
        createdAt: now,
        updatedAt: now,
      );
      final didRestore = container
          .read(absentProvider.notifier)
          .restorePersistedSessionIfAbsent(
            session: persistedSession,
            runHistory: const {'persisted_message': _persistedRun},
          );

      expect(didRestore, isTrue);
      expect(container.read(absentProvider), same(persistedSession));
      _expectHistory(
        container.read(monologueRunHistoryStoreProvider(absentSessionId)),
        key: 'persisted_message',
        run: _persistedRun,
      );
    },
  );

  test(
    'theater hydration preserves live state and initializes absent state',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const participant = TheaterParticipant(
        characterId: 'character',
        name: 'Character',
        role: 'protagonist',
        biography: 'Biography',
      );
      const liveSessionId = 'theater_live';
      final liveProvider = theaterSessionProvider(liveSessionId);
      final liveNotifier = container.read(liveProvider.notifier);
      final liveSession = TheaterSession(
        id: liveSessionId,
        novelId: 'novel',
        title: 'Live title',
        sceneDescription: 'Live scene',
        participants: const [participant],
        phase: TheaterPhase.performing,
        createdAt: now,
        updatedAt: now,
      );
      liveNotifier.setSession(liveSession);
      liveNotifier.restoreRunHistory(const {'live_message': _liveRun});
      container
          .read(theaterRuntimeProvider(liveSessionId).notifier)
          .setProcessing(true);

      final didOverwrite = liveNotifier.restorePersistedSessionIfAbsent(
        session: TheaterSession(
          id: liveSessionId,
          novelId: 'novel',
          title: 'Stale title',
          sceneDescription: 'Stale scene',
          participants: const [participant],
          phase: TheaterPhase.performing,
          createdAt: now,
          updatedAt: now,
        ),
        runHistory: const {'stale_message': _persistedRun},
      );

      expect(didOverwrite, isFalse);
      expect(container.read(liveProvider), same(liveSession));
      _expectHistory(
        container.read(theaterRunHistoryStoreProvider(liveSessionId)),
        key: 'live_message',
        run: _liveRun,
      );

      const absentSessionId = 'theater_absent';
      final absentProvider = theaterSessionProvider(absentSessionId);
      final persistedSession = TheaterSession(
        id: absentSessionId,
        novelId: 'novel',
        sceneDescription: 'Persisted scene',
        participants: const [participant],
        phase: TheaterPhase.completed,
        createdAt: now,
        updatedAt: now,
      );
      final didRestore = container
          .read(absentProvider.notifier)
          .restorePersistedSessionIfAbsent(
            session: persistedSession,
            runHistory: const {'persisted_message': _persistedRun},
          );

      expect(didRestore, isTrue);
      expect(container.read(absentProvider), same(persistedSession));
      _expectHistory(
        container.read(theaterRunHistoryStoreProvider(absentSessionId)),
        key: 'persisted_message',
        run: _persistedRun,
      );
    },
  );

  test(
    'roleplay hydration preserves live state and initializes absent state',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const participant = RoleplayParticipant(
        characterId: 'character',
        name: 'Character',
        role: 'protagonist',
        biography: 'Biography',
      );
      const liveSessionId = 'roleplay_live';
      final liveProvider = roleplaySessionProvider(liveSessionId);
      final liveNotifier = container.read(liveProvider.notifier);
      final liveSession = RoleplaySession(
        id: liveSessionId,
        novelId: 'novel',
        title: 'Live title',
        character: participant,
        phase: RoleplayPhase.generating,
        createdAt: now,
        updatedAt: now,
      );
      liveNotifier.setSession(liveSession);
      liveNotifier.restoreRunHistory(const {'live_message': _liveRun});
      container
          .read(roleplayRuntimeProvider(liveSessionId).notifier)
          .setProcessing(true);

      final didOverwrite = liveNotifier.restorePersistedSessionIfAbsent(
        session: RoleplaySession(
          id: liveSessionId,
          novelId: 'novel',
          title: 'Stale title',
          character: participant,
          phase: RoleplayPhase.generating,
          createdAt: now,
          updatedAt: now,
        ),
        runHistory: const {'stale_message': _persistedRun},
      );

      expect(didOverwrite, isFalse);
      expect(container.read(liveProvider), same(liveSession));
      _expectHistory(
        container.read(roleplayRunHistoryStoreProvider(liveSessionId)),
        key: 'live_message',
        run: _liveRun,
      );

      const absentSessionId = 'roleplay_absent';
      final absentProvider = roleplaySessionProvider(absentSessionId);
      final persistedSession = RoleplaySession(
        id: absentSessionId,
        novelId: 'novel',
        character: participant,
        phase: RoleplayPhase.completed,
        createdAt: now,
        updatedAt: now,
      );
      final didRestore = container
          .read(absentProvider.notifier)
          .restorePersistedSessionIfAbsent(
            session: persistedSession,
            runHistory: const {'persisted_message': _persistedRun},
          );

      expect(didRestore, isTrue);
      expect(container.read(absentProvider), same(persistedSession));
      _expectHistory(
        container.read(roleplayRunHistoryStoreProvider(absentSessionId)),
        key: 'persisted_message',
        run: _persistedRun,
      );
    },
  );
}
