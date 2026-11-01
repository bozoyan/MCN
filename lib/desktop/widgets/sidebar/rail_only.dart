// 职责: 集中定义桌面工作区只保留导航 Rail 的页面集合。
// 关联文件:
//   lib/desktop/widgets/sidebar/sidebar.dart
//   lib/desktop/pages/novel_editor_support.dart
//   lib/shared/models/novel_workspace.dart
import '../../../shared/models/novel_workspace.dart';

bool isRailOnlyWorkspaceSection(NovelWorkspaceSection section) {
  return section == NovelWorkspaceSection.overview ||
      section == NovelWorkspaceSection.maps;
}
