// 职责: 承载移动和平板整集文档并保留助手入口，复用双端统一编辑命令。
// 关联文件:
//   lib/shared/widgets/screenplay/document_editor.dart
//   lib/mobile/features/screenplay/character_picker_sheet.dart
//   lib/mobile/features/screenplay/assistant_bar.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/providers/screenplay_workspace_state_provider.dart';
import '../../../shared/widgets/screenplay/document_editor.dart';
import 'character_picker_sheet.dart';
import 'assistant_bar.dart';

class MobileScreenplayDocument extends ConsumerWidget {
  const MobileScreenplayDocument({
    super.key,
    required this.novel,
    required this.registerFlush,
    required this.onOpenAssistant,
  });
  final Novel novel;
  final ValueChanged<Future<void> Function()?> registerFlush;
  final VoidCallback onOpenAssistant;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = novel.contentDatabasePath!;
    final workspace = ref.watch(
      screenplayWorkspaceStateControllerProvider(novel.id, path),
    );
    final episode = workspace.episodeId;
    if (episode == null) {
      return const SizedBox.shrink();
    }
    return ScreenplayDocumentEditor(
      novel: novel,
      scope: ScreenplayEditorScope(episode, selectedSceneId: workspace.sceneId),
      mobile: true,
      registerFlush: registerFlush,
      pickCharacter: (context, element) => showMobileScreenplayCharacterPicker(
        context,
        databasePath: path,
        selectedId: element.characterId,
      ),
      footerBuilder: (context, session) => MobileScreenplayAssistantBar(
        session: session,
        onOpenAssistant: onOpenAssistant,
      ),
    );
  }
}
