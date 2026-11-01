// 职责: 实体关系图侧边栏列表 — 搜索、类型筛选 chips、按类型分组的实体列表、底部关系概览环形图。
// 关联文件:
//   lib/desktop/widgets/sidebar/sections.dart
//   lib/shared/entity_graph/colors.dart
//   lib/shared/entity_graph/data.dart
//   lib/shared/entity_graph/labels.dart
//   lib/shared/entity_graph/overview.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
//   assets/translations/en/entity.json
//   assets/translations/zh-CN/entity.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../components/collapsible_list_group.dart';
import '../components/reveric_filter_chip.dart';
import '../components/reveric_search_field.dart';
import '../database/novel_content_database.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';
import '../widgets/character_avatar.dart';
import 'colors.dart';
import 'data.dart';
import 'models.dart';
import 'overview.dart';
import 'providers.dart';

/// 实体关系图侧边栏列表 section — 搜索、类型筛选、按类型分组的实体列表，
/// 点击实体行同步 graph 焦点。底部展示关系概览环形图。
class EntityListSection extends ConsumerStatefulWidget {
  const EntityListSection({
    super.key,
    required this.characters,
    required this.factions,
    required this.skills,
    required this.items,
    required this.creatures,
    required this.selectedEntityKey,
    required this.onEntitySelected,
    this.databasePath,
    this.edges,
  });

  final List<CharacterProfile> characters;
  final List<Item> factions;
  final List<Item> skills;
  final List<Item> items;
  final List<Item> creatures;
  final String? selectedEntityKey;
  final ValueSetter<String> onEntitySelected;

  /// 关系图数据库路径 — 传入时自动 watch allRelationsProvider 构建概览环形图。
  final String? databasePath;

  /// 全量边数据，驱动底部关系概览环形图。
  /// 若同时传入 [databasePath] 和 [edges]，优先使用 [edges]。
  final List<EntityEdgeData>? edges;

  @override
  ConsumerState<EntityListSection> createState() => _EntityListSectionState();
}

class _EntityListSectionState extends ConsumerState<EntityListSection> {
  static const Duration _searchDebounceDuration = Duration(milliseconds: 250);

  String? _entityTypeFilter;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final counts = _entityCounts;
    final totalCount = counts.values.fold(0, (sum, count) => sum + count);

