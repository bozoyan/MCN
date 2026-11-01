// 职责: 验证全局子专家仅经由 read 发起保存时仍会持久化并更新列表状态，以及更新后内存态提示词解析与 build() 同源。
// 关联文件:
//   lib/shared/providers/subagent_providers.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/database/app_database.dart
//   lib/shared/services/ai/prompt_template.dart
//   lib/shared/services/ai/prompts/prompt_fragments.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/subagent.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/subagent_providers.dart';
import 'package:reveric/shared/services/ai/prompt_template.dart';

/// 以预设列表作为初始 state，聚焦真实 create/update 的 DB 写入与内存态更新。
class _PresetGlobalSubAgents extends GlobalSubAgents {
  static late List<SubAgent> initial;

  @override
  Future<List<SubAgent>> build() async => initial;
}

String _builtinWriterPrompt() =>
    PromptTemplateService.instance.rawAsset('assets/prompts/agent/writer');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(PromptTemplateService.loadAll);

  group('GlobalSubAgents', () {
    late AppDatabase database;
    late ProviderContainer container;

    setUp(() {
      database = AppDatabase.forTest(NativeDatabase.memory());
      _PresetGlobalSubAgents.initial = const [];
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          globalSubAgentsProvider.overrideWith(_PresetGlobalSubAgents.new),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    test('createSubAgent completes when invoked only through read', () async {
      final created = await container
          .read(globalSubAgentsProvider.notifier)
          .createSubAgent(
            const SubAgentDraft(
              slug: 'read_only_save',
              name: 'Read-only save',
              description: 'Created without a provider listener.',
              prompt: 'Persist this expert.',
              scope: SubAgentScope.global,
              useCustomPrompt: true,
            ),
          );

      final row = await database.globalAgentDao.getBySlug(created.slug);
      expect(row?.id, created.id);
      expect(
        container.read(globalSubAgentsProvider).asData?.value,
        contains(predicate<SubAgent>((agent) => agent.id == created.id)),
      );
    });

    // 回归：内置 SubAgent 用默认提示词（useCustomPrompt=false，DB prompt=''）
    // 时，主编辑面板保存（只改 model/enabled 等非提示词字段）后，内存态必须
    // 重新解析出内置默认提示词，否则 SpawnAgent 会以空身份提示词运行。
    test(
      'updateSubAgent re-resolves builtin default prompt in memory',
      () async {
        final writerPrompt = _builtinWriterPrompt();
        expect(writerPrompt, isNotEmpty, reason: 'writer 内置提示词应可渲染');
        final writer = SubAgent(
          id: 'builtin-writer',
          slug: 'writer',
          name: '写手',
          description: '写作',
          // 与 build() 经 _mapSubAgent 解析后的读出态一致：已回填内置默认提示词。
          prompt: writerPrompt,
          mode: SubAgentMode.chat.value,
          scope: SubAgentScope.global,
          sortOrder: 0,
          useCustomPrompt: false,
        );
        _PresetGlobalSubAgents.initial = [writer];

        final agents = await container.read(globalSubAgentsProvider.future);
        final seeded = agents.firstWhere((a) => a.slug == 'writer');
        expect(seeded.useCustomPrompt, isFalse);
        expect(seeded.prompt, writerPrompt);

        // 模拟主编辑面板保存：useCustomPrompt=false，prompt=''（DB 存空），
        // 仅改 enabled。updateSubAgent 收到的 updated.prompt 为空。
        await container
            .read(globalSubAgentsProvider.notifier)
            .updateSubAgent(
              seeded.copyWith(prompt: '', enabled: !seeded.enabled),
            );

        // DB 里存的是空 prompt（默认提示词不落库）。
        final row = await database.globalAgentDao.getBySlug('writer');
        expect(row?.prompt, '');

        // 内存态必须回填内置默认提示词，与 build() 读出态一致；否则 SpawnAgent
        // 会拿到空身份提示词。
        final memory = container
            .read(globalSubAgentsProvider)
            .asData
            ?.value
            .firstWhere((a) => a.slug == 'writer');
        expect(memory, isNotNull);
        expect(memory!.prompt, writerPrompt);
        expect(memory.prompt, contains('{{#screenplay_workspace}}'));
        expect(memory.prompt, contains('{{^screenplay_workspace}}'));
        expect(memory.prompt, contains('{{fragment_prose_quality_baseline}}'));
        // 副作用字段仍按入参落盘。
        expect(memory.enabled, !seeded.enabled);
      },
    );
  });
}
