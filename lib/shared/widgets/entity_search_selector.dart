// 职责: 实体搜索选择器，支持搜索和选择不同类型的实体。
// 关联文件:
//   lib/shared/widgets/relation_edit_dialog.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/entity_search.json
//   assets/translations/zh-CN/entity_search.json
//   assets/translations/en/entity.json
//   assets/translations/zh-CN/entity.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../components/reveric_input_decoration.dart';
import '../database/novel_content_database.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../providers/novel_providers.dart';
import '../theme/theme.dart';

const double _dropdownMaxHeight = 240;

class EntitySearchSelector extends HookConsumerWidget {
  const EntitySearchSelector({
    super.key,
    required this.databasePath,
    required this.entityType,
    required this.selectedId,
    required this.onChanged,
    this.label,
    this.height = RevericSizes.fieldHeight,
  });

  final String databasePath;
  final String entityType;
  final String selectedId;
  final void Function(String id, String name) onChanged;
  final String? label;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final searchController = useTextEditingController();
    final searchValue = useValueListenable(searchController);
    final debouncedSearchQuery = useDebounced(
      searchValue.text,
      const Duration(milliseconds: 250),
    );
    final link = useMemoized(LayerLink.new);
    final portal = useMemoized(OverlayPortalController.new);
    final fieldKey = useMemoized(GlobalKey.new);
    // 候选列表走 overlay 浮在输入框上下，不参与布局；打开时按剩余空间决定朝向。
    final dropdownAbove = useRef(false);
    final dropdownWidth = useRef(0.0);
    final untitledChapterLabel = context.t(LocaleKeys.aiUntitledChapter);

    final entitiesAsync = _watchEntities(ref, databasePath, entityType);

    useEffect(() {
      if (selectedId.isNotEmpty) {
        _loadSelectedEntityName(
          entitiesAsync,
          selectedId,
          searchController,
          untitledChapterLabel,
        );
      }
      return null;
    }, [selectedId, entitiesAsync, untitledChapterLabel]);

