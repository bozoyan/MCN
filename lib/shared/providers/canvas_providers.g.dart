// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'canvas_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 每本小说(per-novel NovelContentDatabase)一个 CanvasService。
///
/// family 键为 `databasePath`,与 [novelContentDatabaseProvider] 及
/// entityRelations/foreshadowings 等同级 content provider 一致——canvas
/// 表位于 per-novel 的 NovelContentDatabase,需注入该库而非全局 appDatabase。

@ProviderFor(canvasService)
final canvasServiceProvider = CanvasServiceFamily._();

/// 每本小说(per-novel NovelContentDatabase)一个 CanvasService。
///
/// family 键为 `databasePath`,与 [novelContentDatabaseProvider] 及
/// entityRelations/foreshadowings 等同级 content provider 一致——canvas
/// 表位于 per-novel 的 NovelContentDatabase,需注入该库而非全局 appDatabase。

final class CanvasServiceProvider
    extends $FunctionalProvider<CanvasService, CanvasService, CanvasService>
    with $Provider<CanvasService> {
  /// 每本小说(per-novel NovelContentDatabase)一个 CanvasService。
  ///
  /// family 键为 `databasePath`,与 [novelContentDatabaseProvider] 及
  /// entityRelations/foreshadowings 等同级 content provider 一致——canvas
  /// 表位于 per-novel 的 NovelContentDatabase,需注入该库而非全局 appDatabase。
  CanvasServiceProvider._({
    required CanvasServiceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'canvasServiceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$canvasServiceHash();

  @override
  String toString() {
    return r'canvasServiceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<CanvasService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CanvasService create(Ref ref) {
    final argument = this.argument as String;
    return canvasService(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanvasService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CanvasService>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CanvasServiceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$canvasServiceHash() => r'dec26637f4a3647a73a6506f4ba84e62242af9c9';

/// 每本小说(per-novel NovelContentDatabase)一个 CanvasService。
///
/// family 键为 `databasePath`,与 [novelContentDatabaseProvider] 及
/// entityRelations/foreshadowings 等同级 content provider 一致——canvas
/// 表位于 per-novel 的 NovelContentDatabase,需注入该库而非全局 appDatabase。

final class CanvasServiceFamily extends $Family
    with $FunctionalFamilyOverride<CanvasService, String> {
  CanvasServiceFamily._()
    : super(
        retry: null,
        name: r'canvasServiceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 每本小说(per-novel NovelContentDatabase)一个 CanvasService。
  ///
  /// family 键为 `databasePath`,与 [novelContentDatabaseProvider] 及
  /// entityRelations/foreshadowings 等同级 content provider 一致——canvas
  /// 表位于 per-novel 的 NovelContentDatabase,需注入该库而非全局 appDatabase。

  CanvasServiceProvider call(String databasePath) =>
      CanvasServiceProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'canvasServiceProvider';
}

/// 监听当前小说的所有画布(按 sortOrder 排序,过滤软删)。

@ProviderFor(canvases)
final canvasesProvider = CanvasesFamily._();

/// 监听当前小说的所有画布(按 sortOrder 排序,过滤软删)。

final class CanvasesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CanvasEntry>>,
          List<CanvasEntry>,
          Stream<List<CanvasEntry>>
        >
    with
        $FutureModifier<List<CanvasEntry>>,
        $StreamProvider<List<CanvasEntry>> {
  /// 监听当前小说的所有画布(按 sortOrder 排序,过滤软删)。
  CanvasesProvider._({
    required CanvasesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'canvasesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$canvasesHash();

  @override
  String toString() {
    return r'canvasesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<CanvasEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<CanvasEntry>> create(Ref ref) {
    final argument = this.argument as String;
    return canvases(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CanvasesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$canvasesHash() => r'17db177f2a1a98e8887e1e03036f1fe54aa2535b';

/// 监听当前小说的所有画布(按 sortOrder 排序,过滤软删)。

final class CanvasesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<CanvasEntry>>, String> {
  CanvasesFamily._()
    : super(
        retry: null,
        name: r'canvasesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 监听当前小说的所有画布(按 sortOrder 排序,过滤软删)。

  CanvasesProvider call(String databasePath) =>
      CanvasesProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'canvasesProvider';
}

/// 一条整剧摘要流供所有场次节点共享；父级变化也使标题、位置与有效性刷新。

@ProviderFor(canvasSceneReferences)
final canvasSceneReferencesProvider = CanvasSceneReferencesFamily._();

/// 一条整剧摘要流供所有场次节点共享；父级变化也使标题、位置与有效性刷新。

final class CanvasSceneReferencesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, CanvasSceneReference>>,
          Map<String, CanvasSceneReference>,
          FutureOr<Map<String, CanvasSceneReference>>
        >
    with
        $FutureModifier<Map<String, CanvasSceneReference>>,
        $FutureProvider<Map<String, CanvasSceneReference>> {
  /// 一条整剧摘要流供所有场次节点共享；父级变化也使标题、位置与有效性刷新。
  CanvasSceneReferencesProvider._({
    required CanvasSceneReferencesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'canvasSceneReferencesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$canvasSceneReferencesHash();

  @override
  String toString() {
    return r'canvasSceneReferencesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Map<String, CanvasSceneReference>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, CanvasSceneReference>> create(Ref ref) {
    final argument = this.argument as String;
    return canvasSceneReferences(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CanvasSceneReferencesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$canvasSceneReferencesHash() =>
    r'967a1ec56e65d68991074e4a5001de07e7888270';

/// 一条整剧摘要流供所有场次节点共享；父级变化也使标题、位置与有效性刷新。

final class CanvasSceneReferencesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Map<String, CanvasSceneReference>>,
          String
        > {
  CanvasSceneReferencesFamily._()
    : super(
        retry: null,
        name: r'canvasSceneReferencesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 一条整剧摘要流供所有场次节点共享；父级变化也使标题、位置与有效性刷新。

  CanvasSceneReferencesProvider call(String databasePath) =>
      CanvasSceneReferencesProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'canvasSceneReferencesProvider';
}

/// AI 画布操作的广播点。
///
/// canvas 工具写库成功后经注入的 reporter 回调打到这里,画布 UI 据此跟随镜头、
/// 渲染「AI 正在做什么」状态条。DB stream 只能告诉 UI「内容变了」,分不出
/// 是 AI 写的还是用户拖的,也没有语义标签 —— 这条通道补的正是这两点。
///
/// keepAlive:AI 可能在画布页尚未 rebuild 时就写完一批节点,provider 被回收会丢事件。
///
/// state 只保留最新一条,供宿主做「新建/打开画布」这类导航;画布页的分镜导演
/// 走 [attachPacer] 直连 —— 批量处理同一帧连报多条时,watch state 只看得到最后
/// 一条,前面的 add_node 会丢,节点就绕过揭示直接冒出来。

@ProviderFor(CanvasAiActivityNotifier)
final canvasAiActivityProvider = CanvasAiActivityNotifierProvider._();

/// AI 画布操作的广播点。
///
/// canvas 工具写库成功后经注入的 reporter 回调打到这里,画布 UI 据此跟随镜头、
/// 渲染「AI 正在做什么」状态条。DB stream 只能告诉 UI「内容变了」,分不出
/// 是 AI 写的还是用户拖的,也没有语义标签 —— 这条通道补的正是这两点。
///
/// keepAlive:AI 可能在画布页尚未 rebuild 时就写完一批节点,provider 被回收会丢事件。
///
/// state 只保留最新一条,供宿主做「新建/打开画布」这类导航;画布页的分镜导演
/// 走 [attachPacer] 直连 —— 批量处理同一帧连报多条时,watch state 只看得到最后
/// 一条,前面的 add_node 会丢,节点就绕过揭示直接冒出来。
final class CanvasAiActivityNotifierProvider
    extends $NotifierProvider<CanvasAiActivityNotifier, CanvasAiActivity?> {
  /// AI 画布操作的广播点。
  ///
  /// canvas 工具写库成功后经注入的 reporter 回调打到这里,画布 UI 据此跟随镜头、
  /// 渲染「AI 正在做什么」状态条。DB stream 只能告诉 UI「内容变了」,分不出
  /// 是 AI 写的还是用户拖的,也没有语义标签 —— 这条通道补的正是这两点。
  ///
  /// keepAlive:AI 可能在画布页尚未 rebuild 时就写完一批节点,provider 被回收会丢事件。
  ///
  /// state 只保留最新一条,供宿主做「新建/打开画布」这类导航;画布页的分镜导演
  /// 走 [attachPacer] 直连 —— 批量处理同一帧连报多条时,watch state 只看得到最后
  /// 一条,前面的 add_node 会丢,节点就绕过揭示直接冒出来。
  CanvasAiActivityNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'canvasAiActivityProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$canvasAiActivityNotifierHash();

  @$internal
  @override
  CanvasAiActivityNotifier create() => CanvasAiActivityNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanvasAiActivity? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CanvasAiActivity?>(value),
    );
  }
}

String _$canvasAiActivityNotifierHash() =>
    r'e2925edbb008eb4fdf0fad4bf3da1d5a8ff28dbb';

/// AI 画布操作的广播点。
///
/// canvas 工具写库成功后经注入的 reporter 回调打到这里,画布 UI 据此跟随镜头、
/// 渲染「AI 正在做什么」状态条。DB stream 只能告诉 UI「内容变了」,分不出
/// 是 AI 写的还是用户拖的,也没有语义标签 —— 这条通道补的正是这两点。
///
/// keepAlive:AI 可能在画布页尚未 rebuild 时就写完一批节点,provider 被回收会丢事件。
///
/// state 只保留最新一条,供宿主做「新建/打开画布」这类导航;画布页的分镜导演
/// 走 [attachPacer] 直连 —— 批量处理同一帧连报多条时,watch state 只看得到最后
/// 一条,前面的 add_node 会丢,节点就绕过揭示直接冒出来。

abstract class _$CanvasAiActivityNotifier extends $Notifier<CanvasAiActivity?> {
  CanvasAiActivity? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CanvasAiActivity?, CanvasAiActivity?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CanvasAiActivity?, CanvasAiActivity?>,
              CanvasAiActivity?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
