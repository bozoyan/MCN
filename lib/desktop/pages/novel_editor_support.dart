// 职责: 桌面端小说编辑页的辅助工具 — 路径解析、章节同步判定、侧栏宽度判定与草稿模型。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/pages/novel_editor_content_selection.dart
part of 'novel_editor.dart';

@visibleForTesting
bool shouldApplyChapterContentStreamValue({
  required String incomingContent,
  required String controllerContent,
  required String? lastSyncedContent,
  required String? pendingLocalSaveContent,
  required bool targetChanged,
}) {
  if (targetChanged) {
    return true;
  }
  if (incomingContent == controllerContent) {
    return false;
  }
  if (incomingContent == pendingLocalSaveContent ||
      incomingContent == lastSyncedContent) {
    return false;
  }
  final hasLocalEdits =
      lastSyncedContent != null && controllerContent != lastSyncedContent;
  return !hasLocalEdits;
}

String _pathBaseName(String path) {
  final normalized = path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
  return normalized.split(Platform.pathSeparator).last;
}

String _textFileTitle(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  return (dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName).trim();
}

enum _AiProcessingExitDecision { background, pause }

enum _DocumentImportSource { file, directory }

class _WorkspaceCreateDraft {
  const _WorkspaceCreateDraft({
    required this.section,
    required this.previousSelection,
    this.parentId,
  });

  final NovelWorkspaceSection section;
  final WorkspaceSelection previousSelection;
  final String? parentId;
}

/// 侧栏外层宽度：overview / 地图 / 规则的内容在 Main，只保留 Rail，
/// 避免 LeftSidebar 内部已收中栏、外层 AnimatedContainer 仍占满留下空条。
/// 封面工作台需要中栏挂生成记录，不算 rail-only。
bool _isRailOnlySidebarWidth(
  WorkspaceSelection selection,
  _EditorContentSelection contentSelection,
) {
  if (contentSelection is _EditorWorkspaceContentSelection &&
      isRailOnlyWorkspaceSection(selection.section)) {
    return true;
  }
  return switch (contentSelection) {
    _EditorAgentRulesListSelection() || _EditorAgentRuleSelection() => true,
    _ => false,
  };
}

@visibleForTesting
bool shouldAutoCollapseAiPanelForWorkspaceSection(
  NovelWorkspaceSection section,
) {
  return section == NovelWorkspaceSection.entity_graph ||
      section == NovelWorkspaceSection.maps;
}

@visibleForTesting
bool shouldShowWorkspaceHeaderBack({
  required NovelWorkspaceSection section,
  required bool sidebarCollapsed,
  required bool isWindows,
}) {
  if (sidebarCollapsed) {
    return isWindows;
  }
  return isRailOnlyWorkspaceSection(section);
}
