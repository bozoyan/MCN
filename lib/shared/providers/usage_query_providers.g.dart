// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'usage_query_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(usageService)
final usageServiceProvider = UsageServiceProvider._();

final class UsageServiceProvider
    extends $FunctionalProvider<UsageService, UsageService, UsageService>
    with $Provider<UsageService> {
  UsageServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'usageServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$usageServiceHash();

  @$internal
  @override
  $ProviderElement<UsageService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UsageService create(Ref ref) {
    return usageService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UsageService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UsageService>(value),
    );
  }
}

String _$usageServiceHash() => r'226cd9d5e0c74c2103c3b3e2597896338fb78123';

@ProviderFor(usageSummary)
final usageSummaryProvider = UsageSummaryFamily._();

final class UsageSummaryProvider
    extends
        $FunctionalProvider<
          AsyncValue<UsageSummary>,
          UsageSummary,
          Stream<UsageSummary>
        >
    with $FutureModifier<UsageSummary>, $StreamProvider<UsageSummary> {
  UsageSummaryProvider._({
    required UsageSummaryFamily super.from,
    required UsageFilter super.argument,
  }) : super(
         retry: null,
         name: r'usageSummaryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$usageSummaryHash();

  @override
  String toString() {
    return r'usageSummaryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<UsageSummary> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<UsageSummary> create(Ref ref) {
    final argument = this.argument as UsageFilter;
    return usageSummary(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UsageSummaryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$usageSummaryHash() => r'483f340bc62bbf1a8d2c98261ea5890915a16a81';

final class UsageSummaryFamily extends $Family
    with $FunctionalFamilyOverride<Stream<UsageSummary>, UsageFilter> {
  UsageSummaryFamily._()
    : super(
        retry: null,
        name: r'usageSummaryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UsageSummaryProvider call(UsageFilter filter) =>
      UsageSummaryProvider._(argument: filter, from: this);

  @override
  String toString() => r'usageSummaryProvider';
}

@ProviderFor(dailyUsage)
final dailyUsageProvider = DailyUsageFamily._();

final class DailyUsageProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DailyUsage>>,
          List<DailyUsage>,
          Stream<List<DailyUsage>>
        >
    with $FutureModifier<List<DailyUsage>>, $StreamProvider<List<DailyUsage>> {
  DailyUsageProvider._({
    required DailyUsageFamily super.from,
    required UsageFilter super.argument,
  }) : super(
         retry: null,
         name: r'dailyUsageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$dailyUsageHash();

  @override
  String toString() {
    return r'dailyUsageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<DailyUsage>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<DailyUsage>> create(Ref ref) {
    final argument = this.argument as UsageFilter;
    return dailyUsage(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DailyUsageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dailyUsageHash() => r'46aeb3e0817926b334c16868c19d878624cc24fc';

final class DailyUsageFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<DailyUsage>>, UsageFilter> {
  DailyUsageFamily._()
    : super(
        retry: null,
        name: r'dailyUsageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DailyUsageProvider call(UsageFilter filter) =>
      DailyUsageProvider._(argument: filter, from: this);

  @override
  String toString() => r'dailyUsageProvider';
}

@ProviderFor(todayUsage)
final todayUsageProvider = TodayUsageProvider._();

final class TodayUsageProvider
    extends
        $FunctionalProvider<
          AsyncValue<UsageSummary>,
          UsageSummary,
          FutureOr<UsageSummary>
        >
    with $FutureModifier<UsageSummary>, $FutureProvider<UsageSummary> {
  TodayUsageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todayUsageProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todayUsageHash();

  @$internal
  @override
  $FutureProviderElement<UsageSummary> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<UsageSummary> create(Ref ref) {
    return todayUsage(ref);
  }
}

String _$todayUsageHash() => r'e90dc40c9e47af327d00be8d5a60d9cd7c713c6d';

@ProviderFor(thisMonthUsage)
final thisMonthUsageProvider = ThisMonthUsageProvider._();

final class ThisMonthUsageProvider
    extends
        $FunctionalProvider<
          AsyncValue<UsageSummary>,
          UsageSummary,
          FutureOr<UsageSummary>
        >
    with $FutureModifier<UsageSummary>, $FutureProvider<UsageSummary> {
  ThisMonthUsageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'thisMonthUsageProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$thisMonthUsageHash();

  @$internal
  @override
  $FutureProviderElement<UsageSummary> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<UsageSummary> create(Ref ref) {
    return thisMonthUsage(ref);
  }
}

String _$thisMonthUsageHash() => r'2e8ea499a9f69e5045248929578892b62ce419d9';

@ProviderFor(lastNDaysUsage)
final lastNDaysUsageProvider = LastNDaysUsageFamily._();

final class LastNDaysUsageProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DailyUsage>>,
          List<DailyUsage>,
          FutureOr<List<DailyUsage>>
        >
    with $FutureModifier<List<DailyUsage>>, $FutureProvider<List<DailyUsage>> {
  LastNDaysUsageProvider._({
    required LastNDaysUsageFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'lastNDaysUsageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lastNDaysUsageHash();

  @override
  String toString() {
    return r'lastNDaysUsageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<DailyUsage>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<DailyUsage>> create(Ref ref) {
    final argument = this.argument as int;
    return lastNDaysUsage(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LastNDaysUsageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lastNDaysUsageHash() => r'6d56d66153972f283bc1e762d3b0a8bcf9fd4441';

final class LastNDaysUsageFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<DailyUsage>>, int> {
  LastNDaysUsageFamily._()
    : super(
        retry: null,
        name: r'lastNDaysUsageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LastNDaysUsageProvider call(int days) =>
      LastNDaysUsageProvider._(argument: days, from: this);

  @override
  String toString() => r'lastNDaysUsageProvider';
}

@ProviderFor(usageRecordCount)
final usageRecordCountProvider = UsageRecordCountFamily._();

final class UsageRecordCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  UsageRecordCountProvider._({
    required UsageRecordCountFamily super.from,
    required UsageFilter super.argument,
  }) : super(
         retry: null,
         name: r'usageRecordCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$usageRecordCountHash();

  @override
  String toString() {
    return r'usageRecordCountProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    final argument = this.argument as UsageFilter;
    return usageRecordCount(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UsageRecordCountProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$usageRecordCountHash() => r'a8a6d8d52aed6f63f70caf08572d5c0689944bd9';

final class UsageRecordCountFamily extends $Family
    with $FunctionalFamilyOverride<Stream<int>, UsageFilter> {
  UsageRecordCountFamily._()
    : super(
        retry: null,
        name: r'usageRecordCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UsageRecordCountProvider call(UsageFilter filter) =>
      UsageRecordCountProvider._(argument: filter, from: this);

  @override
  String toString() => r'usageRecordCountProvider';
}

@ProviderFor(usageRecordsPage)
final usageRecordsPageProvider = UsageRecordsPageFamily._();

final class UsageRecordsPageProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AiUsageRecord>>,
          List<AiUsageRecord>,
          Stream<List<AiUsageRecord>>
        >
    with
        $FutureModifier<List<AiUsageRecord>>,
        $StreamProvider<List<AiUsageRecord>> {
  UsageRecordsPageProvider._({
    required UsageRecordsPageFamily super.from,
    required (UsageFilter, int) super.argument,
  }) : super(
         retry: null,
         name: r'usageRecordsPageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$usageRecordsPageHash();

  @override
  String toString() {
    return r'usageRecordsPageProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<AiUsageRecord>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<AiUsageRecord>> create(Ref ref) {
    final argument = this.argument as (UsageFilter, int);
    return usageRecordsPage(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is UsageRecordsPageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$usageRecordsPageHash() => r'dfd52f0de996b42251e2161c1f8fa5a6ca4d4c0e';

final class UsageRecordsPageFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<AiUsageRecord>>,
          (UsageFilter, int)
        > {
  UsageRecordsPageFamily._()
    : super(
        retry: null,
        name: r'usageRecordsPageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UsageRecordsPageProvider call(UsageFilter filter, int page) =>
      UsageRecordsPageProvider._(argument: (filter, page), from: this);

  @override
  String toString() => r'usageRecordsPageProvider';
}

@ProviderFor(usageBySource)
final usageBySourceProvider = UsageBySourceFamily._();

final class UsageBySourceProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<UsageSourceSummary>>,
          List<UsageSourceSummary>,
          Stream<List<UsageSourceSummary>>
        >
    with
        $FutureModifier<List<UsageSourceSummary>>,
        $StreamProvider<List<UsageSourceSummary>> {
  UsageBySourceProvider._({
    required UsageBySourceFamily super.from,
    required UsageFilter super.argument,
  }) : super(
         retry: null,
         name: r'usageBySourceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$usageBySourceHash();

  @override
  String toString() {
    return r'usageBySourceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<UsageSourceSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<UsageSourceSummary>> create(Ref ref) {
    final argument = this.argument as UsageFilter;
    return usageBySource(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UsageBySourceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$usageBySourceHash() => r'd6ab5db079f3ed83d746164e86f5e31129a296ae';

final class UsageBySourceFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<UsageSourceSummary>>,
          UsageFilter
        > {
  UsageBySourceFamily._()
    : super(
        retry: null,
        name: r'usageBySourceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UsageBySourceProvider call(UsageFilter filter) =>
      UsageBySourceProvider._(argument: filter, from: this);

  @override
  String toString() => r'usageBySourceProvider';
}

@ProviderFor(dailyUsageBySource)
final dailyUsageBySourceProvider = DailyUsageBySourceFamily._();

final class DailyUsageBySourceProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DailySourceUsage>>,
          List<DailySourceUsage>,
          Stream<List<DailySourceUsage>>
        >
    with
        $FutureModifier<List<DailySourceUsage>>,
        $StreamProvider<List<DailySourceUsage>> {
  DailyUsageBySourceProvider._({
    required DailyUsageBySourceFamily super.from,
    required UsageFilter super.argument,
  }) : super(
         retry: null,
         name: r'dailyUsageBySourceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$dailyUsageBySourceHash();

  @override
  String toString() {
    return r'dailyUsageBySourceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<DailySourceUsage>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<DailySourceUsage>> create(Ref ref) {
    final argument = this.argument as UsageFilter;
    return dailyUsageBySource(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DailyUsageBySourceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dailyUsageBySourceHash() =>
    r'a0666210bed02c7282bbece1e9abd22b19b5d2cb';

final class DailyUsageBySourceFamily extends $Family
    with
        $FunctionalFamilyOverride<Stream<List<DailySourceUsage>>, UsageFilter> {
  DailyUsageBySourceFamily._()
    : super(
        retry: null,
        name: r'dailyUsageBySourceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DailyUsageBySourceProvider call(UsageFilter filter) =>
      DailyUsageBySourceProvider._(argument: filter, from: this);

  @override
  String toString() => r'dailyUsageBySourceProvider';
}

@ProviderFor(topUsageSessions)
final topUsageSessionsProvider = TopUsageSessionsFamily._();

final class TopUsageSessionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<UsageSessionSummary>>,
          List<UsageSessionSummary>,
          Stream<List<UsageSessionSummary>>
        >
    with
        $FutureModifier<List<UsageSessionSummary>>,
        $StreamProvider<List<UsageSessionSummary>> {
  TopUsageSessionsProvider._({
    required TopUsageSessionsFamily super.from,
    required UsageFilter super.argument,
  }) : super(
         retry: null,
         name: r'topUsageSessionsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$topUsageSessionsHash();

  @override
  String toString() {
    return r'topUsageSessionsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<UsageSessionSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<UsageSessionSummary>> create(Ref ref) {
    final argument = this.argument as UsageFilter;
    return topUsageSessions(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TopUsageSessionsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$topUsageSessionsHash() => r'302d2c28b42d45fd288bf464e37a5751c138b18b';

final class TopUsageSessionsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<UsageSessionSummary>>,
          UsageFilter
        > {
  TopUsageSessionsFamily._()
    : super(
        retry: null,
        name: r'topUsageSessionsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TopUsageSessionsProvider call(UsageFilter filter) =>
      TopUsageSessionsProvider._(argument: filter, from: this);

  @override
  String toString() => r'topUsageSessionsProvider';
}

@ProviderFor(usageSessionDetail)
final usageSessionDetailProvider = UsageSessionDetailFamily._();

final class UsageSessionDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<UsageSessionDetail?>,
          UsageSessionDetail?,
          Stream<UsageSessionDetail?>
        >
    with
        $FutureModifier<UsageSessionDetail?>,
        $StreamProvider<UsageSessionDetail?> {
  UsageSessionDetailProvider._({
    required UsageSessionDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'usageSessionDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$usageSessionDetailHash();

  @override
  String toString() {
    return r'usageSessionDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<UsageSessionDetail?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<UsageSessionDetail?> create(Ref ref) {
    final argument = this.argument as String;
    return usageSessionDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UsageSessionDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$usageSessionDetailHash() =>
    r'56d2130c145101562a2ccff8880048274f1605d9';

final class UsageSessionDetailFamily extends $Family
    with $FunctionalFamilyOverride<Stream<UsageSessionDetail?>, String> {
  UsageSessionDetailFamily._()
    : super(
        retry: null,
        name: r'usageSessionDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UsageSessionDetailProvider call(String sessionId) =>
      UsageSessionDetailProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'usageSessionDetailProvider';
}

@ProviderFor(usageSessionMeter)
final usageSessionMeterProvider = UsageSessionMeterFamily._();

final class UsageSessionMeterProvider
    extends
        $FunctionalProvider<
          AsyncValue<UsageSessionMeter?>,
          UsageSessionMeter?,
          Stream<UsageSessionMeter?>
        >
    with
        $FutureModifier<UsageSessionMeter?>,
        $StreamProvider<UsageSessionMeter?> {
  UsageSessionMeterProvider._({
    required UsageSessionMeterFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'usageSessionMeterProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$usageSessionMeterHash();

  @override
  String toString() {
    return r'usageSessionMeterProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<UsageSessionMeter?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<UsageSessionMeter?> create(Ref ref) {
    final argument = this.argument as String;
    return usageSessionMeter(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UsageSessionMeterProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$usageSessionMeterHash() => r'f62422f79e3efeb5e49dc1baffdb37295f4ba18b';

final class UsageSessionMeterFamily extends $Family
    with $FunctionalFamilyOverride<Stream<UsageSessionMeter?>, String> {
  UsageSessionMeterFamily._()
    : super(
        retry: null,
        name: r'usageSessionMeterProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UsageSessionMeterProvider call(String sessionId) =>
      UsageSessionMeterProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'usageSessionMeterProvider';
}
