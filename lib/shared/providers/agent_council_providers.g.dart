// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_council_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AgentCouncilActiveRun)
final agentCouncilActiveRunProvider = AgentCouncilActiveRunFamily._();

final class AgentCouncilActiveRunProvider
    extends $NotifierProvider<AgentCouncilActiveRun, AgentRunState?> {
  AgentCouncilActiveRunProvider._({
    required AgentCouncilActiveRunFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'agentCouncilActiveRunProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentCouncilActiveRunHash();

  @override
  String toString() {
    return r'agentCouncilActiveRunProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentCouncilActiveRun create() => AgentCouncilActiveRun();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentRunState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentRunState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentCouncilActiveRunProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentCouncilActiveRunHash() =>
    r'78ec71636ea193e67ec85fe620bfe272262b7154';

final class AgentCouncilActiveRunFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentCouncilActiveRun,
          AgentRunState?,
          AgentRunState?,
          AgentRunState?,
          String?
        > {
  AgentCouncilActiveRunFamily._()
    : super(
        retry: null,
        name: r'agentCouncilActiveRunProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  AgentCouncilActiveRunProvider call(String? sessionId) =>
      AgentCouncilActiveRunProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'agentCouncilActiveRunProvider';
}

abstract class _$AgentCouncilActiveRun extends $Notifier<AgentRunState?> {
  late final _$args = ref.$arg as String?;
  String? get sessionId => _$args;

  AgentRunState? build(String? sessionId);
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

@ProviderFor(AgentCouncilRunHistoryStore)
final agentCouncilRunHistoryStoreProvider =
    AgentCouncilRunHistoryStoreFamily._();

final class AgentCouncilRunHistoryStoreProvider
    extends
        $NotifierProvider<
          AgentCouncilRunHistoryStore,
          Map<String, AgentRunState>
        > {
  AgentCouncilRunHistoryStoreProvider._({
    required AgentCouncilRunHistoryStoreFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'agentCouncilRunHistoryStoreProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentCouncilRunHistoryStoreHash();

  @override
  String toString() {
    return r'agentCouncilRunHistoryStoreProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentCouncilRunHistoryStore create() => AgentCouncilRunHistoryStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AgentRunState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AgentRunState>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentCouncilRunHistoryStoreProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentCouncilRunHistoryStoreHash() =>
    r'7b6f85660d789282ac9e068ea13a9e570696d717';

final class AgentCouncilRunHistoryStoreFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentCouncilRunHistoryStore,
          Map<String, AgentRunState>,
          Map<String, AgentRunState>,
          Map<String, AgentRunState>,
          String?
        > {
  AgentCouncilRunHistoryStoreFamily._()
    : super(
        retry: null,
        name: r'agentCouncilRunHistoryStoreProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  AgentCouncilRunHistoryStoreProvider call(String? sessionId) =>
      AgentCouncilRunHistoryStoreProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'agentCouncilRunHistoryStoreProvider';
}

abstract class _$AgentCouncilRunHistoryStore
    extends $Notifier<Map<String, AgentRunState>> {
  late final _$args = ref.$arg as String?;
  String? get sessionId => _$args;

  Map<String, AgentRunState> build(String? sessionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<Map<String, AgentRunState>, Map<String, AgentRunState>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, AgentRunState>,
                Map<String, AgentRunState>
              >,
              Map<String, AgentRunState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(AgentCouncilRuntime)
final agentCouncilRuntimeProvider = AgentCouncilRuntimeFamily._();

final class AgentCouncilRuntimeProvider
    extends $NotifierProvider<AgentCouncilRuntime, AiModeRuntimeState> {
  AgentCouncilRuntimeProvider._({
    required AgentCouncilRuntimeFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'agentCouncilRuntimeProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentCouncilRuntimeHash();

  @override
  String toString() {
    return r'agentCouncilRuntimeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentCouncilRuntime create() => AgentCouncilRuntime();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiModeRuntimeState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiModeRuntimeState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentCouncilRuntimeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentCouncilRuntimeHash() =>
    r'a14718ba06afc3fdeb073bb9312534233d43bef1';

final class AgentCouncilRuntimeFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentCouncilRuntime,
          AiModeRuntimeState,
          AiModeRuntimeState,
          AiModeRuntimeState,
          String?
        > {
  AgentCouncilRuntimeFamily._()
    : super(
        retry: null,
        name: r'agentCouncilRuntimeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  AgentCouncilRuntimeProvider call(String? sessionId) =>
      AgentCouncilRuntimeProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'agentCouncilRuntimeProvider';
}

abstract class _$AgentCouncilRuntime extends $Notifier<AiModeRuntimeState> {
  late final _$args = ref.$arg as String?;
  String? get sessionId => _$args;

  AiModeRuntimeState build(String? sessionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AiModeRuntimeState, AiModeRuntimeState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AiModeRuntimeState, AiModeRuntimeState>,
              AiModeRuntimeState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(AgentCouncilSessionNotifier)
final agentCouncilSessionProvider = AgentCouncilSessionNotifierFamily._();

final class AgentCouncilSessionNotifierProvider
    extends
        $NotifierProvider<AgentCouncilSessionNotifier, AgentCouncilSession?> {
  AgentCouncilSessionNotifierProvider._({
    required AgentCouncilSessionNotifierFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'agentCouncilSessionProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentCouncilSessionNotifierHash();

  @override
  String toString() {
    return r'agentCouncilSessionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentCouncilSessionNotifier create() => AgentCouncilSessionNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentCouncilSession? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentCouncilSession?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentCouncilSessionNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentCouncilSessionNotifierHash() =>
    r'038882f56ec86ad1cf1f960b515bdd4c6c33a7ba';

final class AgentCouncilSessionNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentCouncilSessionNotifier,
          AgentCouncilSession?,
          AgentCouncilSession?,
          AgentCouncilSession?,
          String?
        > {
  AgentCouncilSessionNotifierFamily._()
    : super(
        retry: null,
        name: r'agentCouncilSessionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  AgentCouncilSessionNotifierProvider call(String? sessionId) =>
      AgentCouncilSessionNotifierProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'agentCouncilSessionProvider';
}

abstract class _$AgentCouncilSessionNotifier
    extends $Notifier<AgentCouncilSession?> {
  late final _$args = ref.$arg as String?;
  String? get sessionId => _$args;

  AgentCouncilSession? build(String? sessionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AgentCouncilSession?, AgentCouncilSession?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AgentCouncilSession?, AgentCouncilSession?>,
              AgentCouncilSession?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(AgentCouncilConfigNotifier)
final agentCouncilConfigProvider = AgentCouncilConfigNotifierProvider._();

final class AgentCouncilConfigNotifierProvider
    extends $NotifierProvider<AgentCouncilConfigNotifier, AgentCouncilConfig> {
  AgentCouncilConfigNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentCouncilConfigProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentCouncilConfigNotifierHash();

  @$internal
  @override
  AgentCouncilConfigNotifier create() => AgentCouncilConfigNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentCouncilConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentCouncilConfig>(value),
    );
  }
}

String _$agentCouncilConfigNotifierHash() =>
    r'00b01b09f3037765c0a63c6f96ef928d342ef085';

abstract class _$AgentCouncilConfigNotifier
    extends $Notifier<AgentCouncilConfig> {
  AgentCouncilConfig build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AgentCouncilConfig, AgentCouncilConfig>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AgentCouncilConfig, AgentCouncilConfig>,
              AgentCouncilConfig,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 议会成员即 mode=council 的全局 SubAgent；编辑直接写回 SubAgent，
/// 与专家团队页、智能体模型设置页看到的是同一份数据。

@ProviderFor(AgentCouncilParticipantsNotifier)
final agentCouncilParticipantsProvider =
    AgentCouncilParticipantsNotifierProvider._();

/// 议会成员即 mode=council 的全局 SubAgent；编辑直接写回 SubAgent，
/// 与专家团队页、智能体模型设置页看到的是同一份数据。
final class AgentCouncilParticipantsNotifierProvider
    extends
        $AsyncNotifierProvider<
          AgentCouncilParticipantsNotifier,
          List<CouncilParticipant>
        > {
  /// 议会成员即 mode=council 的全局 SubAgent；编辑直接写回 SubAgent，
  /// 与专家团队页、智能体模型设置页看到的是同一份数据。
  AgentCouncilParticipantsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentCouncilParticipantsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentCouncilParticipantsNotifierHash();

  @$internal
  @override
  AgentCouncilParticipantsNotifier create() =>
      AgentCouncilParticipantsNotifier();
}

String _$agentCouncilParticipantsNotifierHash() =>
    r'9323c7c88f355c1d30302c834c51d4b3cedd4d04';

/// 议会成员即 mode=council 的全局 SubAgent；编辑直接写回 SubAgent，
/// 与专家团队页、智能体模型设置页看到的是同一份数据。

abstract class _$AgentCouncilParticipantsNotifier
    extends $AsyncNotifier<List<CouncilParticipant>> {
  FutureOr<List<CouncilParticipant>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<CouncilParticipant>>,
              List<CouncilParticipant>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<CouncilParticipant>>,
                List<CouncilParticipant>
              >,
              AsyncValue<List<CouncilParticipant>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
