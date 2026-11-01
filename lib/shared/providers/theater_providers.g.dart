// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theater_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TheaterActiveRun)
final theaterActiveRunProvider = TheaterActiveRunFamily._();

final class TheaterActiveRunProvider
    extends $NotifierProvider<TheaterActiveRun, AgentRunState?> {
  TheaterActiveRunProvider._({
    required TheaterActiveRunFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'theaterActiveRunProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$theaterActiveRunHash();

  @override
  String toString() {
    return r'theaterActiveRunProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TheaterActiveRun create() => TheaterActiveRun();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentRunState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentRunState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TheaterActiveRunProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$theaterActiveRunHash() => r'ffda62bb6d7fd19b61665c166b3869855c3ea523';

final class TheaterActiveRunFamily extends $Family
    with
        $ClassFamilyOverride<
          TheaterActiveRun,
          AgentRunState?,
          AgentRunState?,
          AgentRunState?,
          String?
        > {
  TheaterActiveRunFamily._()
    : super(
        retry: null,
        name: r'theaterActiveRunProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  TheaterActiveRunProvider call(String? sessionId) =>
      TheaterActiveRunProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'theaterActiveRunProvider';
}

abstract class _$TheaterActiveRun extends $Notifier<AgentRunState?> {
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

@ProviderFor(TheaterRunHistoryStore)
final theaterRunHistoryStoreProvider = TheaterRunHistoryStoreFamily._();

final class TheaterRunHistoryStoreProvider
    extends
        $NotifierProvider<TheaterRunHistoryStore, Map<String, AgentRunState>> {
  TheaterRunHistoryStoreProvider._({
    required TheaterRunHistoryStoreFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'theaterRunHistoryStoreProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$theaterRunHistoryStoreHash();

  @override
  String toString() {
    return r'theaterRunHistoryStoreProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TheaterRunHistoryStore create() => TheaterRunHistoryStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AgentRunState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AgentRunState>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TheaterRunHistoryStoreProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$theaterRunHistoryStoreHash() =>
    r'16d919bf95fb32dcc9794616ea490269d129650d';

final class TheaterRunHistoryStoreFamily extends $Family
    with
        $ClassFamilyOverride<
          TheaterRunHistoryStore,
          Map<String, AgentRunState>,
          Map<String, AgentRunState>,
          Map<String, AgentRunState>,
          String?
        > {
  TheaterRunHistoryStoreFamily._()
    : super(
        retry: null,
        name: r'theaterRunHistoryStoreProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  TheaterRunHistoryStoreProvider call(String? sessionId) =>
      TheaterRunHistoryStoreProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'theaterRunHistoryStoreProvider';
}

abstract class _$TheaterRunHistoryStore
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

@ProviderFor(TheaterRuntime)
final theaterRuntimeProvider = TheaterRuntimeFamily._();

final class TheaterRuntimeProvider
    extends $NotifierProvider<TheaterRuntime, AiModeRuntimeState> {
  TheaterRuntimeProvider._({
    required TheaterRuntimeFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'theaterRuntimeProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$theaterRuntimeHash();

  @override
  String toString() {
    return r'theaterRuntimeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TheaterRuntime create() => TheaterRuntime();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiModeRuntimeState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiModeRuntimeState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TheaterRuntimeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$theaterRuntimeHash() => r'8e5bf446423343d516d8b4a954f4e0db16a17d4e';

final class TheaterRuntimeFamily extends $Family
    with
        $ClassFamilyOverride<
          TheaterRuntime,
          AiModeRuntimeState,
          AiModeRuntimeState,
          AiModeRuntimeState,
          String?
        > {
  TheaterRuntimeFamily._()
    : super(
        retry: null,
        name: r'theaterRuntimeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  TheaterRuntimeProvider call(String? sessionId) =>
      TheaterRuntimeProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'theaterRuntimeProvider';
}

abstract class _$TheaterRuntime extends $Notifier<AiModeRuntimeState> {
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

@ProviderFor(TheaterSessionNotifier)
final theaterSessionProvider = TheaterSessionNotifierFamily._();

final class TheaterSessionNotifierProvider
    extends $NotifierProvider<TheaterSessionNotifier, TheaterSession?> {
  TheaterSessionNotifierProvider._({
    required TheaterSessionNotifierFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'theaterSessionProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$theaterSessionNotifierHash();

  @override
  String toString() {
    return r'theaterSessionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TheaterSessionNotifier create() => TheaterSessionNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TheaterSession? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TheaterSession?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TheaterSessionNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$theaterSessionNotifierHash() =>
    r'd0bb3302d35aa5821b3ff4444e3f7d754259d9a6';

final class TheaterSessionNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          TheaterSessionNotifier,
          TheaterSession?,
          TheaterSession?,
          TheaterSession?,
          String?
        > {
  TheaterSessionNotifierFamily._()
    : super(
        retry: null,
        name: r'theaterSessionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  TheaterSessionNotifierProvider call(String? sessionId) =>
      TheaterSessionNotifierProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'theaterSessionProvider';
}

abstract class _$TheaterSessionNotifier extends $Notifier<TheaterSession?> {
  late final _$args = ref.$arg as String?;
  String? get sessionId => _$args;

  TheaterSession? build(String? sessionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TheaterSession?, TheaterSession?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TheaterSession?, TheaterSession?>,
              TheaterSession?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(TheaterConfigNotifier)
final theaterConfigProvider = TheaterConfigNotifierProvider._();

final class TheaterConfigNotifierProvider
    extends $NotifierProvider<TheaterConfigNotifier, TheaterConfig> {
  TheaterConfigNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'theaterConfigProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$theaterConfigNotifierHash();

  @$internal
  @override
  TheaterConfigNotifier create() => TheaterConfigNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TheaterConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TheaterConfig>(value),
    );
  }
}

String _$theaterConfigNotifierHash() =>
    r'df45661cb43007a27dbdf96b4f3c6f292119ead7';

abstract class _$TheaterConfigNotifier extends $Notifier<TheaterConfig> {
  TheaterConfig build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TheaterConfig, TheaterConfig>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TheaterConfig, TheaterConfig>,
              TheaterConfig,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
