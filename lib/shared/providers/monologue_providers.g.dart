// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monologue_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MonologueActiveRun)
final monologueActiveRunProvider = MonologueActiveRunFamily._();

final class MonologueActiveRunProvider
    extends $NotifierProvider<MonologueActiveRun, AgentRunState?> {
  MonologueActiveRunProvider._({
    required MonologueActiveRunFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'monologueActiveRunProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$monologueActiveRunHash();

  @override
  String toString() {
    return r'monologueActiveRunProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MonologueActiveRun create() => MonologueActiveRun();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentRunState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentRunState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MonologueActiveRunProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$monologueActiveRunHash() =>
    r'811e638ea61d433b8d7168b556a699a0ff993e1a';

final class MonologueActiveRunFamily extends $Family
    with
        $ClassFamilyOverride<
          MonologueActiveRun,
          AgentRunState?,
          AgentRunState?,
          AgentRunState?,
          String?
        > {
  MonologueActiveRunFamily._()
    : super(
        retry: null,
        name: r'monologueActiveRunProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  MonologueActiveRunProvider call(String? sessionId) =>
      MonologueActiveRunProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'monologueActiveRunProvider';
}

abstract class _$MonologueActiveRun extends $Notifier<AgentRunState?> {
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

@ProviderFor(MonologueRunHistoryStore)
final monologueRunHistoryStoreProvider = MonologueRunHistoryStoreFamily._();

final class MonologueRunHistoryStoreProvider
    extends
        $NotifierProvider<
          MonologueRunHistoryStore,
          Map<String, AgentRunState>
        > {
  MonologueRunHistoryStoreProvider._({
    required MonologueRunHistoryStoreFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'monologueRunHistoryStoreProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$monologueRunHistoryStoreHash();

  @override
  String toString() {
    return r'monologueRunHistoryStoreProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MonologueRunHistoryStore create() => MonologueRunHistoryStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AgentRunState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AgentRunState>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MonologueRunHistoryStoreProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$monologueRunHistoryStoreHash() =>
    r'b431028aca21501266d10ebbd26d6eaae3d0f5c9';

final class MonologueRunHistoryStoreFamily extends $Family
    with
        $ClassFamilyOverride<
          MonologueRunHistoryStore,
          Map<String, AgentRunState>,
          Map<String, AgentRunState>,
          Map<String, AgentRunState>,
          String?
        > {
  MonologueRunHistoryStoreFamily._()
    : super(
        retry: null,
        name: r'monologueRunHistoryStoreProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  MonologueRunHistoryStoreProvider call(String? sessionId) =>
      MonologueRunHistoryStoreProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'monologueRunHistoryStoreProvider';
}

abstract class _$MonologueRunHistoryStore
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

@ProviderFor(MonologueRuntime)
final monologueRuntimeProvider = MonologueRuntimeFamily._();

final class MonologueRuntimeProvider
    extends $NotifierProvider<MonologueRuntime, AiModeRuntimeState> {
  MonologueRuntimeProvider._({
    required MonologueRuntimeFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'monologueRuntimeProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$monologueRuntimeHash();

  @override
  String toString() {
    return r'monologueRuntimeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MonologueRuntime create() => MonologueRuntime();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiModeRuntimeState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiModeRuntimeState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MonologueRuntimeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$monologueRuntimeHash() => r'086014543c8b5dfddf701c740f1a817c9c2b3680';

final class MonologueRuntimeFamily extends $Family
    with
        $ClassFamilyOverride<
          MonologueRuntime,
          AiModeRuntimeState,
          AiModeRuntimeState,
          AiModeRuntimeState,
          String?
        > {
  MonologueRuntimeFamily._()
    : super(
        retry: null,
        name: r'monologueRuntimeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  MonologueRuntimeProvider call(String? sessionId) =>
      MonologueRuntimeProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'monologueRuntimeProvider';
}

abstract class _$MonologueRuntime extends $Notifier<AiModeRuntimeState> {
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

@ProviderFor(MonologueSessionNotifier)
final monologueSessionProvider = MonologueSessionNotifierFamily._();

final class MonologueSessionNotifierProvider
    extends $NotifierProvider<MonologueSessionNotifier, MonologueSession?> {
  MonologueSessionNotifierProvider._({
    required MonologueSessionNotifierFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'monologueSessionProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$monologueSessionNotifierHash();

  @override
  String toString() {
    return r'monologueSessionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MonologueSessionNotifier create() => MonologueSessionNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MonologueSession? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MonologueSession?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MonologueSessionNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$monologueSessionNotifierHash() =>
    r'2f3120935a7f8b78a104239a7d36f4df93ae7cbe';

final class MonologueSessionNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          MonologueSessionNotifier,
          MonologueSession?,
          MonologueSession?,
          MonologueSession?,
          String?
        > {
  MonologueSessionNotifierFamily._()
    : super(
        retry: null,
        name: r'monologueSessionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  MonologueSessionNotifierProvider call(String? sessionId) =>
      MonologueSessionNotifierProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'monologueSessionProvider';
}

abstract class _$MonologueSessionNotifier extends $Notifier<MonologueSession?> {
  late final _$args = ref.$arg as String?;
  String? get sessionId => _$args;

  MonologueSession? build(String? sessionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MonologueSession?, MonologueSession?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MonologueSession?, MonologueSession?>,
              MonologueSession?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(MonologueConfigNotifier)
final monologueConfigProvider = MonologueConfigNotifierProvider._();

final class MonologueConfigNotifierProvider
    extends $NotifierProvider<MonologueConfigNotifier, MonologueConfig> {
  MonologueConfigNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'monologueConfigProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$monologueConfigNotifierHash();

  @$internal
  @override
  MonologueConfigNotifier create() => MonologueConfigNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MonologueConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MonologueConfig>(value),
    );
  }
}

String _$monologueConfigNotifierHash() =>
    r'ab354392f1c16a6f950d06d6fed9c45d40ae5ff9';

abstract class _$MonologueConfigNotifier extends $Notifier<MonologueConfig> {
  MonologueConfig build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MonologueConfig, MonologueConfig>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MonologueConfig, MonologueConfig>,
              MonologueConfig,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
