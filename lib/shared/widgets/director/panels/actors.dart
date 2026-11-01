// 职责: 分组搜索角色目录中的人物，将其名称与模型作为独立实例添加到布景。
// 关联文件:
//   lib/shared/models/director/actor_catalog.dart
//   lib/shared/services/director/actor_catalog.dart
//   lib/shared/services/director/session.dart
//   lib/shared/widgets/director/panels/common.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/search-debounce.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../components/reveric_button.dart';
import '../../../components/reveric_placeholder.dart';
import '../../../components/reveric_search_field.dart';
import '../../../models/director/actor_catalog.dart';
import '../../../services/director/actor_catalog.dart';
import '../../../services/director/session.dart';
import '../../../theme/theme.dart';
import '../strings.dart';
import 'common.dart';

class DirectorActorsPanel extends HookWidget {
  const DirectorActorsPanel({
    super.key,
    required this.session,
    required this.catalog,
  });
  final DirectorSession session;
  final DirectorActorCatalogController catalog;

  @override
  Widget build(BuildContext context) {
    useListenable(catalog);
    final search = useDebouncedSearch();
    final matches = useMemoized(
      () => catalog.actors
          .where((actor) => actor.name.toLowerCase().contains(search.query))
          .toList(),
      [catalog.actors, search.query],
    );
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    // 初始候选（剧本里即本场出场人物）单独成组排在前面；只有一组时不加组标题。
    final featuredIds = {
      for (final actor in catalog.source.initialActors ?? const []) actor.id,
    };
    final groups = [
      (
        'actors_featured',
        [
          for (final a in matches)
            if (featuredIds.contains(a.id)) a,
        ],
      ),
      (
        'actors_others',
        [
          for (final a in matches)
            if (!featuredIds.contains(a.id)) a,
        ],
      ),
    ].where((g) => g.$2.isNotEmpty).toList();
    final placed = {
      for (final object in session.history.document.objects)
        if (object['catalog_id'] != null) object['catalog_id']: object['id'],
    };
    void add(DirectorActor actor) => session.attempt(() {
      session.select(session.history.addActor(actor));
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelTitle(tr(context, 'actors')),
        RevericSearchField(
          key: const ValueKey('director-actor-search'),
          controller: search.controller,
          hint: tr(context, 'search_actors'),
        ),
        const SizedBox(height: RevericSpacing.sm),
        Text(
          tr(context, 'actor_catalog_hint'),
          style: typo.uiTiny.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: RevericSpacing.xs),
        if (catalog.loading || (catalog.failed && catalog.actors.isNotEmpty))
          SizedBox(
            height: RevericSizes.fieldHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: catalog.loading
                  ? Text(
                      tr(context, 'actors_loading'),
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    )
                  : Tooltip(
                      message: tr(context, 'actors_load_failed'),
                      child: RevericButton.text(
                        label: tr(context, 'retry'),
                        size: RevericButtonSize.compact,
                        onPressed: catalog.load,
                      ),
                    ),
            ),
          ),
        if (catalog.actors.isEmpty && catalog.failed)
          RevericPlaceholder.error(
            compact: true,
            title: tr(context, 'actors_load_failed'),
            action: RevericButton.secondary(
              label: tr(context, 'retry'),
              onPressed: catalog.load,
            ),
          )
        else if (matches.isEmpty && !catalog.loading)
          RevericPlaceholder.empty(
            compact: true,
            icon: RevericIcons.person,
            title: tr(
              context,
              search.active ? 'actors_no_match' : 'actors_empty',
            ),
          )
        else
          for (final group in groups) ...[
            if (groups.length > 1)
              PanelTitle(tr(context, group.$1), top: RevericSpacing.sm),
            for (final actor in group.$2)
              PanelRow(
                key: ValueKey('director-actor-option:${actor.id}'),
                title: actor.name,
                icon: RevericIcons.person,
                trailingIcon: placed.containsKey(actor.id)
                    ? RevericIcons.check
                    : null,
                selected:
                    placed[actor.id] != null &&
                    placed[actor.id] == session.selected,
                onTap: () => add(actor),
              ),
          ],
      ],
    );
  }
}
