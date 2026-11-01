// 职责: Memory 相关的 Riverpod providers — 状态查询、动作入口、prompt 注入、定时提取与消化
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/services/ai/memory_service.dart
//   lib/shared/services/ai/memory_scheduler.dart
//   lib/shared/services/ai/memory_extraction_service.dart
//   lib/shared/services/ai/memory_dreaming_service.dart
//   lib/shared/services/ai/chat.dart
//   lib/shared/providers/settings_providers.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/ai_provider.dart';
import '../services/ai/chat.dart';
import '../logger/app_logger.dart';
import '../agent/client/trace_headers_http_client.dart'
    show buildTraceSessionHeaders;
import '../services/ai/ai_http_client_lease.dart';
import '../services/ai/memory_dreaming_service.dart';
import '../services/ai/memory_extraction_service.dart';
import '../services/ai/memory_scheduler.dart';
import '../services/ai/memory_service.dart';
import 'ai_providers.dart';
import 'novel_providers.dart';
import 'settings_providers.dart';

part 'memory_providers.g.dart';

final _log = AppLogger.forModule('Memory');

@riverpod
MemoryService memoryService(Ref ref) {
  final database = ref.watch(appDatabaseProvider);
  return MemoryService(database);
}

@riverpod
Stream<List<Memory>> globalMemories(Ref ref) {
  final service = ref.watch(memoryServiceProvider);
  return service.watchGlobal();
}

@riverpod
Stream<List<Memory>> novelMemories(Ref ref, String novelId) {
  final service = ref.watch(memoryServiceProvider);
  return service.watchByNovelId(novelId);
}

@riverpod
Future<List<Memory>> memoriesForPrompt(Ref ref, String? novelId) {
  final service = ref.watch(memoryServiceProvider);
  return service.getMemoriesForPrompt(novelId: novelId);
}

@riverpod
Future<String> memoryBlockForPrompt(Ref ref, String? novelId) async {
  final memories = await ref.watch(memoriesForPromptProvider(novelId).future);
  if (memories.isEmpty) return '';
  return MemoryService.buildMemoryPromptBlock(memories);
}

// =============================================================================
// Memory scheduler, extraction & dreaming
// =============================================================================

/// 记忆任务的 http.Client 租约槽位。
///
/// clientFactory 由 30s 周期的 scheduler 反复调用，租约必须复用而非每次新借，
/// 因此收敛到 provider 级的单槽 holder，随 provider 销毁归还。
AiHttpClientLeaseHolder _memoryLeaseHolder(Ref ref) {
  final holder = AiHttpClientLeaseHolder(
    ref.read(aiHttpClientRegistryProvider),
  );
  ref.onDispose(holder.dispose);
  return holder;
}

/// 记忆提取服务 — 从对话历史中自动提取记忆。
@riverpod
MemoryExtractionService memoryExtractionService(Ref ref) {
  final appDb = ref.watch(appDatabaseProvider);
  final leaseHolder = _memoryLeaseHolder(ref);
  return MemoryExtractionService(
    appDb: appDb,
    clientFactory: () => _createAiClientForMemoryTasks(ref, leaseHolder),
  );
}

/// 记忆消化服务 — 周期性整理记忆（去重合并、升级核心、淘汰过期）。
@riverpod
MemoryDreamingService memoryDreamingService(Ref ref) {
  final appDb = ref.watch(appDatabaseProvider);
  final leaseHolder = _memoryLeaseHolder(ref);
  return MemoryDreamingService(
    appDb: appDb,
    clientFactory: () => _createAiClientForMemoryTasks(ref, leaseHolder),
  );
}

/// 记忆调度器 — 管理定时触发提取和消化的周期任务。
@Riverpod(keepAlive: true)
MemoryScheduler memoryScheduler(Ref ref) {
  final appDb = ref.watch(appDatabaseProvider);
  final extractService = ref.watch(memoryExtractionServiceProvider);
  final dreamService = ref.watch(memoryDreamingServiceProvider);

  final settingsAsync = ref.watch(appSettingsNotifierProvider);
  final settings = settingsAsync.asData?.value;

  final scheduler = MemoryScheduler(
    db: appDb,
    extractionIntervalMinutes: settings?.memoryExtractionIntervalMinutes ?? 60,
    extractionEnabled: settings?.memoryAutoExtract ?? true,
    dreamingEnabled: false,
    onExtract: (novelId) async {
      final novel = await appDb.novelDao.get(novelId);
      final contentPath = novel?.contentDatabasePath;
      if (contentPath == null || contentPath.isEmpty) return;

      final contentDb = ref.read(novelContentDatabaseProvider(contentPath));
      await extractService.extractFromChat(
        novelId: novelId,
        contentDb: contentDb,
      );
    },
    onDream: (novelId) async {
      await dreamService.dream(novelId: novelId);
    },
  );

  ref.listen<AsyncValue<AppSettings>>(appSettingsNotifierProvider, (_, next) {
    final s = next.asData?.value;
    if (s == null) return;
    scheduler.updateConfig(
      extractionIntervalMinutes: s.memoryExtractionIntervalMinutes,
      extractionEnabled: s.memoryAutoExtract,
      dreamingEnabled: false,
    );
  });

  scheduler.start();

  ref.onDispose(scheduler.dispose);
  return scheduler;
}

/// 创建用于记忆任务的轻量 AI 客户端。
///
/// 不传 novelContentService / workingOverlayService，纯聊天不需要工具注册。
Future<AiClient?> _createAiClientForMemoryTasks(
  Ref ref,
  AiHttpClientLeaseHolder leaseHolder,
) async {
  final settings = ref.read(appSettingsNotifierProvider).asData?.value;
  if (settings == null) return null;

  final chatOptions = settings.aiSettings.availableModelOptionsForKind(
    AiModelKind.chat,
  );
  if (chatOptions.isEmpty) return null;

  final defaultId = settings.aiSettings.defaultOptionIdForKind(
    AiModelKind.chat,
  );
  final option = chatOptions.firstWhere(
    (option) => option.id == defaultId,
    orElse: () => chatOptions.first,
  );

  final config = settings.aiSettings.findConfigById(option.providerId);
  if (config == null || !config.isValid) return null;

  final httpClient = leaseHolder.clientFor(config);
  final client = AiClient(
    config,
    chatModel: option.model,

    httpClient: httpClient,
    traceHeadersProvider: () => buildTraceSessionHeaders(sessionMode: 'memory'),
  );

  try {
    await client.initialize();
    return client;
  } catch (e) {
    _log.error('failed to initialize AI client: $e');
    return null;
  }
}
