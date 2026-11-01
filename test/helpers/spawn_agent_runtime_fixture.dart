// 职责: 为会话子运行测试提供真实内存持久化和可控制初始化、模型响应的子任务。
// 关联文件:
//   lib/shared/services/ai/spawn_agent_handler.dart
//   lib/shared/services/ai/session_persistence.dart
//   lib/shared/agent/fake_agent.dart
import 'plugin_host.dart';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:reveric/shared/agent/agent_config.dart';
import 'package:reveric/shared/agent/agent_context_manager.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/subagent.dart';
import 'package:reveric/shared/services/ai/prompt_template.dart';
import 'package:reveric/shared/services/ai/session_persistence.dart';
import 'package:reveric/shared/services/ai/codemode/scheduler.dart';
import 'package:reveric/shared/services/ai/spawn_agent_handler.dart';

class SpawnAgentRuntimeFixture {
  final codemodeScheduler = CodemodeScheduler(maxActive: 1);
  final appDb = AppDatabase.forTest(NativeDatabase.memory());
  final novelDb = NovelContentDatabase.forTest(NativeDatabase.memory());
  late final persistence = AiSessionPersistenceService(
    appDb,
    'novel',
    novelContentDatabase: novelDb,
  );

  Future<void> initialize() async {
    await PromptTemplateService.loadAll();
    for (final id in ['parent', 'other_parent']) {
      await persistence.createActiveSession(
        id: id,
        title: id,
        provider: 'provider',
        model: 'model',
        mode: 'chat',
        agentSlug: 'orchestrator',
      );
    }
  }

  ControlledSubAgent child({
    String parentSessionId = 'parent',
    bool blockInitialization = false,
    bool blockSave = false,
    bool failInitialization = false,
  }) => ControlledSubAgent(
    this,
    parentSessionId: parentSessionId,
    blockInitialization: blockInitialization,
    blockSave: blockSave,
    failInitialization: failInitialization,
  );

  Future<void> dispose() async {
    codemodeScheduler.dispose();
    await novelDb.close();
    await appDb.close();
  }
}

class ControlledSubAgent {
  ControlledSubAgent(
    SpawnAgentRuntimeFixture fixture, {
    required String parentSessionId,
    required bool blockInitialization,
    required bool blockSave,
    required bool failInitialization,
  }) {
    client = FakeProviderClient(
      responder: (_) async {
        if (!requestEntered.isCompleted) {
          requestEntered.complete();
        }
        return response.future;
      },
    );
    final persistence = _SaveGatePersistence(
      fixture.appDb,
      'novel',
      novelContentDatabase: fixture.novelDb,
      entered: saveEntered,
      release: saveRelease,
      blocked: blockSave,
    );
    handler = SpawnAgentHandler(
      pluginHost: emptyPluginHost(),
      codemodeScheduler: fixture.codemodeScheduler,
      workContext: AiSessionContext(
        workId: 'novel',
        contentKind: contentKindNovel,
      ),
      availableSubAgents: const [
        SubAgent(
          id: 'writer',
          slug: 'writer',
          name: 'Writer',
          description: 'writer',
          prompt: 'Write the requested text.',
          scope: SubAgentScope.global,
          sortOrder: 0,
        ),
      ],
      agentConfig: const AgentConfig(),
      defaultProviderId: 'provider',
      defaultModel: 'model',
      parentSessionId: parentSessionId,
      persistence: persistence,
      novelDatabase: fixture.novelDb,
      resourcesResolver:
          ({
            required providerId,
            required model,
            required subSessionId,
            required sourceSessionId,
          }) async {
            initializationEntered.complete();
            if (blockInitialization) {
              await initializationRelease.future;
            }
            if (failInitialization) {
              throw StateError('test resource acquisition failed');
            }
            return SpawnAgentResources(
              client: client,
              toolManager: FakeAgentToolDispatcher(),
              release: () => releases++,
            );
          },
      contextSupplementForSession: (_) async => [],
    );
  }

  late final SpawnAgentHandler handler;
  late final FakeProviderClient client;
  final initializationEntered = Completer<void>();
  final initializationRelease = Completer<void>();
  final requestEntered = Completer<void>();
  final response = Completer<FakeProviderClientResponse>();
  final saveEntered = Completer<void>();
  final saveRelease = Completer<void>();
  int releases = 0;

  void finish([String text = 'done']) {
    response.complete(FakeProviderClientResponse.text(text));
  }
}

class _SaveGatePersistence extends AiSessionPersistenceService {
  _SaveGatePersistence(
    super.appDatabase,
    super.novelId, {
    required super.novelContentDatabase,
    required this.entered,
    required this.release,
    required this.blocked,
  });

  final Completer<void> entered;
  final Completer<void> release;
  final bool blocked;

  @override
  Future<void> saveMessages({
    required String sessionId,
    required List<AiMessage> messages,
    required NovelContentDatabase novelDatabase,
    AgentContextSnapshot? contextSnapshot,
  }) async {
    if (!entered.isCompleted) {
      entered.complete();
    }
    if (blocked) {
      await release.future;
    }
    await super.saveMessages(
      sessionId: sessionId,
      messages: messages,
      novelDatabase: novelDatabase,
      contextSnapshot: contextSnapshot,
    );
  }
}
