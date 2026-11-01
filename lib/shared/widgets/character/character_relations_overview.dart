// 职责: 人物关系网络只读概览 — 按人物/势力/技能/物品四组展示已有关系，编辑入口指向关系图。
// 关联文件:
//   lib/shared/providers/novel_providers.dart
//   lib/shared/entity_graph/labels.dart
//   lib/shared/widgets/character/character_profile_section.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../database/novel_content_database.dart';
import '../../entity_graph/labels.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/novel_providers.dart';
import '../../theme/theme.dart';

/// 每组默认展开的条数；主角关系可以有几十条，全平铺会把整页撑爆。
const int _relationPreviewCap = 6;

/// 关系网络里参与展示的四类对端。
const List<String> _relationGroupTypes = <String>[
  entityTypeCharacter,
  entityTypeFaction,
  entityTypeSkill,
  entityTypeItem,
];

class CharacterRelationEntry {
  const CharacterRelationEntry({required this.typeLabel, required this.name});

  final String typeLabel;
  final String name;
}

class CharacterRelationsOverview extends ConsumerWidget {
  const CharacterRelationsOverview({
    super.key,
    required this.databasePath,
    required this.characterId,
    this.onOpenGraph,
  });

  final String databasePath;
  final String characterId;

  /// 为空时隐藏「在关系图中查看」入口（例如从聊天页推入、无法切回关系图）。
  final VoidCallback? onOpenGraph;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final relations =
        ref
            .watch(
              entityRelationsProvider(
                path: databasePath,
                entityType: entityTypeCharacter,
                entityId: characterId,
              ),
            )
            .value ??
        const <RelationSummary>[];

    final names = <String, Map<String, String>>{
      entityTypeCharacter: {
        for (final character
            in ref.watch(characterProfilesProvider(databasePath)).value ??
                const [])
          character.id: character.name,
      },
      for (final type in _relationGroupTypes.skip(1))
        type: {
          for (final item
              in ref
                      .watch(itemsProvider(path: databasePath, type: type))
                      .value ??
                  const [])
            item.id: item.title,
        },
    };

    final grouped = <String, List<CharacterRelationEntry>>{
      for (final type in _relationGroupTypes) type: <CharacterRelationEntry>[],
    };
    for (final relation in relations.where((r) => r.status == 'active')) {
      final other = _otherEndpoint(relation);
      final bucket = grouped[other.$1];
      if (bucket == null) {
        continue;
      }
      final name = names[other.$1]?[other.$2];
      if (name == null || name.isEmpty) {
        continue;
      }
      bucket.add(
        CharacterRelationEntry(
          typeLabel: localizeRelationTypeLabel(
            context,
            relation.relationType,
            sourceType: relation.sourceType,
            targetType: relation.targetType,
          ),
          name: name,
        ),
      );
    }

    if (grouped.values.every((entries) => entries.isEmpty)) {
      return Row(
        children: [
          Expanded(
            child: Text(
              context.t(LocaleKeys.workspaceCharacterRelationsEmpty),
              style: typo.bodySmall.copyWith(color: colors.textMuted),
            ),
          ),
          if (onOpenGraph != null) _OpenGraphLink(onTap: onOpenGraph!),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final type in _relationGroupTypes)
          if (grouped[type]!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: RevericSpacing.x2l),
              child: _RelationGroup(
                icon: _groupIcon(type),
                title: context.t(_groupTitleKey(type)),
                entries: grouped[type]!,
                onOpenGraph: onOpenGraph,
              ),
            ),
      ],
    );
  }

  /// 关系的另一端；人物↔人物时取 id 不同的那一侧。
  (String, String) _otherEndpoint(RelationSummary relation) {
    final sourceIsSelf =
        relation.sourceType == entityTypeCharacter &&
        relation.sourceId == characterId;
    return sourceIsSelf
        ? (relation.targetType, relation.targetId)
        : (relation.sourceType, relation.sourceId);
  }

  String _groupTitleKey(String type) {
    return switch (type) {
      entityTypeCharacter => LocaleKeys.workspaceCharacterRelationsCharacters,
      entityTypeFaction => LocaleKeys.workspaceCharacterRelationsFactions,
      entityTypeSkill => LocaleKeys.workspaceCharacterSkills,
      _ => LocaleKeys.workspaceCharacterRelationsItems,
    };
  }

  String _groupIcon(String type) {
    return switch (type) {
      entityTypeCharacter => RevericIcons.people,
      entityTypeFaction => RevericIcons.flag,
      entityTypeSkill => RevericIcons.auto_fix_high_outlined,
      _ => RevericIcons.cube,
    };
  }
}

class _RelationGroup extends StatefulWidget {
  const _RelationGroup({
    required this.icon,
    required this.title,
    required this.entries,
    required this.onOpenGraph,
  });

  final String icon;
  final String title;
  final List<CharacterRelationEntry> entries;
  final VoidCallback? onOpenGraph;

  @override
  State<_RelationGroup> createState() => _RelationGroupState();
}

class _RelationGroupState extends State<_RelationGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final overflow = widget.entries.length - _relationPreviewCap;
    final shown = _expanded
        ? widget.entries
        : widget.entries.take(_relationPreviewCap).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RevericIcon(widget.icon, size: 14, color: colors.textMuted),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              widget.title,
              style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              '${widget.entries.length}',
              style: typo.uiTiny.copyWith(color: colors.textSubtle),
            ),
            const Spacer(),
            if (widget.onOpenGraph != null)
              _OpenGraphLink(onTap: widget.onOpenGraph!),
          ],
        ),
        const SizedBox(height: RevericSpacing.sm),
        Wrap(
          spacing: RevericSpacing.xs,
          runSpacing: RevericSpacing.xs,
          children: [
            for (final entry in shown) _RelationChip(entry: entry),
            if (overflow > 0)
              _MoreChip(
                expanded: _expanded,
                overflow: overflow,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
          ],
        ),
      ],
    );
  }
}

class _RelationChip extends StatelessWidget {
  const _RelationChip({required this.entry});

  final CharacterRelationEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: RevericSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.xs,
              vertical: 1,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceDim,
              borderRadius: BorderRadius.circular(RevericRadius.pill),
            ),
            child: Text(
              entry.typeLabel,
              style: typo.uiTiny.copyWith(color: colors.textMuted),
            ),
          ),
          const SizedBox(width: RevericSpacing.xs),
          Text(
            entry.name,
            style: typo.uiSmallSemibold.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _MoreChip extends StatelessWidget {
  const _MoreChip({
    required this.expanded,
    required this.overflow,
    required this.onTap,
  });

  final bool expanded;
  final int overflow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.lg,
            vertical: RevericSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RevericRadius.pill),
            border: Border.all(color: colors.borderInput),
          ),
          child: Text(
            expanded
                ? context.t(LocaleKeys.workspaceCharacterRelationsCollapse)
                : context.t(
                    LocaleKeys.workspaceCharacterRelationsMore,
                    namedArgs: {'count': '$overflow'},
                  ),
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
        ),
      ),
    );
  }
}

class _OpenGraphLink extends StatelessWidget {
  const _OpenGraphLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.xs,
            vertical: 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.t(LocaleKeys.workspaceCharacterRelationsOpenGraph),
                style: typo.uiSmallSemibold.copyWith(color: colors.accentWarm),
              ),
              const SizedBox(width: 2),
              RevericIcon(
                RevericIcons.chevron_right,
                size: 12,
                color: colors.accentWarm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
