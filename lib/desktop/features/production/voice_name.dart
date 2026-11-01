// 职责: 编辑音色名称，保存失败时保留输入供重试。
// 关联文件:
//   lib/shared/services/production/voices.dart
//   lib/desktop/features/production/voices.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/text-input-ime.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_text_field.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/services/production/canvas_service.dart';
import '../../../shared/services/production/voices.dart';

class ProductionVoiceName extends HookWidget {
  const ProductionVoiceName({
    super.key,
    required this.service,
    required this.characterId,
    required this.voice,
  });
  final ProductionCanvasService service;
  final String characterId;
  final CharacterVoice voice;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: voice.name);
    final busy = useState(false);
    final error = useState<String?>(null);
    Future<void> save() async {
      if (busy.value ||
          controller.value.composing.isValid &&
              !controller.value.composing.isCollapsed) {
        return;
      }
      busy.value = true;
      error.value = null;
      try {
        await service.renameCharacterVoice(
          characterId,
          voice.assetId,
          controller.text,
        );
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } catch (_) {
        // 服务层记录数据库异常和 stack trace。
        if (context.mounted) {
          error.value = context.t(LocaleKeys.commonSaveFailed);
        }
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    }

    return PopScope(
      canPop: !busy.value,
      child: RevericDialog.panel(
        title: Text(context.t(LocaleKeys.commonRename)),
        content: SingleChildScrollView(
          child: RevericTextField(
            controller: controller,
            label: context.t(LocaleKeys.commonName),
            autofocus: true,
            enabled: !busy.value,
            errorText: error.value,
            onSubmitted: (_) => save(),
          ),
        ),
        actions: [
          RevericButton.text(
            label: context.t(LocaleKeys.commonCancel),
            onPressed: busy.value ? null : () => Navigator.of(context).pop(),
          ),
          RevericButton.primary(
            label: context.t(LocaleKeys.commonSave),
            loading: busy.value,
            onPressed: save,
          ),
        ],
      ),
    );
  }
}
