// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'novel_collection_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(novelCollections)
final novelCollectionsProvider = NovelCollectionsProvider._();

final class NovelCollectionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LibraryCollection>>,
          List<LibraryCollection>,
          Stream<List<LibraryCollection>>
        >
    with
        $FutureModifier<List<LibraryCollection>>,
        $StreamProvider<List<LibraryCollection>> {
  NovelCollectionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'novelCollectionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$novelCollectionsHash();

  @$internal
  @override
  $StreamProviderElement<List<LibraryCollection>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<LibraryCollection>> create(Ref ref) {
    return novelCollections(ref);
  }
}

String _$novelCollectionsHash() => r'e9b3251b6e83f05a24ea8220061d7e1f4e2734ae';

/// [contentKind] 是作品区的类型筛选，null 表示全部类型。

@ProviderFor(collectionCounts)
final collectionCountsProvider = CollectionCountsFamily._();

/// [contentKind] 是作品区的类型筛选，null 表示全部类型。

final class CollectionCountsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, int?>>,
          Map<String, int?>,
          Stream<Map<String, int?>>
        >
    with
        $FutureModifier<Map<String, int?>>,
        $StreamProvider<Map<String, int?>> {
  /// [contentKind] 是作品区的类型筛选，null 表示全部类型。
  CollectionCountsProvider._({
    required CollectionCountsFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'collectionCountsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$collectionCountsHash();

  @override
  String toString() {
    return r'collectionCountsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Map<String, int?>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, int?>> create(Ref ref) {
    final argument = this.argument as String?;
    return collectionCounts(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CollectionCountsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$collectionCountsHash() => r'5a34e2e2cb641a44064cd39e6cac6c4befc40d37';

/// [contentKind] 是作品区的类型筛选，null 表示全部类型。

final class CollectionCountsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Map<String, int?>>, String?> {
  CollectionCountsFamily._()
    : super(
        retry: null,
        name: r'collectionCountsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// [contentKind] 是作品区的类型筛选，null 表示全部类型。

  CollectionCountsProvider call(String? contentKind) =>
      CollectionCountsProvider._(argument: contentKind, from: this);

  @override
  String toString() => r'collectionCountsProvider';
}

@ProviderFor(collectionWorks)
final collectionWorksProvider = CollectionWorksFamily._();

final class CollectionWorksProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Novel>>,
          List<Novel>,
          Stream<List<Novel>>
        >
    with $FutureModifier<List<Novel>>, $StreamProvider<List<Novel>> {
  CollectionWorksProvider._({
    required CollectionWorksFamily super.from,
    required (String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'collectionWorksProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$collectionWorksHash();

  @override
  String toString() {
    return r'collectionWorksProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<Novel>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Novel>> create(Ref ref) {
    final argument = this.argument as (String, String?);
    return collectionWorks(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is CollectionWorksProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$collectionWorksHash() => r'bf1cfad7e8268f4b53de031d1f6ef0fcbbac82df';

final class CollectionWorksFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Novel>>, (String, String?)> {
  CollectionWorksFamily._()
    : super(
        retry: null,
        name: r'collectionWorksProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CollectionWorksProvider call(String id, String? contentKind) =>
      CollectionWorksProvider._(argument: (id, contentKind), from: this);

  @override
  String toString() => r'collectionWorksProvider';
}

@ProviderFor(collectionMemberships)
final collectionMembershipsProvider = CollectionMembershipsFamily._();

final class CollectionMembershipsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, Set<String>>>,
          Map<String, Set<String>>,
          Stream<Map<String, Set<String>>>
        >
    with
        $FutureModifier<Map<String, Set<String>>>,
        $StreamProvider<Map<String, Set<String>>> {
  CollectionMembershipsProvider._({
    required CollectionMembershipsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'collectionMembershipsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$collectionMembershipsHash();

  @override
  String toString() {
    return r'collectionMembershipsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Map<String, Set<String>>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, Set<String>>> create(Ref ref) {
    final argument = this.argument as String;
    return collectionMemberships(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CollectionMembershipsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$collectionMembershipsHash() =>
    r'73c4a473fb01b55f14f07961503a1a54091f7331';

final class CollectionMembershipsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Map<String, Set<String>>>, String> {
  CollectionMembershipsFamily._()
    : super(
        retry: null,
        name: r'collectionMembershipsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CollectionMembershipsProvider call(String workIdsKey) =>
      CollectionMembershipsProvider._(argument: workIdsKey, from: this);

  @override
  String toString() => r'collectionMembershipsProvider';
}

@ProviderFor(collectionOrder)
final collectionOrderProvider = CollectionOrderProvider._();

final class CollectionOrderProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>?>,
          List<String>?,
          Stream<List<String>?>
        >
    with $FutureModifier<List<String>?>, $StreamProvider<List<String>?> {
  CollectionOrderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'collectionOrderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$collectionOrderHash();

  @$internal
  @override
  $StreamProviderElement<List<String>?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<String>?> create(Ref ref) {
    return collectionOrder(ref);
  }
}

String _$collectionOrderHash() => r'0590b34998fd2ec969cfd0427ef8e65ecd9d43c0';

@ProviderFor(orderedCollections)
final orderedCollectionsProvider = OrderedCollectionsProvider._();

final class OrderedCollectionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LibraryCollection>>,
          List<LibraryCollection>,
          FutureOr<List<LibraryCollection>>
        >
    with
        $FutureModifier<List<LibraryCollection>>,
        $FutureProvider<List<LibraryCollection>> {
  OrderedCollectionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'orderedCollectionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$orderedCollectionsHash();

  @$internal
  @override
  $FutureProviderElement<List<LibraryCollection>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<LibraryCollection>> create(Ref ref) {
    return orderedCollections(ref);
  }
}

String _$orderedCollectionsHash() =>
    r'e8a7632cfe3a6438aad250ec5f5570963f52083b';
