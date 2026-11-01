// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_continue_offer_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// keepAlive 而非 autoDispose：移动端「新对话」走 `pushReplacement`，旧页面先
/// dispose、新页面后 build，两者之间没有任何 listener，autoDispose 会正好在这个
/// 空档把提议清掉。全局单实例（不是 family），只持有三个字符串，不持有
/// controller / stream / client，提议条显示一次后即 [clear]。

@ProviderFor(ChatContinueOfferNotifier)
final chatContinueOfferProvider = ChatContinueOfferNotifierProvider._();

/// keepAlive 而非 autoDispose：移动端「新对话」走 `pushReplacement`，旧页面先
/// dispose、新页面后 build，两者之间没有任何 listener，autoDispose 会正好在这个
/// 空档把提议清掉。全局单实例（不是 family），只持有三个字符串，不持有
/// controller / stream / client，提议条显示一次后即 [clear]。
final class ChatContinueOfferNotifierProvider
    extends $NotifierProvider<ChatContinueOfferNotifier, ChatContinueOffer?> {
  /// keepAlive 而非 autoDispose：移动端「新对话」走 `pushReplacement`，旧页面先
  /// dispose、新页面后 build，两者之间没有任何 listener，autoDispose 会正好在这个
  /// 空档把提议清掉。全局单实例（不是 family），只持有三个字符串，不持有
  /// controller / stream / client，提议条显示一次后即 [clear]。
  ChatContinueOfferNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatContinueOfferProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatContinueOfferNotifierHash();

  @$internal
  @override
  ChatContinueOfferNotifier create() => ChatContinueOfferNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatContinueOffer? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatContinueOffer?>(value),
    );
  }
}

String _$chatContinueOfferNotifierHash() =>
    r'1b5a898d3e3c24818959aaba456274927e6ef9d3';

/// keepAlive 而非 autoDispose：移动端「新对话」走 `pushReplacement`，旧页面先
/// dispose、新页面后 build，两者之间没有任何 listener，autoDispose 会正好在这个
/// 空档把提议清掉。全局单实例（不是 family），只持有三个字符串，不持有
/// controller / stream / client，提议条显示一次后即 [clear]。

abstract class _$ChatContinueOfferNotifier
    extends $Notifier<ChatContinueOffer?> {
  ChatContinueOffer? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ChatContinueOffer?, ChatContinueOffer?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ChatContinueOffer?, ChatContinueOffer?>,
              ChatContinueOffer?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
