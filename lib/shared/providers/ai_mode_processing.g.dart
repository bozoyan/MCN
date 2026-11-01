// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_mode_processing.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AiModeProcessingTracker)
final aiModeProcessingTrackerProvider = AiModeProcessingTrackerProvider._();

final class AiModeProcessingTrackerProvider
    extends $NotifierProvider<AiModeProcessingTracker, Set<String>> {
  AiModeProcessingTrackerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiModeProcessingTrackerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiModeProcessingTrackerHash();

  @$internal
  @override
  AiModeProcessingTracker create() => AiModeProcessingTracker();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$aiModeProcessingTrackerHash() =>
    r'1be460c9d8b43416eacc8cd7fdb5a9d16d75c82b';

abstract class _$AiModeProcessingTracker extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(anyAiModeProcessing)
final anyAiModeProcessingProvider = AnyAiModeProcessingProvider._();

final class AnyAiModeProcessingProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  AnyAiModeProcessingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'anyAiModeProcessingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$anyAiModeProcessingHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return anyAiModeProcessing(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$anyAiModeProcessingHash() =>
    r'e688c42db993fa9c5fd6c6e7721e9bde5c0c0064';

/// 某个 session 当前是否有 agent 在处理。
///
/// session id 全局唯一（随机 id，与 novel 一对一绑定），因此无需再按 novelId
/// 过滤。select 只订阅本 session 的 token，其它 session 状态变化不引发重建。

@ProviderFor(aiSessionProcessing)
final aiSessionProcessingProvider = AiSessionProcessingFamily._();

/// 某个 session 当前是否有 agent 在处理。
///
/// session id 全局唯一（随机 id，与 novel 一对一绑定），因此无需再按 novelId
/// 过滤。select 只订阅本 session 的 token，其它 session 状态变化不引发重建。

final class AiSessionProcessingProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// 某个 session 当前是否有 agent 在处理。
  ///
  /// session id 全局唯一（随机 id，与 novel 一对一绑定），因此无需再按 novelId
  /// 过滤。select 只订阅本 session 的 token，其它 session 状态变化不引发重建。
  AiSessionProcessingProvider._({
    required AiSessionProcessingFamily super.from,
    required ({AiSessionMode mode, String sessionId}) super.argument,
  }) : super(
         retry: null,
         name: r'aiSessionProcessingProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiSessionProcessingHash();

  @override
  String toString() {
    return r'aiSessionProcessingProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    final argument = this.argument as ({AiSessionMode mode, String sessionId});
    return aiSessionProcessing(
      ref,
      mode: argument.mode,
      sessionId: argument.sessionId,
    );
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AiSessionProcessingProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiSessionProcessingHash() =>
    r'f75fc6c596ea8605e9f3b22554f442e7587e21ea';

/// 某个 session 当前是否有 agent 在处理。
///
/// session id 全局唯一（随机 id，与 novel 一对一绑定），因此无需再按 novelId
/// 过滤。select 只订阅本 session 的 token，其它 session 状态变化不引发重建。

final class AiSessionProcessingFamily extends $Family
    with
        $FunctionalFamilyOverride<
          bool,
          ({AiSessionMode mode, String sessionId})
        > {
  AiSessionProcessingFamily._()
    : super(
        retry: null,
        name: r'aiSessionProcessingProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 某个 session 当前是否有 agent 在处理。
  ///
  /// session id 全局唯一（随机 id，与 novel 一对一绑定），因此无需再按 novelId
  /// 过滤。select 只订阅本 session 的 token，其它 session 状态变化不引发重建。

  AiSessionProcessingProvider call({
    required AiSessionMode mode,
    required String sessionId,
  }) => AiSessionProcessingProvider._(
    argument: (mode: mode, sessionId: sessionId),
    from: this,
  );

  @override
  String toString() => r'aiSessionProcessingProvider';
}
