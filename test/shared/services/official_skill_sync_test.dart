// 职责: 验证官方技能同步的安装、升级、退役卸载、身份去重与失败重试边界。
// 关联文件:
//   lib/shared/services/official_skill_sync.dart
//   lib/shared/models/catalog_skill_installation_state.dart
//   lib/shared/models/novel_agent_skill.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/novel_agent_skill.dart';
import 'package:reveric/shared/services/official_skill_sync.dart';
import 'package:reveric/shared/models/official_agent_skill.dart';

void main() {
  test(
    'installs new catalog entries and does not reinstall handled entries',
    () async {
      final harness = _Harness()
        ..catalog.addAll([_catalog('new'), _catalog('removed')])
        ..handled.add('removed');
      final result = await harness.run();
      expect(result.installed, 1);
      expect(result.failed, 0);
      expect(harness.installs, ['new']);
      expect(harness.handled, {'new', 'removed'});
      expect((await harness.run()).installed, 0);
    },
  );

  test(
    'upgrades every stale official copy by source name and keeps local names',
    () async {
      final harness = _Harness()
        ..catalog.addAll([_catalog('official', 2), _catalog('local', 2)])
        ..installed.addAll([
          _installed('one', 'renamed', sourceName: 'official'),
          _installed('two', 'second copy', sourceName: 'official'),
          _installed(
            'fresh',
            'fresh copy',
            sourceName: 'official',
            version: '2',
          ),
          _installed(
            'local',
            'local',
            sourceKind: AgentSkillSourceKind.novelLocal,
          ),
        ]);
      final result = await harness.run();
      expect(result.upgraded, 2);
      expect(harness.upgrades, ['one', 'two']);
      expect(harness.installs, isEmpty);
      expect(harness.handled, {'official', 'local'});
    },
  );

  test('handled identity still receives upgrades', () async {
    final harness = _Harness()
      ..catalog.add(_catalog('official', 3))
      ..installed.add(_installed('id', 'official'))
      ..handled.add('official');
    expect((await harness.run()).upgraded, 1);
    expect(harness.upgrades, ['id']);
  });

  test('failed install stays unhandled and later entries continue', () async {
    final harness = _Harness()
      ..catalog.addAll([_catalog('failed'), _catalog('ok')])
      ..installFailures.add('failed');
    final first = await harness.run();
    expect(first.failed, 1);
    expect(first.installed, 1);
    expect(harness.handled, {'ok'});
    harness.installFailures.clear();
    final second = await harness.run();
    expect(second.installed, 1);
    expect(second.failed, 0);
    expect(harness.handled, {'ok', 'failed'});
  });

  test(
    'failed upgrade does not prevent other copies or new installs',
    () async {
      final harness = _Harness()
        ..catalog.addAll([_catalog('official', 2), _catalog('new')])
        ..installed.addAll([
          _installed('failed', 'official'),
          _installed('ok', 'alias', sourceName: 'official'),
        ])
        ..upgradeFailures.add('failed');
      final result = await harness.run();
      expect(result.failed, 1);
      expect(result.upgraded, 1);
      expect(result.installed, 1);
      expect(harness.upgrades, ['ok']);
    },
  );

  test('install conflict is handled without replacing user content', () async {
    final harness = _Harness()
      ..catalog.add(_catalog('conflict'))
      ..conflicts.add('conflict');
    final result = await harness.run();
    expect(result.installed, 0);
    expect(result.failed, 0);
    expect(harness.handled, {'conflict'});
  });

  test(
    'failed marker retries by recognizing the successful installation',
    () async {
      final harness = _Harness()
        ..catalog.add(_catalog('new'))
        ..markFailures.add('new');
      expect((await harness.run()).failed, 1);
      expect(harness.handled, isEmpty);
      expect(harness.installs, ['new']);
      harness.installed.add(_installed('installed', 'new'));
      harness.markFailures.clear();
      expect((await harness.run()).failed, 0);
      expect(harness.installs, ['new']);
      expect(harness.handled, {'new'});
    },
  );

  test('handled-state read failure prevents all writes', () async {
    final harness = _Harness()
      ..catalog.add(_catalog('new'))
      ..installed.add(_installed('retired', '剧本对白'))
      ..failRead = true;
    await expectLater(harness.run(), throwsStateError);
    expect(harness.installs, isEmpty);
    expect(harness.upgrades, isEmpty);
    expect(harness.handled, isEmpty);
    expect(harness.uninstalls, isEmpty);
  });

  test(
    'reconciles arbitrary unlisted official sources while preserving local and market skills',
    () async {
      final harness = _Harness()
        ..catalog.addAll([_catalog('剧本写作', 5), _catalog('章节写作')])
        ..installed.addAll([
          _installed('writing', '剧本写作', version: '4'),
          _installed('adaptation', '我的改编', sourceName: '剧本改编'),
          _installed('planning', '分集规划'),
          _installed('dialogue', '剧本对白'),
          _installed('review', '剧本审查'),
          _installed(
            'local',
            '剧本对白',
            sourceKind: AgentSkillSourceKind.novelLocal,
          ),
          _installed(
            'market',
            '剧本审查',
            sourceKind: AgentSkillSourceKind.marketplace,
          ),
          _installed('unlisted', '其他未列出的官方技能'),
          _installed('renamed', '剧本对白', sourceName: '章节写作'),
        ]);
      final result = await harness.run();
      expect(result.upgraded, 1);
      expect(result.uninstalled, 5);
      expect(result.failed, 0);
      expect(harness.uninstalls, [
        'adaptation',
        'planning',
        'dialogue',
        'review',
        'unlisted',
      ]);
      expect(harness.installed.map((skill) => skill.id), [
        'writing',
        'local',
        'market',
        'renamed',
      ]);
      expect((await harness.run()).uninstalled, 0);
    },
  );

  test(
    'failed retirement retries while other removals and installs continue',
    () async {
      final harness = _Harness()
        ..catalog.add(_catalog('new'))
        ..installed.addAll([
          _installed('failed', '剧本改编'),
          _installed('ok', '分集规划'),
        ])
        ..uninstallFailures.add('failed');
      final first = await harness.run();
      expect(first.installed, 1);
      expect(first.uninstalled, 1);
      expect(first.failed, 1);
      expect(harness.installed.single.id, 'failed');
      harness.uninstallFailures.clear();
      final retry = await harness.run();
      expect(retry.uninstalled, 1);
      expect(retry.failed, 0);
      expect(harness.uninstalls, ['ok', 'failed']);
      expect(harness.installs, ['new']);
    },
  );

  test('catalog read failure never uninstalls official snapshots', () async {
    final harness = _Harness()
      ..installed.add(_installed('old', '任意旧官方技能'))
      ..failCatalog = true;
    await expectLater(harness.run(), throwsStateError);
    expect(harness.uninstalls, isEmpty);
    expect(harness.installs, isEmpty);
    expect(harness.upgrades, isEmpty);
    expect(harness.installed.single.id, 'old');
  });

  test(
    'an empty authoritative catalog removes only official installations',
    () async {
      final harness = _Harness()
        ..installed.addAll([
          _installed('old', '任意旧官方技能'),
          _installed(
            'local',
            '本地技能',
            sourceKind: AgentSkillSourceKind.novelLocal,
          ),
          _installed(
            'market',
            '市场技能',
            sourceKind: AgentSkillSourceKind.marketplace,
          ),
        ]);
      expect((await harness.run()).uninstalled, 1);
      expect(harness.installed.map((skill) => skill.id), ['local', 'market']);
    },
  );

  test(
    'uninstalls old renamed source before installing the reused name',
    () async {
      final harness = _Harness()
        ..catalog.add(_catalog('new'))
        ..installed.add(_installed('old', 'new', sourceName: 'withdrawn'));
      final result = await harness.run();
      expect(result.uninstalled, 1);
      expect(result.installed, 1);
      expect(harness.installs, ['new']);
    },
  );

  test(
    'failed uninstall does not mark a blocked new name as handled',
    () async {
      final harness = _Harness()
        ..catalog.add(_catalog('new'))
        ..installed.add(_installed('old', 'new', sourceName: 'withdrawn'))
        ..uninstallFailures.add('old');
      final first = await harness.run();
      expect(first.failed, 1);
      expect(first.installed, 0);
      expect(harness.handled, isEmpty);
      harness.uninstallFailures.clear();
      final retry = await harness.run();
      expect(retry.uninstalled, 1);
      expect(retry.installed, 1);
      expect(harness.handled, {'new'});
    },
  );

  test('a listed official skill is not retired', () async {
    final harness = _Harness()
      ..catalog.add(_catalog('剧本对白', 4))
      ..installed.add(_installed('dialogue', '剧本对白', version: '4'));
    expect((await harness.run()).uninstalled, 0);
    expect(harness.installed.single.id, 'dialogue');
  });
}

