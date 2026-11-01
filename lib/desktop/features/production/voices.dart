// 职责: 管理角色共用的参考音频：就地试听、导入、添加内置音色、重命名与解除关联。
// 关联文件:
//   lib/shared/services/production/voices.dart
//   lib/desktop/features/production/support.dart
//   lib/desktop/features/production/voice_name.dart
//   lib/desktop/features/production/voice_row.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:video_player/video_player.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/components/reveric_placeholder.dart';
import '../../../shared/database/app_database.dart' show AssetRow;
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/services/production/canvas_service.dart';
import '../../../shared/services/production/voices.dart';
import '../../../shared/theme/theme.dart';
import 'support.dart';
import 'voice_name.dart';
import 'builtin_voices.dart';
import 'voice_preview.dart';
import 'voice_row.dart';

Future<void> showProductionVoices(
  BuildContext context,
  ProductionCanvasService service,
  String characterId,
) => showRevericDialog<void>(
  context: context,
  builder: (_) =>
      ProductionVoicesDialog(service: service, characterId: characterId),
);

class ProductionVoicesDialog extends HookWidget {
  const ProductionVoicesDialog({
    super.key,
    required this.service,
    required this.characterId,
  });
  final ProductionCanvasService service;
  final String characterId;

  @override
  Widget build(BuildContext context) {
    final character = useStream(
      useMemoized(() => service.watchVoiceCharacter(characterId), [
        service,
        characterId,
      ]),
    );
    final busy = useState(false);
    final preview = useVoicePreview();
    Future<void> run(Future<void> Function() action) async {
      if (busy.value) {
        return;
      }
      busy.value = true;
      try {
        await productionRun(context, action);
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    }

    Future<void> add(Future<AssetRow?> Function() pick) => run(() async {
      final asset = await pick();
      if (asset != null) {
        await service.addCharacterVoice(characterId, asset.id);
      }
    });

    final voices = character.data?.voices ?? const [];
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return RevericDialog.panel(
      width: 480,
      title: Text(
        character.data == null
            ? context.t(LocaleKeys.productionVoices)
            : '${character.data!.name} · ${context.t(LocaleKeys.productionVoices)}',
      ),
      content: character.hasError
          ? RevericPlaceholder.error(
              title: context.t(LocaleKeys.commonLoadFailed),
            )
          : !character.hasData
          ? const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.t(LocaleKeys.productionVoicesHint),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: RevericSpacing.md),
                  if (voices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: RevericSpacing.x3l,
                      ),
                      child: RevericPlaceholder.empty(
                        icon: RevericIcons.music_notes,
                        title: context.t(LocaleKeys.productionVoicesEmpty),
                      ),
                    ),
                  for (final voice in voices)
                    ProductionVoiceRow(
                      key: ValueKey('voice-${voice.assetId}'),
                      name: voice.name.isEmpty
                          ? context.t(LocaleKeys.commonUntitled)
                          : voice.name,
                      playing: preview.playing == voice.assetId,
                      onPlay: () => productionRun(
                        context,
                        () => preview.toggle(voice.assetId, () async {
                          final asset = await service.requireAsset(
                            voice.assetId,
                          );
                          final file = await service.requireFile(
                            asset.path!,
                            type: 'audio',
                          );
                          return VideoPlayerController.file(
                            File(service.library.resolvePath(file.path)),
                          );
                        }),
                      ),
                      trailing: [
                        RevericIconButton(
                          icon: RevericIcons.edit_outlined,
                          tooltip: context.t(LocaleKeys.commonRename),
                          onPressed: busy.value
                              ? null
                              : () => showRevericDialog<void>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => ProductionVoiceName(
                                    service: service,
                                    characterId: characterId,
                                    voice: voice,
                                  ),
                                ),
                        ),
                        RevericIconButton(
                          icon: RevericIcons.link_off,
                          tooltip: context.t(LocaleKeys.commonRemove),
                          onPressed: busy.value
                              ? null
                              : () => run(
                                  () => service.removeCharacterVoice(
                                    characterId,
                                    voice.assetId,
                                  ),
                                ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.productionBuiltinVoices),
          icon: RevericIcons.music_notes,
          onPressed: busy.value || !character.hasData
              ? null
              : () => add(() => pickProductionBuiltinVoice(context, service)),
        ),
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonImport),
          loading: busy.value,
          onPressed: !character.hasData
              ? null
              : () => add(
                  () => pickProductionAsset(
                    context,
                    service,
                    types: const {'audio'},
                  ),
                ),
        ),
        RevericButton.text(
          label: context.t(LocaleKeys.commonClose),
          onPressed: busy.value ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
