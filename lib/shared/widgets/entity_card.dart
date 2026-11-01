// 职责: 展示人物、地点与图鉴实体的头像、名称、类型、摘要或完整资料，供悬浮卡、底部弹层和资料弹窗共用。
// 关联文件:
//   lib/shared/utils/chapter_entity_recognition.dart
//   lib/shared/models/subject.dart
//   lib/shared/widgets/character_avatar.dart
//   lib/shared/widgets/media_asset_image.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity.json
//   assets/translations/zh-CN/entity.json
//   assets/translations/en/character.json
//   assets/translations/zh-CN/character.json
//   assets/translations/en/location.json
//   assets/translations/zh-CN/location.json
//   assets/translations/en/history.json
//   assets/translations/zh-CN/history.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';

import '../database/novel_content_database.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../models/subject.dart';
import '../theme/theme.dart';
import '../utils/chapter_entity_recognition.dart';
import 'character_avatar.dart';
import 'media_asset_image.dart';

/// 卡片外观：普通卡片、带阴影的悬浮卡、无边框（嵌在弹窗里）。
enum EntityCardSurface { card, floating, plain }

/// 实体卡片：头部是头像、名称和定位/类型。
///
/// 没有 [details] 时展示截断摘要（悬浮卡、底部弹层）；有 [details] 时完整列出各字段，
/// 外层负责滚动。[footer] 放在最下方，如照片区。
class EntityCard extends StatelessWidget {
  const EntityCard({
    super.key,
    required this.entity,
    this.surface = EntityCardSurface.card,
    this.details = const [],
    this.footer,
  });

  final ChapterEntityMention entity;
  final EntityCardSurface surface;
  final List<({String label, String text})> details;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final accent = entityAccentColor(entity.entityType, colors);
    final subtitle = _entitySubtitle(context, entity);
    final summary = entity.summary?.trim() ?? '';

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _EntityLeading(entity: entity, accent: accent),
            const SizedBox(width: RevericSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entity.label,
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: RevericSpacing.xxs),
                  Text(
                    subtitle ?? entityTypeLabel(context, entity.entityType),
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (details.isNotEmpty)
          for (final detail in details) ...[
            const SizedBox(height: RevericSpacing.lg),
            Text(
              detail.label,
              style: typo.uiTinySemibold.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: RevericSpacing.xxs),
            SelectableText(
              detail.text,
              style: typo.uiSmall.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
          ]
        else if (summary.isNotEmpty) ...[
          const SizedBox(height: RevericSpacing.md),
          Text(
            summary,
            style: typo.uiSmall.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (footer != null) ...[
          const SizedBox(height: RevericSpacing.lg),
          footer!,
        ],
      ],
    );

    if (surface == EntityCardSurface.plain) {
      return content;
    }
    final radius = BorderRadius.circular(RevericRadius.large);
    final card = Container(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: radius,
        border: Border.all(color: colors.border),
      ),
      child: content,
    );
    if (surface == EntityCardSurface.card) {
      return card;
    }
    return Material(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      borderRadius: radius,
      color: colors.surfaceContainer,
      child: card,
    );
  }
}

/// 把主体资料字段转成卡片详情行。
List<({String label, String text})> subjectProfileDetails(
  BuildContext context,
  SubjectProfile profile,
) => [
  for (final (field, text) in profile.fields)
    (
      label: context.t(switch (field) {
        SubjectField.identity => LocaleKeys.historyFieldIdentity,
        SubjectField.age => LocaleKeys.historyFieldAge,
        SubjectField.appearance => LocaleKeys.workspaceCharacterAppearanceLabel,
        SubjectField.description =>
          profile.entity.entityType == entityTypeCharacter
              ? LocaleKeys.workspaceCharacterDescriptionLabel
              : LocaleKeys.mapEditorStudioFieldDescription,
        SubjectField.personality =>
          LocaleKeys.workspaceCharacterPersonalityLabel,
        SubjectField.motivation => LocaleKeys.historyFieldMotivation,
        SubjectField.arc => LocaleKeys.historyFieldArc,
        SubjectField.biography => LocaleKeys.workspaceCharacterSummaryLabel,
        SubjectField.currentState =>
          LocaleKeys.workspaceCharacterCurrentStateLabel,
        SubjectField.category => LocaleKeys.workspaceEntryCategoryLabel,
        SubjectField.content => LocaleKeys.historyFieldContent,
      }),
      text: text,
    ),
];

class _EntityLeading extends StatelessWidget {
  const _EntityLeading({required this.entity, required this.accent});

