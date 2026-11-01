// 职责: 验证开场请求在目标会话被订阅后初始化，跨帧不会丢失自动发送所需的就绪态。
// 关联文件:
//   lib/desktop/widgets/ai/chat/handoff_activation.dart
//   lib/shared/providers/ai_providers.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/desktop/widgets/ai/chat/handoff_activation.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';

void main() {
  testWidgets('handoff waits for target subscription and initializes once', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [aiSettingsProvider.overrideWithValue(AiSettings.defaults())],
    );
    addTearDown(container.dispose);
    var initialized = 0;
    String? selected;
    Future<void> render(String active) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _Harness(
          active: active,
          onSelect: (id) async => selected = id,
          onReady: () {
            initialized++;
            container
                .read(aiChatSessionProvider('target').notifier)
                .startNewSession(sessionId: 'target');
          },
        ),
      ),
    );
    await render('previous');
    expect(selected, 'target');
    // 模拟父级会话解析晚于当前帧，未订阅的 autoDispose provider 会被回收。
    await container.pump();
    expect(initialized, 0);
    await render('target');
    await container.pump();
    expect(container.read(aiChatSessionProvider('target')).isLoaded, isTrue);
    expect(initialized, 1);
    await render('target');
    await tester.pump();
    expect(initialized, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _Harness extends HookConsumerWidget {
  const _Harness({
    required this.active,
    required this.onSelect,
    required this.onReady,
  });
  final String active;
  final Future<void> Function(String?) onSelect;
  final VoidCallback onReady;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(aiChatSessionProvider(active));
    useHandoffActivation(
      requestId: 'request',
      targetSessionId: 'target',
      activeSessionId: active,
      onSelectSession: onSelect,
      onReady: onReady,
    );
    return const SizedBox.shrink();
  }
}
