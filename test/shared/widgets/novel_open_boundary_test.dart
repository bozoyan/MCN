// 职责: 验证作品页面在维护提交结束前不读取内容，保留页面和后台生命周期不释放保护。
// 关联文件:
//   lib/shared/widgets/novel_open_boundary.dart
//   lib/shared/providers/novel_maintenance_providers.dart
//   lib/shared/services/novel_maintenance_coordinator.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/providers/novel_maintenance_providers.dart';
import 'package:reveric/shared/services/novel_maintenance_coordinator.dart';
import 'package:reveric/shared/widgets/novel_open_boundary.dart';
import 'package:reveric/shared/theme/theme.dart';

void main() {
  testWidgets('first content read waits for an existing cleanup permit', (
    tester,
  ) async {
    final coordinator = NovelMaintenanceCoordinator();
    final permit = coordinator.tryAcquireCleanup('novel')!;
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelMaintenanceCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: MaterialApp(
          home: RevericTheme(
            data: RevericThemeData.reveric,
            child: NovelOpenBoundary(
              novelId: 'novel',
              child: Builder(
                builder: (_) {
                  reads++;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(reads, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final background = find
        .ancestor(
          of: find.byType(CircularProgressIndicator),
          matching: find.byType(ColoredBox),
        )
        .first;
    expect(
      tester.widget<ColoredBox>(background).color,
      RevericThemeData.reveric.colors.canvas,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(reads, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(coordinator.isOpen('novel'), isTrue);
    permit.release();
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(coordinator.isOpen('novel'), isFalse);
  });

  testWidgets('retained routes and app background keep the work protected', (
    tester,
  ) async {
    final coordinator = NovelMaintenanceCoordinator();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelMaintenanceCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          home: const NovelOpenBoundary(
            novelId: 'novel',
            child: Scaffold(body: SizedBox()),
          ),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(coordinator.tryAcquireCleanup('novel'), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(coordinator.tryAcquireCleanup('novel'), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(coordinator.isOpen('novel'), isFalse);
  });
}
