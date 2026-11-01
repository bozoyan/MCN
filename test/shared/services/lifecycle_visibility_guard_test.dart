import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/lifecycle_visibility_guard.dart';
import 'package:reveric/shared/services/window_lifecycle_channel.dart';

/// 走真实的 `SystemChannels.lifecycle` 平台消息路径。
///
/// 这是本文件的关键约束：直接调用 `binding.handleAppLifecycleStateChanged()` 会绕开
/// `ServicesBinding._generateStateTransitions`，测试里就永远看不到框架**合成**的中间
/// 状态 —— 而那正是 `f0e050143` 的守卫在真机上失效的原因，也是它的回归测试当时全绿的
/// 原因。任何生命周期用例都必须从这里发消息。
Future<void> _engineSends(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}

/// 挂一棵最小树，让 `_readyToProduceFrames` 为真 —— 否则 `framesEnabled`
/// 恒为 false，断言不出生命周期对出帧的真实影响。
Future<WidgetsBinding> _pumpBoundTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.binding.resetInternalState();
  return tester.binding;
}

class _FakeWindowLifecycleChannel implements WindowLifecycleChannel {
  /// [appActive] / [windowKey] 默认跟随 [appOcclusionVisible] —— 真机上「被完全遮挡」
  /// 与「应用在后台」总是同时成立（见冻结日志里那 25 次全 false 的采样）。旧实现把它们
  /// 硬编码成 true，等于断言「窗口被盖住的同时还是前台 key window」，物理上不可能，
  /// 也正好掩盖了守卫在 occlusion 滞后时该纠正却不纠正的缺陷。要拆开两者的用例显式传参。
  _FakeWindowLifecycleChannel({
    required this.appOcclusionVisible,
    bool? appActive,
    bool? windowKey,
    this.windowMiniaturized = false,
    this.recoverOnReseed = false,
  }) : appActive = appActive ?? appOcclusionVisible,
       windowKey = windowKey ?? appOcclusionVisible;

  bool appOcclusionVisible;
  bool appActive;
  bool windowKey;
  bool windowMiniaturized;

  /// 模拟原生回灌真的治好了引擎：引擎自己经平台消息发回 resumed。
  bool recoverOnReseed;

  int reseedCalls = 0;
  WidgetTester? tester;

  WindowVisibilitySnapshot _snapshot({required bool reseeded}) =>
      WindowVisibilitySnapshot(
        appOcclusionVisible: appOcclusionVisible,
        appActive: appActive,
        windowVisible: !windowMiniaturized,
        windowMiniaturized: windowMiniaturized,
        windowKey: windowKey,
        windowOcclusionVisible: appOcclusionVisible,
        reseeded: reseeded,
      );

  @override
  Future<WindowVisibilitySnapshot> reseedEngineVisibility() async {
    reseedCalls += 1;
    if (recoverOnReseed && appOcclusionVisible) {
      await _engineSends(tester!, AppLifecycleState.resumed);
    }
    return _snapshot(reseeded: true);
  }

  @override
  Future<WindowVisibilitySnapshot> getVisibilityState() async =>
      _snapshot(reseeded: false);
}

