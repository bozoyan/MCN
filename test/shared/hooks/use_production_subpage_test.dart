// 职责: 验证导演台上下文随页面切换、重命名和卸载更新，旧页面清理不覆盖新页面。
// 关联文件:
//   lib/shared/hooks/use_production_subpage.dart
//   lib/shared/providers/production_view.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/hooks/use_production_subpage.dart';
import 'package:reveric/shared/providers/production_view.dart';

class _Page extends HookConsumerWidget {
  const _Page({super.key, required this.page});
  final ProductionSubpageContext page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useProductionSubpage(ref, 'work', page.label, stagingId: page.stagingId);
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('page identity follows switching, renaming, editing and exit', (
    tester,
  ) async {
    final container = ProviderContainer.test();
    final provider = productionSubpageProvider('work');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    Future<void> show(ProductionSubpageContext? page) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: page == null
              ? const SizedBox.shrink()
              : _Page(key: ValueKey(page.stagingId), page: page),
        ),
      );
      await tester.pump();
      expect(container.read(provider), page);
    }

    const first = (label: 'Director · Courtyard', stagingId: 'stage_a');
    const second = (label: 'Director · Hall', stagingId: 'stage_b');
    await show(first);
    await show(second);
    // 旧页面延迟卸载不能清除已经打开的新调度。
    container.read(provider.notifier).clear(first);
    expect(container.read(provider), second);
    await show((label: 'Director · New hall', stagingId: 'stage_b'));
    await show((label: 'Editing', stagingId: null));
    await show(first);
    await show(null);
    expect(tester.takeException(), isNull);
  });
}