  final ChapterEntityMention entity;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final photoAssetId = entity.photoAssetIds.firstOrNull;
    if (entity.entityType == entityTypeCharacter &&
        (entity.avatarAssetId != null || photoAssetId == null)) {
      return CharacterAvatar(
        avatarAssetId: entity.avatarAssetId,
        fallbackName: entity.label,
        size: 40,
        backgroundColor: accent.withValues(alpha: 0.2),
        textColor: accent,
      );
    }
    final icon = Center(
      child: RevericIcon(
        entityIcon(entity.entityType),
        size: 20,
        color: accent,
      ),
    );
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.16),
      ),
      child: photoAssetId == null
          ? icon
          : ClipOval(
              child: MediaAssetImage(assetId: photoAssetId, placeholder: icon),
            ),
    );
  }
}

Color entityAccentColor(String entityType, RevericColors colors) {
  return switch (entityType) {
    entityTypeCharacter => colors.accent,
    entityTypeLocation => colors.success,
    entityTypeSkill => colors.accentAmber,
    entityTypeItem => colors.accentWarm,
    entityTypeCreature => colors.error,
    entityTypeFaction => colors.additionBorder,
    _ => colors.textMuted,
  };
}

String entityIcon(String entityType) {
  return switch (entityType) {
    entityTypeCharacter => RevericIcons.person,
    entityTypeLocation => RevericIcons.place,
    entityTypeSkill => RevericIcons.auto_awesome,
    entityTypeItem => RevericIcons.inventory_2,
    entityTypeCreature => RevericIcons.bug_beetle_outlined,
    entityTypeFaction => RevericIcons.group,
    _ => RevericIcons.help_outline,
  };
}

String entityTypeLabel(BuildContext context, String entityType) {
  return switch (entityType) {
    entityTypeCharacter => context.t(LocaleKeys.entityTypeCharacter),
    entityTypeLocation => context.t(LocaleKeys.entityTypeLocation),
    entityTypeSkill => context.t(LocaleKeys.entityTypeSkill),
    entityTypeItem => context.t(LocaleKeys.entityTypeItem),
    entityTypeCreature => context.t(LocaleKeys.entityTypeCreature),
    entityTypeFaction => context.t(LocaleKeys.entityTypeFaction),
    _ => context.t(LocaleKeys.entityTypeUnknown),
  };
}

String? _entitySubtitle(BuildContext context, ChapterEntityMention entity) {
  final raw = entity.subtitle?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return switch (entity.entityType) {
    entityTypeCharacter => characterRoleLabel(context, raw),
    entityTypeLocation => _locationTypeLabel(context, raw),
    _ => raw,
  };
}

String characterRoleLabel(BuildContext context, String role) {
  return switch (role) {
    characterRoleProtagonist => context.t(LocaleKeys.characterRoleProtagonist),
    characterRoleAntagonist => context.t(LocaleKeys.characterRoleAntagonist),
    characterRoleSupporting => context.t(LocaleKeys.characterRoleSupporting),
    characterRoleMinor => context.t(LocaleKeys.characterRoleMinor),
    _ => context.t(LocaleKeys.characterRoleSupporting),
  };
}

String _locationTypeLabel(BuildContext context, String type) {
  return switch (type) {
    locationTypeWorld => context.t(LocaleKeys.locationTypeWorld),
    locationTypeContinent => context.t(LocaleKeys.locationTypeContinent),
    locationTypeCountry => context.t(LocaleKeys.locationTypeCountry),
    locationTypeRegion => context.t(LocaleKeys.locationTypeRegion),
    locationTypeCity => context.t(LocaleKeys.locationTypeCity),
    locationTypeDistrict => context.t(LocaleKeys.locationTypeDistrict),
    locationTypeMountain => context.t(LocaleKeys.locationTypeMountain),
    locationTypePlain => context.t(LocaleKeys.locationTypePlain),
    locationTypeForest => context.t(LocaleKeys.locationTypeForest),
    locationTypeRiver => context.t(LocaleKeys.locationTypeRiver),
    locationTypeLake => context.t(LocaleKeys.locationTypeLake),
    locationTypeSea => context.t(LocaleKeys.locationTypeSea),
    locationTypeIsland => context.t(LocaleKeys.locationTypeIsland),
    locationTypeBuilding => context.t(LocaleKeys.locationTypeBuilding),
    locationTypeLandmark => context.t(LocaleKeys.locationTypeLandmark),
    locationTypeNatural => context.t(LocaleKeys.locationTypeNatural),
    locationTypeCustom => context.t(LocaleKeys.locationTypeCustom),
    _ => context.t(LocaleKeys.locationTypeGeneric),
  };
}
