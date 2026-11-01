// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'screenplay_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(screenplayService)
final screenplayServiceProvider = ScreenplayServiceFamily._();

final class ScreenplayServiceProvider
    extends
        $FunctionalProvider<
          ScreenplayService,
          ScreenplayService,
          ScreenplayService
        >
    with $Provider<ScreenplayService> {
  ScreenplayServiceProvider._({
    required ScreenplayServiceFamily super.from,
    required (String, {String? novelId}) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayServiceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayServiceHash();

  @override
  String toString() {
    return r'screenplayServiceProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<ScreenplayService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ScreenplayService create(Ref ref) {
    final argument = this.argument as (String, {String? novelId});
    return screenplayService(ref, argument.$1, novelId: argument.novelId);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ScreenplayService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ScreenplayService>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayServiceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayServiceHash() => r'db08b91303ea1632d53bca288efda34374848aa7';

final class ScreenplayServiceFamily extends $Family
    with
        $FunctionalFamilyOverride<
          ScreenplayService,
          (String, {String? novelId})
        > {
  ScreenplayServiceFamily._()
    : super(
        retry: null,
        name: r'screenplayServiceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplayServiceProvider call(String databasePath, {String? novelId}) =>
      ScreenplayServiceProvider._(
        argument: (databasePath, novelId: novelId),
        from: this,
      );

  @override
  String toString() => r'screenplayServiceProvider';
}

@ProviderFor(screenplayRoot)
final screenplayRootProvider = ScreenplayRootFamily._();

final class ScreenplayRootProvider
    extends
        $FunctionalProvider<
          AsyncValue<ScreenplayRow?>,
          ScreenplayRow?,
          Stream<ScreenplayRow?>
        >
    with $FutureModifier<ScreenplayRow?>, $StreamProvider<ScreenplayRow?> {
  ScreenplayRootProvider._({
    required ScreenplayRootFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'screenplayRootProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayRootHash();

  @override
  String toString() {
    return r'screenplayRootProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<ScreenplayRow?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ScreenplayRow?> create(Ref ref) {
    final argument = this.argument as String;
    return screenplayRoot(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayRootProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayRootHash() => r'b101ef4d63ab2fd43f995c2015186afdfb89f6b3';

final class ScreenplayRootFamily extends $Family
    with $FunctionalFamilyOverride<Stream<ScreenplayRow?>, String> {
  ScreenplayRootFamily._()
    : super(
        retry: null,
        name: r'screenplayRootProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplayRootProvider call(String databasePath) =>
      ScreenplayRootProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'screenplayRootProvider';
}

@ProviderFor(screenplaySeasons)
final screenplaySeasonsProvider = ScreenplaySeasonsFamily._();

final class ScreenplaySeasonsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ScreenplaySeasonRow>>,
          List<ScreenplaySeasonRow>,
          Stream<List<ScreenplaySeasonRow>>
        >
    with
        $FutureModifier<List<ScreenplaySeasonRow>>,
        $StreamProvider<List<ScreenplaySeasonRow>> {
  ScreenplaySeasonsProvider._({
    required ScreenplaySeasonsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplaySeasonsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplaySeasonsHash();

  @override
  String toString() {
    return r'screenplaySeasonsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<ScreenplaySeasonRow>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ScreenplaySeasonRow>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return screenplaySeasons(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplaySeasonsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplaySeasonsHash() => r'dac7aefba30b7b59cf4390fa043782945986053f';

final class ScreenplaySeasonsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<ScreenplaySeasonRow>>,
          (String, String)
        > {
  ScreenplaySeasonsFamily._()
    : super(
        retry: null,
        name: r'screenplaySeasonsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplaySeasonsProvider call(String databasePath, String screenplayId) =>
      ScreenplaySeasonsProvider._(
        argument: (databasePath, screenplayId),
        from: this,
      );

  @override
  String toString() => r'screenplaySeasonsProvider';
}

@ProviderFor(screenplayEpisodes)
final screenplayEpisodesProvider = ScreenplayEpisodesFamily._();

final class ScreenplayEpisodesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ScreenplayEpisodeRow>>,
          List<ScreenplayEpisodeRow>,
          Stream<List<ScreenplayEpisodeRow>>
        >
    with
        $FutureModifier<List<ScreenplayEpisodeRow>>,
        $StreamProvider<List<ScreenplayEpisodeRow>> {
  ScreenplayEpisodesProvider._({
    required ScreenplayEpisodesFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayEpisodesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayEpisodesHash();

  @override
  String toString() {
    return r'screenplayEpisodesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<ScreenplayEpisodeRow>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ScreenplayEpisodeRow>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return screenplayEpisodes(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayEpisodesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayEpisodesHash() =>
    r'72191d87db60e30efee3928fa79f9cbcf90dcf1e';

final class ScreenplayEpisodesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<ScreenplayEpisodeRow>>,
          (String, String)
        > {
  ScreenplayEpisodesFamily._()
    : super(
        retry: null,
        name: r'screenplayEpisodesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplayEpisodesProvider call(String databasePath, String seasonId) =>
      ScreenplayEpisodesProvider._(
        argument: (databasePath, seasonId),
        from: this,
      );

  @override
  String toString() => r'screenplayEpisodesProvider';
}

/// 整剧的集，一条流覆盖所有季，供需要全剧目录的场景使用。

@ProviderFor(screenplayEpisodesOfScreenplay)
final screenplayEpisodesOfScreenplayProvider =
    ScreenplayEpisodesOfScreenplayFamily._();

/// 整剧的集，一条流覆盖所有季，供需要全剧目录的场景使用。

final class ScreenplayEpisodesOfScreenplayProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ScreenplayEpisodeRow>>,
          List<ScreenplayEpisodeRow>,
          Stream<List<ScreenplayEpisodeRow>>
        >
    with
        $FutureModifier<List<ScreenplayEpisodeRow>>,
        $StreamProvider<List<ScreenplayEpisodeRow>> {
  /// 整剧的集，一条流覆盖所有季，供需要全剧目录的场景使用。
  ScreenplayEpisodesOfScreenplayProvider._({
    required ScreenplayEpisodesOfScreenplayFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayEpisodesOfScreenplayProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayEpisodesOfScreenplayHash();

  @override
  String toString() {
    return r'screenplayEpisodesOfScreenplayProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<ScreenplayEpisodeRow>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ScreenplayEpisodeRow>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return screenplayEpisodesOfScreenplay(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayEpisodesOfScreenplayProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayEpisodesOfScreenplayHash() =>
    r'079b07d4aba85ebdeabf73bd0ed3d55b5e3ac973';

/// 整剧的集，一条流覆盖所有季，供需要全剧目录的场景使用。

final class ScreenplayEpisodesOfScreenplayFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<ScreenplayEpisodeRow>>,
          (String, String)
        > {
  ScreenplayEpisodesOfScreenplayFamily._()
    : super(
        retry: null,
        name: r'screenplayEpisodesOfScreenplayProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 整剧的集，一条流覆盖所有季，供需要全剧目录的场景使用。

  ScreenplayEpisodesOfScreenplayProvider call(
    String databasePath,
    String screenplayId,
  ) => ScreenplayEpisodesOfScreenplayProvider._(
    argument: (databasePath, screenplayId),
    from: this,
  );

  @override
  String toString() => r'screenplayEpisodesOfScreenplayProvider';
}

@ProviderFor(screenplayEpisode)
final screenplayEpisodeProvider = ScreenplayEpisodeFamily._();

final class ScreenplayEpisodeProvider
    extends
        $FunctionalProvider<
          AsyncValue<ScreenplayEpisodeRow?>,
          ScreenplayEpisodeRow?,
          Stream<ScreenplayEpisodeRow?>
        >
    with
        $FutureModifier<ScreenplayEpisodeRow?>,
        $StreamProvider<ScreenplayEpisodeRow?> {
  ScreenplayEpisodeProvider._({
    required ScreenplayEpisodeFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayEpisodeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayEpisodeHash();

  @override
  String toString() {
    return r'screenplayEpisodeProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<ScreenplayEpisodeRow?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ScreenplayEpisodeRow?> create(Ref ref) {
    final argument = this.argument as (String, String);
    return screenplayEpisode(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayEpisodeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayEpisodeHash() => r'8f59a36c417a0599873a52504a61d6d382ecc657';

final class ScreenplayEpisodeFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<ScreenplayEpisodeRow?>,
          (String, String)
        > {
  ScreenplayEpisodeFamily._()
    : super(
        retry: null,
        name: r'screenplayEpisodeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplayEpisodeProvider call(String databasePath, String episodeId) =>
      ScreenplayEpisodeProvider._(
        argument: (databasePath, episodeId),
        from: this,
      );

  @override
  String toString() => r'screenplayEpisodeProvider';
}

@ProviderFor(screenplayScenes)
final screenplayScenesProvider = ScreenplayScenesFamily._();

final class ScreenplayScenesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ScreenplaySceneSummary>>,
          List<ScreenplaySceneSummary>,
          Stream<List<ScreenplaySceneSummary>>
        >
    with
        $FutureModifier<List<ScreenplaySceneSummary>>,
        $StreamProvider<List<ScreenplaySceneSummary>> {
  ScreenplayScenesProvider._({
    required ScreenplayScenesFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayScenesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayScenesHash();

  @override
  String toString() {
    return r'screenplayScenesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<ScreenplaySceneSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ScreenplaySceneSummary>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return screenplayScenes(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayScenesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayScenesHash() => r'f2995efd4ad511328fbfbfee8de09dd78c8b3001';

final class ScreenplayScenesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<ScreenplaySceneSummary>>,
          (String, String)
        > {
  ScreenplayScenesFamily._()
    : super(
        retry: null,
        name: r'screenplayScenesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplayScenesProvider call(String databasePath, String episodeId) =>
      ScreenplayScenesProvider._(
        argument: (databasePath, episodeId),
        from: this,
      );

  @override
  String toString() => r'screenplayScenesProvider';
}

/// 整剧场次，按 episodeId 分组，一条流替代逐集订阅。

@ProviderFor(screenplayScenesOfScreenplay)
final screenplayScenesOfScreenplayProvider =
    ScreenplayScenesOfScreenplayFamily._();

/// 整剧场次，按 episodeId 分组，一条流替代逐集订阅。

final class ScreenplayScenesOfScreenplayProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, List<ScreenplaySceneSummary>>>,
          Map<String, List<ScreenplaySceneSummary>>,
          Stream<Map<String, List<ScreenplaySceneSummary>>>
        >
    with
        $FutureModifier<Map<String, List<ScreenplaySceneSummary>>>,
        $StreamProvider<Map<String, List<ScreenplaySceneSummary>>> {
  /// 整剧场次，按 episodeId 分组，一条流替代逐集订阅。
  ScreenplayScenesOfScreenplayProvider._({
    required ScreenplayScenesOfScreenplayFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayScenesOfScreenplayProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayScenesOfScreenplayHash();

  @override
  String toString() {
    return r'screenplayScenesOfScreenplayProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<Map<String, List<ScreenplaySceneSummary>>>
  $createElement($ProviderPointer pointer) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, List<ScreenplaySceneSummary>>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return screenplayScenesOfScreenplay(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayScenesOfScreenplayProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayScenesOfScreenplayHash() =>
    r'89bb8c43560a535190104da388d60d18fcd38df8';

/// 整剧场次，按 episodeId 分组，一条流替代逐集订阅。

final class ScreenplayScenesOfScreenplayFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<Map<String, List<ScreenplaySceneSummary>>>,
          (String, String)
        > {
  ScreenplayScenesOfScreenplayFamily._()
    : super(
        retry: null,
        name: r'screenplayScenesOfScreenplayProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 整剧场次，按 episodeId 分组，一条流替代逐集订阅。

  ScreenplayScenesOfScreenplayProvider call(
    String databasePath,
    String screenplayId,
  ) => ScreenplayScenesOfScreenplayProvider._(
    argument: (databasePath, screenplayId),
    from: this,
  );

  @override
  String toString() => r'screenplayScenesOfScreenplayProvider';
}

@ProviderFor(screenplayOutline)
final screenplayOutlineProvider = ScreenplayOutlineFamily._();

final class ScreenplayOutlineProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ScreenplayOutlineEntry>>,
          List<ScreenplayOutlineEntry>,
          Stream<List<ScreenplayOutlineEntry>>
        >
    with
        $FutureModifier<List<ScreenplayOutlineEntry>>,
        $StreamProvider<List<ScreenplayOutlineEntry>> {
  ScreenplayOutlineProvider._({
    required ScreenplayOutlineFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayOutlineProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayOutlineHash();

  @override
  String toString() {
    return r'screenplayOutlineProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<ScreenplayOutlineEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ScreenplayOutlineEntry>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return screenplayOutline(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayOutlineProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayOutlineHash() => r'e74f8a0489327eadb710ebcc4a625ab77c2b22c5';

final class ScreenplayOutlineFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<ScreenplayOutlineEntry>>,
          (String, String)
        > {
  ScreenplayOutlineFamily._()
    : super(
        retry: null,
        name: r'screenplayOutlineProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplayOutlineProvider call(String databasePath, String episodeId) =>
      ScreenplayOutlineProvider._(
        argument: (databasePath, episodeId),
        from: this,
      );

  @override
  String toString() => r'screenplayOutlineProvider';
}

@ProviderFor(screenplayBeats)
final screenplayBeatsProvider = ScreenplayBeatsFamily._();

final class ScreenplayBeatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ScreenplayBeatSummary>>,
          List<ScreenplayBeatSummary>,
          Stream<List<ScreenplayBeatSummary>>
        >
    with
        $FutureModifier<List<ScreenplayBeatSummary>>,
        $StreamProvider<List<ScreenplayBeatSummary>> {
  ScreenplayBeatsProvider._({
    required ScreenplayBeatsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayBeatsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayBeatsHash();

  @override
  String toString() {
    return r'screenplayBeatsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<ScreenplayBeatSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ScreenplayBeatSummary>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return screenplayBeats(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayBeatsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayBeatsHash() => r'607bb834413c63b405dd0d1cc6034f12122f6dce';

final class ScreenplayBeatsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<ScreenplayBeatSummary>>,
          (String, String)
        > {
  ScreenplayBeatsFamily._()
    : super(
        retry: null,
        name: r'screenplayBeatsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplayBeatsProvider call(String databasePath, String episodeId) =>
      ScreenplayBeatsProvider._(
        argument: (databasePath, episodeId),
        from: this,
      );

  @override
  String toString() => r'screenplayBeatsProvider';
}

@ProviderFor(screenplayAppearanceMatrix)
final screenplayAppearanceMatrixProvider = ScreenplayAppearanceMatrixFamily._();

final class ScreenplayAppearanceMatrixProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ScreenplayAppearanceMatrixRow>>,
          List<ScreenplayAppearanceMatrixRow>,
          Stream<List<ScreenplayAppearanceMatrixRow>>
        >
    with
        $FutureModifier<List<ScreenplayAppearanceMatrixRow>>,
        $StreamProvider<List<ScreenplayAppearanceMatrixRow>> {
  ScreenplayAppearanceMatrixProvider._({
    required ScreenplayAppearanceMatrixFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayAppearanceMatrixProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayAppearanceMatrixHash();

  @override
  String toString() {
    return r'screenplayAppearanceMatrixProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<ScreenplayAppearanceMatrixRow>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ScreenplayAppearanceMatrixRow>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return screenplayAppearanceMatrix(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayAppearanceMatrixProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayAppearanceMatrixHash() =>
    r'f804faa2fdc9a71b715b1fe636fb5a9f79e64869';

final class ScreenplayAppearanceMatrixFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<ScreenplayAppearanceMatrixRow>>,
          (String, String)
        > {
  ScreenplayAppearanceMatrixFamily._()
    : super(
        retry: null,
        name: r'screenplayAppearanceMatrixProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplayAppearanceMatrixProvider call(
    String databasePath,
    String episodeId,
  ) => ScreenplayAppearanceMatrixProvider._(
    argument: (databasePath, episodeId),
    from: this,
  );

  @override
  String toString() => r'screenplayAppearanceMatrixProvider';
}

@ProviderFor(screenplaySceneElements)
final screenplaySceneElementsProvider = ScreenplaySceneElementsFamily._();

final class ScreenplaySceneElementsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ScreenplayElement>>,
          List<ScreenplayElement>,
          Stream<List<ScreenplayElement>>
        >
    with
        $FutureModifier<List<ScreenplayElement>>,
        $StreamProvider<List<ScreenplayElement>> {
  ScreenplaySceneElementsProvider._({
    required ScreenplaySceneElementsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplaySceneElementsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplaySceneElementsHash();

  @override
  String toString() {
    return r'screenplaySceneElementsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<ScreenplayElement>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ScreenplayElement>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return screenplaySceneElements(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplaySceneElementsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplaySceneElementsHash() =>
    r'fb9cf916de99af239e86f429d4bfe5691b27aa86';

final class ScreenplaySceneElementsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<ScreenplayElement>>,
          (String, String)
        > {
  ScreenplaySceneElementsFamily._()
    : super(
        retry: null,
        name: r'screenplaySceneElementsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplaySceneElementsProvider call(String databasePath, String sceneId) =>
      ScreenplaySceneElementsProvider._(
        argument: (databasePath, sceneId),
        from: this,
      );

  @override
  String toString() => r'screenplaySceneElementsProvider';
}

@ProviderFor(screenplayOverview)
final screenplayOverviewProvider = ScreenplayOverviewFamily._();

final class ScreenplayOverviewProvider
    extends
        $FunctionalProvider<
          AsyncValue<ScreenplayOverview>,
          ScreenplayOverview,
          Stream<ScreenplayOverview>
        >
    with
        $FutureModifier<ScreenplayOverview>,
        $StreamProvider<ScreenplayOverview> {
  ScreenplayOverviewProvider._({
    required ScreenplayOverviewFamily super.from,
    required (String, String, {String? seasonId}) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayOverviewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayOverviewHash();

  @override
  String toString() {
    return r'screenplayOverviewProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<ScreenplayOverview> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ScreenplayOverview> create(Ref ref) {
    final argument = this.argument as (String, String, {String? seasonId});
    return screenplayOverview(
      ref,
      argument.$1,
      argument.$2,
      seasonId: argument.seasonId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayOverviewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayOverviewHash() =>
    r'e94c6727c32de3a53a9eedbfb0b50f2df5eb94f6';

final class ScreenplayOverviewFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<ScreenplayOverview>,
          (String, String, {String? seasonId})
        > {
  ScreenplayOverviewFamily._()
    : super(
        retry: null,
        name: r'screenplayOverviewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplayOverviewProvider call(
    String databasePath,
    String screenplayId, {
    String? seasonId,
  }) => ScreenplayOverviewProvider._(
    argument: (databasePath, screenplayId, seasonId: seasonId),
    from: this,
  );

  @override
  String toString() => r'screenplayOverviewProvider';
}

@ProviderFor(screenplayEpisodeScriptPreview)
final screenplayEpisodeScriptPreviewProvider =
    ScreenplayEpisodeScriptPreviewFamily._();

final class ScreenplayEpisodeScriptPreviewProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<EpisodeScriptScenePreview>>,
          List<EpisodeScriptScenePreview>,
          Stream<List<EpisodeScriptScenePreview>>
        >
    with
        $FutureModifier<List<EpisodeScriptScenePreview>>,
        $StreamProvider<List<EpisodeScriptScenePreview>> {
  ScreenplayEpisodeScriptPreviewProvider._({
    required ScreenplayEpisodeScriptPreviewFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'screenplayEpisodeScriptPreviewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$screenplayEpisodeScriptPreviewHash();

  @override
  String toString() {
    return r'screenplayEpisodeScriptPreviewProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<EpisodeScriptScenePreview>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<EpisodeScriptScenePreview>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return screenplayEpisodeScriptPreview(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ScreenplayEpisodeScriptPreviewProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$screenplayEpisodeScriptPreviewHash() =>
    r'399a724e52ebfbac07dc0f19cd7089dfcb84d2ff';

final class ScreenplayEpisodeScriptPreviewFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<EpisodeScriptScenePreview>>,
          (String, String)
        > {
  ScreenplayEpisodeScriptPreviewFamily._()
    : super(
        retry: null,
        name: r'screenplayEpisodeScriptPreviewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ScreenplayEpisodeScriptPreviewProvider call(
    String databasePath,
    String episodeId,
  ) => ScreenplayEpisodeScriptPreviewProvider._(
    argument: (databasePath, episodeId),
    from: this,
  );

  @override
  String toString() => r'screenplayEpisodeScriptPreviewProvider';
}
