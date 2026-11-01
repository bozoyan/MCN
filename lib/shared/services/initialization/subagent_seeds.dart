// 职责: 内置 SubAgent 种子数据
// 关联文件:
//   lib/shared/services/initialization/agent_seeds.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent.json
//   assets/translations/zh-CN/agent.json

class SubAgentSeed {
  const SubAgentSeed({
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

List<SubAgentSeed> defaultGlobalSubAgentSeeds() {
  return [
    SubAgentSeed(
      slug: 'chronicler',
      name: '编年史者',
      description: '小说章节与剧本场次的事实提取、连续性核验和故事状态维护。',
      prompt: '',
    ),
    SubAgentSeed(
      slug: 'writer',
      name: '正文写手',
      description: '按任务要求完成正文创作与写入，交付实际结果和未解决问题。',
      prompt: '',
    ),
    SubAgentSeed(
      slug: 'review',
      name: '内容核验',
      description: '核验情节逻辑、角色一致性、世界观规则及用户自定义规则的符合度。适合在内容完成后进行全面核验。',
      prompt: '',
    ),
    SubAgentSeed(
      slug: 'style_polish',
      name: '文风润色',
      description: '提升文笔流畅度、节奏和画面感，不改变剧情事实。适合内容无误但需要润色的场景。',
      prompt: '',
    ),
    SubAgentSeed(
      slug: 'plot_architect',
      name: '剧情架构师',
      description: '分析剧情结构、伏笔布局和高潮设计。当需要规划或评估故事架构时可委派。',
      prompt: '',
      mode: 'council',
    ),
    SubAgentSeed(
      slug: 'character_analyst',
      name: '角色分析师',
      description: '分析角色动机、成长弧线和人际关系。当需要深入检查角色一致性时使用。',
      prompt: '',
      mode: 'council',
    ),
    SubAgentSeed(
      slug: 'world_builder',
      name: '世界观构建师',
      description: '维护世界观一致性，补充设定细节。当需要检查设定连贯性或扩写世界观时使用。',
      prompt: '',
      mode: 'council',
    ),
    SubAgentSeed(
      slug: 'pacing_expert',
      name: '叙事节奏师',
      description: '评估叙事节奏和紧张感平衡。当需要分析章节节奏或场景流转时使用。',
      prompt: '',
      mode: 'council',
    ),
    SubAgentSeed(
      slug: 'conflict_designer',
      name: '冲突设计师',
      description: '设计冲突与对抗以增强故事张力。当需要构建或评估戏剧张力时使用。',
      prompt: '',
      mode: 'council',
    ),
    SubAgentSeed(
      slug: 'theme_guardian',
      name: '主题守护者',
      description: '确保故事主题贯穿始终。当需要检查各章节和角色弧线的主题一致性时使用。',
      prompt: '',
      mode: 'council',
    ),
    SubAgentSeed(
      slug: 'explorer',
      name: '资料收集',
      description: '搜索互联网、读取网页、浏览内部资料，收集用户所需的信息和素材。适合需要查找参考资料、背景知识或写作素材的场景。',
      prompt: '',
    ),
  ];
}
