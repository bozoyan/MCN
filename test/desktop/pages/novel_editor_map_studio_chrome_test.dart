// 职责: 验证 Map Studio 进入时的 AI 面板折叠与工作区返回入口规则。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/pages/novel_editor_support.dart
//   lib/shared/models/novel_workspace.dart
// 遵循的 Rules:
//   .agents/rules/testing.md
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/pages/novel_editor.dart';
import 'package:reveric/desktop/widgets/sidebar/rail_only.dart';
import 'package:reveric/shared/models/novel_workspace.dart';

void main() {
  test('Map Studio defaults to collapsed AI chat', () {
    expect(
      shouldAutoCollapseAiPanelForWorkspaceSection(NovelWorkspaceSection.maps),
      isTrue,
    );
    expect(
      shouldAutoCollapseAiPanelForWorkspaceSection(
        NovelWorkspaceSection.chapters,
      ),
      isFalse,
    );
  });

  test('Map Studio shows the same expanded-sidebar back entry as overview', () {
    for (final section in const [
      NovelWorkspaceSection.overview,
      NovelWorkspaceSection.maps,
    ]) {
      expect(
        shouldShowWorkspaceHeaderBack(
          section: section,
          sidebarCollapsed: false,
          isWindows: false,
        ),
        isTrue,
      );
    }
    expect(
      shouldShowWorkspaceHeaderBack(
        section: NovelWorkspaceSection.chapters,
        sidebarCollapsed: false,
        isWindows: false,
      ),
      isFalse,
    );
  });

  test('Map Studio is a rail-only workspace section', () {
    expect(isRailOnlyWorkspaceSection(NovelWorkspaceSection.maps), isTrue);
    expect(isRailOnlyWorkspaceSection(NovelWorkspaceSection.chapters), isFalse);
  });
}
