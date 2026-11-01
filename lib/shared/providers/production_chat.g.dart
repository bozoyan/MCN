// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_chat.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 由编辑页 watch 保活；制片页只在视图切换和卸载时写入。

@ProviderFor(ProductionChat)
final productionChatProvider = ProductionChatFamily._();

/// 由编辑页 watch 保活；制片页只在视图切换和卸载时写入。
final class ProductionChatProvider
    extends $NotifierProvider<ProductionChat, ProductionChatState> {
  /// 由编辑页 watch 保活；制片页只在视图切换和卸载时写入。
  ProductionChatProvider._({
    required ProductionChatFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'productionChatProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$productionChatHash();

  @override
  String toString() {
    return r'productionChatProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ProductionChat create() => ProductionChat();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProductionChatState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProductionChatState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProductionChatProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$productionChatHash() => r'4862dfd43875dde468ef49c857d5be021357b46b';

/// 由编辑页 watch 保活；制片页只在视图切换和卸载时写入。

final class ProductionChatFamily extends $Family
    with
        $ClassFamilyOverride<
          ProductionChat,
          ProductionChatState,
          ProductionChatState,
          ProductionChatState,
          String
        > {
  ProductionChatFamily._()
    : super(
        retry: null,
        name: r'productionChatProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 由编辑页 watch 保活；制片页只在视图切换和卸载时写入。

  ProductionChatProvider call(String novelId) =>
      ProductionChatProvider._(argument: novelId, from: this);

  @override
  String toString() => r'productionChatProvider';
}

/// 由编辑页 watch 保活；制片页只在视图切换和卸载时写入。

abstract class _$ProductionChat extends $Notifier<ProductionChatState> {
  late final _$args = ref.$arg as String;
  String get novelId => _$args;

  ProductionChatState build(String novelId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ProductionChatState, ProductionChatState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProductionChatState, ProductionChatState>,
              ProductionChatState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
