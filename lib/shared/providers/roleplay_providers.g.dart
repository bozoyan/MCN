// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'roleplay_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(RoleplayActiveRun)
final roleplayActiveRunProvider = RoleplayActiveRunFamily._();

final class RoleplayActiveRunProvider
    extends $NotifierProvider<RoleplayActiveRun, AgentRunState?> {
  RoleplayActiveRunProvider._({
    required RoleplayActiveRunFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'roleplayActiveRunProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roleplayActiveRunHash();

  @override
  String toString() {
    return r'roleplayActiveRunProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RoleplayActiveRun create() => RoleplayActiveRun();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentRunState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentRunState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RoleplayActiveRunProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roleplayActiveRunHash() => r'062718dfbdec412b847af9fdc5a7d326af67ae98';

final class RoleplayActiveRunFamily extends $Family
    with
        $ClassFamilyOverride<
          RoleplayActiveRun,
          AgentRunState?,
          AgentRunState?,
          AgentRunState?,
          String?
        > {
  RoleplayActiveRunFamily._()
    : super(
        retry: null,
        name: r'roleplayActiveRunProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  RoleplayActiveRunProvider call(String? sessionId) =>
      RoleplayActiveRunProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'roleplayActiveRunProvider';
}

abstract class _$RoleplayActiveRun extends $Notifier<AgentRunState?> {
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

@ProviderFor(RoleplayRunHistoryStore)
final roleplayRunHistoryStoreProvider = RoleplayRunHistoryStoreFamily._();

final class RoleplayRunHistoryStoreProvider
    extends
        $NotifierProvider<RoleplayRunHistoryStore, Map<String, AgentRunState>> {
  RoleplayRunHistoryStoreProvider._({
    required RoleplayRunHistoryStoreFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'roleplayRunHistoryStoreProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roleplayRunHistoryStoreHash();

  @override
  String toString() {
    return r'roleplayRunHistoryStoreProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RoleplayRunHistoryStore create() => RoleplayRunHistoryStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AgentRunState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AgentRunState>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RoleplayRunHistoryStoreProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roleplayRunHistoryStoreHash() =>
    r'f9cca5a041be680cabe90b7dc04910bb4a59fd7d';

final class RoleplayRunHistoryStoreFamily extends $Family
    with
        $ClassFamilyOverride<
          RoleplayRunHistoryStore,
          Map<String, AgentRunState>,
          Map<String, AgentRunState>,
          Map<String, AgentRunState>,
          String?
        > {
  RoleplayRunHistoryStoreFamily._()
    : super(
        retry: null,
        name: r'roleplayRunHistoryStoreProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  RoleplayRunHistoryStoreProvider call(String? sessionId) =>
      RoleplayRunHistoryStoreProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'roleplayRunHistoryStoreProvider';
}

abstract class _$RoleplayRunHistoryStore
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

@ProviderFor(RoleplayRuntime)
final roleplayRuntimeProvider = RoleplayRuntimeFamily._();

final class RoleplayRuntimeProvider
    extends $NotifierProvider<RoleplayRuntime, AiModeRuntimeState> {
  RoleplayRuntimeProvider._({
    required RoleplayRuntimeFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'roleplayRuntimeProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roleplayRuntimeHash();

  @override
  String toString() {
    return r'roleplayRuntimeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RoleplayRuntime create() => RoleplayRuntime();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiModeRuntimeState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiModeRuntimeState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RoleplayRuntimeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roleplayRuntimeHash() => r'6a7fcfd43c139b2c68dde551e7ec1cba06e1a2d7';

final class RoleplayRuntimeFamily extends $Family
    with
        $ClassFamilyOverride<
          RoleplayRuntime,
          AiModeRuntimeState,
          AiModeRuntimeState,
          AiModeRuntimeState,
          String?
        > {
  RoleplayRuntimeFamily._()
    : super(
        retry: null,
        name: r'roleplayRuntimeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  RoleplayRuntimeProvider call(String? sessionId) =>
      RoleplayRuntimeProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'roleplayRuntimeProvider';
}

abstract class _$RoleplayRuntime extends $Notifier<AiModeRuntimeState> {
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

@ProviderFor(RoleplaySessionNotifier)
final roleplaySessionProvider = RoleplaySessionNotifierFamily._();

final class RoleplaySessionNotifierProvider
    extends $NotifierProvider<RoleplaySessionNotifier, RoleplaySession?> {
  RoleplaySessionNotifierProvider._({
    required RoleplaySessionNotifierFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'roleplaySessionProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roleplaySessionNotifierHash();

  @override
  String toString() {
    return r'roleplaySessionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RoleplaySessionNotifier create() => RoleplaySessionNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoleplaySession? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoleplaySession?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RoleplaySessionNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roleplaySessionNotifierHash() =>
    r'910d5d1074fef55bbeee629cf299bdfe53a9a713';

final class RoleplaySessionNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          RoleplaySessionNotifier,
          RoleplaySession?,
          RoleplaySession?,
          RoleplaySession?,
          String?
        > {
  RoleplaySessionNotifierFamily._()
    : super(
        retry: null,
        name: r'roleplaySessionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  RoleplaySessionNotifierProvider call(String? sessionId) =>
      RoleplaySessionNotifierProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'roleplaySessionProvider';
}

abstract class _$RoleplaySessionNotifier extends $Notifier<RoleplaySession?> {
  late final _$args = ref.$arg as String?;
  String? get sessionId => _$args;

  RoleplaySession? build(String? sessionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RoleplaySession?, RoleplaySession?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RoleplaySession?, RoleplaySession?>,
              RoleplaySession?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(RoleplayConfigNotifier)
final roleplayConfigProvider = RoleplayConfigNotifierProvider._();

final class RoleplayConfigNotifierProvider
    extends $NotifierProvider<RoleplayConfigNotifier, RoleplayConfig> {
  RoleplayConfigNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roleplayConfigProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roleplayConfigNotifierHash();

  @$internal
  @override
  RoleplayConfigNotifier create() => RoleplayConfigNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoleplayConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoleplayConfig>(value),
    );
  }
}

String _$roleplayConfigNotifierHash() =>
    r'729e30ff35ec4ca48673893ffa7c1db07571a977';

abstract class _$RoleplayConfigNotifier extends $Notifier<RoleplayConfig> {
  RoleplayConfig build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RoleplayConfig, RoleplayConfig>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RoleplayConfig, RoleplayConfig>,
              RoleplayConfig,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
