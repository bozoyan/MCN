// 职责: 共享角色选择器 — 角色类型筛选 + 搜索 + 网格（桌面 3 列 / 移动端自适应），支持单选/多选。
// 关联文件:
//   lib/desktop/features/monologue/panel.dart
//   lib/desktop/features/roleplay/panel.dart
//   lib/desktop/features/theater/panel.dart
//   lib/mobile/features/monologue/page.dart
//   lib/mobile/features/roleplay/page.dart
//   lib/mobile/features/theater/page.dart
//   lib/shared/widgets/character_avatar.dart
//   lib/shared/models/character_profile.dart
//   lib/shared/components/reveric_search_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/character.json
//   assets/translations/zh-CN/character.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/hooks.md
//   .agents/rules/search-debounce.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../components/reveric_search_field.dart';
import '../../database/novel_content_database.dart' hide AgentRule;
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/character_profile.dart';
import '../../theme/theme.dart';
import '../character_avatar.dart';

/// 角色筛选 Tab 顺序：主角 → 配角 → 反派 → 龙套 → 全部（末位）。
const _roleFiltersInOrder = <String>[
  characterRoleProtagonist,
  characterRoleSupporting,
  characterRoleAntagonist,
  characterRoleMinor,
];

/// 响应式网格：按可用宽度估算列数（移动端）。
const _gridMinTileWidth = 96.0;
const _gridMainAxisExtent = 108.0;

int _resolveGridColumnCount(double width, int? fixedColumnCount) {
  if (fixedColumnCount != null) {
    return fixedColumnCount;
  }
  final estimated = (width / _gridMinTileWidth).floor();
  return estimated.clamp(2, 3);
}

/// 共享角色选择器，用于 monologue / roleplay / theater 的 setup 阶段。
///
/// - 默认展示「主角」Tab；「全部」Tab 位于末位。
/// - 角色数 ≥ [searchThreshold] 时显示搜索框；搜索时跨全部角色匹配。
/// - 角色网格默认桌面端固定 3 列；[gridColumnCount] 为 null 时按宽度自适应（移动端）。
class CharacterPicker extends HookWidget {
  const CharacterPicker({
    super.key,
    required this.characters,
    required this.selectedIds,
    required this.onToggle,
    required this.accentColor,
    this.multiSelect = false,
    this.onSelectAll,
    this.onClear,
    this.searchThreshold = 6,
    this.maxListHeight = 280,
    this.gridColumnCount = 3,
  });

  final List<CharacterProfile> characters;
  final Set<String> selectedIds;
  final void Function(String id) onToggle;
  final Color accentColor;

  /// true: 多选；展示已选数量与全选/清空按钮。
  final bool multiSelect;

  /// 多选模式下的全选回调；不提供则不展示该按钮。
  final VoidCallback? onSelectAll;

  /// 多选模式下的清空回调；不提供则不展示该按钮。
  final VoidCallback? onClear;

  /// 角色数 ≥ 该阈值时显示搜索框。
  final int searchThreshold;

  /// 列表最大高度；为 null 时不限制高度（适合嵌在外层 ScrollView 的移动端）。
  final double? maxListHeight;

  /// 网格列数；为 null 时按可用宽度在 2–3 列间自适应（移动端）。
  final int? gridColumnCount;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final search = useDebouncedSearch();
    final roleFilter = useState<String?>(characterRoleProtagonist);

    final showSearch = characters.length >= searchThreshold;
    final filtered = _filterCharacters(
      characters,
      roleFilter: roleFilter.value,
      query: search.query,
    );
    final showRoleBadge = roleFilter.value == null || search.active;

    final list = filtered.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: RevericSpacing.lg),
            child: Center(
              child: Text(
                context.t(LocaleKeys.commonNoResults),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
            ),
          )
        : _CharacterGrid(
            characters: filtered,
            selectedIds: selectedIds,
            accentColor: accentColor,
            showRoleBadge: showRoleBadge,
            gridColumnCount: gridColumnCount,
            onToggle: onToggle,
          );

    final listSection = Container(
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.xl),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: maxListHeight == null
          ? list
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight!),
              child: SingleChildScrollView(child: list),
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (multiSelect)
          Padding(
            padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
            child: Row(
              children: [
                Text(
                  context.t(
                    LocaleKeys.commonSelectedCountFmt,
                    namedArgs: {'count': selectedIds.length.toString()},
                  ),
                  style: typo.uiTiny.copyWith(color: colors.textMuted),
                ),
                const Spacer(),
                if (onSelectAll != null)
                  _LinkButton(
                    label: context.t(LocaleKeys.commonSelectAll),
                    color: accentColor,
                    onPressed: onSelectAll,
                  ),
                if (onSelectAll != null && onClear != null)
                  const SizedBox(width: RevericSpacing.sm),
                if (onClear != null)
                  _LinkButton(
                    label: context.t(LocaleKeys.commonClearSelection),
                    color: colors.textMuted,
                    onPressed: selectedIds.isEmpty ? null : onClear,
                  ),
              ],
            ),
          ),
        if (showSearch)
          Padding(
            padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
            child: RevericSearchField(
              controller: search.controller,
              hint: context.t(LocaleKeys.commonSearchCharacters),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < _roleFiltersInOrder.length; i++) ...[
                if (i > 0) const SizedBox(width: RevericSpacing.sm),
                _RoleFilterChip(
                  label: _localizedRole(context, _roleFiltersInOrder[i]),
                  count: _countForRole(characters, _roleFiltersInOrder[i]),
                  isSelected: roleFilter.value == _roleFiltersInOrder[i],
                  accentColor: accentColor,
                  onTap: () {
                    roleFilter.value = _roleFiltersInOrder[i];
                  },
                ),
              ],
              const SizedBox(width: RevericSpacing.sm),
              _RoleFilterChip(
                label: context.t(LocaleKeys.commonFilterAll),
                count: characters.length,
                isSelected: roleFilter.value == null,
                accentColor: accentColor,
                onTap: () {
                  roleFilter.value = null;
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: RevericSpacing.sm),
        listSection,
      ],
    );
  }
}

