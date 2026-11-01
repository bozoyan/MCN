// 职责: 搜索与分组展示作品资源及季集场次，禁用已有引用并创建选中资源节点。
// 关联文件:
//   lib/desktop/features/canvas/scene_reference.dart
//   lib/desktop/features/canvas/widgets/canvas_node_widget.dart
//   lib/shared/providers/canvas_providers.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/providers/maps_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/hooks.md
//   .agents/rules/search-debounce.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/components/reveric_search_field.dart';
import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/models/outline_draft.dart';
import '../../../../shared/providers/canvas_providers.dart';
import '../../../../shared/providers/maps_providers.dart';
import '../../../../shared/providers/novel_providers.dart';
import '../../../../shared/theme/theme.dart';
import '../scene_reference.dart';
import '../edit_session.dart';
import 'canvas_node_widget.dart';

/// 资源选择器中的一条资源(统一模型,抹平各资源表字段差异)。
class _ResourceItem {
  const _ResourceItem({
    required this.id,
    required this.title,
    required this.refType,
    this.group,
    this.searchText,
  });

  final String id;
  final String title;
  final String refType;
  final String? group;
  final String? searchText;
}

/// 打开画布引用资源选择器;选中资源后在其 [viewportCenter] 位置新建引用节点。
///
/// 已在画布上的(同 refType + refId)资源会禁用并标记「已在画布」。
/// 设计参考 `designs/desktop/canvas/panels.jsx` 的 `CvResourcePopover`。
Future<void> showCanvasResourcePicker({
  required BuildContext context,
  required String databasePath,
  required String canvasId,
  required Offset viewportCenter,
  CanvasEditSession? editSession,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Theme.of(dialogContext).colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.xl,
        vertical: RevericSpacing.xl,
      ),
      child: _CanvasResourcePicker(
        databasePath: databasePath,
        canvasId: canvasId,
        viewportCenter: viewportCenter,
        editSession: editSession,
      ),
    ),
  );
}

class _CanvasResourcePicker extends HookConsumerWidget {
  const _CanvasResourcePicker({
    required this.databasePath,
    required this.canvasId,
    required this.viewportCenter,
    this.editSession,
  });

  final String databasePath;
  final String canvasId;
  final Offset viewportCenter;
  final CanvasEditSession? editSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final search = useDebouncedSearch();

    // 汇集所有资源(各 provider 异步,取 asData 兜底空列表)。
    // 不用 useMemoized:_gatherResources 内含 ref.watch,需每次 build 重跑以
    // 拿到最新数据并维持 provider 订阅。
    final allResources = _gatherResources(context, ref);
    // 已在画布上的 (refType, refId) 集合,用于禁用重复引用。
    final contentAsync = ref.watch(
      canvasContentStreamProvider((
        canvasId: canvasId,
        databasePath: databasePath,
      )),
    );
    final usedKeys = useMemoized(() {
      final content = contentAsync.asData?.value;
      if (content == null) return const <String>{};
      return {
        for (final n in content.nodes)
          if (n.type == canvasNodeTypeReference &&
              n.refType != null &&
              n.refId != null)
            '${n.refType}:${n.refId}',
      };
    }, [contentAsync]);

    // 搜索过滤后按资源类型及场次季集分组，保留资源顺序。
    final filtered = useMemoized(() {
      final q = search.query;
      final hits = allResources
          .where(
            (r) =>
                q.isEmpty ||
                (r.searchText ?? r.title).toLowerCase().contains(q),
          )
          .toList();
      // 普通资源按类型分组；场次在类型内再按季集分组。
      final groups = <String, List<_ResourceItem>>{};
      for (final r in hits) {
        groups.putIfAbsent('${r.refType}:${r.group ?? ''}', () => []).add(r);
      }
      return groups;
    }, [allResources, search.query]);

