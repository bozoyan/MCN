// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_id_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Device ID 服务 Provider。

@ProviderFor(deviceIdService)
final deviceIdServiceProvider = DeviceIdServiceProvider._();

/// Device ID 服务 Provider。

final class DeviceIdServiceProvider
    extends
        $FunctionalProvider<DeviceIdService, DeviceIdService, DeviceIdService>
    with $Provider<DeviceIdService> {
  /// Device ID 服务 Provider。
  DeviceIdServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceIdServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceIdServiceHash();

  @$internal
  @override
  $ProviderElement<DeviceIdService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DeviceIdService create(Ref ref) {
    return deviceIdService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeviceIdService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeviceIdService>(value),
    );
  }
}

String _$deviceIdServiceHash() => r'09da18b9d8c5888913a45cc6a5b94d2e8ff60351';
