// 职责: 提供官方技能目录查询与广场目录缓存、加载和刷新状态。
//   类别候选见 dictionary_providers.skillCategoriesProvider。
// 关联文件:
//   lib/shared/services/agent_skill_catalog_service.dart
//   lib/shared/models/official_agent_skill.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/models/marketplace_agent_skill.dart
//   lib/shared/services/proxy_client.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/error-handling.md
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logger/app_logger.dart';
import '../models/marketplace_agent_skill.dart';
import '../services/agent_skill_catalog_service.dart';
import '../services/proxy_client.dart';
import 'settings_providers.dart';

/// 目录查询过滤参数,作为 family 入参。
///
/// 使用 record 类型,Dart 3 自带值相等,可直接作为 family key。
typedef AgentSkillCatalogFilter = ({String? category, String? tag});

/// 创建 [AgentSkillCatalogFilter] 的便利构造。
AgentSkillCatalogFilter agentSkillCatalogFilter({
  String? category,
  String? tag,
}) {
  return (category: category, tag: tag);
}

final _log = AppLogger.forModule('AgentSkillCatalog');

// ── Service 单例 ──────────────────────────────────────────────────────────────

/// 操作开始时读取代理设置；目录刷新和仓库扫描均独占客户端并负责关闭。
final skillHttpClientFactoryProvider = Provider<Future<Dio> Function()>((ref) {
  return () async {
    final settings = await ref.read(appSettingsProvider.future);
    if (!ref.mounted) {
      throw StateError('Skill HTTP client factory disposed');
    }
    return createProxyDioClient(
      settings.networkProxy,
      options: BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        headers: {'User-Agent': 'Reveric-Skills'},
      ),
    );
  };
});

