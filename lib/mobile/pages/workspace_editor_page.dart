// 职责: 移动端作品编辑入口 — 按持久化内容类型分派小说或剧本编辑器。
// 关联文件:
//   lib/mobile/pages/novel_editor_page.dart
//   lib/mobile/features/screenplay/editor_page.dart
//   lib/shared/models/content_kind.dart
//   lib/shared/database/app_database.dart

import 'package:flutter/material.dart';

import '../../shared/database/app_database.dart';
import '../../shared/models/content_kind.dart';
import '../features/screenplay/editor_page.dart';
import 'novel_editor_page.dart';

class MobileWorkspaceEditorPage extends StatelessWidget {
  const MobileWorkspaceEditorPage({
    super.key,
    required this.novel,
    this.initialChatKickoffPrompt,
    this.openChatOnEntry = false,
  });

  final Novel novel;
  final String? initialChatKickoffPrompt;
  final bool openChatOnEntry;

  @override
  Widget build(BuildContext context) {
    if (novel.contentKind == contentKindScreenplay) {
      return MobileScreenplayEditorPage(novel: novel);
    }
    return MobileNovelEditorPage(
      novel: novel,

      initialChatKickoffPrompt: initialChatKickoffPrompt,
      openChatOnEntry: openChatOnEntry,
    );
  }
}
