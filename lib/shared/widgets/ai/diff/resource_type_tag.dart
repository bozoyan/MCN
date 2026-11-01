// 职责: 把 WorkingChange.resourceType 映射成用户可读的类型小标签（章节/人物/伏笔…）
// 关联文件:
//   lib/shared/widgets/ai/diff/recent_changes_log.dart
//   lib/desktop/widgets/ai/diff/pending_changes_detail_dialog.dart
//   lib/shared/services/working_overlay.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/entity.json
//   assets/translations/zh-CN/entity.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../theme/theme.dart';

/// 资源类型 → section i18n key 映射（章节/大纲/人物/伏笔…）。
/// 未知类型返回 null，调用方据此不显示标签 —— 宁可不标，也不要标错。
String? resourceTypeLabelKey(String resourceType) {
  return switch (resourceType) {
    'chapters' => LocaleKeys.workspaceChapters,
    'volumes' => LocaleKeys.workspaceVolume,
    'outlines' => LocaleKeys.workspaceOutlines,
    'characters' => LocaleKeys.workspaceCharacters,
    'foreshadowing' => LocaleKeys.workspaceForeshadowings,
    // 'worldbuilding' 是 /lore 改名前留下的存量 working change 的 resourceType。
    'lore' || 'worldbuilding' => LocaleKeys.workspaceLore,
    'materials' => LocaleKeys.workspaceMaterials,
    'skills' => LocaleKeys.workspaceSkills,
    'items' => LocaleKeys.workspaceItems,
    'factions' => LocaleKeys.workspaceFactions,
    'creatures' => LocaleKeys.workspaceCreatures,
    'locations' => LocaleKeys.entityTypeLocation,
    'relations' => LocaleKeys.workspaceRelations,
    'screenplay_scenes' => LocaleKeys.screenplayScenes,
    'production_clips' => LocaleKeys.storyboardBoard,
    'screenplay_episodes' => LocaleKeys.screenplayEpisodes,
    'novel' => LocaleKeys.workspaceNovelDescription,
    _ => null,
  };
}

/// 资源类型小标签：中性 muted 配色，区别于彩色的改动类型标签。
class ResourceTypeTag extends StatelessWidget {
  const ResourceTypeTag({super.key, required this.labelKey});

  final String labelKey;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RevericRadius.small),
        color: colors.surfaceContainerHigh,
      ),
      child: Text(
        context.t(labelKey),
        style: typo.uiSmall.copyWith(color: colors.textSubtle, fontSize: 11),
      ),
    );
  }
}