    Future<void> handlePick(_ResourceItem item) async {
      final service = ref.read(canvasServiceProvider(databasePath));
      Future<void> save() async {
        await service.addNode(
          canvasId: canvasId,
          type: canvasNodeTypeReference,
          refType: item.refType,
          refId: item.id,
          x: viewportCenter.dx,
          y: viewportCenter.dy,
        );
      }

      if (editSession case final session?) {
        await session.write('add-reference', save);
      } else {
        await save();
      }
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(RevericRadius.xl),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题 + 搜索框。
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.lg,
                RevericSpacing.lg,
                RevericSpacing.lg,
                RevericSpacing.sm,
              ),
              child: Row(
                children: [
                  Text(
                    context.t(LocaleKeys.canvasResourcePickerTitle),
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: RevericIcon(
                      RevericIcons.close,
                      size: 16,
                      color: colors.textMuted,
                    ),
                    tooltip: context.t(LocaleKeys.commonClose),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.lg,
              ),
              child: RevericSearchField(
                controller: search.controller,
                hint: context.t(LocaleKeys.canvasResourcePickerSearchHint),
                autofocus: true,
              ),
            ),
            const SizedBox(height: RevericSpacing.sm),
            Flexible(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(RevericSpacing.xl),
                        child: Text(
                          context.t(LocaleKeys.canvasResourcePickerEmpty),
                          style: typo.uiSmall.copyWith(color: colors.textMuted),
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(
                        bottom: RevericSpacing.sm,
                      ),
                      children: [
                        for (final entry in filtered.entries) ...[
                          _GroupHeader(
                            refType: entry.value.first.refType,
                            group: entry.value.first.group,
                          ),
                          for (final item in entry.value)
                            _ResourceRow(
                              item: item,
                              used: usedKeys.contains(
                                '${item.refType}:${item.id}',
                              ),
                              onTap: handlePick,
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 从各 per-novel provider 汇集资源,按 refType 顺序注入。
  ///
  /// 在 build 中订阅最新投影；场次按季、集、场号排序，其余资源沿用原顺序。
  List<_ResourceItem> _gatherResources(BuildContext context, WidgetRef ref) {
    final items = <_ResourceItem>[];

    void add(String refType, String id, String title) {
      if (id.isEmpty) return;
      items.add(_ResourceItem(id: id, title: title, refType: refType));
    }

    final characters =
        ref.watch(characterProfilesProvider(databasePath)).asData?.value ??
        const <CharacterProfile>[];
    for (final c in characters) {
      add(entityTypeCharacter, c.id, c.name);
    }

    final chapters =
        ref.watch(chaptersProvider(databasePath)).asData?.value ??
        const <Chapter>[];
    for (final c in chapters) {
      add(entityTypeChapter, c.id, c.title ?? '');
    }

    final foreshadowings =
        ref.watch(foreshadowingsProvider(databasePath)).asData?.value ??
        const <Foreshadowing>[];
    for (final f in foreshadowings) {
      add(entityTypeForeshadowing, f.id, f.title);
    }

    final outlines =
        ref.watch(outlinesProvider(databasePath)).asData?.value ??
        const <OutlineDraft>[];
    for (final o in outlines) {
      add(canvasNodeRefTypeOutline, o.documentId, o.title);
    }

    final locations =
        ref.watch(locationsProvider(databasePath)).asData?.value ??
        const <Location>[];
    for (final l in locations) {
      add(entityTypeLocation, l.id, l.name);
    }

    // item/faction/skill/creature 共存于 items 表,type 列区分。
    for (final type in [
      entityTypeItem,
      entityTypeFaction,
      entityTypeSkill,
      entityTypeCreature,
    ]) {
      final list =
          ref
              .watch(itemsProvider(path: databasePath, type: type))
              .asData
              ?.value ??
          const <Item>[];
      for (final i in list) {
        add(type, i.id, i.title);
      }
    }

    final documents =
        ref
            .watch(
              documentsProvider(path: databasePath, type: documentTypeMaterial),
            )
            .asData
            ?.value ??
        const <Document>[];
    for (final d in documents) {
      add(canvasNodeRefTypeDocument, d.id, d.title);
    }

    final scenes = ref.watch(canvasSceneReferencesProvider(databasePath)).value;
    if (scenes != null) {
      final ordered = scenes.values.toList()
        ..sort((a, b) {
          var order = a.season.seasonNumber.compareTo(b.season.seasonNumber);
          if (order == 0) {
            order = a.episode.episodeNumber.compareTo(b.episode.episodeNumber);
          }
          if (order == 0) {
            order = a.scene.sceneNumber.compareTo(b.scene.sceneNumber);
          }
          return order == 0 ? a.scene.id.compareTo(b.scene.id) : order;
        });
      for (final reference in ordered) {
        final title = canvasSceneTitle(context, reference);
        final location = canvasSceneLocationLabel(context, reference);
        items.add(
          _ResourceItem(
            id: reference.scene.id,
            title: title,
            refType: canvasNodeRefTypeScreenplayScene,
            group: canvasSceneGroupLabel(context, reference),
            searchText: '$title $location',
          ),
        );
      }
    }
    return items;
  }
}

class _GroupHeader extends StatelessWidget {
  final String? group;
  const _GroupHeader({required this.refType, this.group});

  final String refType;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: RevericSpacing.xs,
      ),
      child: Text(
        group == null
            ? canvasRefTypeLabel(context, refType)
            : '${canvasRefTypeLabel(context, refType)} · $group',
        style: typo.uiTinySemibold.copyWith(color: colors.textMuted),
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.item,
    required this.used,
    required this.onTap,
  });

  final _ResourceItem item;
  final bool used;
  final ValueChanged<_ResourceItem> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return InkWell(
      onTap: used ? null : () => onTap(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.lg,
          vertical: RevericSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accent.withValues(
                  alpha: colors.isDark ? 0.18 : 0.10,
                ),
                borderRadius: BorderRadius.circular(RevericRadius.medium),
              ),
              child: RevericIcon(
                canvasRefTypeIcon(item.refType),
                size: 13,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                item.title.isEmpty ? '—' : item.title,
                style: typo.uiSmall.copyWith(
                  color: used ? colors.textSubtle : colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (used)
              Text(
                context.t(LocaleKeys.canvasResourcePickerAlreadyOnCanvas),
                style: typo.uiTiny.copyWith(color: colors.textSubtle),
              ),
          ],
        ),
      ),
    );
  }
}
