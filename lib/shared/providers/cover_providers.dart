// 职责: 封面工作台的共享 Riverpod providers — 封面档案读稿、作品体量与过时判断。
// 关联文件:
//   lib/shared/services/ai/cover_brief_service.dart
//   lib/shared/database/novel_content_daos/chapter_dao.dart
//   lib/shared/models/cover_brief.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/providers/server_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/ai-calling.md

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../agent/client/trace_headers_http_client.dart'
    show buildTraceSessionHeaders;
import '../database/novel_content_daos/chapter_dao.dart';
import '../logger/app_logger.dart';
import '../models/ai_provider.dart';
import '../models/cover_brief.dart';
import '../services/ai/ai_http_client_lease.dart';
import '../services/ai/chat.dart';
import '../services/ai/cover_brief_service.dart';
import 'ai_providers.dart';
import 'novel_providers.dart';
import 'settings_providers.dart';

part 'cover_providers.g.dart';

final _log = AppLogger.forModule('CoverBrief');

/// 读稿任务的 http.Client 租约槽位，随 provider 销毁归还。
AiHttpClientLeaseHolder _coverBriefLeaseHolder(Ref ref) {
  final holder = AiHttpClientLeaseHolder(
    ref.read(aiHttpClientRegistryProvider),
  );
  ref.onDispose(holder.dispose);
  return holder;
}

Future<AiClient?> _createAiClientForCoverBrief(
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
    (item) => item.id == defaultId,
    orElse: () => chatOptions.first,
  );

  final config = settings.aiSettings.findConfigById(option.providerId);
  if (config == null || !config.isValid) return null;
  final client = AiClient(
    config,
    chatModel: option.model,

    httpClient: leaseHolder.clientFor(config),
    traceHeadersProvider: () =>
        buildTraceSessionHeaders(sessionMode: 'cover_brief'),
  );
  try {
    await client.initialize();
    return client;
  } catch (error) {
    _log.error('failed to initialize AI client: $error');
    return null;
  }
}

@riverpod
CoverBriefService coverBriefService(Ref ref) {
  final leaseHolder = _coverBriefLeaseHolder(ref);
  return CoverBriefService(
    clientFactory: () => _createAiClientForCoverBrief(ref, leaseHolder),
  );
}

/// 档案状态：未读 / 读取中 / 已读。
@riverpod
Stream<CoverBriefState> coverBriefState(Ref ref, String databasePath) {
  final contentDb = ref.watch(novelContentDatabaseProvider(databasePath));
  return ref.watch(coverBriefServiceProvider).watch(contentDb);
}

/// 档案是否已经跟不上稿子。没有档案时返回 false。
@riverpod
Future<bool> coverBriefStale(Ref ref, String databasePath) async {
  final state = await ref.watch(coverBriefStateProvider(databasePath).future);
  final brief = state.brief;
  if (brief == null) return false;
  final contentDb = ref.watch(novelContentDatabaseProvider(databasePath));
  final service = ref.watch(coverBriefServiceProvider);
  final stats = await service.currentStats(contentDb, brief: brief);
  return isCoverBriefStale(brief, stats);
}

/// 作品卡片的体量：章节数与总字数，取自内容库当前值。
///
/// 一次性读取而不是订阅：封面面板打开期间体量不会变到影响判断，订阅全量章节
/// （`chaptersProvider` 走的是带正文的 VIEW）只为数两个数字并不划算。
@riverpod
Future<ChapterListStats> coverWorkStats(Ref ref, String databasePath) {
  final contentDb = ref.watch(novelContentDatabaseProvider(databasePath));
  return contentDb.chapterDao.getListStats();
}
