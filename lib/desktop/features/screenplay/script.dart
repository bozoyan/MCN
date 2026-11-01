// 职责: 将桌面当前集挂接到共享剧本文档编辑器，提供朗读入口并按场次 ID 双向同步定位。
// 关联文件:
//   lib/shared/widgets/screenplay/document_editor.dart
//   lib/shared/providers/screenplay_workspace_state_provider.dart
//   lib/desktop/features/screenplay/character_picker.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/providers/screenplay_workspace_state_provider.dart';
import '../../../shared/widgets/screenplay/document_editor.dart';
import 'character_picker.dart';
import '../narration/button.dart';
export 'script_status.dart';

class ScreenplayScriptRegion extends HookConsumerWidget {
  const ScreenplayScriptRegion({
    super.key,
    required this.novel,
    required this.registerFlush,
  });
  final Novel novel;
  final ValueChanged<Future<void> Function()?> registerFlush;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = novel.contentDatabasePath!;
    final stateProvider = screenplayWorkspaceStateControllerProvider(
      novel.id,
      path,
    );
    final workspace = ref.watch(stateProvider);
    // 正文滚到哪一场，中栏场次列表就跟到哪一场。回调读最新 state 而不是捕获
    // build 时的快照，才能保持稳定 —— 它一变，整棵正文就要重建。
    final onVisibleSceneChanged = useCallback<ValueChanged<String>>((sceneId) {
      final current = ref.read(stateProvider);
      if (current.sceneId == sceneId) {
        return;
      }
      ref
          .read(stateProvider.notifier)
          .update(current.copyWith(sceneId: sceneId));
    }, [stateProvider]);
    final episode = workspace.episodeId;
    if (episode == null) {
      return const SizedBox.shrink();
    }
    return ScreenplayDocumentEditor(
      novel: novel,
      scope: ScreenplayEditorScope(episode, selectedSceneId: workspace.sceneId),
      registerFlush: registerFlush,
      onVisibleSceneChanged: onVisibleSceneChanged,
      toolbarTrailingBuilder: (context, session) => NarrationButton(
        workId: novel.id,
        session: session,
        sceneId: workspace.sceneId,
      ),
      pickCharacter: (context, element) async {
        final box = context.findRenderObject()! as RenderBox;
        final result = await showScreenplayCharacterPickerPopover(
          context,
          anchor: box.localToGlobal(Offset.zero) & box.size,
          databasePath: path,
          selectedId: element.characterId,
        );
        return result?.characterId;
      },
    );
  }
}
