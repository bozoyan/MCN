// 职责: AI 快捷方式模型 — 定义全局快捷方式、适用位置与内置默认。
// 关联文件:
//   lib/shared/providers/ai_shortcut_action_providers.dart
//   lib/shared/database/daos/ai_shortcut_action_dao.dart
//   lib/shared/database/app_database.dart

enum AiShortcutActionLocation {
  novel_description,
  chapter,
  outline,
  outline_beat,
  character,
  worldbuilding,
  material,
  skill_entry,
  item,
  faction,
  creature,
  foreshadowing;

  String get dbValue => name;

  static AiShortcutActionLocation? maybeFromDbValue(String value) {
    for (final location in values) {
      if (location.dbValue == value) {
        return location;
      }
    }
    return null;
  }
}

class AiShortcutActionDefinition {
  const AiShortcutActionDefinition({
    required this.id,
    required this.name,
    required this.prompt,
    required this.locations,
    this.builtinId,
    this.enabled = true,
    this.autoSend = false,
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? builtinId;
  final String name;
  final String prompt;
  final List<AiShortcutActionLocation> locations;
  final bool enabled;
  final bool autoSend;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isBuiltin => builtinId != null && builtinId!.isNotEmpty;

  AiShortcutActionDefinition copyWith({
    String? id,
    String? builtinId,
    bool clearBuiltinId = false,
    String? name,
    String? prompt,
    List<AiShortcutActionLocation>? locations,
    bool? enabled,
    bool? autoSend,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AiShortcutActionDefinition(
      id: id ?? this.id,
      builtinId: clearBuiltinId ? null : (builtinId ?? this.builtinId),
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      locations: locations ?? this.locations,
      enabled: enabled ?? this.enabled,
      autoSend: autoSend ?? this.autoSend,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class AiShortcutActionDraft {
  const AiShortcutActionDraft({
    required this.name,
    required this.prompt,
    required this.locations,
    this.enabled = true,
    this.autoSend = false,
  });

  final String name;
  final String prompt;
  final List<AiShortcutActionLocation> locations;
  final bool enabled;
  final bool autoSend;
}

class BuiltinAiShortcutAction {
  const BuiltinAiShortcutAction({
    required this.id,
    required this.name,
    required this.prompt,
    required this.locations,
    this.autoSend = false,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String prompt;
  final List<AiShortcutActionLocation> locations;
  final bool autoSend;
  final bool enabled;

  AiShortcutActionDefinition toDefinition({required int sortOrder}) {
    return AiShortcutActionDefinition(
      id: 'builtin_$id',
      builtinId: id,
      name: name,
      prompt: prompt,
      locations: locations,
      enabled: enabled,
      autoSend: autoSend,
      sortOrder: sortOrder,
    );
  }
}

const builtinAiShortcutActions = <BuiltinAiShortcutAction>[
  BuiltinAiShortcutAction(
    id: 'outline_beat_generate_chapter_outlines',
    name: '生成章纲',
    prompt: '请根据当前选中的节拍和所属大纲，生成这个节拍覆盖的所有章节大纲。',
    locations: [AiShortcutActionLocation.outline_beat],
  ),
  BuiltinAiShortcutAction(
    id: 'chapter_generate_draft',
    name: '生成正文',
    prompt: '请根据当前章节的大纲、上下文和小说设定，生成这一章的正文草稿。',
    locations: [AiShortcutActionLocation.chapter],
  ),
  BuiltinAiShortcutAction(
    id: 'chapter_polish',
    name: '润色本章',
    prompt: '请润色当前章节，保持原有剧情与作者声音，优化节奏、表达和细节。',
    locations: [AiShortcutActionLocation.chapter],
  ),
  BuiltinAiShortcutAction(
    id: 'chapter_summarize',
    name: '总结本章',
    prompt: '请总结当前章节的关键剧情、人物变化、伏笔和后续需要注意的连续性问题。',
    locations: [AiShortcutActionLocation.chapter],
  ),
  BuiltinAiShortcutAction(
    id: 'character_generate_arc',
    name: '生成角色弧光',
    prompt: '请根据当前角色资料，设计或完善这个角色的成长弧光、关键选择和剧情作用。',
    locations: [AiShortcutActionLocation.character],
  ),
  BuiltinAiShortcutAction(
    id: 'setting_expand',
    name: '扩写设定',
    prompt: '请根据当前引用的设定条目扩写内容，补充可用于写作的细节、限制、冲突和剧情用途。',
    locations: [
      AiShortcutActionLocation.worldbuilding,
      AiShortcutActionLocation.material,
      AiShortcutActionLocation.skill_entry,
      AiShortcutActionLocation.item,
      AiShortcutActionLocation.faction,
      AiShortcutActionLocation.creature,
    ],
  ),
  BuiltinAiShortcutAction(
    id: 'foreshadowing_payoff_plan',
    name: '设计兑现方案',
    prompt: '请根据当前伏笔，设计多个兑现方案，并说明每个方案的情绪效果、风险和适用章节。',
    locations: [AiShortcutActionLocation.foreshadowing],
  ),
  BuiltinAiShortcutAction(
    id: 'novel_generate_book_plan',
    name: '生成全书创作规划',
    prompt: '请根据当前小说简介，生成全书创作规划，包括核心卖点、结构、主要冲突、人物线和写作推进建议。',
    locations: [AiShortcutActionLocation.novel_description],
  ),
];