    void open() {
      final box = fieldKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final top = box.localToGlobal(Offset.zero).dy;
        final screen = MediaQuery.sizeOf(context).height;
        final below = screen - top - box.size.height;
        dropdownAbove.value =
            below < _dropdownMaxHeight + RevericSpacing.lg && top > below;
        dropdownWidth.value = box.size.width;
      }
      portal.show();
    }

    void close() => portal.hide();

    Widget dropdown(BuildContext context) {
      final typo = RevericTheme.typographyOf(context);
      final above = dropdownAbove.value;
      Widget message(String text) => Padding(
        padding: const EdgeInsets.all(RevericSpacing.lg),
        child: Text(text, style: typo.ui.copyWith(color: colors.textMuted)),
      );
      return CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        targetAnchor: above ? Alignment.topLeft : Alignment.bottomLeft,
        followerAnchor: above ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(0, above ? -RevericSpacing.xs : RevericSpacing.xs),
        child: Align(
          alignment: above ? Alignment.bottomLeft : Alignment.topLeft,
          child: TapRegion(
            groupId: link,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: dropdownWidth.value,
                constraints: const BoxConstraints(
                  maxHeight: _dropdownMaxHeight,
                ),
                padding: const EdgeInsets.all(RevericSpacing.xs),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(RevericRadius.large),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: colors.textPrimary.withValues(alpha: 0.16),
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: entitiesAsync.when(
                  data: (entities) {
                    final filtered = _filterEntities(
                      entities,
                      searchValue.text.trim().isEmpty
                          ? ''
                          : debouncedSearchQuery ?? '',
                      untitledChapterLabel,
                    );
                    if (filtered.isEmpty) {
                      return message(
                        context.t(
                          LocaleKeys.entityGraphSearchEmpty,
                          namedArgs: {
                            'type': _getEntityTypeName(context, entityType),
                          },
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final (id, name) = _getEntityIdAndName(
                          filtered[index],
                          untitledChapterLabel,
                        );
                        final isSelected = id == selectedId;
                        return InkWell(
                          borderRadius: BorderRadius.circular(
                            RevericRadius.medium,
                          ),
                          hoverColor: colors.hover,
                          onTap: () {
                            searchController.text = name;
                            onChanged(id, name);
                            close();
                          },
                          child: Ink(
                            padding: const EdgeInsets.all(RevericSpacing.sm),
                            decoration: BoxDecoration(
                              color: isSelected ? colors.selected : null,
                              borderRadius: BorderRadius.circular(
                                RevericRadius.medium,
                              ),
                            ),
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: typo.ui.copyWith(
                                color: isSelected
                                    ? colors.accent
                                    : colors.textPrimary,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(RevericSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stack) => message(
                    context.t(
                      LocaleKeys.entitySearchLoadFailed,
                      namedArgs: {'error': error.toString()},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: RevericTheme.typographyOf(context).uiSemibold),
          const SizedBox(height: 8),
        ],
        OverlayPortal(
          controller: portal,
          overlayChildBuilder: dropdown,
          child: CompositedTransformTarget(
            link: link,
            child: TapRegion(
              groupId: link,
              onTapOutside: (_) => close(),
              child: SizedBox(
                key: fieldKey,
                height: height,
                child: TextFormField(
                  controller: searchController,
                  textAlignVertical: TextAlignVertical.center,
                  style: RevericTheme.typographyOf(
                    context,
                  ).ui.copyWith(color: colors.textPrimary, height: 1.6),
                  // suffix 是「展开/收起下拉」而不是清除，套不进 RevericSearchField，
                  // 按 design-system.md 走 revericInputDecoration 这个逃生口。
                  decoration: revericInputDecoration(
                    context,
                    hintText: context.t(
                      LocaleKeys.entitySearchHint,
                      namedArgs: {
                        'type': _getEntityTypeName(context, entityType),
                      },
                    ),
                    suffixIcon: InkWell(
                      borderRadius: BorderRadius.circular(RevericRadius.large),
                      onTap: () => portal.isShowing ? close() : open(),
                      child: Center(
                        child: RevericIcon(
                          RevericIcons.search,
                          size: 14,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    suffixIconConstraints: BoxConstraints.tightFor(
                      width: 36,
                      height: height,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: RevericSpacing.lg,
                    ),
                  ),
                  onChanged: (_) {
                    if (!portal.isShowing) {
                      open();
                    }
                  },
                  onTap: open,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  AsyncValue<List<dynamic>> _watchEntities(
    WidgetRef ref,
    String databasePath,
    String entityType,
  ) {
    switch (entityType) {
      case entityTypeCharacter:
        return ref.watch(characterProfilesProvider(databasePath));
      case entityTypeChapter:
        return ref.watch(chaptersProvider(databasePath));
      case entityTypeSkill:
        return ref.watch(itemsProvider(path: databasePath, type: 'skill'));
      case entityTypeItem:
        return ref.watch(itemsProvider(path: databasePath, type: 'item'));
      case entityTypeFaction:
        return ref.watch(itemsProvider(path: databasePath, type: 'faction'));
      case entityTypeLocation:
        return ref.watch(itemsProvider(path: databasePath, type: 'location'));
      case entityTypeCreature:
        return ref.watch(itemsProvider(path: databasePath, type: 'creature'));
      default:
        return AsyncValue.data([]);
    }
  }

  void _loadSelectedEntityName(
    AsyncValue<List<dynamic>> entitiesAsync,
    String selectedId,
    TextEditingController controller,
    String untitledChapterLabel,
  ) {
    entitiesAsync.whenData((entities) {
      for (final entity in entities) {
        final (id, name) = _getEntityIdAndName(entity, untitledChapterLabel);
        if (id == selectedId) {
          controller.text = name;
          break;
        }
      }
    });
  }

  List<dynamic> _filterEntities(
    List<dynamic> entities,
    String query,
    String untitledChapterLabel,
  ) {
    if (query.isEmpty) {
      return entities;
    }
    final lowerQuery = query.toLowerCase();
    return entities.where((entity) {
      final (_, name) = _getEntityIdAndName(entity, untitledChapterLabel);
      return name.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  (String, String) _getEntityIdAndName(
    dynamic entity,
    String untitledChapterLabel,
  ) {
    if (entity is CharacterProfile) {
      return (entity.id, entity.name);
    }
    if (entity is Chapter) {
      return (entity.id, entity.title ?? untitledChapterLabel);
    }
    if (entity is Item) {
      return (entity.id, entity.title);
    }
    return ('', '');
  }

  String _getEntityTypeName(BuildContext context, String type) {
    switch (type) {
      case entityTypeCharacter:
        return context.t(LocaleKeys.entityTypeCharacter);
      case entityTypeFaction:
        return context.t(LocaleKeys.entityTypeFaction);
      case entityTypeSkill:
        return context.t(LocaleKeys.entityTypeSkill);
      case entityTypeItem:
        return context.t(LocaleKeys.entityTypeItem);
      case entityTypeLocation:
        return context.t(LocaleKeys.entityTypeLocation);
      case entityTypeChapter:
        return context.t(LocaleKeys.entityTypeChapter);
      case entityTypeForeshadowing:
        return context.t(LocaleKeys.entityTypeForeshadowing);
      case entityTypeCreature:
        return context.t(LocaleKeys.entityTypeCreature);
      default:
        return type;
    }
  }
}
