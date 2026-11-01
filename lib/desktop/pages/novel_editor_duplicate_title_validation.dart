// 职责: 小说编辑页标题保存前校验 — 拦截重复标题与 AI 路径结构字符（? /）。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/directory-structure.md

part of 'novel_editor.dart';

String _duplicateTitleError(
  BuildContext context, {
  required String title,
  required String location,
}) {
  return context.t(
    LocaleKeys.commonDuplicateTitleIn,
    namedArgs: {'title': title, 'location': location},
  );
}

String? _documentTypeForDuplicateTitleSection(NovelWorkspaceSection section) {
  return switch (section) {
    NovelWorkspaceSection.lore => documentTypeLore,
    NovelWorkspaceSection.materials => documentTypeMaterial,
    _ => null,
  };
}

String? _itemTypeForDuplicateTitleSection(NovelWorkspaceSection section) {
  return switch (section) {
    NovelWorkspaceSection.skills => 'skill',
    NovelWorkspaceSection.items => 'item',
    NovelWorkspaceSection.factions => 'faction',
    NovelWorkspaceSection.creatures => 'creature',
    _ => null,
  };
}

List<Item> _itemsForDuplicateTitleSection({
  required NovelWorkspaceSection section,
  required List<Item> skillEntries,
  required List<Item> items,
  required List<Item> factionEntries,
  required List<Item> creatureEntries,
}) {
  return switch (section) {
    NovelWorkspaceSection.skills => skillEntries,
    NovelWorkspaceSection.items => items,
    NovelWorkspaceSection.factions => factionEntries,
    NovelWorkspaceSection.creatures => creatureEntries,
    _ => const <Item>[],
  };
}

bool _itemTitleExistsForDuplicateTitleSection({
  required NovelWorkspaceSection section,
  required String title,
  required List<Item> skillEntries,
  required List<Item> items,
  required List<Item> factionEntries,
  required List<Item> creatureEntries,
  String? excludeId,
}) {
  final entries = _itemsForDuplicateTitleSection(
    section: section,
    skillEntries: skillEntries,
    items: items,
    factionEntries: factionEntries,
    creatureEntries: creatureEntries,
  );
  return entries.any((item) => item.id != excludeId && item.title == title);
}

bool _foreshadowingTitleExistsForDuplicateTitle({
  required String title,
  required List<Foreshadowing> foreshadowings,
  String? excludeId,
}) {
  return foreshadowings.any(
    (entry) => entry.id != excludeId && entry.title == title,
  );
}

/// title 寻址集合的名称/标题含 `?` 或 `/` 时无法在 AI 路径中寻址，保存前拦截。
/// foreshadowing 等按 id 寻址的集合不受限。
String? _aiPathStructuralCharFieldError(
  BuildContext context, {
  required NovelWorkspaceSection section,
  required String title,
}) {
  final isTitleAddressed =
      section == NovelWorkspaceSection.lore ||
      section == NovelWorkspaceSection.outlines ||
      section == NovelWorkspaceSection.materials ||
      section == NovelWorkspaceSection.skills ||
      section == NovelWorkspaceSection.items ||
      section == NovelWorkspaceSection.factions ||
      section == NovelWorkspaceSection.creatures;
  if (!isTitleAddressed || !nameHasAiPathStructuralChars(title)) {
    return null;
  }
  return context.t(LocaleKeys.commonNameHasPathChar);
}

Future<String?> _duplicateTitleFieldError({
  required BuildContext context,
  required NovelContentService service,
  required NovelWorkspaceSection section,
  required String title,
  required List<Item> skillEntries,
  required List<Item> items,
  required List<Item> factionEntries,
  required List<Item> creatureEntries,
  required List<Foreshadowing> foreshadowings,
  String? parentId,
  String? excludeId,
}) async {
  final structuralError = _aiPathStructuralCharFieldError(
    context,
    section: section,
    title: title,
  );
  if (structuralError != null) {
    return structuralError;
  }
  final sectionError = _duplicateTitleError(
    context,
    title: title,
    location: context.t(sectionLocaleKey(section)),
  );
  final docType = _documentTypeForDuplicateTitleSection(section);
  if (docType != null) {
    final location = parentId == null
        ? context.t(LocaleKeys.commonRootDirectory)
        : context.t(LocaleKeys.commonThisFolder);
    final documentError = _duplicateTitleError(
      context,
      title: title,
      location: location,
    );
    final available = await service.documentsService.isTitleAvailable(
      type: docType,
      title: title,
      parentId: parentId,
      excludeId: excludeId,
    );
    if (!available) {
      return documentError;
    }
  }

  if (_itemTypeForDuplicateTitleSection(section) != null &&
      _itemTitleExistsForDuplicateTitleSection(
        section: section,
        title: title,
        excludeId: excludeId,
        skillEntries: skillEntries,
        items: items,
        factionEntries: factionEntries,
        creatureEntries: creatureEntries,
      )) {
    return sectionError;
  }

  if (section == NovelWorkspaceSection.foreshadowings &&
      _foreshadowingTitleExistsForDuplicateTitle(
        title: title,
        excludeId: excludeId,
        foreshadowings: foreshadowings,
      )) {
    return sectionError;
  }

  return null;
}
