// 职责: 提供作品标签、技能分类和技能标签的本地候选常量。
// 关联文件:
//   lib/shared/providers/dictionary_providers.dart
//   lib/shared/models/novel_categories.dart
//   lib/desktop/features/agent_skills/setup_panel.dart

/// 作品标签候选。
const List<String> kFallbackNovelTags = <String>[
  '热血',
  '爽文',
  '群像',
  '单女主',
  '多女主',
  '无女主',
  '慢热',
  '快节奏',
  '脑洞',
  '治愈',
];

/// 技能分类候选。
const List<String> kFallbackSkillCategories = <String>[
  '扩写',
  '润色',
  '校对',
  '设定考据',
  '结构',
  '对白',
  '节奏',
  '文风',
];

/// 技能标签候选。
const List<String> kFallbackSkillTags = <String>[
  '通用',
  '长篇',
  '短篇',
  '对话',
  '描写',
  '叙事',
  '言情',
  '悬疑',
  '效率',
  '入门',
];
