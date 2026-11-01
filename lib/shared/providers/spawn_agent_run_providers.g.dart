// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'spawn_agent_run_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 一次 SpawnAgent 调用期间子 Agent 的实时运行状态，key 为父会话里的 tool callId。
///
/// 子会话消息要等 SpawnAgent 跑完才落库，运行中只能靠这份内存状态展示动态。
/// 用 [KeepAliveLink] 在运行期间临时保活（行滚出视口也不丢），[clear] 时立即释放，
/// 因此不会随 family 参数增长常驻内存。

@ProviderFor(SpawnAgentActiveRun)
final spawnAgentActiveRunProvider = SpawnAgentActiveRunFamily._();

/// 一次 SpawnAgent 调用期间子 Agent 的实时运行状态，key 为父会话里的 tool callId。
///
/// 子会话消息要等 SpawnAgent 跑完才落库，运行中只能靠这份内存状态展示动态。
/// 用 [KeepAliveLink] 在运行期间临时保活（行滚出视口也不丢），[clear] 时立即释放，
/// 因此不会随 family 参数增长常驻内存。
final class SpawnAgentActiveRunProvider
    extends $NotifierProvider<SpawnAgentActiveRun, AgentRunState?> {
  /// 一次 SpawnAgent 调用期间子 Agent 的实时运行状态，key 为父会话里的 tool callId。
  ///
  /// 子会话消息要等 SpawnAgent 跑完才落库，运行中只能靠这份内存状态展示动态。
  /// 用 [KeepAliveLink] 在运行期间临时保活（行滚出视口也不丢），[clear] 时立即释放，
  /// 因此不会随 family 参数增长常驻内存。
  SpawnAgentActiveRunProvider._({
    required SpawnAgentActiveRunFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'spawnAgentActiveRunProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$spawnAgentActiveRunHash();

  @override
  String toString() {
    return r'spawnAgentActiveRunProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SpawnAgentActiveRun create() => SpawnAgentActiveRun();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentRunState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentRunState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SpawnAgentActiveRunProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$spawnAgentActiveRunHash() =>
    r'27bc36161b9d899086fb2d9457b9d0533ee0fbae';

/// 一次 SpawnAgent 调用期间子 Agent 的实时运行状态，key 为父会话里的 tool callId。
///
/// 子会话消息要等 SpawnAgent 跑完才落库，运行中只能靠这份内存状态展示动态。
/// 用 [KeepAliveLink] 在运行期间临时保活（行滚出视口也不丢），[clear] 时立即释放，
/// 因此不会随 family 参数增长常驻内存。

final class SpawnAgentActiveRunFamily extends $Family
    with
        $ClassFamilyOverride<
          SpawnAgentActiveRun,
          AgentRunState?,
          AgentRunState?,
          AgentRunState?,
          String
        > {
  SpawnAgentActiveRunFamily._()
    : super(
        retry: null,
        name: r'spawnAgentActiveRunProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 一次 SpawnAgent 调用期间子 Agent 的实时运行状态，key 为父会话里的 tool callId。
  ///
  /// 子会话消息要等 SpawnAgent 跑完才落库，运行中只能靠这份内存状态展示动态。
  /// 用 [KeepAliveLink] 在运行期间临时保活（行滚出视口也不丢），[clear] 时立即释放，
  /// 因此不会随 family 参数增长常驻内存。

  SpawnAgentActiveRunProvider call(String callId) =>
      SpawnAgentActiveRunProvider._(argument: callId, from: this);

  @override
  String toString() => r'spawnAgentActiveRunProvider';
}

/// 一次 SpawnAgent 调用期间子 Agent 的实时运行状态，key 为父会话里的 tool callId。
///
/// 子会话消息要等 SpawnAgent 跑完才落库，运行中只能靠这份内存状态展示动态。
/// 用 [KeepAliveLink] 在运行期间临时保活（行滚出视口也不丢），[clear] 时立即释放，
/// 因此不会随 family 参数增长常驻内存。

abstract class _$SpawnAgentActiveRun extends $Notifier<AgentRunState?> {
  late final _$args = ref.$arg as String;
  String get callId => _$args;

  AgentRunState? build(String callId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AgentRunState?, AgentRunState?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AgentRunState?, AgentRunState?>,
              AgentRunState?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
