// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'maps_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(locationsService)
final locationsServiceProvider = LocationsServiceFamily._();

final class LocationsServiceProvider
    extends
        $FunctionalProvider<
          LocationsService,
          LocationsService,
          LocationsService
        >
    with $Provider<LocationsService> {
  LocationsServiceProvider._({
    required LocationsServiceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'locationsServiceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$locationsServiceHash();

  @override
  String toString() {
    return r'locationsServiceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<LocationsService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LocationsService create(Ref ref) {
    final argument = this.argument as String;
    return locationsService(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocationsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LocationsService>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LocationsServiceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$locationsServiceHash() => r'c919f6eaea9a177b11e51ba1ac4f9cfd929f5722';

final class LocationsServiceFamily extends $Family
    with $FunctionalFamilyOverride<LocationsService, String> {
  LocationsServiceFamily._()
    : super(
        retry: null,
        name: r'locationsServiceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LocationsServiceProvider call(String databasePath) =>
      LocationsServiceProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'locationsServiceProvider';
}

@ProviderFor(mapsService)
final mapsServiceProvider = MapsServiceFamily._();

final class MapsServiceProvider
    extends $FunctionalProvider<MapsService, MapsService, MapsService>
    with $Provider<MapsService> {
  MapsServiceProvider._({
    required MapsServiceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mapsServiceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mapsServiceHash();

  @override
  String toString() {
    return r'mapsServiceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<MapsService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MapsService create(Ref ref) {
    final argument = this.argument as String;
    return mapsService(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MapsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MapsService>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MapsServiceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mapsServiceHash() => r'2f3aac84c54dc376847952b23fdcd504f673a6bb';

final class MapsServiceFamily extends $Family
    with $FunctionalFamilyOverride<MapsService, String> {
  MapsServiceFamily._()
    : super(
        retry: null,
        name: r'mapsServiceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MapsServiceProvider call(String databasePath) =>
      MapsServiceProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'mapsServiceProvider';
}

@ProviderFor(mapLocationsService)
final mapLocationsServiceProvider = MapLocationsServiceFamily._();

final class MapLocationsServiceProvider
    extends
        $FunctionalProvider<
          MapLocationsService,
          MapLocationsService,
          MapLocationsService
        >
    with $Provider<MapLocationsService> {
  MapLocationsServiceProvider._({
    required MapLocationsServiceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mapLocationsServiceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mapLocationsServiceHash();

  @override
  String toString() {
    return r'mapLocationsServiceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<MapLocationsService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MapLocationsService create(Ref ref) {
    final argument = this.argument as String;
    return mapLocationsService(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MapLocationsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MapLocationsService>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MapLocationsServiceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mapLocationsServiceHash() =>
    r'bbeefab28f2f9e245c3b788ff556d020f6a12ba5';

final class MapLocationsServiceFamily extends $Family
    with $FunctionalFamilyOverride<MapLocationsService, String> {
  MapLocationsServiceFamily._()
    : super(
        retry: null,
        name: r'mapLocationsServiceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MapLocationsServiceProvider call(String databasePath) =>
      MapLocationsServiceProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'mapLocationsServiceProvider';
}

@ProviderFor(locations)
final locationsProvider = LocationsFamily._();

final class LocationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Location>>,
          List<Location>,
          Stream<List<Location>>
        >
    with $FutureModifier<List<Location>>, $StreamProvider<List<Location>> {
  LocationsProvider._({
    required LocationsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'locationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$locationsHash();

  @override
  String toString() {
    return r'locationsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Location>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Location>> create(Ref ref) {
    final argument = this.argument as String;
    return locations(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LocationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$locationsHash() => r'877da65aa6ea0f3497ccade46cdd2d502ebe7348';

final class LocationsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Location>>, String> {
  LocationsFamily._()
    : super(
        retry: null,
        name: r'locationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LocationsProvider call(String databasePath) =>
      LocationsProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'locationsProvider';
}

@ProviderFor(locationById)
final locationByIdProvider = LocationByIdFamily._();

final class LocationByIdProvider
    extends $FunctionalProvider<Location?, Location?, Location?>
    with $Provider<Location?> {
  LocationByIdProvider._({
    required LocationByIdFamily super.from,
    required ({String databasePath, String locationId}) super.argument,
  }) : super(
         retry: null,
         name: r'locationByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$locationByIdHash();

  @override
  String toString() {
    return r'locationByIdProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<Location?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Location? create(Ref ref) {
    final argument =
        this.argument as ({String databasePath, String locationId});
    return locationById(
      ref,
      databasePath: argument.databasePath,
      locationId: argument.locationId,
    );
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Location? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Location?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LocationByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$locationByIdHash() => r'52b3e895189c9d19285553b54f45dd9ec433ea0b';

final class LocationByIdFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Location?,
          ({String databasePath, String locationId})
        > {
  LocationByIdFamily._()
    : super(
        retry: null,
        name: r'locationByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LocationByIdProvider call({
    required String databasePath,
    required String locationId,
  }) => LocationByIdProvider._(
    argument: (databasePath: databasePath, locationId: locationId),
    from: this,
  );

  @override
  String toString() => r'locationByIdProvider';
}

@ProviderFor(maps)
final mapsProvider = MapsFamily._();

final class MapsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<NovelMap>>,
          List<NovelMap>,
          Stream<List<NovelMap>>
        >
    with $FutureModifier<List<NovelMap>>, $StreamProvider<List<NovelMap>> {
  MapsProvider._({
    required MapsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mapsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mapsHash();

  @override
  String toString() {
    return r'mapsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<NovelMap>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<NovelMap>> create(Ref ref) {
    final argument = this.argument as String;
    return maps(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MapsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mapsHash() => r'853d0cdf41055f9894678f14f306b08652fd86b1';

final class MapsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<NovelMap>>, String> {
  MapsFamily._()
    : super(
        retry: null,
        name: r'mapsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MapsProvider call(String databasePath) =>
      MapsProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'mapsProvider';
}

@ProviderFor(mapById)
final mapByIdProvider = MapByIdFamily._();

final class MapByIdProvider
    extends $FunctionalProvider<NovelMap?, NovelMap?, NovelMap?>
    with $Provider<NovelMap?> {
  MapByIdProvider._({
    required MapByIdFamily super.from,
    required ({String databasePath, String mapId}) super.argument,
  }) : super(
         retry: null,
         name: r'mapByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mapByIdHash();

  @override
  String toString() {
    return r'mapByIdProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<NovelMap?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NovelMap? create(Ref ref) {
    final argument = this.argument as ({String databasePath, String mapId});
    return mapById(
      ref,
      databasePath: argument.databasePath,
      mapId: argument.mapId,
    );
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NovelMap? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NovelMap?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MapByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mapByIdHash() => r'2b25d40d44d60fbc7d2fe976968b2ee7f1c90cd9';

final class MapByIdFamily extends $Family
    with
        $FunctionalFamilyOverride<
          NovelMap?,
          ({String databasePath, String mapId})
        > {
  MapByIdFamily._()
    : super(
        retry: null,
        name: r'mapByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MapByIdProvider call({required String databasePath, required String mapId}) =>
      MapByIdProvider._(
        argument: (databasePath: databasePath, mapId: mapId),
        from: this,
      );

  @override
  String toString() => r'mapByIdProvider';
}

@ProviderFor(mapLocations)
final mapLocationsProvider = MapLocationsFamily._();

final class MapLocationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MapLocation>>,
          List<MapLocation>,
          Stream<List<MapLocation>>
        >
    with
        $FutureModifier<List<MapLocation>>,
        $StreamProvider<List<MapLocation>> {
  MapLocationsProvider._({
    required MapLocationsFamily super.from,
    required ({String databasePath, String mapId}) super.argument,
  }) : super(
         retry: null,
         name: r'mapLocationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mapLocationsHash();

  @override
  String toString() {
    return r'mapLocationsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<MapLocation>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<MapLocation>> create(Ref ref) {
    final argument = this.argument as ({String databasePath, String mapId});
    return mapLocations(
      ref,
      databasePath: argument.databasePath,
      mapId: argument.mapId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MapLocationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mapLocationsHash() => r'31b40baf1f1d5c202e9f10470fb032afa1e4e7bf';

final class MapLocationsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<MapLocation>>,
          ({String databasePath, String mapId})
        > {
  MapLocationsFamily._()
    : super(
        retry: null,
        name: r'mapLocationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MapLocationsProvider call({
    required String databasePath,
    required String mapId,
  }) => MapLocationsProvider._(
    argument: (databasePath: databasePath, mapId: mapId),
    from: this,
  );

  @override
  String toString() => r'mapLocationsProvider';
}
