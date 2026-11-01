// 职责: 验证本地官方技能目录加载、缓存刷新与市场未接入状态。
// 关联文件:
//   lib/shared/providers/agent_skill_catalog_providers.dart
//   lib/shared/services/agent_skill_catalog_service.dart
//   lib/shared/models/official_agent_skill.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/error-handling.md
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/providers/agent_skill_catalog_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/agent_skill_catalog_service.dart';

void main() {
  group('AgentSkillCatalog providers', () {
    group('officialAgentSkillsProvider', () {
      test('resolves the bundled list via service', () async {
        final fake = _FakeAgentSkillCatalogService(
          officialList: const OfficialAgentSkillCatalog(
            agentSkills: [
              OfficialAgentSkill(
                listingId: 'official-1',
                name: 'Weather',
                whenToUse: 'when weather',
                description: 'desc',
                prompt: 'prompt',
                category: 'utils',
                tags: ['weather'],
                version: 1,
                sortOrder: 0,
                updatedAt: '2026-01-01T00:00:00Z',
              ),
            ],
          ),
        );
        final container = _testContainer(
          overrides: [agentSkillCatalogServiceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        final result = await container.read(
          officialAgentSkillsProvider(agentSkillCatalogFilter()).future,
        );

        expect(result.agentSkills.length, 1);
        expect(result.agentSkills.first.listingId, 'official-1');
        expect(fake.officialCalls, 1);

        // fresh 窗口内再次 read 应命中缓存，不重复读取目录。
        await container.read(
          officialAgentSkillsProvider(agentSkillCatalogFilter()).future,
        );
        expect(fake.officialCalls, 1);
      });

      test('ensureFresh force refetches within stale window', () async {
        final fake = _FakeAgentSkillCatalogService(
          officialList: const OfficialAgentSkillCatalog(
            agentSkills: [
              OfficialAgentSkill(
                listingId: 'official-1',
                name: 'Weather',
                whenToUse: 'when weather',
                description: 'desc',
                prompt: 'prompt',
                category: 'utils',
                tags: ['weather'],
                version: 1,
                sortOrder: 0,
                updatedAt: '2026-01-01T00:00:00Z',
              ),
            ],
          ),
        );
        final container = _testContainer(
          overrides: [agentSkillCatalogServiceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        final filter = agentSkillCatalogFilter();
        await container.read(officialAgentSkillsProvider(filter).future);
        expect(fake.officialCalls, 1);

        await container
            .read(officialAgentSkillsProvider(filter).notifier)
            .ensureFresh(force: true);
        expect(fake.officialCalls, 2);
      });

      test('ensureFresh keeps previous data when refetch fails', () async {
        final fake = _FakeAgentSkillCatalogService(
          officialList: const OfficialAgentSkillCatalog(
            agentSkills: [
              OfficialAgentSkill(
                listingId: 'official-1',
                name: 'Weather',
                whenToUse: 'when weather',
                description: 'desc',
                prompt: 'prompt',
                category: 'utils',
                tags: ['weather'],
                version: 1,
                sortOrder: 0,
                updatedAt: '2026-01-01T00:00:00Z',
              ),
            ],
          ),
        );
        final container = _testContainer(
          overrides: [agentSkillCatalogServiceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        final filter = agentSkillCatalogFilter();
        final first = await container.read(
          officialAgentSkillsProvider(filter).future,
        );
        expect(first.agentSkills.first.listingId, 'official-1');

        fake.officialError = StateError('network down');
        await container
            .read(officialAgentSkillsProvider(filter).notifier)
            .ensureFresh(force: true);

        final state = container.read(officialAgentSkillsProvider(filter));
        expect(state.hasValue, isTrue);
        expect(state.requireValue.agentSkills.first.listingId, 'official-1');
      });

      test('filters the full cached directory locally', () async {
        final fake = _FakeAgentSkillCatalogService(
          officialList: const OfficialAgentSkillCatalog(
            agentSkills: [
              OfficialAgentSkillSummary(
                listingId: 'official-match',
                name: 'Match',
                description: 'desc',
                category: 'utils',
                tags: ['weather'],
                version: 1,
                updatedAt: '2026-01-01T00:00:00Z',
              ),
              OfficialAgentSkillSummary(
                listingId: 'official-other',
                name: 'Other',
                description: 'desc',
                category: 'other',
                tags: ['other'],
                version: 1,
                updatedAt: '2026-01-01T00:00:00Z',
              ),
            ],
          ),
        );
        final container = _testContainer(
          overrides: [agentSkillCatalogServiceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        await container.read(
          officialAgentSkillsProvider(
            agentSkillCatalogFilter(category: 'utils', tag: 'weather'),
          ).future,
        );

        final filtered = container.read(
          officialAgentSkillsProvider(
            agentSkillCatalogFilter(category: 'utils', tag: 'weather'),
          ),
        );
        expect(
          filtered.requireValue.agentSkills.single.listingId,
          'official-match',
        );
        // service 只暴露无参 listOfficial —— 过滤没有下推到目录读取层，
        // 全量目录只被读了一次。
        expect(fake.officialCalls, 1);
      });
    });
  });
}

ProviderContainer _testContainer({required List<Override> overrides}) {
  final database = AppDatabase.forTest(NativeDatabase.memory());
  addTearDown(database.close);
  return ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(database), ...overrides],
  );
}

// ── Fakes ────────────────────────────────────────────────────────────────────

/// 实现 [AgentSkillCatalogService] 接口的 fake,记录调用参数供断言。
///
/// 仅实现 catalog provider 实际调用的方法;create/withdraw 等编辑类方法
/// 抛 [UnimplementedError](本测试不覆盖)。
class _FakeAgentSkillCatalogService extends AgentSkillCatalogService {
  _FakeAgentSkillCatalogService({OfficialAgentSkillCatalog? officialList})
    : _officialList =
          officialList ?? const OfficialAgentSkillCatalog(agentSkills: []);
  final OfficialAgentSkillCatalog _officialList;
  int officialCalls = 0;
  Object? officialError;
  @override
  Future<OfficialAgentSkillCatalog> listOfficial() async {
    officialCalls++;
    if (officialError != null) {
      throw officialError!;
    }
    return _officialList;
  }

  @override
  Future<OfficialAgentSkill> getOfficial({required String listingId}) =>
      throw UnimplementedError();
}
