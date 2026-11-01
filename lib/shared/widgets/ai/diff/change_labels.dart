// 职责: 为两端最近改动与详情弹窗解析资源标题、编号和字段翻译。
// 关联文件:
//   lib/shared/widgets/ai/diff/recent_changes_log.dart
//   lib/desktop/widgets/ai/diff/pending_changes_detail_dialog.dart
//   lib/shared/widgets/ai/tools/tool_resource_resolver.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
import 'package:flutter/widgets.dart';

import '../../../database/novel_content_database.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../services/novel_content.dart';
import '../../../services/storyboard/service.dart';
import '../../../services/working_change_summary.dart';
import '../../../utils/resource_path.dart';
import '../tools/tool_resource_resolver.dart';

class ChangeResourceTitle {
  const ChangeResourceTitle(
    this.title, {
    this.ordinals = const {},
    this.labelKey,
  });

  final String title;
  final String? labelKey;
  final Map<String, int> ordinals;

  String label(BuildContext context) => [
    for (final entry in ordinals.entries)
      context.t(entry.key, namedArgs: {'number': '${entry.value}'}),
    if (labelKey != null) context.t(labelKey!),
    if (title.isNotEmpty) title,
  ].join(' · ');
}

Future<ChangeResourceTitle> resolveChangeResourceTitle(
  List<WorkingChange> changes,
  NovelContentService service,
) async {
  final change = changes.first;
  final id = change.resourceId;
  final type = change.resourceType;
  final ordinals = <String, int>{};
  String? title;
  String? labelKey;
  if (type == 'novel') {
    return const ChangeResourceTitle('');
  }
  if (id != null) {
    switch (type) {
      case 'chapters':
        final chapter = await service.getChapterById(id);
        title = chapter?.title;
        if (chapter != null && (title == null || title.trim().isEmpty)) {
          if (chapter.isExtra) {
            labelKey = LocaleKeys.workspaceExtra;
          } else if (chapter.chapterNum != null) {
            ordinals[LocaleKeys.commonChapterNumber] = chapter.chapterNum!;
          }
        }
      case 'volumes':
        final volume = await service.getChapterById(id);
        title = volume?.title;
        if (volume?.volumeNum != null) {
          ordinals[LocaleKeys.workspaceVolumeNumber] = volume!.volumeNum!;
        }
      case 'characters':
        title = (await service.getCharacterProfileById(id))?.name;
      case 'foreshadowing':
        title = (await service.getForeshadowingById(id))?.title;
      case 'outlines':
        title = (await service.outlineService.getByDocumentId(id))?.title;
      case 'lore':
      case 'worldbuilding':
      case 'materials':
        title = (await service.documentsService.getDocumentById(id))?.title;
      case 'skills':
      case 'items':
      case 'factions':
      case 'creatures':
        title = (await service.getItemById(id))?.title;
      case 'locations':
        title = (await service.locationsService.getLocationById(id))?.name;
      case 'production_clips':
        title = (await StoryboardService(service.database).getShot(id))?.title;
        labelKey = LocaleKeys.storyboardBoard;
      case 'screenplay_episodes':
        final episode = await service.database.screenplayDao.getEpisode(id);
        if (episode != null) {
          title = episode.title;
          final season = await service.database.screenplayDao.getSeason(
            episode.seasonId,
          );
          if (season != null) {
            ordinals[LocaleKeys.screenplaySeason] = season.seasonNumber;
          }
          ordinals[LocaleKeys.screenplayEpisode] = episode.episodeNumber;
        }
      case 'screenplay_scenes':
        final scene = await service.database.screenplayDao.getScene(id);
        if (scene != null) {
          final number = await service.database.screenplayDao.getSceneNumber(
            scene,
          );
          final episode = await service.database.screenplayDao.getEpisode(
            scene.episodeId,
          );
          if (episode != null) {
            final season = await service.database.screenplayDao.getSeason(
              episode.seasonId,
            );
            if (season != null) {
              ordinals[LocaleKeys.screenplaySeason] = season.seasonNumber;
            }
            ordinals[LocaleKeys.screenplayEpisode] = episode.episodeNumber;
          }
          if (number > 0) {
            ordinals[LocaleKeys.screenplayScene] = number;
          }
        }
    }
  }
  if ((title == null || title.trim().isEmpty) &&
      ordinals.isEmpty &&
      labelKey == null) {
    // 仅已知创建预览格式的首行是标题；不把任意字段正文猜作资源名。
    final created = changes
        .where((item) => item.changeType == 'create')
        .firstOrNull;
    if (created != null) {
      if (type == 'chapters') {
        title = extractCreatedChapterTitle(created.newText);
      } else if (const {
        'characters',
        'foreshadowing',
        'skills',
        'items',
        'factions',
        'creatures',
        'lore',
        'worldbuilding',
        'materials',
        'volumes',
        'outlines',
      }.contains(type)) {
        title = created.newText?.split('\n').first.trim();
      }
    }
    if (title == null || title.trim().isEmpty) {
      title = canonicalResourcePath(change.resourcePath);
    }
  }
  return ChangeResourceTitle(
    title?.trim() ?? '',
    ordinals: ordinals,
    labelKey: labelKey,
  );
}

/// 字段 → 展示标签。`summary`/`description` 等字段名在不同资源类型下语义不同
/// （角色的 description 是稳定人物描述，作品的 description 是作品简介），
/// 先按 resourceType 取专用标签，再回退到与 AI 工具卡片共用的通用映射。
String? changeFieldLabel(
  BuildContext context,
  String resourceType,
  String field,
) {
  if (resourceType == 'characters') {
    final specific = switch (field) {
      'summary' || 'biography' => LocaleKeys.workspaceCharacterSummaryLabel,
      'description' => LocaleKeys.workspaceCharacterDescriptionLabel,
      'appearance' => LocaleKeys.workspaceCharacterAppearanceLabel,
      'personality' => LocaleKeys.workspaceCharacterPersonalityLabel,
      'aliases' => LocaleKeys.workspaceCharacterAliasesLabel,
      'behavior_tags' => LocaleKeys.workspaceCharacterBehaviorTagsLabel,
      'current_state' => LocaleKeys.workspaceCharacterCurrentStateLabel,
      _ => null,
    };
    if (specific != null) {
      return context.t(specific);
    }
  }
  // 作品的 description 是作品简介，与通用「描述」语义不同，保留专用标签。
  if (resourceType == 'novel' && field == 'description') {
    return context.t(LocaleKeys.workspaceNovelDescription);
  }
  // 未知字段返回 null，副标题里省略而不是显示原始字段名。
  final label = aiToolFieldLabel(context, field);
  return label == field ? null : label;
}