List<CharacterProfile> _filterCharacters(
  List<CharacterProfile> characters, {
  required String? roleFilter,
  required String query,
}) {
  var result = characters;
  if (query.isNotEmpty) {
    result = result.where((character) {
      return character.name.toLowerCase().contains(query) ||
          character.role.toLowerCase().contains(query);
    }).toList();
  } else if (roleFilter != null) {
    result = result
        .where((character) => character.normalizedRole == roleFilter)
        .toList();
  }
  return result.sorted;
}

int _countForRole(List<CharacterProfile> characters, String role) {
  return characters
      .where((character) => character.normalizedRole == role)
      .length;
}

class _CharacterGrid extends StatelessWidget {
  const _CharacterGrid({
    required this.characters,
    required this.selectedIds,
    required this.accentColor,
    required this.showRoleBadge,
    required this.gridColumnCount,
    required this.onToggle,
  });

  final List<CharacterProfile> characters;
  final Set<String> selectedIds;
  final Color accentColor;
  final bool showRoleBadge;
  final int? gridColumnCount;
  final void Function(String id) onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = _resolveGridColumnCount(
          constraints.maxWidth,
          gridColumnCount,
        );

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(RevericSpacing.sm),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            crossAxisSpacing: RevericSpacing.sm,
            mainAxisSpacing: RevericSpacing.sm,
            mainAxisExtent: _gridMainAxisExtent,
          ),
          itemCount: characters.length,
          itemBuilder: (context, index) {
            final character = characters[index];
            return _CharacterGridTile(
              key: ValueKey(character.id),
              character: character,
              isSelected: selectedIds.contains(character.id),
              accentColor: accentColor,
              showRoleBadge: showRoleBadge,
              onToggle: () => onToggle(character.id),
            );
          },
        );
      },
    );
  }
}

class _CharacterGridTile extends StatelessWidget {
  const _CharacterGridTile({
    super.key,
    required this.character,
    required this.isSelected,
    required this.accentColor,
    required this.showRoleBadge,
    required this.onToggle,
  });

  final CharacterProfile character;
  final bool isSelected;
  final Color accentColor;
  final bool showRoleBadge;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final roleLabel = character.role.trim().isEmpty
        ? null
        : _localizedRole(context, character.role);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        hoverColor: colors.hover,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.08)
                : colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.5)
                  : colors.border,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.xs,
            vertical: RevericSpacing.sm,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  CharacterAvatar(
                    character: character,
                    size: 32,
                    backgroundColor: isSelected
                        ? accentColor
                        : accentColor.withValues(alpha: 0.3),
                  ),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: _SelectionIndicator(
                      isSelected: isSelected,
                      accentColor: accentColor,
                      borderColor: colors.border,
                      compact: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RevericSpacing.xs),
              Text(
                character.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: typo.uiTiny.copyWith(
                  color: isSelected ? accentColor : colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  height: 1.2,
                ),
              ),
              if (showRoleBadge && roleLabel != null) ...[
                const SizedBox(height: RevericSpacing.xxs),
                Text(
                  roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: typo.uiTiny.copyWith(color: colors.textSubtle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({
    required this.isSelected,
    required this.accentColor,
    required this.borderColor,
    this.compact = false,
  });

  final bool isSelected;
  final Color accentColor;
  final Color borderColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 16.0 : 18.0;
    final iconSize = compact ? 8.0 : 10.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? accentColor : Colors.transparent,
        border: Border.all(
          color: isSelected ? accentColor : borderColor,
          width: 1.5,
        ),
      ),
      child: isSelected
          ? Center(
              child: RevericIcon(
                RevericIcons.check,
                size: iconSize,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}

class _RoleFilterChip extends StatelessWidget {
  const _RoleFilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.lg,
          vertical: RevericSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(RevericRadius.full),
          border: Border.all(
            color: isSelected
                ? accentColor.withValues(alpha: 0.35)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: (isSelected ? typo.uiSemibold : typo.uiSmall).copyWith(
                color: isSelected ? accentColor : colors.textSecondary,
              ),
            ),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              '$count',
              style: typo.uiSmall.copyWith(
                color: isSelected ? accentColor : colors.textSubtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 将角色类型常量映射为本地化文案；非预设角色（自由文本）原样返回。
String _localizedRole(BuildContext context, String role) => switch (role) {
  characterRoleProtagonist => context.t(LocaleKeys.characterRoleProtagonist),
  characterRoleAntagonist => context.t(LocaleKeys.characterRoleAntagonist),
  characterRoleSupporting => context.t(LocaleKeys.characterRoleSupporting),
  characterRoleMinor => context.t(LocaleKeys.characterRoleMinor),
  _ => role,
};

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.xs,
          vertical: RevericSpacing.xxs,
        ),
        child: Text(
          label,
          style: typo.uiTiny.copyWith(
            color: onPressed == null ? color.withValues(alpha: 0.4) : color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
