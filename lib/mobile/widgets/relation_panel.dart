// 职责: 为移动关系列表、详情与证据跳转提供弹层和页面导航外壳。
// 关联文件:
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/widgets/relation/providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/relation.json
//   assets/translations/zh-CN/relation.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/entity_graph.json
//   assets/translations/zh-CN/entity_graph.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../shared/components/reveric_button.dart';
import '../../shared/entity_graph/entity_list_section.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/providers/novel_providers.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/relation/detail.dart';
import '../../shared/widgets/relation/list_region.dart';
import '../features/screenplay/scene_editor.dart';
import '../pages/chapter_editor_page.dart';
import 'sheet.dart';

class RelationEntityPickerButton extends StatelessWidget {
  const RelationEntityPickerButton({
    super.key,
    required this.databasePath,
    required this.onSelected,
  });
  final String databasePath;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => RevericButton.text(
    label: context.t(LocaleKeys.entityGraphBrowseEntities),
    onPressed: () => showMobileSheet<void>(
      context: context,
      builder: (sheetContext) => MobileSheetScaffold(
        expand: true,
        header: MobileSheetHeader.closable(
          title: context.t(LocaleKeys.entityGraphBrowseEntities),
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
        child: _EntityPickerContent(
          databasePath: databasePath,
          onSelected: (id) {
            Navigator.of(sheetContext).pop();
            onSelected(id);
          },
        ),
      ),
    ),
  );
}

class _EntityPickerContent extends ConsumerWidget {
  const _EntityPickerContent({
    required this.databasePath,
    required this.onSelected,
  });
  final String databasePath;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context, WidgetRef ref) => EntityListSection(
    characters:
        ref.watch(characterProfilesProvider(databasePath)).value ?? const [],
    factions:
        ref.watch(itemsProvider(path: databasePath, type: 'faction')).value ??
        const [],
    skills:
        ref.watch(itemsProvider(path: databasePath, type: 'skill')).value ??
        const [],
    items:
        ref.watch(itemsProvider(path: databasePath, type: 'item')).value ??
        const [],
    creatures:
        ref.watch(itemsProvider(path: databasePath, type: 'creature')).value ??
        const [],
    selectedEntityKey: null,
    onEntitySelected: onSelected,
  );
}

Future<void> showRelationListSheet(
  BuildContext context,
  String databasePath,
  String entityKey,
  Map<String, String> names, {
  required String novelId,
}) => showMobileSheet<void>(
  context: context,
  builder: (_) => _RelationSheet(
    novelId: novelId,
    databasePath: databasePath,
    entityKey: entityKey,
    names: names,
  ),
);

class _RelationSheet extends ConsumerWidget {
  const _RelationSheet({
    required this.novelId,
    required this.databasePath,
    required this.entityKey,
    required this.names,
  });
  final String novelId;
  final String databasePath;
  final String entityKey;
  final Map<String, String> names;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void evidence(String kind, String id) =>
        _openEvidence(context, ref, novelId, databasePath, kind, id);
    return MobileSheetScaffold(
      expand: true,
      header: MobileSheetHeader.closable(
        title: context.t(
          LocaleKeys.entityGraphRelationsOf,
          namedArgs: {
            'name': names[entityKey] ?? context.t(LocaleKeys.commonUntitled),
          },
        ),
        onClose: () => Navigator.of(context).pop(),
      ),
      child: RelationListRegion(
        databasePath: databasePath,
        entityKey: entityKey,
        names: names,
        onOpenEvidence: evidence,
        onOpenDetail: (id) => showMobileSheet<void>(
          context: context,
          builder: (detailContext) => MobileSheetScaffold(
            expand: true,
            header: MobileSheetHeader.closable(
              title: context.t(LocaleKeys.relationType),
              onClose: () => Navigator.of(detailContext).pop(),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(RevericSpacing.lg),
              child: RelationDetail(
                databasePath: databasePath,
                relationId: id,
                names: names,
                onOpenEvidence: evidence,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openEvidence(
  BuildContext context,
  WidgetRef ref,
  String novelId,
  String path,
  String kind,
  String id,
) async {
  final novel = await ref.read(appDatabaseProvider).novelDao.get(novelId);
  if (!context.mounted) {
    return;
  }
  if (novel == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t(LocaleKeys.relationNotFound))),
    );
    return;
  }
  final db = ref.read(novelContentDatabaseProvider(path));
  Widget? page;
  if (kind == 'chapter') {
    if (await db.chapterDao.getById(id) != null) {
      page = MobileChapterEditorPage(
        novel: novel,
        databasePath: path,
        initialChapterId: id,
      );
    }
  } else {
    final row = await db.screenplayDao.getScene(id);
    if (row != null) {
      final scene = (await db.screenplayDao.watchScenes(row.episodeId).first)
          .where((s) => s.id == id)
          .firstOrNull;
      if (scene != null) {
        page = MobileScreenplaySceneEditorPage(novel: novel, scene: scene);
      }
    }
  }
  if (!context.mounted) {
    return;
  }
  if (page == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t(LocaleKeys.relationEvidenceDeleted))),
    );
    return;
  }
  final theme = RevericTheme.of(context);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RevericTheme(data: theme, child: page!),
    ),
  );
}
