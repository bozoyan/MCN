// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trace_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Trace 上报服务 Provider（全局单例，keepAlive）
///

@ProviderFor(traceReporterService)
final traceReporterServiceProvider = TraceReporterServiceProvider._();

/// Trace 上报服务 Provider（全局单例，keepAlive）
///

final class TraceReporterServiceProvider
    extends
        $FunctionalProvider<
          TraceReporterService,
          TraceReporterService,
          TraceReporterService
        >
    with $Provider<TraceReporterService> {
  /// Trace 上报服务 Provider（全局单例，keepAlive）
  ///
  TraceReporterServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'traceReporterServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$traceReporterServiceHash();

  @$internal
  @override
  $ProviderElement<TraceReporterService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TraceReporterService create(Ref ref) {
    return traceReporterService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TraceReporterService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TraceReporterService>(value),
    );
  }
}

String _$traceReporterServiceHash() =>
    r'c7ea1bb35f25bf379907a3a593528a7868e90032';
