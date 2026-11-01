// 职责: 验证启动首帧、初始化防重入和失败放行时的业务子树挂载顺序。
// 关联文件:
//   lib/shared/widgets/app_startup_gate.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/widgets/app_startup_gate.dart';

void main() {
  const loadingKey = ValueKey('startup-loading');
  const businessKey = ValueKey('business-app');

  testWidgets(
    'shows a frame before initialization and mounts business once ready',
    (tester) async {
      final completion = Completer<void>();
      var calls = 0;
      var businessBuilds = 0;
      var loadingMountedAtStart = false;
      int? businessBuildsAtStart;

      Widget app() => AppStartupGate(
        initialize: () {
          calls++;
          loadingMountedAtStart = find.byKey(loadingKey).evaluate().isNotEmpty;
          businessBuildsAtStart = businessBuilds;
          return completion.future;
        },
        loading: const SizedBox(key: loadingKey),
        child: Builder(
          builder: (_) {
            businessBuilds++;
            return const SizedBox(key: businessKey);
          },
        ),
      );

      await tester.pumpWidget(app());
      expect(calls, 1);
      expect(loadingMountedAtStart, isTrue);
      expect(businessBuildsAtStart, 0);
      expect(businessBuilds, 0);

      // 父级重建并提供新闭包时，仍继续等待同一次初始化。
      await tester.pumpWidget(app());
      expect(calls, 1);
      expect(businessBuilds, 0);
      expect(find.byKey(loadingKey), findsOneWidget);

      completion.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(loadingKey), findsNothing);
      expect(find.byKey(businessKey), findsOneWidget);
      expect(businessBuilds, 1);

      await tester.pumpWidget(app());
      expect(calls, 1);
      expect(find.byKey(businessKey), findsOneWidget);
    },
  );

  testWidgets('initialization failure still mounts business without retry', (
    tester,
  ) async {
    final completion = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      AppStartupGate(
        initialize: () {
          calls++;
          return completion.future;
        },
        loading: const SizedBox(key: loadingKey),
        child: const SizedBox(key: businessKey),
      ),
    );

    expect(find.byKey(businessKey), findsNothing);
    completion.completeError(StateError('initialization failed'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(loadingKey), findsNothing);
    expect(find.byKey(businessKey), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('completion after unmount does not mount business', (
    tester,
  ) async {
    final completion = Completer<void>();
    var businessBuilds = 0;
    await tester.pumpWidget(
      AppStartupGate(
        initialize: () => completion.future,
        loading: const SizedBox(key: loadingKey),
        child: Builder(
          builder: (_) {
            businessBuilds++;
            return const SizedBox(key: businessKey);
          },
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    completion.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(businessBuilds, 0);
  });
}
