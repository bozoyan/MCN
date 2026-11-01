// 职责: 验证连线限帧驱动的速率、相位、暂停和销毁，避免退化为全速 ticker。
// 关联文件:
//   lib/third/flow/vyuh_node_flow/lib/src/editor/connection_animation_driver.dart

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/third/flow/vyuh_node_flow/lib/src/editor/connection_animation_driver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('30 Hz uses no ticker and preserves the animation cycle duration', () {
    fakeAsync((async) {
      final animation = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(seconds: 2),
      );
      final driver = ConnectionAnimationDriver(animation);
      var updates = 0;
      animation.addListener(() => updates++);
      driver.update(running: true, enabled: true, frameRate: 30);
      expect(animation.isAnimating, isFalse);
      async.elapse(const Duration(milliseconds: 1001));
      expect(updates, 30);
      expect(animation.value, closeTo(.5, .001));

      // Rebuilding with the same configuration must not restart the clock.
      driver.update(running: true, enabled: true, frameRate: 30);
      async.elapse(const Duration(milliseconds: 1000));
      expect(updates, 60);
      expect(animation.value, closeTo(0, .001));

      driver.update(running: true, enabled: false, frameRate: 30);
      final paused = animation.value;
      async.elapse(const Duration(seconds: 1));
      expect(updates, 60);
      expect(animation.value, paused);
      expect(async.periodicTimerCount, 0);

      driver.update(running: true, enabled: true, frameRate: 30);
      async.elapse(const Duration(milliseconds: 501));
      expect(animation.value, closeTo(.25, .001));
      animation.duration = const Duration(seconds: 4);
      driver.update(running: true, enabled: true, frameRate: 30);
      async.elapse(const Duration(milliseconds: 1001));
      expect(animation.value, closeTo(.5, .001));
      driver.update(running: false, enabled: true, frameRate: 30);
      expect(async.periodicTimerCount, 0);
      driver.update(running: true, enabled: true, frameRate: 30);
      driver.dispose();
      expect(async.periodicTimerCount, 0);
      animation.dispose();
    });
  });

  testWidgets('hidden apps suspend the timer and resume the flow', (
    tester,
  ) async {
    final animation = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 2),
    );
    final driver = ConnectionAnimationDriver(animation);
    var updates = 0;
    animation.addListener(() => updates++);
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      driver.update(running: true, enabled: true, frameRate: 30);
      await tester.pump(const Duration(milliseconds: 40));
      expect(updates, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 1));
      expect(updates, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 40));
      expect(updates, 2);
      expect(animation.isAnimating, isFalse);
    } finally {
      driver.dispose();
      animation.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });
}