void main() {
  for (final stoppedState in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    testWidgets('纠正 ${stoppedState.name} 时遵循 listener 状态机且能再次恢复', (
      tester,
    ) async {
      final binding = await _pumpBoundTree(tester);
      await _engineSends(tester, stoppedState);
      final states = <AppLifecycleState>[];
      final listener = AppLifecycleListener(onStateChange: states.add);
      addTearDown(listener.dispose);
      final guard = LifecycleVisibilityGuard(
        channel: _FakeWindowLifecycleChannel(appOcclusionVisible: true),
        reseedGracePeriod: Duration.zero,
      )..install();
      addTearDown(guard.dispose);

      for (var recovery = 0; recovery < 2; recovery++) {
        if (recovery > 0) {
          await _engineSends(tester, stoppedState);
        }
        states.clear();
        final correction = guard.correctIfEngineIsWrong();
        await tester.idle();
        await correction;

        expect(tester.takeException(), isNull);
        expect(states, [
          if (stoppedState == AppLifecycleState.paused)
            AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]);
        expect(binding.framesEnabled, isTrue);
      }
      guard.dispose();
    });
  }

  // 回归钉子（f0e050143）：守卫强改 resumed 之后，引擎的下一个 hidden 会被
  // `_generateStateTransitions` 补成 [inactive, hidden] 两次派发。旧实现把那个**合成
  // 的** inactive 当作「引擎已健康」而解除守卫，于是紧随其后的 hidden 无人纠正，
  // framesEnabled 永久为 false —— 表现为「界面出来了但不再刷新，点了没反应」。
  testWidgets('引擎再次上报 hidden 时守卫仍然纠正，出帧不被永久关闭', (tester) async {
    final binding = await _pumpBoundTree(tester);
    final channel = _FakeWindowLifecycleChannel(appOcclusionVisible: true);
    final guard = LifecycleVisibilityGuard(
      channel: channel,
      reseedGracePeriod: Duration.zero,
    )..install();

    await _engineSends(tester, AppLifecycleState.hidden);
    await tester.idle();
    expect(binding.lifecycleState, AppLifecycleState.resumed);
    expect(binding.framesEnabled, isTrue, reason: '首次纠正应恢复出帧');

    // 用户切走再切回来：引擎 `_visible` 仍是 NO，于是又发一次 hidden。
    await _engineSends(tester, AppLifecycleState.hidden);
    expect(
      binding.framesEnabled,
      isFalse,
      reason: '合成的 hidden 先把出帧关掉，守卫随后才有机会纠正',
    );
    await tester.idle();

    expect(binding.lifecycleState, AppLifecycleState.resumed);
    expect(binding.framesEnabled, isTrue, reason: '出帧不应被永久关闭');
    expect(
      channel.reseedCalls,
      greaterThanOrEqualTo(2),
      reason: '两次 hidden 都应核对原生实况',
    );

    guard.dispose();
  });

  testWidgets('原生说窗口真被遮挡时不纠正，帧合法停止', (tester) async {
    final binding = await _pumpBoundTree(tester);
    final channel = _FakeWindowLifecycleChannel(appOcclusionVisible: false);
    final guard = LifecycleVisibilityGuard(
      channel: channel,
      reseedGracePeriod: Duration.zero,
    )..install();

    await _engineSends(tester, AppLifecycleState.hidden);
    await tester.idle();

    expect(binding.lifecycleState, AppLifecycleState.hidden);
    expect(binding.framesEnabled, isFalse, reason: '真遮挡下继续出帧就是空转烧 CPU');

    guard.dispose();
  });

  testWidgets('最小化时不纠正', (tester) async {
    final binding = await _pumpBoundTree(tester);
    final channel = _FakeWindowLifecycleChannel(
      appOcclusionVisible: true,
      windowMiniaturized: true,
    );
    final guard = LifecycleVisibilityGuard(
      channel: channel,
      reseedGracePeriod: Duration.zero,
    )..install();

    await _engineSends(tester, AppLifecycleState.hidden);
    await tester.idle();

    expect(binding.lifecycleState, AppLifecycleState.hidden);
    expect(binding.framesEnabled, isFalse);

    guard.dispose();
  });

  testWidgets('原生回灌治好引擎后不再强改状态', (tester) async {
    final binding = await _pumpBoundTree(tester);
    final channel = _FakeWindowLifecycleChannel(
      appOcclusionVisible: true,
      recoverOnReseed: true,
    )..tester = tester;
    final guard = LifecycleVisibilityGuard(
      channel: channel,
      reseedGracePeriod: Duration.zero,
    )..install();

    await _engineSends(tester, AppLifecycleState.hidden);
    await tester.idle();

    expect(binding.lifecycleState, AppLifecycleState.resumed);
    expect(binding.framesEnabled, isTrue);
    expect(channel.reseedCalls, 1, reason: '引擎自己恢复后不该反复回灌');

    guard.dispose();
  });

  testWidgets('启动期 hidden 早于守卫注册时，轮询仍能纠正', (tester) async {
    final binding = await _pumpBoundTree(tester);

    // 守卫尚未安装，引擎的 hidden 已经到了 —— 这是冷启动的真实时序。
    await _engineSends(tester, AppLifecycleState.hidden);
    expect(binding.framesEnabled, isFalse);

    final channel = _FakeWindowLifecycleChannel(appOcclusionVisible: true);
    final guard = LifecycleVisibilityGuard(
      channel: channel,
      startupPollInterval: const Duration(milliseconds: 10),
      reseedGracePeriod: Duration.zero,
    )..install();

    await tester.pump(const Duration(milliseconds: 20));
    await tester.idle();

    expect(binding.lifecycleState, AppLifecycleState.resumed);
    expect(binding.framesEnabled, isTrue);

    guard.dispose();
  });

  // 回归钉子（round 4 现场，2026-08-30 12:57:54 的日志）：窗口 order in 之后
  // NSApp.occlusionState 由窗口服务器异步更新，滞后期内即使应用已经 active 且本窗口
  // 是 key window，它仍报 false。旧判据一路 `&&`，被这个假阴性一票否决，30 次启动轮询
  // 全部输出「hidden is genuine, no correction」，一次都没纠正。
  testWidgets('应用 active 且持有 key window 时，滞后的 occlusion 不该否决纠正', (
    tester,
  ) async {
    final binding = await _pumpBoundTree(tester);
    final channel = _FakeWindowLifecycleChannel(
      appOcclusionVisible: false,
      appActive: true,
      windowKey: true,
    );
    final guard = LifecycleVisibilityGuard(
      channel: channel,
      reseedGracePeriod: Duration.zero,
    )..install();

    await _engineSends(tester, AppLifecycleState.hidden);
    await tester.idle();

    expect(binding.lifecycleState, AppLifecycleState.resumed);
    expect(binding.framesEnabled, isTrue, reason: '前台 key window 不可能被盖住');

    guard.dispose();
  });

  // 回归钉子（复发机制本身）：启动轮询用尽后，引擎已经停在 hidden，同状态会被
  // `_generateStateTransitions` 去重，didChangeAppLifecycleState 再也不会被调用。
  // 没有常驻看门狗的话，「启动那几秒里窗口恰好真被遮挡」就等于这个进程余生都是冻的。
  testWidgets('启动轮询用尽后窗口才露出来，常驻看门狗仍能恢复出帧', (tester) async {
    final binding = await _pumpBoundTree(tester);

    await _engineSends(tester, AppLifecycleState.hidden);
    expect(binding.framesEnabled, isFalse);

    // 冷启动时窗口真被别的应用盖着 —— 启动轮询每一次都合理地判定「不该纠正」。
    final channel = _FakeWindowLifecycleChannel(appOcclusionVisible: false);
    final guard = LifecycleVisibilityGuard(
      channel: channel,
      startupPollInterval: const Duration(milliseconds: 10),
      startupPolls: 3,
      watchdogInterval: const Duration(milliseconds: 50),
      reseedGracePeriod: Duration.zero,
    )..install();

    await tester.pump(const Duration(milliseconds: 45));
    await tester.idle();
    expect(binding.framesEnabled, isFalse, reason: '真遮挡期间纠正就是空转烧 CPU');
    expect(binding.lifecycleState, AppLifecycleState.hidden);
    expect(channel.reseedCalls, 3, reason: '启动轮询跑满 3 次就停表');

    // 用户切回 app。刻意不发任何平台消息 —— 真机上这里也不会有，引擎重发的 hidden
    // 与当前状态相同，框架直接吞掉。
    channel
      ..appOcclusionVisible = true
      ..appActive = true
      ..windowKey = true;

    await tester.pump(const Duration(milliseconds: 60));
    await tester.idle();
    await tester.pump();

    expect(binding.lifecycleState, AppLifecycleState.resumed);
    expect(
      binding.framesEnabled,
      isTrue,
      reason: '守卫必须能在启动窗口之外恢复，否则「猜错一次」就是永久冻结',
    );
    expect(
      channel.reseedCalls,
      greaterThan(3),
      reason: '恢复只可能来自看门狗 —— 启动轮询此时已经停表',
    );

    guard.dispose();
  });
}
