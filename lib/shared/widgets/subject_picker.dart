// 职责: 按名称搜索、按图鉴类型筛选并选择人物、地点或图鉴主体。
// 关联文件:
//   lib/shared/models/subject.dart
//   lib/shared/services/subjects.dart
//   lib/shared/components/reveric_filter_chip.dart
//   lib/shared/widgets/character_avatar.dart
//   lib/shared/widgets/media_asset_image.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity.json
//   assets/translations/zh-CN/entity.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/search-debounce.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../components/reveric_button.dart';
import '../components/reveric_dialog.dart';
import '../components/reveric_filter_chip.dart';
import '../components/reveric_placeholder.dart';
import '../components/reveric_search_field.dart';
import '../database/novel_content_database.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../models/subject.dart';
import '../services/subjects.dart';
import '../theme/theme.dart';
import 'character_avatar.dart';
import 'media_asset_image.dart';

/// 图鉴类型筛选顺序与文案，和侧栏图鉴分组一致。
const _categoryLabels = {
  entityTypeFaction: LocaleKeys.workspaceFactions,
  entityTypeCreature: LocaleKeys.workspaceCreatures,
  entityTypeItem: LocaleKeys.workspaceItems,
  entityTypeSkill: LocaleKeys.workspaceSkills,
};

/// 打开主体选择弹窗，返回选中主体的 id；取消时为 null。
Future<String?> showSubjectPicker(
  BuildContext context, {
  required NovelContentDatabase db,
  required SubjectKind kind,
  Widget Function(String assetId)? coverBuilder,
}) => showRevericDialog<String>(
  context: context,
  builder: (_) => SubjectPicker(db: db, kind: kind, coverBuilder: coverBuilder),
);

/// 主体选择：搜索名字（人物含别名），图鉴可按类型筛选；卡片展示首张照片和照片数。
class SubjectPicker extends HookWidget {
  const SubjectPicker({
    super.key,
    required this.db,
    required this.kind,
    this.coverBuilder,
  });
  final NovelContentDatabase db;
  final SubjectKind kind;

  /// 按资产 id 构建封面；为空时用共享的 [MediaAssetImage]。
  final Widget Function(String assetId)? coverBuilder;

  static const double _width = 720;
  static const double _gridHeight = 420;
  static const double _tileWidth = 168;
  static const double _tileHeight = 200;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final search = useDebouncedSearch();
    final category = useState<String?>(null);
    final subjects = useFuture(
      useMemoized(() => loadSubjects(db, kind), [db, kind]),
    );
    final all = subjects.data ?? const <Subject>[];
    final character = kind == SubjectKind.character;
    final (icon, titleKey, emptyKey, searchKey) = switch (kind) {
      SubjectKind.character => (
        RevericIcons.person,
        LocaleKeys.workspaceCharacters,
        LocaleKeys.entitySubjectCharactersEmpty,
        LocaleKeys.commonSearchCharacters,
      ),
      SubjectKind.location => (
        RevericIcons.location_on,
        LocaleKeys.entitySubjectLocations,
        LocaleKeys.entitySubjectLocationsEmpty,
        LocaleKeys.commonSearchLocations,
      ),
      SubjectKind.compendium => (
        RevericIcons.inventory_2,
        LocaleKeys.workspaceSidebarCompendium,
        LocaleKeys.entitySubjectCompendiumEmpty,
        LocaleKeys.commonSearch,
      ),
    };
    final counts = useMemoized(() {
      final counts = <String, int>{};
      for (final subject in all) {
        if (subject.category case final type?) {
          counts[type] = (counts[type] ?? 0) + 1;
        }
      }
      return counts;
    }, [all]);
    final matches = useMemoized(
      () => all
          .where(
            (s) =>
                (category.value == null || s.category == category.value) &&
                (!search.active || s.matches(search.query)),
          )
          .toList(),
      [all, category.value, search.query],
    );

