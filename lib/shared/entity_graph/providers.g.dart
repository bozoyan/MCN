// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(entityRelationsService)
final entityRelationsServiceProvider = EntityRelationsServiceFamily._();

final class EntityRelationsServiceProvider
    extends
        $FunctionalProvider<
          EntityRelationsService,
          EntityRelationsService,
          EntityRelationsService
        >
    with $Provider<EntityRelationsService> {
  EntityRelationsServiceProvider._({
    required EntityRelationsServiceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'entityRelationsServiceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$entityRelationsServiceHash();

  @override
  String toString() {
    return r'entityRelationsServiceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<EntityRelationsService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  EntityRelationsService create(Ref ref) {
    final argument = this.argument as String;
    return entityRelationsService(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EntityRelationsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EntityRelationsService>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EntityRelationsServiceProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$entityRelationsServiceHash() =>
    r'82aed2fc91808a386d8f2440dd3a268d9d7438de';

final class EntityRelationsServiceFamily extends $Family
    with $FunctionalFamilyOverride<EntityRelationsService, String> {
  EntityRelationsServiceFamily._()
    : super(
        retry: null,
        name: r'entityRelationsServiceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  EntityRelationsServiceProvider call(String databasePath) =>
      EntityRelationsServiceProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'entityRelationsServiceProvider';
}

@ProviderFor(allRelations)
final allRelationsProvider = AllRelationsFamily._();

final class AllRelationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RelationSummary>>,
          List<RelationSummary>,
          Stream<List<RelationSummary>>
        >
    with
        $FutureModifier<List<RelationSummary>>,
        $StreamProvider<List<RelationSummary>> {
  AllRelationsProvider._({
    required AllRelationsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'allRelationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$allRelationsHash();

  @override
  String toString() {
    return r'allRelationsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<RelationSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<RelationSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return allRelations(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AllRelationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$allRelationsHash() => r'4b9c4c6f1990675f4b726b20bc8b75696553cab7';

final class AllRelationsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<RelationSummary>>, String> {
  AllRelationsFamily._()
    : super(
        retry: null,
        name: r'allRelationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AllRelationsProvider call(String databasePath) =>
      AllRelationsProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'allRelationsProvider';
}

@ProviderFor(characterNetwork)
final characterNetworkProvider = CharacterNetworkFamily._();

final class CharacterNetworkProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, List<RelationSummary>>>,
          Map<String, List<RelationSummary>>,
          FutureOr<Map<String, List<RelationSummary>>>
        >
    with
        $FutureModifier<Map<String, List<RelationSummary>>>,
        $FutureProvider<Map<String, List<RelationSummary>>> {
  CharacterNetworkProvider._({
    required CharacterNetworkFamily super.from,
    required ({String databasePath, String characterId}) super.argument,
  }) : super(
         retry: null,
         name: r'characterNetworkProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$characterNetworkHash();

  @override
  String toString() {
    return r'characterNetworkProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<Map<String, List<RelationSummary>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, List<RelationSummary>>> create(Ref ref) {
    final argument =
        this.argument as ({String databasePath, String characterId});
    return characterNetwork(
      ref,
      databasePath: argument.databasePath,
      characterId: argument.characterId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CharacterNetworkProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$characterNetworkHash() => r'9b659160c3c5edb57590d2c814b255a02b76103d';

final class CharacterNetworkFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Map<String, List<RelationSummary>>>,
          ({String databasePath, String characterId})
        > {
  CharacterNetworkFamily._()
    : super(
        retry: null,
        name: r'characterNetworkProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CharacterNetworkProvider call({
    required String databasePath,
    required String characterId,
  }) => CharacterNetworkProvider._(
    argument: (databasePath: databasePath, characterId: characterId),
    from: this,
  );

  @override
  String toString() => r'characterNetworkProvider';
}

@ProviderFor(entityGraphNodeDetail)
final entityGraphNodeDetailProvider = EntityGraphNodeDetailFamily._();

final class EntityGraphNodeDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<EntityGraphNodeDetail?>,
          EntityGraphNodeDetail?,
          FutureOr<EntityGraphNodeDetail?>
        >
    with
        $FutureModifier<EntityGraphNodeDetail?>,
        $FutureProvider<EntityGraphNodeDetail?> {
  EntityGraphNodeDetailProvider._({
    required EntityGraphNodeDetailFamily super.from,
    required ({String databasePath, String entityType, String entityId})
    super.argument,
  }) : super(
         retry: null,
         name: r'entityGraphNodeDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$entityGraphNodeDetailHash();

  @override
  String toString() {
    return r'entityGraphNodeDetailProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<EntityGraphNodeDetail?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<EntityGraphNodeDetail?> create(Ref ref) {
    final argument =
        this.argument
            as ({String databasePath, String entityType, String entityId});
    return entityGraphNodeDetail(
      ref,
      databasePath: argument.databasePath,
      entityType: argument.entityType,
      entityId: argument.entityId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EntityGraphNodeDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$entityGraphNodeDetailHash() =>
    r'6bf06f75289a52e46773334c7822c0a6ffb93c51';

final class EntityGraphNodeDetailFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<EntityGraphNodeDetail?>,
          ({String databasePath, String entityType, String entityId})
        > {
  EntityGraphNodeDetailFamily._()
    : super(
        retry: null,
        name: r'entityGraphNodeDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  EntityGraphNodeDetailProvider call({
    required String databasePath,
    required String entityType,
    required String entityId,
  }) => EntityGraphNodeDetailProvider._(
    argument: (
      databasePath: databasePath,
      entityType: entityType,
      entityId: entityId,
    ),
    from: this,
  );

  @override
  String toString() => r'entityGraphNodeDetailProvider';
}
