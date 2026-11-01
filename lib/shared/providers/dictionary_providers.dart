// 职责: 提供作品与技能表单共用的本地分类和标签候选。
// 关联文件:
//   lib/shared/models/novel_categories.dart
//   lib/shared/models/dictionary_fallbacks.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dictionary_fallbacks.dart';
import '../models/novel_categories.dart';

/// 作品分类候选。
final novelCategoriesProvider = FutureProvider<List<String>>(
  (ref) => novelCategorySuggestions,
);

/// 作品标签候选。
final novelTagsProvider = FutureProvider<List<String>>(
  (ref) => kFallbackNovelTags,
);

/// 技能分类候选。
final skillCategoriesProvider = FutureProvider<List<String>>(
  (ref) => kFallbackSkillCategories,
);

/// 技能标签候选。
final skillTagsProvider = FutureProvider<List<String>>(
  (ref) => kFallbackSkillTags,
);
