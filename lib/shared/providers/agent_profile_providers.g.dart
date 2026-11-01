// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_profile_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(GlobalAgentProfiles)
final globalAgentProfilesProvider = GlobalAgentProfilesProvider._();

final class GlobalAgentProfilesProvider
    extends $AsyncNotifierProvider<GlobalAgentProfiles, List<AgentProfile>> {
  GlobalAgentProfilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'globalAgentProfilesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$globalAgentProfilesHash();

  @$internal
  @override
  GlobalAgentProfiles create() => GlobalAgentProfiles();
}

String _$globalAgentProfilesHash() =>
    r'8dcff8e1b044f0df25dfa2f2dc50add75c40e42d';

abstract class _$GlobalAgentProfiles
    extends $AsyncNotifier<List<AgentProfile>> {
  FutureOr<List<AgentProfile>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<AgentProfile>>, List<AgentProfile>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<AgentProfile>>, List<AgentProfile>>,
              AsyncValue<List<AgentProfile>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(globalAgentProfilesStream)
final globalAgentProfilesStreamProvider = GlobalAgentProfilesStreamProvider._();

final class GlobalAgentProfilesStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentProfile>>,
          List<AgentProfile>,
          Stream<List<AgentProfile>>
        >
    with
        $FutureModifier<List<AgentProfile>>,
        $StreamProvider<List<AgentProfile>> {
  GlobalAgentProfilesStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'globalAgentProfilesStreamProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$globalAgentProfilesStreamHash();

  @$internal
  @override
  $StreamProviderElement<List<AgentProfile>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<AgentProfile>> create(Ref ref) {
    return globalAgentProfilesStream(ref);
  }
}

String _$globalAgentProfilesStreamHash() =>
    r'aad42941b9faae1c38a42c54c77b9e5bf4c0aa73';

@ProviderFor(NovelAgentProfiles)
final novelAgentProfilesProvider = NovelAgentProfilesFamily._();

final class NovelAgentProfilesProvider
    extends $AsyncNotifierProvider<NovelAgentProfiles, List<AgentProfile>> {
  NovelAgentProfilesProvider._({
    required NovelAgentProfilesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'novelAgentProfilesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$novelAgentProfilesHash();

  @override
  String toString() {
    return r'novelAgentProfilesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  NovelAgentProfiles create() => NovelAgentProfiles();

  @override
  bool operator ==(Object other) {
    return other is NovelAgentProfilesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$novelAgentProfilesHash() =>
    r'68f796af8ea5fa4d3c356aef4620166c1de40a5c';

final class NovelAgentProfilesFamily extends $Family
    with
        $ClassFamilyOverride<
          NovelAgentProfiles,
          AsyncValue<List<AgentProfile>>,
          List<AgentProfile>,
          FutureOr<List<AgentProfile>>,
          String
        > {
  NovelAgentProfilesFamily._()
    : super(
        retry: null,
        name: r'novelAgentProfilesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  NovelAgentProfilesProvider call(String novelId) =>
      NovelAgentProfilesProvider._(argument: novelId, from: this);

  @override
  String toString() => r'novelAgentProfilesProvider';
}

abstract class _$NovelAgentProfiles extends $AsyncNotifier<List<AgentProfile>> {
  late final _$args = ref.$arg as String;
  String get novelId => _$args;

  FutureOr<List<AgentProfile>> build(String novelId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<AgentProfile>>, List<AgentProfile>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<AgentProfile>>, List<AgentProfile>>,
              AsyncValue<List<AgentProfile>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(novelAgentProfilesStream)
final novelAgentProfilesStreamProvider = NovelAgentProfilesStreamFamily._();

final class NovelAgentProfilesStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentProfile>>,
          List<AgentProfile>,
          Stream<List<AgentProfile>>
        >
    with
        $FutureModifier<List<AgentProfile>>,
        $StreamProvider<List<AgentProfile>> {
  NovelAgentProfilesStreamProvider._({
    required NovelAgentProfilesStreamFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'novelAgentProfilesStreamProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$novelAgentProfilesStreamHash();

  @override
  String toString() {
    return r'novelAgentProfilesStreamProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<AgentProfile>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<AgentProfile>> create(Ref ref) {
    final argument = this.argument as String;
    return novelAgentProfilesStream(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is NovelAgentProfilesStreamProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$novelAgentProfilesStreamHash() =>
    r'd14d394661382fed54b8aec2877e58a555ea0b90';

final class NovelAgentProfilesStreamFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<AgentProfile>>, String> {
  NovelAgentProfilesStreamFamily._()
    : super(
        retry: null,
        name: r'novelAgentProfilesStreamProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  NovelAgentProfilesStreamProvider call(String novelId) =>
      NovelAgentProfilesStreamProvider._(argument: novelId, from: this);

  @override
  String toString() => r'novelAgentProfilesStreamProvider';
}

@ProviderFor(mergedAgentProfiles)
final mergedAgentProfilesProvider = MergedAgentProfilesFamily._();

final class MergedAgentProfilesProvider
    extends
        $FunctionalProvider<
          List<AgentProfile>,
          List<AgentProfile>,
          List<AgentProfile>
        >
    with $Provider<List<AgentProfile>> {
  MergedAgentProfilesProvider._({
    required MergedAgentProfilesFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'mergedAgentProfilesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mergedAgentProfilesHash();

  @override
  String toString() {
    return r'mergedAgentProfilesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<AgentProfile>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<AgentProfile> create(Ref ref) {
    final argument = this.argument as String?;
    return mergedAgentProfiles(ref, novelId: argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AgentProfile> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AgentProfile>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MergedAgentProfilesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mergedAgentProfilesHash() =>
    r'7903626635e565894c535c5035bbf8dfe7b7cfe3';

final class MergedAgentProfilesFamily extends $Family
    with $FunctionalFamilyOverride<List<AgentProfile>, String?> {
  MergedAgentProfilesFamily._()
    : super(
        retry: null,
        name: r'mergedAgentProfilesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MergedAgentProfilesProvider call({String? novelId}) =>
      MergedAgentProfilesProvider._(argument: novelId, from: this);

  @override
  String toString() => r'mergedAgentProfilesProvider';
}

@ProviderFor(agentProfileBySlug)
final agentProfileBySlugProvider = AgentProfileBySlugFamily._();

final class AgentProfileBySlugProvider
    extends $FunctionalProvider<AgentProfile?, AgentProfile?, AgentProfile?>
    with $Provider<AgentProfile?> {
  AgentProfileBySlugProvider._({
    required AgentProfileBySlugFamily super.from,
    required ({String slug, String? novelId}) super.argument,
  }) : super(
         retry: null,
         name: r'agentProfileBySlugProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentProfileBySlugHash();

  @override
  String toString() {
    return r'agentProfileBySlugProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<AgentProfile?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AgentProfile? create(Ref ref) {
    final argument = this.argument as ({String slug, String? novelId});
    return agentProfileBySlug(
      ref,
      slug: argument.slug,
      novelId: argument.novelId,
    );
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentProfile? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentProfile?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentProfileBySlugProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentProfileBySlugHash() =>
    r'9ab3a8520a6442f5853d4e993a1724d8dec19ea4';

final class AgentProfileBySlugFamily extends $Family
    with
        $FunctionalFamilyOverride<
          AgentProfile?,
          ({String slug, String? novelId})
        > {
  AgentProfileBySlugFamily._()
    : super(
        retry: null,
        name: r'agentProfileBySlugProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentProfileBySlugProvider call({required String slug, String? novelId}) =>
      AgentProfileBySlugProvider._(
        argument: (slug: slug, novelId: novelId),
        from: this,
      );

  @override
  String toString() => r'agentProfileBySlugProvider';
}
