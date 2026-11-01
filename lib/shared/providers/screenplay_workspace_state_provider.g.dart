// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'screenplay_workspace_state_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ScreenplayWorkspaceStateController)
final screenplayWorkspaceStateControllerProvider =
    ScreenplayWorkspaceStateControllerFamily._();

final class ScreenplayWorkspaceStateControllerProvider
    extends
        $NotifierProvider<
          ScreenplayWorkspaceStateController,
          ScreenplayWorkspaceState
        > {
  ScreenplayWorkspaceStateControllerProvider._({
    required ScreenplayWorkspaceStateControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayWorkspaceStateControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$screenplayWorkspaceStateControllerHash();

  @override
  String toString() {
    return r'screenplayWorkspaceStateControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ScreenplayWorkspaceStateController create() =>
      ScreenplayWorkspaceStateController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ScreenplayWorkspaceState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ScreenplayWorkspaceState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayWorkspaceStateControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayWorkspaceStateControllerHash() =>
    r'c15d0d8997ece6deee5fe88155ff07508aaf612f';

final class ScreenplayWorkspaceStateControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ScreenplayWorkspaceStateController,
          ScreenplayWorkspaceState,
          ScreenplayWorkspaceState,
          ScreenplayWorkspaceState,
          (String, String)
        > {
  ScreenplayWorkspaceStateControllerFamily._()
    : super(
        retry: null,
        name: r'screenplayWorkspaceStateControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplayWorkspaceStateControllerProvider call(
    String workId,
    String databasePath,
  ) => ScreenplayWorkspaceStateControllerProvider._(
    argument: (workId, databasePath),
    from: this,
  );

  @override
  String toString() => r'screenplayWorkspaceStateControllerProvider';
}

abstract class _$ScreenplayWorkspaceStateController
    extends $Notifier<ScreenplayWorkspaceState> {
  late final _$args = ref.$arg as (String, String);
  String get workId => _$args.$1;
  String get databasePath => _$args.$2;

  ScreenplayWorkspaceState build(String workId, String databasePath);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<ScreenplayWorkspaceState, ScreenplayWorkspaceState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ScreenplayWorkspaceState, ScreenplayWorkspaceState>,
              ScreenplayWorkspaceState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
