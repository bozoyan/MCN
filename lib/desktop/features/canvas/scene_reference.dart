// 职责: 将画布场次投影显示为本地化标题、季集场号及可打开正文的梗概详情。
// 关联文件:
//   lib/shared/models/canvas_scene_reference.dart
//   lib/shared/providers/canvas_providers.dart
//   lib/desktop/features/canvas/widgets/canvas_node_widget.dart
//   lib/desktop/features/canvas/widgets/canvas_detail_layer.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/components/reveric_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/canvas_scene_reference.dart';
import '../../../shared/providers/canvas_providers.dart';
import '../../../shared/theme/theme.dart';

String canvasSceneTitle(BuildContext context, CanvasSceneReference reference) {
  return reference.scene.title.trim().isEmpty
      ? context.t(
          LocaleKeys.screenplayScene,
          namedArgs: {'number': '${reference.scene.sceneNumber}'},
        )
      : reference.scene.title;
}

String canvasSceneGroupLabel(
  BuildContext context,
  CanvasSceneReference reference,
) {
  final season = context.t(
    LocaleKeys.screenplaySeason,
    namedArgs: {'number': '${reference.season.seasonNumber}'},
  );
  final episode = context.t(
    LocaleKeys.screenplayEpisode,
    namedArgs: {'number': '${reference.episode.episodeNumber}'},
  );
  return '$season / $episode';
}

String canvasSceneLocationLabel(
  BuildContext context,
  CanvasSceneReference reference,
) {
  final scene = context.t(
    LocaleKeys.screenplayScene,
    namedArgs: {'number': '${reference.scene.sceneNumber}'},
  );
  return '${canvasSceneGroupLabel(context, reference)} / $scene';
}

class CanvasSceneReferenceDetails extends ConsumerWidget {
  const CanvasSceneReferenceDetails({
    super.key,
    required this.databasePath,
    required this.sceneId,
    this.onOpen,
  });

  final String databasePath;
  final String sceneId;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = ref
        .watch(canvasSceneReferencesProvider(databasePath))
        .value?[sceneId];
    if (reference == null) {
      return const SizedBox.shrink();
    }
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          canvasSceneTitle(context, reference),
          style: typo.uiSemibold.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: RevericSpacing.xs),
        Text(
          canvasSceneLocationLabel(context, reference),
          style: typo.uiTiny.copyWith(color: colors.textMuted),
        ),
        if (reference.scene.synopsis.isNotEmpty) ...[
          const SizedBox(height: RevericSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              child: SelectableText(
                reference.scene.synopsis,
                style: typo.uiSmall.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ],
        if (onOpen != null) ...[
          const SizedBox(height: RevericSpacing.sm),
          RevericButton.secondary(
            onPressed: () => onOpen!(sceneId),
            size: RevericButtonSize.compact,
            label: context.t(LocaleKeys.canvasOpenScene),
          ),
        ],
      ],
    );
  }
}