    Widget placeholder(Widget child) => Center(child: child);
    final body = subjects.hasError
        ? placeholder(
            RevericPlaceholder.error(
              title: context.t(LocaleKeys.commonLoadFailed),
            ),
          )
        : !subjects.hasData
        ? const Center(child: CircularProgressIndicator())
        : all.isEmpty
        ? placeholder(
            RevericPlaceholder.empty(icon: icon, title: context.t(emptyKey)),
          )
        : matches.isEmpty
        ? placeholder(
            RevericPlaceholder.empty(
              icon: RevericIcons.search,
              title: context.t(LocaleKeys.commonNoResults),
            ),
          )
        : GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _tileWidth,
              mainAxisExtent: _tileHeight,
              mainAxisSpacing: RevericSpacing.md,
              crossAxisSpacing: RevericSpacing.md,
            ),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final subject = matches[index];
              final cover = subject.photos.firstOrNull?.assetId;
              final fallback = ColoredBox(
                color: colors.surfaceDim,
                child: Center(
                  child: character
                      ? CharacterAvatar(
                          avatarAssetId: subject.avatarAssetId,
                          fallbackName: subject.name,
                          size: 48,
                          backgroundColor: colors.selected,
                          textColor: colors.accent,
                        )
                      : RevericIcon(icon, size: 24, color: colors.textSubtle),
                ),
              );
              return SubjectPickerTile(
                key: ValueKey(subject.id),
                label: subject.name,
                meta: context.t(
                  LocaleKeys.entitySubjectPhotoCount,
                  namedArgs: {'count': '${subject.photos.length}'},
                ),
                onTap: () => Navigator.of(context).pop(subject.id),
                cover: cover != null
                    ? coverBuilder?.call(cover) ??
                          MediaAssetImage(assetId: cover, placeholder: fallback)
                    : fallback,
              );
            },
          );

    return RevericDialog.panel(
      width: _width,
      title: Text(context.t(titleKey)),
      content: SizedBox(
        width: _width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RevericSearchField(
              controller: search.controller,
              autofocus: true,
              hint: context.t(searchKey),
            ),
            if (counts.isNotEmpty) ...[
              const SizedBox(height: RevericSpacing.md),
              Wrap(
                spacing: RevericSpacing.xs,
                runSpacing: RevericSpacing.xs,
                children: [
                  RevericFilterChip(
                    label: context.t(LocaleKeys.commonFilterAll),
                    count: all.length,
                    selected: category.value == null,
                    onTap: () => category.value = null,
                  ),
                  for (final MapEntry(key: type, value: labelKey)
                      in _categoryLabels.entries)
                    RevericFilterChip(
                      label: context.t(labelKey),
                      count: counts[type] ?? 0,
                      selected: category.value == type,
                      onTap: counts.containsKey(type)
                          ? () => category.value = type
                          : null,
                    ),
                ],
              ),
            ],
            const SizedBox(height: RevericSpacing.lg),
            // 搜索时保持期望高度，矮窗口下按弹窗剩余空间收缩。
            Flexible(
              child: SizedBox(height: _gridHeight, child: body),
            ),
          ],
        ),
      ),
      actions: [
        RevericButton.text(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// 选择卡片：上方封面铺满，下方可选名称和说明；选中时描强调色边。
class SubjectPickerTile extends StatelessWidget {
  const SubjectPickerTile({
    super.key,
    required this.cover,
    required this.onTap,
    this.label,
    this.meta,
    this.selected = false,
  });
  final Widget cover;
  final VoidCallback onTap;
  final String? label;
  final String? meta;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final radius = BorderRadius.circular(RevericRadius.large);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        hoverColor: colors.hover,
        child: Ink(
          padding: const EdgeInsets.all(RevericSpacing.xs),
          decoration: BoxDecoration(
            color: selected ? colors.selected : colors.surface,
            borderRadius: radius,
            border: Border.all(
              color: selected ? colors.accent : colors.borderSubtle,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(RevericRadius.medium),
                  child: cover,
                ),
              ),
              if (label != null) ...[
                const SizedBox(height: RevericSpacing.xs),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.xxs,
                  ),
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSmallSemibold.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
              if (meta != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.xxs,
                  ),
                  child: Text(
                    meta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
