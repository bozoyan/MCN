// 职责: 定义固定中文的内置 Primary Agent 种子数据
// 关联文件:
//   lib/shared/services/initialization/agent_seeds.dart
//   lib/shared/services/ai/builtin_agent_tools.dart

import '../../models/agent_profile.dart';

class PrimaryAgentSeed {
  const PrimaryAgentSeed({
    required this.slug,
    required this.name,
    required this.description,
    required this.prompt,
    this.mode = 'chat',
  });

  final String slug;
  final String name;
  final String description;
  final String prompt;
  final String mode;
}

List<PrimaryAgentSeed> defaultPrimaryAgentSeeds() {
  return [
    PrimaryAgentSeed(
      slug: builtinAgentSlugMonologueNarrator,
      name: '独白叙述者',
      description: '角色内心独白叙述',
      prompt: '',
      mode: 'monologue',
    ),
    PrimaryAgentSeed(
      slug: builtinAgentSlugRoleplayMaster,
      name: '角色扮演大师',
      description: '角色扮演与对话互动',
      prompt: '',
      mode: 'roleplay',
    ),
    PrimaryAgentSeed(
      slug: builtinAgentSlugTheaterActor,
      name: '小剧场演员',
      description: '多角色场景表演',
      prompt: '',
      mode: 'theater',
    ),
  ];
}
