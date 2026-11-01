// 职责: 管理子智能体配置，并保留默认提示词模板供调用时按作品上下文渲染
// 关联文件:
//   lib/shared/models/subagent.dart
//   lib/shared/database/app_database.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/services/initialization/agent_seeds.dart
//   lib/shared/services/ai/prompt_template.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/ai/builtin_agent_tools.dart';
import '../database/app_database.dart';
import '../models/agent_profile.dart';
import '../logger/app_logger.dart';
import '../models/subagent.dart';
import '../services/ai/prompt_template.dart';
import '../utils/random_id.dart';
import 'novel_providers.dart';

part 'subagent_providers.g.dart';

final _log = AppLogger.forModule('SubAgent');

const internalChatSubAgentSlugs = {builtinAgentSlugChronicler};

bool isInternalChatSubAgent(SubAgent agent) {
  return agent.mode == SubAgentMode.chat.value &&
      internalChatSubAgentSlugs.contains(agent.slug);
}

bool isUserVisibleSubAgent(SubAgent agent) {
  return !isInternalChatSubAgent(agent);
}

const _agentAvatarBySlug = {
  'planner': '🧠',
  'writer': '✍️',
  'artist': '🎨',
  'review': '🔍',
  'style_polish': '✨',
  'plot_architect': '🏗️',
  'character_analyst': '🎭',
  'world_builder': '🌍',
  'pacing_expert': '⏱️',
  'conflict_designer': '⚔️',
  'theme_guardian': '🔮',
  'explorer': '🔭',
};

const _agentFallbackAvatars = [
  '🤖',
  '👾',
  '🎯',
  '🎲',
  '🦊',
  '🐺',
  '🦅',
  '🐉',
  '🦋',
  '🦄',
  '🐱',
  '🐰',
  '👑',
  '🎩',
  '🧙',
  '🪄',
  '⚡',
  '🔥',
  '💡',
  '🔮',
];

String _resolveAvatar(String slug) {
  final bySlug = _agentAvatarBySlug[slug];
  if (bySlug != null) return bySlug;
  final hash = slug.hashCode;
  return _agentFallbackAvatars[hash.abs() % _agentFallbackAvatars.length];
}

String _resolveBuiltinSubAgentPrompt(String slug) {
  if (!builtinSubAgentSlugs.contains(slug)) return '';
  try {
    if (PromptTemplateService.isInitialized) {
      // 保留条件与变量，等调用入口取得当前作品上下文后再渲染。
      return PromptTemplateService.instance.rawAsset(
        'assets/prompts/agent/$slug',
      );
    }
  } catch (_) {}
  return '';
}

SubAgent _mapSubAgent(GlobalAgent agent) {
  final scope = agent.scope == agentScopeGlobal
      ? SubAgentScope.global
      : SubAgentScope.novel;
  return SubAgent(
    id: agent.id,
    slug: agent.slug,
    name: agent.name,
    description: agent.description,
    prompt: !agent.useCustomPrompt && builtinSubAgentSlugs.contains(agent.slug)
        ? _resolveBuiltinSubAgentPrompt(agent.slug)
        : agent.prompt,
    mode: agent.mode,
    avatarEmoji: _resolveAvatar(agent.slug),
    avatarPath: agent.avatarPath,
    scope: scope,
    sortOrder: agent.sortOrder,
    enabled: agent.enabled,
    useCustomPrompt: agent.useCustomPrompt,
    novelId: agent.novelId.isEmpty ? null : agent.novelId,
    providerId: agent.providerId,
    model: agent.model,
    reasoningEffort: agent.reasoningEffort,
    createdAt: agent.createdAt,
    updatedAt: agent.updatedAt,
  );
}

/// 对已保存的 [SubAgent] 应用与 [_mapSubAgent] 一致的提示词解析：内置
/// SubAgent 在 `useCustomPrompt=false` 时 DB 里 `prompt` 为空，需回填内置
/// 默认提示词，否则内存态会比 `build()` 读出态少掉身份提示词。
SubAgent _withResolvedPrompt(SubAgent agent) {
  if (!agent.useCustomPrompt && builtinSubAgentSlugs.contains(agent.slug)) {
    return agent.copyWith(prompt: _resolveBuiltinSubAgentPrompt(agent.slug));
  }
  return agent;
}

bool _slugExists(Iterable<SubAgent> items, String slug, String currentId) {
  return items.any((item) => item.slug == slug && item.id != currentId);
}

@Riverpod(keepAlive: true)
class GlobalSubAgents extends _$GlobalSubAgents {
  @override
  Future<List<SubAgent>> build() async {
    final db = ref.watch(appDatabaseProvider);
    final agents = await db.globalAgentDao.getByScope(agentScopeGlobal);
    // Home 的 SubAgent 导航读这里。Council 角色也是 subagent（mode=council），
    // 需要随普通 subagent 一起展示，供用户查看/编辑 council subagent 提示词。
    final subagents = agents
        .where((agent) => agent.category == 'subagent')
        .map(_mapSubAgent)
        .toList();
    return subagents;
  }

