// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reading_progress_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 监听某本作品的阅读进度。
///
/// 通过 AppDatabase 的 ReadingProgress 表持久化状态。
/// Reader 页面使用此 provider 作为唯一写入入口与读取入口。

@ProviderFor(NovelReadingProgress)
final novelReadingProgressProvider = NovelReadingProgressFamily._();

/// 监听某本作品的阅读进度。
///
/// 通过 AppDatabase 的 ReadingProgress 表持久化状态。
/// Reader 页面使用此 provider 作为唯一写入入口与读取入口。
final class NovelReadingProgressProvider
    extends $AsyncNotifierProvider<NovelReadingProgress, ReadingProgressData> {
  /// 监听某本作品的阅读进度。
  ///
  /// 通过 AppDatabase 的 ReadingProgress 表持久化状态。
  /// Reader 页面使用此 provider 作为唯一写入入口与读取入口。
  NovelReadingProgressProvider._({
    required NovelReadingProgressFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'novelReadingProgressProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$novelReadingProgressHash();

  @override
  String toString() {
    return r'novelReadingProgressProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  NovelReadingProgress create() => NovelReadingProgress();

  @override
  bool operator ==(Object other) {
    return other is NovelReadingProgressProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$novelReadingProgressHash() =>
    r'b8a6ad64e381e1e1e6e8b0d0387a6abc5d7fbd07';

/// 监听某本作品的阅读进度。
///
/// 通过 AppDatabase 的 ReadingProgress 表持久化状态。
/// Reader 页面使用此 provider 作为唯一写入入口与读取入口。

final class NovelReadingProgressFamily extends $Family
    with
        $ClassFamilyOverride<
          NovelReadingProgress,
          AsyncValue<ReadingProgressData>,
          ReadingProgressData,
          FutureOr<ReadingProgressData>,
          String
        > {
  NovelReadingProgressFamily._()
    : super(
        retry: null,
        name: r'novelReadingProgressProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 监听某本作品的阅读进度。
  ///
  /// 通过 AppDatabase 的 ReadingProgress 表持久化状态。
  /// Reader 页面使用此 provider 作为唯一写入入口与读取入口。

  NovelReadingProgressProvider call(String novelId) =>
      NovelReadingProgressProvider._(argument: novelId, from: this);

  @override
  String toString() => r'novelReadingProgressProvider';
}

/// 监听某本作品的阅读进度。
///
/// 通过 AppDatabase 的 ReadingProgress 表持久化状态。
/// Reader 页面使用此 provider 作为唯一写入入口与读取入口。

abstract class _$NovelReadingProgress
    extends $AsyncNotifier<ReadingProgressData> {
  late final _$args = ref.$arg as String;
  String get novelId => _$args;

  FutureOr<ReadingProgressData> build(String novelId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ReadingProgressData>, ReadingProgressData>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ReadingProgressData>, ReadingProgressData>,
              AsyncValue<ReadingProgressData>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
