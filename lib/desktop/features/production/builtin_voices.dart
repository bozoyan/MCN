// 职责: 展示应用内置音色，就地试听，选定后导入并返回当前作品的音频资产。
// 关联文件:
//   lib/shared/models/production/builtin_voices.dart
//   lib/shared/services/production/builtin_voice_orchestrator.dart
//   lib/desktop/features/production/asset_picker.dart
//   lib/desktop/features/production/voice_row.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/database/app_database.dart' show AssetRow;
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/production/builtin_voices.dart';
import '../../../shared/services/production/builtin_voice_orchestrator.dart';
import '../../../shared/services/production/canvas_service.dart';
import 'package:video_player/video_player.dart';
import 'support.dart';
import 'voice_preview.dart';
import 'voice_row.dart';

Future<AssetRow?> pickProductionBuiltinVoice(
  BuildContext context,
  ProductionCanvasService service,
) => showRevericDialog<AssetRow>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ProductionBuiltinVoicesPicker(service: service),
);

class ProductionBuiltinVoicesPicker extends HookWidget {
  const ProductionBuiltinVoicesPicker({super.key, required this.service});
  final ProductionCanvasService service;

  @override
  Widget build(BuildContext context) {
    final picked = useState<BuiltinVoice?>(null);
    final busy = useState(false);
    final preview = useVoicePreview();
    Future<void> confirm() async {
      final voice = picked.value;
      if (voice == null || busy.value) {
        return;
      }
      busy.value = true;
      try {
        await productionRun(context, () async {
          final asset = await BuiltinVoiceOrchestrator().run(
            library: service.library,
            novelId: service.novelId,
            voice: voice,
            name: context.t(voice.nameKey),
          );
          if (context.mounted) {
            Navigator.of(context).pop(asset);
          }
        });
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    }

    return PopScope(
      canPop: !busy.value,
      child: RevericDialog.panel(
        width: 420,
        title: Text(context.t(LocaleKeys.productionBuiltinVoices)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final voice in productionBuiltinVoices)
                ProductionVoiceRow(
                  key: ValueKey('builtin-voice-${voice.id}'),
                  name: context.t(voice.nameKey),
                  detail: '${(voice.durationMs / 1000).toStringAsFixed(1)}s',
                  playing: preview.playing == voice.id,
                  selected: picked.value == voice,
                  onPlay: () => productionRun(
                    context,
                    () => preview.toggle(
                      voice.id,
                      () async => VideoPlayerController.asset(voice.bundlePath),
                    ),
                  ),
                  onTap: busy.value ? null : () => picked.value = voice,
                ),
            ],
          ),
        ),
        actions: [
          RevericButton.text(
            label: context.t(LocaleKeys.commonCancel),
            onPressed: busy.value ? null : () => Navigator.of(context).pop(),
          ),
          RevericButton.primary(
            label: context.t(LocaleKeys.commonConfirm),
            loading: busy.value,
            onPressed: picked.value == null ? null : confirm,
          ),
        ],
      ),
    );
  }
}
