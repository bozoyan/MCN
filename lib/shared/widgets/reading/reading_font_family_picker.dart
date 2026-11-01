// 职责: 阅读字体选择器 — 列出内置与系统字体、支持自定义字体名，并写入阅读字体偏好。
// 关联文件:
//   lib/shared/widgets/settings/reading_settings_section.dart
//   lib/shared/widgets/reading/reading_settings_controls.dart
//   lib/shared/providers/system_font_providers.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../components/reveric_inputs.dart';
import '../../components/reveric_select.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/settings_providers.dart';
import '../../providers/system_font_providers.dart';
import '../../theme/theme.dart';

const _customFontValue = '__custom_reading_font__';

/// 设置页与阅读页内的阅读设置共用同一个字体选择器。
class ReadingFontFamilyPicker extends HookConsumerWidget {
  const ReadingFontFamilyPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFont = ref.watch(readingFontFamilyProvider);
    final fontFamiliesAsync = ref.watch(systemFontFamiliesProvider);
    final systemFontFamilies = fontFamiliesAsync.hasValue
        ? fontFamiliesAsync.value ?? const <String>[]
        : const <String>[];
    final fontFamilies = [
      ...AppSettings.bundledFontFamilies,
      ...systemFontFamilies.where(
        (font) => !AppSettings.bundledFontFamilies.contains(font),
      ),
    ];
    final notifier = ref.read(appSettingsProvider.notifier);
    final controller = useTextEditingController(text: currentFont);
    final showCustomInput = useState(false);
    final isFontListLoaded = fontFamiliesAsync.hasValue;
    final isCustom = isFontListLoaded && !fontFamilies.contains(currentFont);
    final shouldShowCustomInput = isCustom || showCustomInput.value;
    final selectedFontValue = isCustom ? _customFontValue : currentFont;

    useEffect(() {
      showCustomInput.value = isCustom;
      if (controller.text != currentFont) {
        controller.value = controller.value.copyWith(
          text: currentFont,
          selection: TextSelection.collapsed(offset: currentFont.length),
          composing: TextRange.empty,
        );
      }
      return null;
    }, [currentFont, isCustom]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RevericSelect<String>(
          value: selectedFontValue,
          placeholder: currentFont,
          items: [
            for (final font in fontFamilies)
              RevericSelectItem(value: font, label: font),
            RevericSelectItem(
              value: _customFontValue,
              label: context.t(LocaleKeys.settingsAddCustomProvider),
            ),
          ],
          enabled: !fontFamiliesAsync.isLoading,
          onChanged: (font) {
            if (font == _customFontValue) {
              showCustomInput.value = true;
              return;
            }
            showCustomInput.value = false;
            notifier.setReadingFontFamily(font);
            controller.text = font;
          },
        ),
        _FontListStatus(fontFamiliesAsync: fontFamiliesAsync),
        if (shouldShowCustomInput) ...[
          const SizedBox(height: RevericSpacing.sm),
          RevericInlineActionInput(
            controller: controller,
            hintText: isCustom
                ? currentFont
                : context.t(LocaleKeys.settingsReadingFont),
            actionLabel: context.t(LocaleKeys.commonSave),
            onActionPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                showCustomInput.value = true;
                notifier.setReadingFontFamily(text);
              }
            },
          ),
        ],
      ],
    );
  }
}

class _FontListStatus extends StatelessWidget {
  const _FontListStatus({required this.fontFamiliesAsync});

  final AsyncValue<List<String>> fontFamiliesAsync;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final message = fontFamiliesAsync.when(
      data: (fonts) {
        if (fonts.isEmpty) {
          return context.t(LocaleKeys.settingsEditorFontsUnavailable);
        }
        return null;
      },
      error: (error, stackTrace) =>
          context.t(LocaleKeys.settingsEditorFontsUnavailable),
      loading: () => context.t(LocaleKeys.settingsEditorFontsLoading),
    );
    if (message == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: RevericSpacing.xs),
      child: Text(
        message,
        style: typo.uiSmall.copyWith(color: colors.textMuted),
      ),
    );
  }
}
