// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cover_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(coverBriefService)
final coverBriefServiceProvider = CoverBriefServiceProvider._();

final class CoverBriefServiceProvider
    extends
        $FunctionalProvider<
          CoverBriefService,
          CoverBriefService,
          CoverBriefService
        >
    with $Provider<CoverBriefService> {
  CoverBriefServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'coverBriefServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$coverBriefServiceHash();

  @$internal
  @override
  $ProviderElement<CoverBriefService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CoverBriefService create(Ref ref) {
    return coverBriefService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CoverBriefService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CoverBriefService>(value),
    );
  }
}

String _$coverBriefServiceHash() => r'b76f376427ba8fe54765816fa6118edc3ff6317c';

/// 档案状态：未读 / 读取中 / 已读。

@ProviderFor(coverBriefState)
final coverBriefStateProvider = CoverBriefStateFamily._();

/// 档案状态：未读 / 读取中 / 已读。

final class CoverBriefStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<CoverBriefState>,
          CoverBriefState,
          Stream<CoverBriefState>
        >
    with $FutureModifier<CoverBriefState>, $StreamProvider<CoverBriefState> {
  /// 档案状态：未读 / 读取中 / 已读。
  CoverBriefStateProvider._({
    required CoverBriefStateFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'coverBriefStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$coverBriefStateHash();

  @override
  String toString() {
    return r'coverBriefStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<CoverBriefState> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<CoverBriefState> create(Ref ref) {
    final argument = this.argument as String;
    return coverBriefState(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CoverBriefStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$coverBriefStateHash() => r'741d224723b937c5af859d940d57d3acb120decf';

/// 档案状态：未读 / 读取中 / 已读。

final class CoverBriefStateFamily extends $Family
    with $FunctionalFamilyOverride<Stream<CoverBriefState>, String> {
  CoverBriefStateFamily._()
    : super(
        retry: null,
        name: r'coverBriefStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 档案状态：未读 / 读取中 / 已读。

  CoverBriefStateProvider call(String databasePath) =>
      CoverBriefStateProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'coverBriefStateProvider';
}

/// 档案是否已经跟不上稿子。没有档案时返回 false。

@ProviderFor(coverBriefStale)
final coverBriefStaleProvider = CoverBriefStaleFamily._();

/// 档案是否已经跟不上稿子。没有档案时返回 false。

final class CoverBriefStaleProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// 档案是否已经跟不上稿子。没有档案时返回 false。
  CoverBriefStaleProvider._({
    required CoverBriefStaleFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'coverBriefStaleProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$coverBriefStaleHash();

  @override
  String toString() {
    return r'coverBriefStaleProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as String;
    return coverBriefStale(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CoverBriefStaleProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$coverBriefStaleHash() => r'c41742a5bb6103b41b6c81d355a5705530e60dec';

/// 档案是否已经跟不上稿子。没有档案时返回 false。

final class CoverBriefStaleFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  CoverBriefStaleFamily._()
    : super(
        retry: null,
        name: r'coverBriefStaleProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 档案是否已经跟不上稿子。没有档案时返回 false。

  CoverBriefStaleProvider call(String databasePath) =>
      CoverBriefStaleProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'coverBriefStaleProvider';
}

/// 作品卡片的体量：章节数与总字数，取自内容库当前值。
///
/// 一次性读取而不是订阅：封面面板打开期间体量不会变到影响判断，订阅全量章节
/// （`chaptersProvider` 走的是带正文的 VIEW）只为数两个数字并不划算。

@ProviderFor(coverWorkStats)
final coverWorkStatsProvider = CoverWorkStatsFamily._();

/// 作品卡片的体量：章节数与总字数，取自内容库当前值。
///
/// 一次性读取而不是订阅：封面面板打开期间体量不会变到影响判断，订阅全量章节
/// （`chaptersProvider` 走的是带正文的 VIEW）只为数两个数字并不划算。

final class CoverWorkStatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ChapterListStats>,
          ChapterListStats,
          FutureOr<ChapterListStats>
        >
    with $FutureModifier<ChapterListStats>, $FutureProvider<ChapterListStats> {
  /// 作品卡片的体量：章节数与总字数，取自内容库当前值。
  ///
  /// 一次性读取而不是订阅：封面面板打开期间体量不会变到影响判断，订阅全量章节
  /// （`chaptersProvider` 走的是带正文的 VIEW）只为数两个数字并不划算。
  CoverWorkStatsProvider._({
    required CoverWorkStatsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'coverWorkStatsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$coverWorkStatsHash();

  @override
  String toString() {
    return r'coverWorkStatsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ChapterListStats> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ChapterListStats> create(Ref ref) {
    final argument = this.argument as String;
    return coverWorkStats(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CoverWorkStatsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$coverWorkStatsHash() => r'575f2620ca08485a5282949efcdf5864ddc94352';

/// 作品卡片的体量：章节数与总字数，取自内容库当前值。
///
/// 一次性读取而不是订阅：封面面板打开期间体量不会变到影响判断，订阅全量章节
/// （`chaptersProvider` 走的是带正文的 VIEW）只为数两个数字并不划算。

final class CoverWorkStatsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ChapterListStats>, String> {
  CoverWorkStatsFamily._()
    : super(
        retry: null,
        name: r'coverWorkStatsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 作品卡片的体量：章节数与总字数，取自内容库当前值。
  ///
  /// 一次性读取而不是订阅：封面面板打开期间体量不会变到影响判断，订阅全量章节
  /// （`chaptersProvider` 走的是带正文的 VIEW）只为数两个数字并不划算。

  CoverWorkStatsProvider call(String databasePath) =>
      CoverWorkStatsProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'coverWorkStatsProvider';
}
