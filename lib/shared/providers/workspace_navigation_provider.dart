// 职责: 工作区导航请求信号 — 「最近改动」点击条目时写入请求，novel_editor 监听后切换 selection/主内容区。
// 关联文件:
//   lib/shared/widgets/ai/diff/recent_changes_log.dart
//   lib/desktop/pages/novel_editor.dart
//   lib/shared/models/novel_workspace.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/novel_workspace.dart';

part 'workspace_navigation_provider.g.dart';

/// 一次性工作区导航请求：跳转到 [section] 下的 [itemId]（null 表示该 section 无独立条目，如作品简介）。
class WorkspaceNavigationRequest {
  const WorkspaceNavigationRequest({required this.section, this.itemId});

  final NovelWorkspaceSection section;
  final String? itemId;
}

/// 桌面端「最近改动」→ 工作区跳转的一次性信号。写入后由 novel_editor 监听消费并立即 [clear]。
@Riverpod(keepAlive: true)
class WorkspaceNavigation extends _$WorkspaceNavigation {
  @override
  WorkspaceNavigationRequest? build() => null;

  void request(WorkspaceNavigationRequest value) => state = value;

  void clear() => state = null;
}
