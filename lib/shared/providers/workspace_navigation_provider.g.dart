// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_navigation_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 桌面端「最近改动」→ 工作区跳转的一次性信号。写入后由 novel_editor 监听消费并立即 [clear]。

@ProviderFor(WorkspaceNavigation)
final workspaceNavigationProvider = WorkspaceNavigationProvider._();

/// 桌面端「最近改动」→ 工作区跳转的一次性信号。写入后由 novel_editor 监听消费并立即 [clear]。
final class WorkspaceNavigationProvider
    extends
        $NotifierProvider<WorkspaceNavigation, WorkspaceNavigationRequest?> {
  /// 桌面端「最近改动」→ 工作区跳转的一次性信号。写入后由 novel_editor 监听消费并立即 [clear]。
  WorkspaceNavigationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceNavigationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceNavigationHash();

  @$internal
  @override
  WorkspaceNavigation create() => WorkspaceNavigation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceNavigationRequest? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceNavigationRequest?>(value),
    );
  }
}

String _$workspaceNavigationHash() =>
    r'ab4ee42d01835039603249b7e0443326da20b995';

/// 桌面端「最近改动」→ 工作区跳转的一次性信号。写入后由 novel_editor 监听消费并立即 [clear]。

abstract class _$WorkspaceNavigation
    extends $Notifier<WorkspaceNavigationRequest?> {
  WorkspaceNavigationRequest? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<WorkspaceNavigationRequest?, WorkspaceNavigationRequest?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                WorkspaceNavigationRequest?,
                WorkspaceNavigationRequest?
              >,
              WorkspaceNavigationRequest?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
