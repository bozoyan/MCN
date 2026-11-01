// 职责: 从桌面剧本正文打开当前场次起的朗读快照。
// 关联文件:
//   lib/desktop/features/screenplay/script.dart
//   lib/desktop/features/narration/dialog.dart
//   lib/shared/widgets/screenplay/document_session.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/narration.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/screenplay/document_session.dart';
import 'dialog.dart';

class NarrationButton extends HookWidget {
  const NarrationButton({
    super.key,
    required this.workId,
    required this.session,
    this.sceneId,
  });
  final String workId;
  final ScreenplayDocumentSession session;
  final String? sceneId;

  @override
  Widget build(BuildContext context) {
    final composing = useListenableSelector(
      session.controller,
      () => session.controller.isComposing,
    );
    final supported =
        !kIsWeb &&
        {
          TargetPlatform.windows,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform);
    if (!supported) {
      return const SizedBox.shrink();
    }
    return RevericButton.text(
      key: const ValueKey('screenplay-narration'),
      size: RevericButtonSize.compact,
      label: context.t(LocaleKeys.narrationTitle),
      icon: RevericIcons.play_arrow,
      onPressed: composing
          ? null
          : () {
              final controller = session.controller;
              if (sceneId != null &&
                  !controller.screenplay!.sceneOrder.contains(sceneId)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.t(LocaleKeys.narrationMissingScene)),
                  ),
                );
                return;
              }
              final source = NarrationSource(
                document: controller.screenplay!,
                characterNames: controller.characterNames,
                locationNames: controller.locationNames,
                startSceneId: sceneId,
              );
              showRevericDialog<void>(
                context: context,
                builder: (_) => NarrationDialog(workId: workId, source: source),
              );
            },
    );
  }
}
