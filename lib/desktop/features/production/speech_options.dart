// 职责: 在语音合成工具栏中选择预设或自定义音色，并编辑模型支持的演绎说明。
// 关联文件:
//   lib/desktop/features/production/audio_composer.dart
//   lib/desktop/features/storyboard/edit_form.dart
//   lib/shared/models/audio/config.dart
//   lib/shared/localization/audio_voice_localization.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/audio.json
//   assets/translations/zh-CN/audio.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/form.md
//   .agents/rules/text-input-ime.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_select.dart';
import '../../../shared/components/reveric_text_field.dart';
import '../../../shared/form/form.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/audio_voice_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/audio/config.dart';
import '../../../shared/theme/theme.dart';
import '../storyboard/edit_form.dart';

/// 「自定义音色 ID…」入口的占位值；不会写进表单。
const _customVoice = '\u0000custom';

class ProductionSpeechVoiceSelect extends HookWidget {
  const ProductionSpeechVoiceSelect({
    super.key,
    required this.capability,
    required this.hasReference,
  });
  final AudioModelCapabilities capability;
  final bool hasReference;

  @override
  Widget build(BuildContext context) {
    final form = useFormContext<ShotField>(context);
    final voice = useListenableSelector(
      form,
      () => form.getValue<String>(ShotField.audioVoice) ?? '',
    );
    final typo = RevericTheme.typographyOf(context);
    final custom = voice.isNotEmpty && !capability.voices.contains(voice);
    Future<void> changed(String id) async {
      if (id != _customVoice) {
        form.updateValue(ShotField.audioVoice, id);
        return;
      }
      final entered = await showRevericDialog<String>(
        context: context,
        builder: (_) => _CustomVoiceDialog(initial: custom ? voice : ''),
      );
      if (entered != null && entered.isNotEmpty && context.mounted) {
        form.updateValue(ShotField.audioVoice, entered);
      }
    }

    return SizedBox(
      width: 150,
      child: RevericSelect<String>(
        value: hasReference || voice.isEmpty ? null : voice,
        enabled: !hasReference,
        compact: true,
        dropUp: true,
        height: 30,
        menuWidth: 240,
        maxMenuHeight: 320,
        leadingIcon: RevericIcons.music_notes,
        textStyle: typo.uiSmall,
        placeholder: context.t(
          hasReference
              ? LocaleKeys.productionSpeechUsingReference
              : LocaleKeys.productionVoices,
        ),
        // 预设可能有几十条，自定义入口放最前，不用滚到底才找到。
        items: [
          RevericSelectItem(
            value: _customVoice,
            label: context.t(LocaleKeys.productionSpeechCustomVoice),
          ),
          if (custom) RevericSelectItem(value: voice, label: voice),
          for (final id in capability.voices)
            RevericSelectItem(
              value: id,
              label: localizedAudioVoiceName(
                context,
                id,
                presetIndex: capability.voices.indexOf(id),
              ),
            ),
        ],
        onChanged: changed,
      ),
    );
  }
}

/// 演绎说明独立于台词；模型不支持时不渲染。
class ProductionSpeechInstructions extends StatelessWidget {
  const ProductionSpeechInstructions({super.key, this.autofocus = false});
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: RevericSpacing.sm),
    child: HookedTextFormField<ShotField>(
      fieldHook: ShotField.audioInstructions,
      notifyOnChange: true,
      multiline: true,
      minLines: 1,
      maxLines: 3,
      autofocus: autofocus,
      hintText: context.t(LocaleKeys.productionSpeechInstructionsHint),
    ),
  );
}

class _CustomVoiceDialog extends HookWidget {
  const _CustomVoiceDialog({required this.initial});
  final String initial;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: initial);
    final text = useValueListenable(controller);
    void submit() {
      // 输入法组字未提交时不能取值，否则会带走半个拼音。
      if (text.composing.isValid && !text.composing.isCollapsed) {
        return;
      }
      final id = controller.text.trim();
      if (id.isNotEmpty) {
        Navigator.of(context).pop(id);
      }
    }

    return RevericDialog.panel(
      width: 400,
      title: Text(context.t(LocaleKeys.productionSpeechVoiceId)),
      content: RevericTextField(
        controller: controller,
        autofocus: true,
        hintText: context.t(LocaleKeys.productionSpeechVoiceIdHint),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        RevericButton.text(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        RevericButton.primary(
          label: context.t(LocaleKeys.commonConfirm),
          onPressed: text.text.trim().isEmpty ? null : submit,
        ),
      ],
    );
  }
}
