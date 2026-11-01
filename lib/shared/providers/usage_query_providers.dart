// 职责: AI Usage 查询 Provider — 装配 UsageService 并暴露统计、图表、分页查询入口
// 关联文件:
//   lib/shared/providers/novel_providers.dart
//   lib/shared/services/ai/usage_service.dart
//   lib/shared/database/app_database.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/db-query-aggregation.md

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/app_database.dart';
import '../services/ai/usage_service.dart';
import 'novel_providers.dart';

part 'usage_query_providers.g.dart';

// 后台 Agent 与统计页共用一个无运行态服务，随应用级 ProviderContainer 释放。
@Riverpod(keepAlive: true)
UsageService usageService(Ref ref) {
  final appDatabase = ref.watch(appDatabaseProvider);
  return UsageService(appDatabase: appDatabase);
}

@riverpod
Stream<UsageSummary> usageSummary(Ref ref, UsageFilter filter) {
  final service = ref.watch(usageServiceProvider);
  return service.watchSummary(filter);
}

@riverpod
Stream<List<DailyUsage>> dailyUsage(Ref ref, UsageFilter filter) {
  final service = ref.watch(usageServiceProvider);
  return service.watchDailyUsage(filter);
}

@riverpod
Future<UsageSummary> todayUsage(Ref ref) {
  final service = ref.watch(usageServiceProvider);
  return service.getTodayUsage();
}

@riverpod
Future<UsageSummary> thisMonthUsage(Ref ref) {
  final service = ref.watch(usageServiceProvider);
  return service.getThisMonthUsage();
}

@riverpod
Future<List<DailyUsage>> lastNDaysUsage(Ref ref, int days) {
  final service = ref.watch(usageServiceProvider);
  return service.getLastNDaysUsage(days);
}

@riverpod
Stream<int> usageRecordCount(Ref ref, UsageFilter filter) {
  final service = ref.watch(usageServiceProvider);
  return service.watchUsageRecordCount(filter);
}

@riverpod
Stream<List<AiUsageRecord>> usageRecordsPage(
  Ref ref,
  UsageFilter filter,
  int page,
) {
  const pageSize = 10;
  final service = ref.watch(usageServiceProvider);
  return service.watchUsageRecords(
    filter,
    limit: pageSize,
    offset: page * pageSize,
  );
}

@riverpod
Stream<List<UsageSourceSummary>> usageBySource(Ref ref, UsageFilter filter) {
  final service = ref.watch(usageServiceProvider);
  return service.watchSourceUsage(filter);
}

@riverpod
Stream<List<DailySourceUsage>> dailyUsageBySource(Ref ref, UsageFilter filter) {
  final service = ref.watch(usageServiceProvider);
  return service.watchDailySourceUsage(filter);
}

@riverpod
Stream<List<UsageSessionSummary>> topUsageSessions(
  Ref ref,
  UsageFilter filter,
) {
  final service = ref.watch(usageServiceProvider);
  return service.watchTopSessions(filter);
}

@riverpod
Stream<UsageSessionDetail?> usageSessionDetail(Ref ref, String sessionId) {
  final service = ref.watch(usageServiceProvider);
  return service.watchSessionDetail(sessionId);
}

@riverpod
Stream<UsageSessionMeter?> usageSessionMeter(Ref ref, String sessionId) {
  final service = ref.watch(usageServiceProvider);
  return service.watchSessionMeter(sessionId);
}
