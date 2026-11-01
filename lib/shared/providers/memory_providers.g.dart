// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'memory_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(memoryService)
final memoryServiceProvider = MemoryServiceProvider._();

final class MemoryServiceProvider
    extends $FunctionalProvider<MemoryService, MemoryService, MemoryService>
    with $Provider<MemoryService> {
  MemoryServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'memoryServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$memoryServiceHash();

  @$internal
  @override
  $ProviderElement<MemoryService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MemoryService create(Ref ref) {
    return memoryService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MemoryService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MemoryService>(value),
    );
  }
}

String _$memoryServiceHash() => r'24346aafcd6487323d1e4a700320beaf326436ec';

@ProviderFor(globalMemories)
final globalMemoriesProvider = GlobalMemoriesProvider._();

final class GlobalMemoriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Memory>>,
          List<Memory>,
          Stream<List<Memory>>
        >
    with $FutureModifier<List<Memory>>, $StreamProvider<List<Memory>> {
  GlobalMemoriesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'globalMemoriesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$globalMemoriesHash();

  @$internal
  @override
  $StreamProviderElement<List<Memory>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Memory>> create(Ref ref) {
    return globalMemories(ref);
  }
}

String _$globalMemoriesHash() => r'46b5b37ae2b0cdc370d8c0da47ab8081bb7e792a';

@ProviderFor(novelMemories)
final novelMemoriesProvider = NovelMemoriesFamily._();