/// 官方本地目录与广场目录服务单例；本地读取不触发代理配置加载。
final agentSkillCatalogServiceProvider = Provider<AgentSkillCatalogService>((
  ref,
) {
  final service = AgentSkillCatalogService(
    createClient: ref.watch(skillHttpClientFactoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// 单个轻量目录跨标签页保留，筛选只使用 Widget 局部状态。
final marketplaceAgentSkillsProvider =
    NotifierProvider<MarketplaceAgentSkillsNotifier, MarketplaceCatalogState>(
      MarketplaceAgentSkillsNotifier.new,
    );

class MarketplaceCatalogState {
  const MarketplaceCatalogState({
    this.skills,
    this.loading = false,
    this.error,
  });
  final List<MarketplaceAgentSkill>? skills;
  final bool loading;
  final Object? error;
}

class MarketplaceAgentSkillsNotifier extends Notifier<MarketplaceCatalogState> {
  Future<void>? _pending;

  @override
  MarketplaceCatalogState build() {
    final service = ref.watch(agentSkillCatalogServiceProvider);
    _pending = Future<void>(() async {
      final cached = await service.readMarketplaceCache();
      if (!ref.mounted) {
        return;
      }
      state = MarketplaceCatalogState(skills: cached, loading: true);
      await _load(service);
    }).whenComplete(() => _pending = null);
    return const MarketplaceCatalogState(loading: true);
  }

  Future<void> refresh() {
    return _pending ??= _load(
      ref.read(agentSkillCatalogServiceProvider),
    ).whenComplete(() => _pending = null);
  }

  Future<void> _load(AgentSkillCatalogService service) async {
    state = MarketplaceCatalogState(skills: state.skills, loading: true);
    try {
      final skills = await service.listMarketplace();
      if (ref.mounted) {
        state = MarketplaceCatalogState(skills: skills);
      }
    } catch (error) {
      if (ref.mounted) {
        state = MarketplaceCatalogState(skills: state.skills, error: error);
      }
    }
  }
}

// ── 官方目录(本地打包，无需登录)────────────────────────────────────────────────

/// 全量官方目录。不过滤；family 只在内存里按 category/tag 切片。
///
/// 非 autoDispose：tab 过滤切换与预热共用同一份 asset 读取结果。
final officialAgentSkillCatalogProvider =
    FutureProvider<OfficialAgentSkillCatalog>((ref) {
      return ref.watch(agentSkillCatalogServiceProvider).listOfficial();
    });

/// 拉取官方 AgentSkill 目录摘要。读客户端 asset，不打网、不写磁盘缓存。
///
/// 目录过滤完全在本地摘要索引进行；[AgentSkillCatalogFilter.tag] 在官方目录里
/// 按关键词解释，详见 [OfficialAgentSkillsNotifier._matchesKeyword]。
/// 重读 asset：`ref.read(provider(filter).notifier).ensureFresh(force: true)`。
final officialAgentSkillsProvider = AsyncNotifierProvider.autoDispose
    .family<
      OfficialAgentSkillsNotifier,
      OfficialAgentSkillCatalog,
      AgentSkillCatalogFilter
    >(OfficialAgentSkillsNotifier.new);

class OfficialAgentSkillsNotifier
    extends AsyncNotifier<OfficialAgentSkillCatalog> {
  OfficialAgentSkillsNotifier(this.filter);

  final AgentSkillCatalogFilter filter;

  @override
  Future<OfficialAgentSkillCatalog> build() async {
    final list = await ref.watch(officialAgentSkillCatalogProvider.future);
    return _filter(list);
  }

  /// 重读打包目录。[build] 已 watch [officialAgentSkillCatalogProvider]，目录
  /// 状态由它单向驱动，因此这里只重建上游、不再自行写 state —— 两个 writer 抢同
  /// 一个 state 会让重试后出现「已出数据又闪回 loading」。
  ///
  /// 非 [force] 调用无事可做：只要有 listener，build 的 watch 已保证有值。
  Future<void> ensureFresh({bool force = false}) async {
    if (!force) {
      return;
    }
    try {
      // refresh 而非 invalidate：invalidate 的重建是异步调度的，调用方 await
      // 返回时上游可能还没重新读过 asset。
      final refreshed = ref.refresh(officialAgentSkillCatalogProvider.future);
      await refreshed;
    } catch (error, stackTrace) {
      // 失败态会作为 AsyncError（带旧值）出现在 state 上，UI 已能呈现；此处
      // 只留痕，不重复写 state。
      _log.warning(
        'refresh bundled official AgentSkill catalog failed '
        'error=$error stack=$stackTrace',
      );
    }
  }

  OfficialAgentSkillCatalog _filter(OfficialAgentSkillCatalog source) {
    final keyword = filter.tag?.trim().toLowerCase() ?? '';
    return OfficialAgentSkillCatalog(
      agentSkills: [
        for (final entry in source.agentSkills)
          if ((filter.category == null ||
                  filter.category!.isEmpty ||
                  entry.category == filter.category) &&
              _matchesKeyword(entry, keyword))
            entry,
      ],
    );
  }

  /// 官方目录是本地全量小目录，[AgentSkillCatalogFilter.tag] 在这里按关键词用：
  /// 搜索框文案是「搜索智能体技能」而非搜标签，且打包技能的 frontmatter 只声明
  /// metadata.category、不声明 tags，只比 tags 会让任何输入都搜空。
  ///
  /// [keyword] 由调用方转小写（`useDebouncedSearch` 已如此），此处按小写子串比。
  bool _matchesKeyword(OfficialAgentSkillSummary entry, String keyword) {
    if (keyword.isEmpty) {
      return true;
    }
    for (final field in [
      entry.name,
      entry.description,
      entry.category,
      ...entry.tags,
    ]) {
      if (field.toLowerCase().contains(keyword)) {
        return true;
      }
    }
    return false;
  }
}

/// 按 name（listingId）拉取官方 AgentSkill 完整详情。
final officialAgentSkillDetailProvider = FutureProvider.autoDispose
    .family<OfficialAgentSkill, String>((ref, listingId) {
      return ref
          .read(agentSkillCatalogServiceProvider)
          .getOfficial(listingId: listingId);
    });
