// 职责: 承载移动单场入口，拆场后在同一共享文档范围继续编辑并在退出前 flush。
// 关联文件:
//   lib/shared/widgets/screenplay/document_editor.dart
//   lib/mobile/features/screenplay/character_picker_sheet.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/models/screenplay.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/screenplay/document_editor.dart';
import 'character_picker_sheet.dart';
import 'support.dart';

class MobileScreenplaySceneEditorPage extends HookWidget {
  const MobileScreenplaySceneEditorPage({
    super.key,
    required this.novel,
    required this.scene,
  });

  final Novel novel;
  final ScreenplaySceneSummary scene;

  @override
  Widget build(BuildContext context) {
    final flush = useRef<Future<void> Function()?>(null);
    final allowPop = useState(false);
    Future<void> close() async {
      try {
        await flush.value?.call();
      } catch (_) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      allowPop.value = true;
      await Future<void>.delayed(Duration.zero);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    final colors = RevericTheme.colorsOf(context);
    return PopScope(
      canPop: allowPop.value,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          close();
        }
      },
      child: Scaffold(
        backgroundColor: colors.canvas,
        appBar: AppBar(
          leading: IconButton(
            onPressed: close,
            icon: const RevericIcon(RevericIcons.arrow_back, size: 20),
          ),
          title: Text(mobileSceneLabel(context, scene)),
        ),
        body: MobileScreenplaySceneEditor(
          novel: novel,
          scene: scene,
          registerFlush: (value) => flush.value = value,
        ),
      ),
    );
  }
}

class MobileScreenplaySceneEditor extends StatelessWidget {
  const MobileScreenplaySceneEditor({
    super.key,
    required this.novel,
    required this.scene,
    required this.registerFlush,
  });
  final Novel novel;
  final ScreenplaySceneSummary scene;
  final ValueChanged<Future<void> Function()?> registerFlush;
  @override
  Widget build(BuildContext context) => ScreenplayDocumentEditor(
    novel: novel,
    scope: ScreenplayEditorScope(scene.episodeId, sceneId: scene.id),
    mobile: true,
    registerFlush: registerFlush,
    pickCharacter: (context, element) => showMobileScreenplayCharacterPicker(
      context,
      databasePath: novel.contentDatabasePath!,
      selectedId: element.characterId,
    ),
  );
}
