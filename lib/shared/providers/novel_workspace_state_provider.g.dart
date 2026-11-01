// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'novel_workspace_state_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(NovelWorkspaceStateController)
final novelWorkspaceStateControllerProvider =
    NovelWorkspaceStateControllerFamily._();

final class NovelWorkspaceStateControllerProvider
    extends
        $NotifierProvider<
          NovelWorkspaceStateController,
          NovelWorkspaceStateData
        > {
  NovelWorkspaceStateControllerProvider._({
    required NovelWorkspaceStateControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'novelWorkspaceStateControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$novelWorkspaceStateControllerHash();

  @override
  String toString() {
    return r'novelWorkspaceStateControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  NovelWorkspaceStateController create() => NovelWorkspaceStateController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NovelWorkspaceStateData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NovelWorkspaceStateData>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NovelWorkspaceStateControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$novelWorkspaceStateControllerHash() =>
    r'0db0a7b5d772d56a5db169b63bea8e6b2ba8d230';

final class NovelWorkspaceStateControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          NovelWorkspaceStateController,
          NovelWorkspaceStateData,
          NovelWorkspaceStateData,
          NovelWorkspaceStateData,
          String
        > {
  NovelWorkspaceStateControllerFamily._()
    : super(
        retry: null,
        name: r'novelWorkspaceStateControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  NovelWorkspaceStateControllerProvider call(String novelId) =>
      NovelWorkspaceStateControllerProvider._(argument: novelId, from: this);

  @override
  String toString() => r'novelWorkspaceStateControllerProvider';
}

abstract class _$NovelWorkspaceStateController
    extends $Notifier<NovelWorkspaceStateData> {
  late final _$args = ref.$arg as String;
  String get novelId => _$args;

  NovelWorkspaceStateData build(String novelId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<NovelWorkspaceStateData, NovelWorkspaceStateData>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NovelWorkspaceStateData, NovelWorkspaceStateData>,
              NovelWorkspaceStateData,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
