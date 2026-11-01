// 职责: 验证特殊模式资源的初始化、取消、独立标题租约与幂等释放。
// 关联文件:
//   lib/shared/services/ai/mode_run_resources.dart
//   lib/shared/services/ai/chat.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/ai_session_mode.dart';
import 'package:reveric/shared/services/ai/chat.dart';
import 'package:reveric/shared/services/ai/mode_run_resources.dart';

const _model = AiModelOption(
  providerId: 'custom',
  providerDisplayName: 'Test',
  model: 'test',
  kind: AiModelKind.chat,
);
const _second = AiModelOption(
  providerId: 'custom',
  providerDisplayName: 'Test',
  model: 'second',
  kind: AiModelKind.chat,
);

class _Client extends AiClient {
  _Client() : super(aiProviderBuiltinDefaults.first, chatModel: 'test');
  int disposals = 0;
  @override
  void dispose() {
    disposals++;
  }
}

AiModeRunResources _resources(AiModeClientFactory factory) =>
    AiModeRunResources(
      factory: factory,
      selection: AiModeRunSelection(model: _model, memberModels: [_second]),
      context: const AiSessionContext(workId: 'work'),
      sessionId: 'session',
      mode: AiSessionMode.council,
    );

void main() {
  test(
    'clients are shared within one operation and released exactly once',
    () async {
      final clients = <_Client>[];
      var releases = 0;
      final resources = _resources((request) async {
        expect(request.sessionId, 'session');
        expect(request.context.workId, 'work');
        final client = _Client();
        clients.add(client);
        return AiModeOwnedClient(client, () => releases++);
      });
      final main = await resources.mainClient();
      expect(await resources.mainClient(), same(main));
      final member = await resources.memberClient(_second.id);
      expect(member, isNot(same(main)));
      expect(await resources.memberClient(_second.id), same(member));
      await resources.close();
      await resources.close();
      expect(releases, 2);
      expect(clients.map((client) => client.disposals), [1, 1]);
    },
  );

  test('cancelling during initialization closes the late client', () async {
    final pending = Completer<AiModeOwnedClient>();
    final resources = _resources((_) => pending.future);
    final initializing = resources.mainClient();
    final rejected = expectLater(
      initializing,
      throwsA(isA<AiModeRunCancelled>()),
    );
    resources.cancelMain();
    final client = _Client();
    var releases = 0;
    pending.complete(AiModeOwnedClient(client, () => releases++));
    await rejected;
    await resources.close();
    expect(client.disposals, 1);
    expect(releases, 1);
  });

  test(
    'a failed member initialization still releases the main client',
    () async {
      final client = _Client();
      var releases = 0;
      final resources = _resources((request) async {
        if (request.model.id == _second.id) {
          throw const AiModeClientUnavailable();
        }
        return AiModeOwnedClient(client, () => releases++);
      });
      await resources.mainClient();
      expect(await resources.memberClient(_second.id), isNull);
      await resources.close();
      expect(client.disposals, 1);
      expect(releases, 1);
    },
  );

  test('late title owns its client after the main operation closes', () async {
    final clients = <_Client>[];
    var releases = 0;
    final resources = _resources((_) async {
      final client = _Client();
      clients.add(client);
      return AiModeOwnedClient(client, () => releases++);
    });
    await resources.mainClient();
    final title = Completer<String>();
    final started = Completer<void>();
    final pending = resources.withDetachedClient((_) {
      started.complete();
      return title.future;
    });
    await started.future;
    await resources.close();
    expect(clients.map((c) => c.disposals), [1, 0]);
    expect(releases, 1);
    title.complete('Title');
    expect(await pending, 'Title');
    expect(clients.map((c) => c.disposals), [1, 1]);
    expect(releases, 2);
  });

  test('provider teardown closes both main and title clients', () async {
    final clients = <_Client>[];
    var releases = 0;
    final resources = _resources((_) async {
      final client = _Client();
      clients.add(client);
      return AiModeOwnedClient(client, () => releases++);
    });
    await resources.mainClient();
    final started = Completer<void>();
    final title = Completer<String>();
    final pending = resources.withDetachedClient((_) {
      started.complete();
      return title.future;
    });
    await started.future;
    resources.cancelAll();
    await resources.close();
    expect(clients.map((c) => c.disposals), [1, 1]);
    title.complete('Late title');
    await pending;
    expect(releases, 2);
  });
}