OfficialAgentSkillSummary _catalog(String name, [int version = 1]) =>
    OfficialAgentSkillSummary(
      listingId: name,
      name: name,
      description: '',
      category: '',
      tags: const [],
      version: version,
      updatedAt: '2026-01-01T00:00:00Z',
    );

NovelAgentSkillModel _installed(
  String id,
  String name, {
  String? sourceName,
  String version = '1',
  AgentSkillSourceKind sourceKind = AgentSkillSourceKind.official,
}) => NovelAgentSkillModel(
  id: id,
  name: name,
  sourceKind: sourceKind,
  sourceListingPublicId: 'legacy-uuid-$id',
  sourceDisplayName: sourceName ?? name,
  sourceVersion: version,
  description: '',
  prompt: '',
);

class _Harness {
  final installed = <NovelAgentSkillModel>[];
  final catalog = <OfficialAgentSkillSummary>[];
  final handled = <String>{};
  final installs = <String>[];
  final upgrades = <String>[];
  final uninstalls = <String>[];
  final installFailures = <String>{};
  final upgradeFailures = <String>{};
  final uninstallFailures = <String>{};
  final markFailures = <String>{};
  final conflicts = <String>{};
  bool failRead = false;
  bool failCatalog = false;

  Future<OfficialSkillSyncResult> run() => OfficialSkillSyncOrchestrator().run(
    loadInstalledSkills: () async => installed,
    loadOfficialCatalog: () async {
      if (failCatalog) {
        throw StateError('catalog unavailable');
      }
      return catalog;
    },
    loadHandledNames: () async {
      if (failRead) {
        throw StateError('read failed');
      }
      return handled;
    },
    markHandled: (name) async {
      if (markFailures.contains(name)) {
        throw StateError('mark failed');
      }
      handled.add(name);
    },
    loadOfficialSkill: (id) async => OfficialAgentSkill(
      listingId: id,
      name: id,
      description: '',
      category: '',
      tags: const [],
      version: 1,
      updatedAt: '2026-01-01T00:00:00Z',
      whenToUse: '',
      prompt: '',
      sortOrder: 0,
    ),
    installOfficialSkill: (source) async {
      if (installFailures.contains(source.name)) {
        throw StateError('install failed');
      }
      if (conflicts.contains(source.name)) {
        return false;
      }
      installs.add(source.name);
      return true;
    },
    uninstallOfficialSkill: (id) async {
      if (uninstallFailures.contains(id)) {
        throw StateError('uninstall failed');
      }
      uninstalls.add(id);
      installed.removeWhere((skill) => skill.id == id);
    },
    upgradeOfficialSkill: (id) async {
      if (upgradeFailures.contains(id)) {
        throw StateError('upgrade failed');
      }
      upgrades.add(id);
    },
  );
}