    final effectiveEdges =
        widget.edges ??
        (widget.databasePath != null
            ? _watchEdges(context, widget.databasePath!)
            : const <EntityEdgeData>[]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: RevericSpacing.x2l,
            right: RevericSpacing.sm,
            top: RevericSpacing.xs,
            bottom: RevericSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.t(LocaleKeys.entityGraphViewGraph),
                  style: typo.uiSmallSemibold.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Text(
                '$totalCount',
                style: typo.uiTiny.copyWith(color: colors.textSubtle),
              ),
              const SizedBox(width: RevericSpacing.sm),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.x2l),
          child: RevericDebouncedSearchField(
            hint: context.t(LocaleKeys.entityGraphSearchPlaceholder),
            initialQuery: _searchQuery,
            debounce: _searchDebounceDuration,
            onDebouncedChanged: _setSearchQuery,
          ),
        ),
        const SizedBox(height: RevericSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.x2l),
          child: Wrap(
            spacing: RevericSpacing.xxs,
            runSpacing: RevericSpacing.xxs,
            children: [
              RevericFilterChip(
                label: context.t(LocaleKeys.entityGraphFilterAll),
                count: totalCount,
                selected: _entityTypeFilter == null,
                onTap: () => _setFilter(null),
              ),
              RevericFilterChip(
                label: context.t(LocaleKeys.entityTypeCharacter),
                count: counts[entityTypeCharacter] ?? 0,
                selected: _entityTypeFilter == entityTypeCharacter,
                onTap: () => _setFilter(entityTypeCharacter),
              ),
              RevericFilterChip(
                label: context.t(LocaleKeys.entityTypeFaction),
                count: counts[entityTypeFaction] ?? 0,
                selected: _entityTypeFilter == entityTypeFaction,
                onTap: () => _setFilter(entityTypeFaction),
              ),
              RevericFilterChip(
                label: context.t(LocaleKeys.entityTypeSkill),
                count: counts[entityTypeSkill] ?? 0,
                selected: _entityTypeFilter == entityTypeSkill,
                onTap: () => _setFilter(entityTypeSkill),
              ),
              RevericFilterChip(
                label: context.t(LocaleKeys.entityTypeItem),
                count: counts[entityTypeItem] ?? 0,
                selected: _entityTypeFilter == entityTypeItem,
                onTap: () => _setFilter(entityTypeItem),
              ),
              RevericFilterChip(
                label: context.t(LocaleKeys.entityTypeCreature),
                count: counts[entityTypeCreature] ?? 0,
                selected: _entityTypeFilter == entityTypeCreature,
                onTap: () => _setFilter(entityTypeCreature),
              ),
            ],
          ),
        ),
        const SizedBox(height: RevericSpacing.sm),
        Divider(height: RevericSizes.dividerThickness, color: colors.border),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: RevericSpacing.sm),
            children: _buildEntitySections(context, colors, typo),
          ),
        ),
        if (effectiveEdges.isNotEmpty)
          EntityGraphOverviewDonut(
            counts: relationCategoryCounts(effectiveEdges),
          ),
      ],
    );
  }

  List<EntityEdgeData> _watchEdges(BuildContext context, String databasePath) {
    final relations =
        ref.watch(allRelationsProvider(databasePath)).value ??
        const <RelationSummary>[];
    return buildEntityGraphEdges(
      context: context,
      relations: relations,
      includeEdgeLabels: false,
    );
  }

  Map<String, int> get _entityCounts {
    return {
      entityTypeCharacter: widget.characters.length,
      entityTypeFaction: widget.factions.length,
      entityTypeSkill: widget.skills.length,
      entityTypeItem: widget.items.length,
      entityTypeCreature: widget.creatures.length,
    };
  }

  void _setSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }
    setState(() {
      _searchQuery = value;
    });
  }

  void _setFilter(String? type) {
    setState(() {
      _entityTypeFilter = type;
    });
  }

  List<Widget> _buildEntitySections(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
  ) {
    final sections = <Widget>[];
    _addSection<CharacterProfile>(
      context,
      sections,
      title: context.t(LocaleKeys.workspaceCharacters),
      entityType: entityTypeCharacter,
      entries: widget.characters,
      nameOf: (entry) => entry.name,
      subtitleOf: (entry) => _localizeCharacterRole(context, entry.role),
      avatarOf: (entry) => entry.avatarAssetId,
      typeKeyOf: (entry) => entry.role,
      idOf: (entry) => entry.id,
      colors: colors,
      typo: typo,
    );
    _addSection<Item>(
      context,
      sections,
      title: context.t(LocaleKeys.workspaceFactions),
      entityType: entityTypeFaction,
      entries: widget.factions,
      nameOf: (entry) => entry.title,
      subtitleOf: (_) => context.t(LocaleKeys.entityTypeFaction),
      idOf: (entry) => entry.id,
      colors: colors,
      typo: typo,
    );
    _addSection<Item>(
      context,
      sections,
      title: context.t(LocaleKeys.workspaceSkills),
      entityType: entityTypeSkill,
      entries: widget.skills,
      nameOf: (entry) => entry.title,
      subtitleOf: (_) => context.t(LocaleKeys.entityTypeSkill),
      idOf: (entry) => entry.id,
      colors: colors,
      typo: typo,
    );
    _addSection<Item>(
      context,
      sections,
      title: context.t(LocaleKeys.workspaceItems),
      entityType: entityTypeItem,
      entries: widget.items,
      nameOf: (entry) => entry.title,
      subtitleOf: (_) => context.t(LocaleKeys.entityTypeItem),
      idOf: (entry) => entry.id,
      colors: colors,
      typo: typo,
    );
    _addSection<Item>(
      context,
      sections,
      title: context.t(LocaleKeys.workspaceCreatures),
      entityType: entityTypeCreature,
      entries: widget.creatures,
      nameOf: (entry) => entry.title,
      subtitleOf: (_) => context.t(LocaleKeys.entityTypeCreature),
      idOf: (entry) => entry.id,
      colors: colors,
      typo: typo,
    );
    if (sections.isEmpty) {
      sections.add(_buildEmptyHint(context, colors, typo));
    }
    return sections;
  }

  void _addSection<T>(
    BuildContext context,
    List<Widget> sections, {
    required String title,
    required String entityType,
    required List<T> entries,
    required String Function(T entry) nameOf,
    required String Function(T entry) subtitleOf,
    required String Function(T entry) idOf,
    required RevericColors colors,
    required RevericTypography typo,
    String? Function(T entry)? avatarOf,
    String? Function(T entry)? typeKeyOf,
  }) {
    if (_entityTypeFilter != null && _entityTypeFilter != entityType) {
      return;
    }

    final query = _searchQuery.trim().toLowerCase();
    final filtered = entries.where((entry) {
      final name = nameOf(entry).toLowerCase();
      return query.isEmpty || name.contains(query);
    }).toList();
    if (filtered.isEmpty) {
      return;
    }

    sections.add(
      CollapsibleListGroup(
        title: title,
        count: filtered.length,
        children: [
          for (final entry in filtered)
            _EntityListRow(
              key: ValueKey('${entityType}_${idOf(entry)}'),
              name: nameOf(entry),
              subtitle: subtitleOf(entry),
              entityType: entityType,
              typeKey: typeKeyOf?.call(entry),
              avatarAssetId: avatarOf?.call(entry),
              selected:
                  widget.selectedEntityKey == '${entityType}_${idOf(entry)}',
              colors: colors,
              typo: typo,
              onTap: () {
                widget.onEntitySelected('${entityType}_${idOf(entry)}');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyHint(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x2l,
        vertical: RevericSpacing.lg,
      ),
      child: Text(
        context.t(LocaleKeys.sidebarEmptyHint),
        style: typo.uiSmall.copyWith(color: colors.textMuted),
      ),
    );
  }
}

class _EntityListRow extends StatelessWidget {
  const _EntityListRow({
    super.key,
    required this.name,
    required this.subtitle,
    required this.entityType,
    required this.selected,
    required this.colors,
    required this.typo,
    required this.onTap,
    this.avatarAssetId,
    this.typeKey,
  });

  final String name;
  final String subtitle;
  final String entityType;
  final String? typeKey;
  final bool selected;
  final RevericColors colors;
  final RevericTypography typo;
  final VoidCallback onTap;
  final String? avatarAssetId;

  @override
  Widget build(BuildContext context) {
    final ringColor = entityGraphRingColor(
      entityType,
      colors,
      typeKey: typeKey,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.hover,
        child: Container(
          color: selected ? colors.selected : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.x2l,
            vertical: RevericSpacing.xs,
          ),
          child: Row(
            children: [
              CharacterAvatar(
                avatarAssetId: avatarAssetId,
                fallbackName: name,
                size: 30,
                backgroundColor: ringColor.withValues(alpha: 0.15),
                textColor: ringColor,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiSmall.copyWith(
                        color: colors.textPrimary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiTiny.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _localizeCharacterRole(BuildContext context, String role) {
  switch (role) {
    case characterRoleProtagonist:
      return context.t(LocaleKeys.characterRoleProtagonist);
    case characterRoleAntagonist:
      return context.t(LocaleKeys.characterRoleAntagonist);
    case characterRoleSupporting:
      return context.t(LocaleKeys.characterRoleSupporting);
    case characterRoleMinor:
      return context.t(LocaleKeys.characterRoleMinor);
    default:
      return role;
  }
}