final class NovelMemoriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Memory>>,
          List<Memory>,
          Stream<List<Memory>>
        >
    with $FutureModifier<List<Memory>>, $StreamProvider<List<Memory>> {
  NovelMemoriesProvider._({
    required NovelMemoriesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'novelMemoriesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$novelMemoriesHash();

  @override
  String toString() {
    return r'novelMemoriesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Memory>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Memory>> create(Ref ref) {
    final argument = this.argument as String;
    return novelMemories(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is NovelMemoriesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$novelMemoriesHash() => r'e3e127935d51ee1b53d0165b8085c2d3e99d4b1b';

final class NovelMemoriesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Memory>>, String> {
  NovelMemoriesFamily._()
    : super(
        retry: null,
        name: r'novelMemoriesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  NovelMemoriesProvider call(String novelId) =>
      NovelMemoriesProvider._(argument: novelId, from: this);

  @override
  String toString() => r'novelMemoriesProvider';
}

@ProviderFor(memoriesForPrompt)
final memoriesForPromptProvider = MemoriesForPromptFamily._();

final class MemoriesForPromptProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Memory>>,
          List<Memory>,
          FutureOr<List<Memory>>
        >
    with $FutureModifier<List<Memory>>, $FutureProvider<List<Memory>> {
  MemoriesForPromptProvider._({
    required MemoriesForPromptFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'memoriesForPromptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$memoriesForPromptHash();

  @override
  String toString() {
    return r'memoriesForPromptProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Memory>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Memory>> create(Ref ref) {
    final argument = this.argument as String?;
    return memoriesForPrompt(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MemoriesForPromptProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$memoriesForPromptHash() => r'11971ccee52ba2a98d5888556b0bb4185dd957d3';

final class MemoriesForPromptFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Memory>>, String?> {
  MemoriesForPromptFamily._()
    : super(
        retry: null,
        name: r'memoriesForPromptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MemoriesForPromptProvider call(String? novelId) =>
      MemoriesForPromptProvider._(argument: novelId, from: this);

  @override
  String toString() => r'memoriesForPromptProvider';
}

@ProviderFor(memoryBlockForPrompt)
final memoryBlockForPromptProvider = MemoryBlockForPromptFamily._();

final class MemoryBlockForPromptProvider
    extends $FunctionalProvider<AsyncValue<String>, String, FutureOr<String>>
    with $FutureModifier<String>, $FutureProvider<String> {
  MemoryBlockForPromptProvider._({
    required MemoryBlockForPromptFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'memoryBlockForPromptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$memoryBlockForPromptHash();

  @override
  String toString() {
    return r'memoryBlockForPromptProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<String> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String> create(Ref ref) {
    final argument = this.argument as String?;
    return memoryBlockForPrompt(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MemoryBlockForPromptProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$memoryBlockForPromptHash() =>
    r'1bc54481d14a37032d47208c531b8dd25a1658b8';

final class MemoryBlockForPromptFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<String>, String?> {
  MemoryBlockForPromptFamily._()
    : super(
        retry: null,
        name: r'memoryBlockForPromptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MemoryBlockForPromptProvider call(String? novelId) =>
      MemoryBlockForPromptProvider._(argument: novelId, from: this);

  @override
  String toString() => r'memoryBlockForPromptProvider';
}

/// 记忆提取服务 — 从对话历史中自动提取记忆。

@ProviderFor(memoryExtractionService)
final memoryExtractionServiceProvider = MemoryExtractionServiceProvider._();

/// 记忆提取服务 — 从对话历史中自动提取记忆。

final class MemoryExtractionServiceProvider
    extends
        $FunctionalProvider<
          MemoryExtractionService,
          MemoryExtractionService,
          MemoryExtractionService
        >
    with $Provider<MemoryExtractionService> {
  /// 记忆提取服务 — 从对话历史中自动提取记忆。
  MemoryExtractionServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'memoryExtractionServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$memoryExtractionServiceHash();

  @$internal
  @override
  $ProviderElement<MemoryExtractionService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MemoryExtractionService create(Ref ref) {
    return memoryExtractionService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MemoryExtractionService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MemoryExtractionService>(value),
    );
  }
}

String _$memoryExtractionServiceHash() =>
    r'13f45e467977053414e9325a84f1538b39bacb34';

/// 记忆消化服务 — 周期性整理记忆（去重合并、升级核心、淘汰过期）。

@ProviderFor(memoryDreamingService)
final memoryDreamingServiceProvider = MemoryDreamingServiceProvider._();

/// 记忆消化服务 — 周期性整理记忆（去重合并、升级核心、淘汰过期）。

final class MemoryDreamingServiceProvider
    extends
        $FunctionalProvider<
          MemoryDreamingService,
          MemoryDreamingService,
          MemoryDreamingService
        >
    with $Provider<MemoryDreamingService> {
  /// 记忆消化服务 — 周期性整理记忆（去重合并、升级核心、淘汰过期）。
  MemoryDreamingServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'memoryDreamingServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$memoryDreamingServiceHash();

  @$internal
  @override
  $ProviderElement<MemoryDreamingService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MemoryDreamingService create(Ref ref) {
    return memoryDreamingService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MemoryDreamingService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MemoryDreamingService>(value),
    );
  }
}

String _$memoryDreamingServiceHash() =>
    r'7ed4fd20885fe8d2f23134d9df449f67632d4e0e';

/// 记忆调度器 — 管理定时触发提取和消化的周期任务。

@ProviderFor(memoryScheduler)
final memorySchedulerProvider = MemorySchedulerProvider._();

/// 记忆调度器 — 管理定时触发提取和消化的周期任务。

final class MemorySchedulerProvider
    extends
        $FunctionalProvider<MemoryScheduler, MemoryScheduler, MemoryScheduler>
    with $Provider<MemoryScheduler> {
  /// 记忆调度器 — 管理定时触发提取和消化的周期任务。
  MemorySchedulerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'memorySchedulerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$memorySchedulerHash();

  @$internal
  @override
  $ProviderElement<MemoryScheduler> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MemoryScheduler create(Ref ref) {
    return memoryScheduler(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MemoryScheduler value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MemoryScheduler>(value),
    );
  }
}

String _$memorySchedulerHash() => r'c2983eb5d0383539ff1d4045112aedae94de39ea';
