import 'package:easy_localization/easy_localization.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/app_database.dart';
import '../services/ai/builtin_agent_tools.dart';
import '../localization/locale_keys.dart';
import '../models/agent_profile.dart';
import '../services/ai/prompt_template.dart';

part 'agent_profile_providers.g.dart';

const _agentAvatarBySlug = {
  'planner': '🧠',
  'writer': '✍️',
  'artist': '🎨',
  'chronicler': '📜',
  'monologue_narrator': '💭',
  'roleplay_master': '🎭',
  'theater_actor': '🎪',
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

String _resolveDescription(String slug) {
  return switch (slug) {
    builtinAgentSlugPlanner => tr(LocaleKeys.agentDescPlanner),
    builtinAgentSlugWriter => tr(LocaleKeys.agentDescWriter),
    builtinAgentSlugArtist => tr(LocaleKeys.agentDescArtist),
    builtinAgentSlugChronicler => tr(LocaleKeys.agentDescChronicler),
    builtinAgentSlugMonologueNarrator => tr(
      LocaleKeys.agentDescMonologueNarrator,
    ),
    builtinAgentSlugRoleplayMaster => tr(LocaleKeys.agentDescRoleplayMaster),
    builtinAgentSlugTheaterActor => tr(LocaleKeys.agentDescTheaterActor),
    _ => '',
  };
}

AgentProfileRole _roleFromSlug(String slug) => switch (slug) {
  builtinAgentSlugPlanner => AgentProfileRole.planner,
  builtinAgentSlugWriter => AgentProfileRole.writer,
  builtinAgentSlugArtist => AgentProfileRole.artist,
  _ => AgentProfileRole.custom,
};

String _resolveBuiltinPrimaryPrompt(String slug) {
  if (!builtinPrimaryAgentSlugs.contains(slug)) return '';
  try {
    if (PromptTemplateService.isInitialized) {
      return PromptTemplateService.instance.rawAsset(
        'assets/prompts/agent/$slug',
      );
    }
  } catch (_) {}
  return '';
}

AgentProfile _mapAgent(GlobalAgent agent) {
  final scope = agent.scope == agentScopeGlobal
      ? AgentProfileScope.global
      : AgentProfileScope.novel;
  final resolvedDesc = _resolveDescription(agent.slug);
  return AgentProfile(
    id: agent.id,
    slug: agent.slug,
    name: agent.name,
    description: resolvedDesc.isNotEmpty ? resolvedDesc : agent.description,
    systemPrompt: agent.useCustomPrompt
        ? agent.prompt
        : _resolveBuiltinPrimaryPrompt(agent.slug),
    mode: agent.mode,
    avatarEmoji: _resolveAvatar(agent.slug),
    avatarPath: agent.avatarPath,
    role: _roleFromSlug(agent.slug),
    scope: scope,
    sortOrder: agent.sortOrder,
    enabled: agent.enabled,
    useCustomPrompt: agent.useCustomPrompt,
    novelId: agent.novelId.isEmpty ? null : agent.novelId,
    providerId: agent.providerId,
    model: agent.model,
    createdAt: agent.createdAt,
    updatedAt: agent.updatedAt,
  );
}

// Agent Profile 暂时只承载 primary agent，也就是 Home 导航里展示的“提示词”。
// Council 参与者仍归属 SubAgent（category=subagent, mode=council），不要混到这里。
List<AgentProfile> _onlyPrimary(Iterable<AgentProfile> agents) => agents
    .where(
      (agent) =>
          agent.role != AgentProfileRole.custom ||
          builtinPrimaryAgentSlugs.contains(agent.slug),
    )
    .toList();

@riverpod
class GlobalAgentProfiles extends _$GlobalAgentProfiles {
  @override
  Future<List<AgentProfile>> build() async {
    final db = AppDatabase();
    final agents = await db.globalAgentDao.getByScope(agentScopeGlobal);
    final profiles = _onlyPrimary(
      agents.where((agent) => agent.category == 'primary').map(_mapAgent),
    );
    return profiles;
  }

  Future<void> updateAgentProfile(AgentProfile profile) async {
    final db = AppDatabase();
    final now = DateTime.now();
    await db.globalAgentDao.upsert(
      GlobalAgent(
        scope: agentScopeGlobal,
        id: profile.id,
        slug: profile.slug,
        name: profile.name,
        description: profile.description,
        prompt: profile.systemPrompt,
        mode: profile.mode,
        category: 'primary',
        enabled: profile.enabled,
        useCustomPrompt: profile.useCustomPrompt,
        sortOrder: profile.sortOrder,
        novelId: '',
        allowedToolNames: const [],
        ignoredSkillNames: profile.ignoredSkillNames,
        providerId: profile.providerId,
        model: profile.model,
        avatarPath: profile.avatarPath,
        createdAt: profile.createdAt ?? now,
        updatedAt: now,
        deletedAt: notDeletedSentinel,
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> deleteAgentProfile(String slug) async {
    final current = state.value ?? const <AgentProfile>[];
    AgentProfile? match;
    for (final item in current) {
      if (item.slug == slug) {
        match = item;
        break;
      }
    }
    if (match == null) return;
    final db = AppDatabase();
    await db.globalAgentDao.hardDelete(match.id);
    ref.invalidateSelf();
  }
}

@riverpod
Stream<List<AgentProfile>> globalAgentProfilesStream(Ref ref) async* {
  final db = AppDatabase();
  yield* db.globalAgentDao
      .watchByScope(agentScopeGlobal)
      .map(
        (agents) => _onlyPrimary(
          agents.where((agent) => agent.category == 'primary').map(_mapAgent),
        ),
      );
}

@riverpod
class NovelAgentProfiles extends _$NovelAgentProfiles {
  @override
  Future<List<AgentProfile>> build(String novelId) async {
    final db = AppDatabase();
    final agents = await db.globalAgentDao.getByScope(
      agentScopeNovel,
      novelId: novelId,
    );
    final profiles = _onlyPrimary(
      agents.where((agent) => agent.category == 'primary').map(_mapAgent),
    );
    return profiles;
  }

  Future<void> updateAgentProfile(AgentProfile profile) async {
    final db = AppDatabase();
    final current = state.value ?? const <AgentProfile>[];
    final existingBySlug = {for (final item in current) item.slug: item};
    final existing = existingBySlug[profile.slug];
    final now = DateTime.now();
    await db.globalAgentDao.upsert(
      GlobalAgent(
        scope: agentScopeNovel,
        id: existing?.id ?? profile.id,
        slug: profile.slug,
        name: profile.name,
        description: profile.description,
        prompt: profile.systemPrompt,
        mode: profile.mode,
        category: 'primary',
        enabled: profile.enabled,
        useCustomPrompt: profile.useCustomPrompt,
        sortOrder: existing?.sortOrder ?? profile.sortOrder,
        novelId: profile.novelId ?? '',
        allowedToolNames: const [],
        ignoredSkillNames: profile.ignoredSkillNames,
        providerId: profile.providerId,
        model: profile.model,
        createdAt: existing?.createdAt ?? profile.createdAt ?? now,
        updatedAt: now,
        deletedAt: notDeletedSentinel,
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> deleteAgentProfile(String slug) async {
    final current = state.value ?? const <AgentProfile>[];
    AgentProfile? match;
    for (final item in current) {
      if (item.slug == slug) {
        match = item;
        break;
      }
    }
    if (match == null) return;
    final db = AppDatabase();
    await db.globalAgentDao.hardDelete(match.id);
    ref.invalidateSelf();
  }
}

@riverpod
Stream<List<AgentProfile>> novelAgentProfilesStream(Ref ref, String novelId) {
  final db = AppDatabase();
  return db.globalAgentDao
      .watchByScope(agentScopeNovel, novelId: novelId)
      .map(
        (agents) => _onlyPrimary(
          agents.where((agent) => agent.category == 'primary').map(_mapAgent),
        ),
      );
}

@riverpod
List<AgentProfile> mergedAgentProfiles(Ref ref, {String? novelId}) {
  final globalProfiles =
      ref.watch(globalAgentProfilesProvider).value ?? const <AgentProfile>[];
  final novelProfiles = novelId == null
      ? const <AgentProfile>[]
      : ref.watch(novelAgentProfilesProvider(novelId)).value ??
            const <AgentProfile>[];

  final novelBySlug = {
    for (final profile in novelProfiles) profile.slug: profile,
  };
  final merged = <AgentProfile>[
    ...novelProfiles,
    for (final profile in globalProfiles)
      if (!novelBySlug.containsKey(profile.slug)) profile,
  ];
  merged.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return merged;
}

@riverpod
AgentProfile? agentProfileBySlug(
  Ref ref, {
  required String slug,
  String? novelId,
}) {
  final profiles = ref.watch(mergedAgentProfilesProvider(novelId: novelId));
  for (final profile in profiles) {
    if (profile.slug == slug) return profile;
  }
  return null;
}
