// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'codemode_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(codemodeScheduler)
final codemodeSchedulerProvider = CodemodeSchedulerProvider._();

final class CodemodeSchedulerProvider
    extends
        $FunctionalProvider<
          CodemodeScheduler,
          CodemodeScheduler,
          CodemodeScheduler
        >
    with $Provider<CodemodeScheduler> {
  CodemodeSchedulerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'codemodeSchedulerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$codemodeSchedulerHash();

  @$internal
  @override
  $ProviderElement<CodemodeScheduler> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CodemodeScheduler create(Ref ref) {
    return codemodeScheduler(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CodemodeScheduler value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CodemodeScheduler>(value),
    );
  }
}

String _$codemodeSchedulerHash() => r'f46fa22d9d58f023fe8f552681074303ed60db9f';
