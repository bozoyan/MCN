// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subagent_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(GlobalSubAgents)
final globalSubAgentsProvider = GlobalSubAgentsProvider._();

final class GlobalSubAgentsProvider
    extends $AsyncNotifierProvider<GlobalSubAgents, List<SubAgent>> {
  GlobalSubAgentsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'globalSubAgentsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$globalSubAgentsHash();

  @$internal
  @override
  GlobalSubAgents create() => GlobalSubAgents();
}

String _$globalSubAgentsHash() => r'7f2f2f0029ba178abde17914bf33ada5fc402251';

abstract class _$GlobalSubAgents extends $AsyncNotifier<List<SubAgent>> {
  FutureOr<List<SubAgent>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<SubAgent>>, List<SubAgent>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<SubAgent>>, List<SubAgent>>,
              AsyncValue<List<SubAgent>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(globalSubAgentsStream)
final globalSubAgentsStreamProvider = GlobalSubAgentsStreamProvider._();

final class GlobalSubAgentsStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SubAgent>>,
          List<SubAgent>,
          Stream<List<SubAgent>>
        >
    with $FutureModifier<List<SubAgent>>, $StreamProvider<List<SubAgent>> {
  GlobalSubAgentsStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'globalSubAgentsStreamProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$globalSubAgentsStreamHash();

  @$internal
  @override
  $StreamProviderElement<List<SubAgent>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<SubAgent>> create(Ref ref) {
    return globalSubAgentsStream(ref);
  }
}

String _$globalSubAgentsStreamHash() =>
    r'b4f598a59de966b1fd03de645e7ce0570af26334';

@ProviderFor(NovelSubAgents)
final novelSubAgentsProvider = NovelSubAgentsFamily._();

final class NovelSubAgentsProvider
    extends $AsyncNotifierProvider<NovelSubAgents, List<SubAgent>> {
  NovelSubAgentsProvider._({
    required NovelSubAgentsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'novelSubAgentsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$novelSubAgentsHash();

  @override
  String toString() {
    return r'novelSubAgentsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  NovelSubAgents create() => NovelSubAgents();

  @override
  bool operator ==(Object other) {
    return other is NovelSubAgentsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$novelSubAgentsHash() => r'093bf7d5c77092f7e9c5cde790b090e28983cac9';

final class NovelSubAgentsFamily extends $Family
    with
        $ClassFamilyOverride<
          NovelSubAgents,
          AsyncValue<List<SubAgent>>,
          List<SubAgent>,
          FutureOr<List<SubAgent>>,
          String
        > {
  NovelSubAgentsFamily._()
    : super(
        retry: null,
        name: r'novelSubAgentsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  NovelSubAgentsProvider call(String novelId) =>
      NovelSubAgentsProvider._(argument: novelId, from: this);

  @override
  String toString() => r'novelSubAgentsProvider';
}

abstract class _$NovelSubAgents extends $AsyncNotifier<List<SubAgent>> {
  late final _$args = ref.$arg as String;
  String get novelId => _$args;

  FutureOr<List<SubAgent>> build(String novelId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<SubAgent>>, List<SubAgent>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<SubAgent>>, List<SubAgent>>,
              AsyncValue<List<SubAgent>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(novelSubAgentsStream)
final novelSubAgentsStreamProvider = NovelSubAgentsStreamFamily._();

final class NovelSubAgentsStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SubAgent>>,
          List<SubAgent>,
          Stream<List<SubAgent>>
        >
    with $FutureModifier<List<SubAgent>>, $StreamProvider<List<SubAgent>> {
  NovelSubAgentsStreamProvider._({
    required NovelSubAgentsStreamFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'novelSubAgentsStreamProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$novelSubAgentsStreamHash();

  @override
  String toString() {
    return r'novelSubAgentsStreamProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<SubAgent>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<SubAgent>> create(Ref ref) {
    final argument = this.argument as String;
    return novelSubAgentsStream(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is NovelSubAgentsStreamProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$novelSubAgentsStreamHash() =>
    r'ccbb9f4d20cdce7cf34b2ae5c6c8a9ba8d3146f0';

final class NovelSubAgentsStreamFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<SubAgent>>, String> {
  NovelSubAgentsStreamFamily._()
    : super(
        retry: null,
        name: r'novelSubAgentsStreamProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  NovelSubAgentsStreamProvider call(String novelId) =>
      NovelSubAgentsStreamProvider._(argument: novelId, from: this);

  @override
  String toString() => r'novelSubAgentsStreamProvider';
}

@ProviderFor(mergedSubAgents)
final mergedSubAgentsProvider = MergedSubAgentsProvider._();

final class MergedSubAgentsProvider
    extends $FunctionalProvider<List<SubAgent>, List<SubAgent>, List<SubAgent>>
    with $Provider<List<SubAgent>> {
  MergedSubAgentsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mergedSubAgentsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mergedSubAgentsHash();

  @$internal
  @override
  $ProviderElement<List<SubAgent>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<SubAgent> create(Ref ref) {
    return mergedSubAgents(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<SubAgent> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<SubAgent>>(value),
    );
  }
}

String _$mergedSubAgentsHash() => r'b4be7675d69c99dca33e61001e9f049792827099';
