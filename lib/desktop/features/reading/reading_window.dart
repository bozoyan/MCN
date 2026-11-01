// 职责: 在独立子窗口中打开某部作品的阅读页，供编辑剧本时对照原著。
// 关联文件:
//   lib/desktop/widgets/detached_window.dart
//   lib/desktop/features/reading/reading_page.dart
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../../shared/database/app_database.dart';
import '../../widgets/detached_window.dart';
import 'reading_page.dart';

class ReadingWindowSession extends DetachedWindowSession {
  ReadingWindowSession()
    : super(
        placementKey: 'reading_window_placement',
        defaultSize: const Size(760, 880),
        constraints: const BoxConstraints(minWidth: 480, minHeight: 480),
        logModule: 'ReadingWindow',
      );

  Novel? _novel;

  /// 打开 [novel] 的阅读窗口；已打开时切换到该作品并激活窗口。
  Future<void> openNovel(Novel novel, {required DetachedWindowTheme theme}) {
    _novel = novel;
    return open(title: novel.title, theme: theme);
  }
}

class ReadingWindowAnchor extends StatelessWidget {
  const ReadingWindowAnchor({
    super.key,
    required this.session,
    required this.child,
  });

  final ReadingWindowSession session;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DetachedWindowAnchor(
      session: session,
      builder: (context) {
        final novel = session._novel;
        final databasePath = novel?.contentDatabasePath;
        if (novel == null || databasePath == null) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<bool>(
          valueListenable: session.alwaysOnTop,
          builder: (context, pinned, _) => DesktopReadingPage(
            key: ValueKey(novel.id),
            novelId: novel.id,
            novelTitle: novel.title,
            databasePath: databasePath,
            detachedWindow: true,
            pinned: pinned,
            onPinnedChanged: session.supportsAlwaysOnTop
                ? session.setAlwaysOnTop
                : null,
          ),
        );
      },
      child: child,
    );
  }
}
