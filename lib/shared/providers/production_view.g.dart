// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_view.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 制片页当前停在分镜视图（默认视图）；画布和列表视图不显示底栏。
///
/// 工作区外壳在制片分区时 watch 保活；制片页只在切视图和卸载时写入。

@ProviderFor(ProductionSegmentsView)
final productionSegmentsViewProvider = ProductionSegmentsViewFamily._();

/// 制片页当前停在分镜视图（默认视图）；画布和列表视图不显示底栏。
///
/// 工作区外壳在制片分区时 watch 保活；制片页只在切视图和卸载时写入。
final class ProductionSegmentsViewProvider
    extends $NotifierProvider<ProductionSegmentsView, bool> {
  /// 制片页当前停在分镜视图（默认视图）；画布和列表视图不显示底栏。
  ///
  /// 工作区外壳在制片分区时 watch 保活；制片页只在切视图和卸载时写入。
  ProductionSegmentsViewProvider._({
    required ProductionSegmentsViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'productionSegmentsViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$productionSegmentsViewHash();

  @override
  String toString() {
    return r'productionSegmentsViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ProductionSegmentsView create() => ProductionSegmentsView();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProductionSegmentsViewProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$productionSegmentsViewHash() =>
    r'1859fadbb3a9a93a8d4742e7e1a273f12de159fa';

/// 制片页当前停在分镜视图（默认视图）；画布和列表视图不显示底栏。
///
/// 工作区外壳在制片分区时 watch 保活；制片页只在切视图和卸载时写入。

final class ProductionSegmentsViewFamily extends $Family
    with
        $ClassFamilyOverride<ProductionSegmentsView, bool, bool, bool, String> {
  ProductionSegmentsViewFamily._()
    : super(
        retry: null,
        name: r'productionSegmentsViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 制片页当前停在分镜视图（默认视图）；画布和列表视图不显示底栏。
  ///
  /// 工作区外壳在制片分区时 watch 保活；制片页只在切视图和卸载时写入。

  ProductionSegmentsViewProvider call(String novelId) =>
      ProductionSegmentsViewProvider._(argument: novelId, from: this);

  @override
  String toString() => r'productionSegmentsViewProvider';
}

/// 制片页当前停在分镜视图（默认视图）；画布和列表视图不显示底栏。
///
/// 工作区外壳在制片分区时 watch 保活；制片页只在切视图和卸载时写入。

abstract class _$ProductionSegmentsView extends $Notifier<bool> {
  late final _$args = ref.$arg as String;
  String get novelId => _$args;

  bool build(String novelId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// 制片页里打开的剪辑或导演台；名称用于面包屑，调度 ID 用于 AI 上下文。
///
/// 按作品内容库路径区分：剪辑和导演台只持有路径。工作区外壳在制片分区时 watch 保活。

@ProviderFor(ProductionSubpage)
final productionSubpageProvider = ProductionSubpageFamily._();

/// 制片页里打开的剪辑或导演台；名称用于面包屑，调度 ID 用于 AI 上下文。
///
/// 按作品内容库路径区分：剪辑和导演台只持有路径。工作区外壳在制片分区时 watch 保活。
final class ProductionSubpageProvider
    extends $NotifierProvider<ProductionSubpage, ProductionSubpageContext?> {
  /// 制片页里打开的剪辑或导演台；名称用于面包屑，调度 ID 用于 AI 上下文。
  ///
  /// 按作品内容库路径区分：剪辑和导演台只持有路径。工作区外壳在制片分区时 watch 保活。
  ProductionSubpageProvider._({
    required ProductionSubpageFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'productionSubpageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$productionSubpageHash();

  @override
  String toString() {
    return r'productionSubpageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ProductionSubpage create() => ProductionSubpage();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProductionSubpageContext? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProductionSubpageContext?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProductionSubpageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$productionSubpageHash() => r'86f594fd7f444a97df9a4ab31361618cc363f981';

/// 制片页里打开的剪辑或导演台；名称用于面包屑，调度 ID 用于 AI 上下文。
///
/// 按作品内容库路径区分：剪辑和导演台只持有路径。工作区外壳在制片分区时 watch 保活。

final class ProductionSubpageFamily extends $Family
    with
        $ClassFamilyOverride<
          ProductionSubpage,
          ProductionSubpageContext?,
          ProductionSubpageContext?,
          ProductionSubpageContext?,
          String
        > {
  ProductionSubpageFamily._()
    : super(
        retry: null,
        name: r'productionSubpageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 制片页里打开的剪辑或导演台；名称用于面包屑，调度 ID 用于 AI 上下文。
  ///
  /// 按作品内容库路径区分：剪辑和导演台只持有路径。工作区外壳在制片分区时 watch 保活。

  ProductionSubpageProvider call(String databasePath) =>
      ProductionSubpageProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'productionSubpageProvider';
}

/// 制片页里打开的剪辑或导演台；名称用于面包屑，调度 ID 用于 AI 上下文。
///
/// 按作品内容库路径区分：剪辑和导演台只持有路径。工作区外壳在制片分区时 watch 保活。

abstract class _$ProductionSubpage
    extends $Notifier<ProductionSubpageContext?> {
  late final _$args = ref.$arg as String;
  String get databasePath => _$args;

  ProductionSubpageContext? build(String databasePath);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<ProductionSubpageContext?, ProductionSubpageContext?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProductionSubpageContext?, ProductionSubpageContext?>,
              ProductionSubpageContext?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