  Future<SubAgent> createSubAgent(SubAgentDraft draft) async {
    final currentAgents = state.value ?? await future;
    if (_slugExists(currentAgents, draft.slug, '')) {
      throw SubAgentNameConflictException(draft.slug);
    }
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now();
    final agent = SubAgent(
      id: buildRandomId('subagent'),
      slug: draft.slug,
      name: draft.name,
      description: draft.description,
      prompt: draft.prompt,
      mode: draft.mode,
      scope: SubAgentScope.global,
      sortOrder: currentAgents.length,
      enabled: draft.enabled,
      useCustomPrompt: draft.useCustomPrompt,
      providerId: draft.providerId,
      model: draft.model,
      reasoningEffort: draft.reasoningEffort,
      avatarPath: draft.avatarPath,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await db.globalAgentDao.upsert(
        GlobalAgent(
          scope: agentScopeGlobal,
          id: agent.id,
          slug: agent.slug,
          name: agent.name,
          description: agent.description,
          prompt: agent.prompt,
          mode: agent.mode,
          category: 'subagent',
          enabled: agent.enabled,
          useCustomPrompt: agent.useCustomPrompt,
          sortOrder: agent.sortOrder,
          novelId: '',
          allowedToolNames: const [],
          ignoredSkillNames: const <String>[],
          providerId: agent.providerId,
          model: agent.model,
          reasoningEffort: agent.reasoningEffort,
          avatarPath: agent.avatarPath,
          createdAt: agent.createdAt!,
          updatedAt: agent.updatedAt!,
          deletedAt: notDeletedSentinel,
        ),
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB][agents][INSERT] failed id=${agent.id}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    if (ref.mounted) {
      state = AsyncData([...currentAgents, _withResolvedPrompt(agent)]);
    }
    return agent;
  }

  Future<void> updateSubAgent(SubAgent agent) async {
    final currentAgents = state.value ?? await future;
    if (_slugExists(currentAgents, agent.slug, agent.id)) {
      throw SubAgentNameConflictException(agent.slug);
    }
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now();
    final updated = agent.copyWith(updatedAt: now);
    try {
      await db.globalAgentDao.upsert(
        GlobalAgent(
          scope: agentScopeGlobal,
          id: agent.id,
          slug: agent.slug,
          name: agent.name,
          description: agent.description,
          prompt: agent.prompt,
          mode: agent.mode,
          category: 'subagent',
          enabled: agent.enabled,
          useCustomPrompt: agent.useCustomPrompt,
          sortOrder: agent.sortOrder,
          novelId: '',
          allowedToolNames: const [],
          ignoredSkillNames: const <String>[],
          providerId: agent.providerId,
          model: agent.model,
          reasoningEffort: agent.reasoningEffort,
          avatarPath: agent.avatarPath,
          createdAt: updated.createdAt ?? now,
          updatedAt: now,
          deletedAt: notDeletedSentinel,
        ),
      );
    } catch (error, stackTrace) {
      _log.error(
        '[DB][agents][UPDATE] failed id=${agent.id}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    if (ref.mounted) {
      state = AsyncData([
        for (final item in currentAgents)
          if (item.id == updated.id) _withResolvedPrompt(updated) else item,
      ]);
    }
  }

  Future<void> deleteSubAgent(String id) async {
    final currentAgents = state.value ?? await future;
    final db = ref.read(appDatabaseProvider);
    try {
      await db.globalAgentDao.softDelete(id);
    } catch (error, stackTrace) {
      _log.error(
        '[DB][agents][SOFT_DELETE] failed id=$id',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    if (ref.mounted) {
      state = AsyncData([
        for (final item in currentAgents)
          if (item.id != id) item,
      ]);
    }
  }

  Future<void> reorderSubAgents(List<String> ids) async {
    final currentAgents = state.value ?? await future;
    final db = ref.read(appDatabaseProvider);
    try {
      await db.globalAgentDao.reorder(ids);
    } catch (error, stackTrace) {
      _log.error(
        '[DB][agents][REORDER] failed count=${ids.length}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    if (ref.mounted) {
      final agentsById = {for (final agent in currentAgents) agent.id: agent};
      state = AsyncData([
        for (final id in ids)
          if (agentsById[id] != null)
            agentsById[id]!.copyWith(sortOrder: ids.indexOf(id)),
      ]);
    }
  }
}

@riverpod
Stream<List<SubAgent>> globalSubAgentsStream(Ref ref) async* {
  final db = AppDatabase();
  yield* db.globalAgentDao
      .watchByScope(agentScopeGlobal)
      .map(
        (agents) => agents
            .where((agent) => agent.category == 'subagent')
            .map(_mapSubAgent)
            .toList(),
      );
}

@riverpod
class NovelSubAgents extends _$NovelSubAgents {
  @override
  Future<List<SubAgent>> build(String novelId) async {
    final db = AppDatabase();
    final agents = await db.globalAgentDao.getByScope(
      agentScopeNovel,
      novelId: novelId,
    );
    final subagents = agents
        .where((agent) => agent.category == 'subagent')
        .map(_mapSubAgent)
        .toList();
    return subagents;
  }

  Future<SubAgent> createSubAgent(SubAgentDraft draft) async {
    final currentAgents = state.value ?? const <SubAgent>[];
    if (_slugExists(currentAgents, draft.slug, '')) {
      throw SubAgentNameConflictException(draft.slug);
    }
    final db = AppDatabase();
    final now = DateTime.now();
    final agent = SubAgent(
      id: buildRandomId('subagent'),
      slug: draft.slug,
      name: draft.name,
      description: draft.description,
      prompt: draft.prompt,
      mode: draft.mode,
      scope: SubAgentScope.novel,
      sortOrder: currentAgents.length,
      enabled: draft.enabled,
      useCustomPrompt: draft.useCustomPrompt,
      novelId: draft.novelId,
      providerId: draft.providerId,
      model: draft.model,
      reasoningEffort: draft.reasoningEffort,
      avatarPath: draft.avatarPath,
      createdAt: now,
      updatedAt: now,
    );
    await db.globalAgentDao.upsert(
      GlobalAgent(
        scope: agentScopeNovel,
        novelId: agent.novelId ?? '',
        allowedToolNames: const [],
        id: agent.id,
        slug: agent.slug,
        name: agent.name,
        description: agent.description,
        prompt: agent.prompt,
        mode: agent.mode,
        category: 'subagent',
        enabled: agent.enabled,
        useCustomPrompt: agent.useCustomPrompt,
        sortOrder: agent.sortOrder,
        ignoredSkillNames: const <String>[],
        providerId: agent.providerId,
        model: agent.model,
        reasoningEffort: agent.reasoningEffort,
        avatarPath: agent.avatarPath,
        createdAt: agent.createdAt!,
        updatedAt: agent.updatedAt!,
        deletedAt: notDeletedSentinel,
      ),
    );
    ref.invalidateSelf();
    return agent;
  }

  Future<void> updateSubAgent(SubAgent agent) async {
    final currentAgents = state.value ?? const <SubAgent>[];
    if (_slugExists(currentAgents, agent.slug, agent.id)) {
      throw SubAgentNameConflictException(agent.slug);
    }
    final db = AppDatabase();
    final now = DateTime.now();
    await db.globalAgentDao.upsert(
      GlobalAgent(
        scope: agentScopeNovel,
        novelId: agent.novelId ?? '',
        allowedToolNames: const [],
        id: agent.id,
        slug: agent.slug,
        name: agent.name,
        description: agent.description,
        prompt: agent.prompt,
        mode: agent.mode,
        category: 'subagent',
        enabled: agent.enabled,
        useCustomPrompt: agent.useCustomPrompt,
        sortOrder: agent.sortOrder,
        ignoredSkillNames: const <String>[],
        providerId: agent.providerId,
        model: agent.model,
        reasoningEffort: agent.reasoningEffort,
        avatarPath: agent.avatarPath,
        createdAt: agent.createdAt ?? now,
        updatedAt: now,
        deletedAt: notDeletedSentinel,
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> deleteSubAgent(String id) async {
    final db = AppDatabase();
    try {
      await db.globalAgentDao.softDelete(id);
    } catch (error, stackTrace) {
      _log.error(
        '[DB][agents][SOFT_DELETE] failed id=$id',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    if (ref.mounted) {
      ref.invalidateSelf();
    }
  }

  Future<void> reorderSubAgents(List<String> ids) async {
    final db = AppDatabase();
    await db.globalAgentDao.reorder(ids);
    ref.invalidateSelf();
  }
}

@riverpod
Stream<List<SubAgent>> novelSubAgentsStream(Ref ref, String novelId) {
  final db = AppDatabase();
  return db.globalAgentDao
      .watchByScope(agentScopeNovel, novelId: novelId)
      .map(
        (agents) => agents
            .where((agent) => agent.category == 'subagent')
            .map(_mapSubAgent)
            .toList(),
      );
}

@riverpod
List<SubAgent> mergedSubAgents(Ref ref) {
  // 子 Agent 的可用列表来自全局配置。
  final globalAgents =
      ref.watch(globalSubAgentsProvider).value ?? const <SubAgent>[];
  final merged = [...globalAgents]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return merged;
}
