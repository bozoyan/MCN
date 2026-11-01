// 职责: 章节手动保存的修改历史写入 — 对比新旧 title/outline/content，stage 变更并提交 manual commit，供桌面与移动端复用。
// 关联文件:
//   lib/shared/services/working_overlay.dart
//   lib/shared/models/chapter.dart
//   lib/desktop/pages/novel_editor.dart
//   lib/mobile/pages/chapter_editor_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/history.json
//   assets/translations/zh-CN/history.json
import 'novel_content.dart';
import 'working_overlay.dart';

/// 章节手动保存的 manual commit 消息 key（与桌面历史文案一致）。
const String chapterManualSaveMessage =
    'history.commit_message.manual_chapter_save';

/// 从数据库读取最新章节作为基线，再按字段 stage 文本变更并提交
/// 一条 manual commit。基线不由 UI provider 快照提供，避免连续保存时重复记录
/// 旧版本。
///
/// 与桌面 [NovelEditorPage.saveChapter] 行为一致：仅对实际变化的字段（title /
/// outline / content）调用 [WorkingOverlayService.stageTextChange]，再以
/// `manual_chapter_save` 消息 [commitManualSave]。无变更时不提交。
///
/// 返回是否有字段变化（即是否产生了 commit）。
Future<bool> commitChapterManualSave(
  WorkingOverlayService overlay,
  NovelContentService contentService, {
  required String chapterId,
  required String newTitle,
  required String newOutline,
  required String newContent,
}) async {
  final before = await contentService.getChapterById(chapterId);
  if (before == null) {
    return false;
  }
  final trimmedTitle = newTitle.trim();
  final changeIds = <String>[];
  if (before.title != trimmedTitle) {
    final change = await overlay.stageTextChange(
      resourcePath: '/chapters/$chapterId/title',
      resourceType: 'chapters',
      resourceId: chapterId,
      field: 'title',
      oldText: before.title ?? '',
      newText: trimmedTitle,
      source: workingChangeSourceManual,
      summary: 'Update chapter title',
    );
    changeIds.add(change.id);
  }
  if (before.outline != newOutline) {
    final change = await overlay.stageTextChange(
      resourcePath: '/chapters/$chapterId/outline',
      resourceType: 'chapters',
      resourceId: chapterId,
      field: 'outline',
      oldText: before.outline,
      newText: newOutline,
      source: workingChangeSourceManual,
      summary: 'Update chapter outline',
    );
    changeIds.add(change.id);
  }
  if (before.content != newContent) {
    final change = await overlay.stageTextChange(
      resourcePath: '/chapters/$chapterId/content',
      resourceType: 'chapters',
      resourceId: chapterId,
      field: 'content',
      oldText: before.content,
      newText: newContent,
      source: workingChangeSourceManual,
      summary: 'Update chapter content',
    );
    changeIds.add(change.id);
  }
  if (changeIds.isEmpty) {
    return false;
  }
  await overlay.commitManualSave(
    manualChangeIds: changeIds,
    resourceScopes: ['/chapters/$chapterId'],
    manualMessage: chapterManualSaveMessage,
  );
  return true;
}
