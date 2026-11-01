// 职责: 阅读设置控件组 — 按平台密度组织排版、外观与翻页设置，并写入阅读偏好。
// 关联文件:
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/reading/reading_theme_palette.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../components/reveric_switch.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/settings_providers.dart';
import '../../theme/theme.dart';
import 'reading_font_family_picker.dart';
import 'reading_theme_palette.dart';

enum ReadingSettingsPlatform { desktop, mobile }

/// 阅读设置的跨端主体。桌面端在宽容器中并列显示排版组，移动端保持单列。
class ReadingSettingsControls extends ConsumerWidget {
  const ReadingSettingsControls({
    super.key,
    required this.compact,
    required this.platform,
  });

  final bool compact;
  final ReadingSettingsPlatform platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final notifier = ref.read(appSettingsProvider.notifier);

    final fontSize = ref.watch(readingFontSizeProvider);
    final letterSpacing = ref.watch(readingLetterSpacingProvider);
    final lineHeight = ref.watch(readingLineHeightProvider);
    final paragraphSpacing = ref.watch(readingParagraphSpacingProvider);
    final margin = ref.watch(readingMarginProvider);
    final bold = ref.watch(readingBoldProvider);
    final backgroundTheme = ref.watch(readingBackgroundThemeProvider);
    final desktopMode = ref.watch(desktopReadingModeProvider);
    final mobileMode = ref.watch(mobileReadingModeProvider);
    final groupGap = compact ? RevericSpacing.x3l : RevericSpacing.x4l;

    final typographyGroup = _ReadingSettingsGroup(
      title: context.t(LocaleKeys.settingsReadingGroupTypography),
      colors: colors,
      typo: typo,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
          child: _ReadingSettingField(
            label: context.t(LocaleKeys.settingsReadingFont),
            child: const ReadingFontFamilyPicker(),
          ),
        ),
        _ReadingSettingSlider(
          label: context.t(LocaleKeys.settingsReadingFontSize),
          value: fontSize.toDouble(),
          min: 12,
          max: 36,
          divisions: 24,
          valueLabel: '$fontSize',
          colors: colors,
          typo: typo,
          onChanged: (value) => notifier.setReadingFontSize(value.round()),
        ),
        _ReadingSettingToggle(
          label: context.t(LocaleKeys.settingsReadingBold),
          value: bold,
          colors: colors,
          typo: typo,
          onChanged: notifier.setReadingBold,
        ),
      ],
    );
    final layoutGroup = _ReadingSettingsGroup(
      title: context.t(LocaleKeys.settingsReadingGroupLayout),
      colors: colors,
      typo: typo,
      children: [
        _ReadingSettingSlider(
          label: context.t(LocaleKeys.settingsReadingLetterSpacing),
          value: letterSpacing,
          min: -1,
          max: 4,
          divisions: 50,
          valueLabel: letterSpacing.toStringAsFixed(2),
          colors: colors,
          typo: typo,
          onChanged: notifier.setReadingLetterSpacing,
        ),
        _ReadingSettingSlider(
          label: context.t(LocaleKeys.settingsReadingLineHeight),
          value: lineHeight,
          min: 1.2,
          max: 2.8,
          divisions: 32,
          valueLabel: lineHeight.toStringAsFixed(2),
          colors: colors,
          typo: typo,
          onChanged: notifier.setReadingLineHeight,
        ),
        _ReadingSettingSlider(
          label: context.t(LocaleKeys.settingsReadingParagraphSpacing),
          value: paragraphSpacing,
          min: 0.5,
          max: 3.0,
          divisions: 25,
          valueLabel: paragraphSpacing.toStringAsFixed(2),
          colors: colors,
          typo: typo,
          onChanged: notifier.setReadingParagraphSpacing,
        ),
        _ReadingSettingSlider(
          label: context.t(LocaleKeys.settingsReadingMargin),
          value: margin,
          min: 8,
          max: 96,
          divisions: 22,
          valueLabel: margin.toStringAsFixed(0),
          colors: colors,
          typo: typo,
          onChanged: notifier.setReadingMargin,
        ),
      ],
    );
    final experienceGroup = _ReadingSettingsGroup(
      title: context.t(LocaleKeys.settingsReadingGroupExperience),
      colors: colors,
      typo: typo,
      children: [
        _ReadingSettingField(
          label: context.t(LocaleKeys.settingsReadingBackgroundTheme),
          child: _ReadingBackgroundThemePicker(
            value: backgroundTheme,
            colors: colors,
            typo: typo,
            onChanged: notifier.setReadingBackgroundTheme,
          ),
        ),
        const SizedBox(height: RevericSpacing.x2l),
        _ReadingSettingField(
          label: context.t(LocaleKeys.settingsReadingPageTurn),
          child: switch (platform) {
            ReadingSettingsPlatform.desktop =>
              _ReadingModeSelector<DesktopReadingMode>(
                value: desktopMode,
                colors: colors,
                typo: typo,
                options: [
                  _ReadingModeOption(
                    value: DesktopReadingMode.chapter,
                    label: context.t(LocaleKeys.settingsDesktopReadingChapter),
                  ),
                  _ReadingModeOption(
                    value: DesktopReadingMode.continuous_scroll,
                    label: context.t(
                      LocaleKeys.settingsDesktopReadingContinuousScroll,
                    ),
                  ),
                ],
                onChanged: notifier.setDesktopReadingMode,
              ),
            ReadingSettingsPlatform.mobile =>
              _ReadingModeSelector<MobileReadingMode>(
                value: mobileMode,
                colors: colors,
                typo: typo,
                options: [
                  _ReadingModeOption(
                    value: MobileReadingMode.vertical_scroll,
                    label: context.t(LocaleKeys.settingsMobileReadingScroll),
                  ),
                  _ReadingModeOption(
                    value: MobileReadingMode.horizontal_page,
                    label: context.t(
                      LocaleKeys.settingsMobileReadingHorizontal,
                    ),
                  ),
                ],
                onChanged: notifier.setMobileReadingMode,
              ),
          },
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = !compact && constraints.maxWidth >= 620;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (useTwoColumns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        typographyGroup,
                        SizedBox(height: groupGap),
                        experienceGroup,
                      ],
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.x5l),
                  Expanded(child: layoutGroup),
                ],
              )
            else ...[
              typographyGroup,
              SizedBox(height: groupGap),
              layoutGroup,
              SizedBox(height: groupGap),
              experienceGroup,
            ],
          ],
        );
      },
    );
  }
}

/// 设置面板底部的恢复默认操作，由平台外壳决定停靠位置。
class ReadingSettingsResetButton extends StatelessWidget {
  const ReadingSettingsResetButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return TextButton.icon(
      onPressed: onPressed,
      icon: RevericIcon(
        RevericIcons.arrow_counter_clockwise,
        size: 16,
        color: colors.textSecondary,
      ),
      label: Text(
        context.t(LocaleKeys.settingsReadingResetTypography),
        style: typo.uiSemibold.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

class _ReadingSettingsGroup extends StatelessWidget {
  const _ReadingSettingsGroup({
    required this.title,
    required this.colors,
    required this.typo,
    required this.children,
  });

  final String title;
  final RevericColors colors;
  final RevericTypography typo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: typo.uiSemibold.copyWith(color: colors.textPrimary)),
        const SizedBox(height: RevericSpacing.sm),
        ...children,
      ],
    );
  }
}

class _ReadingSettingSlider extends StatelessWidget {
  const _ReadingSettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.colors,
    required this.typo,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final RevericColors colors;
  final RevericTypography typo;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: typo.ui.copyWith(color: colors.textSecondary),
                ),
              ),
              Text(
                valueLabel,
                style: typo.uiSmall.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ReadingSettingToggle extends StatelessWidget {
  const _ReadingSettingToggle({
    required this.label,
    required this.value,
    required this.colors,
    required this.typo,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final RevericColors colors;
  final RevericTypography typo;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: SizedBox(
          height: RevericSizes.buttonHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: typo.ui.copyWith(color: colors.textSecondary),
                ),
              ),
              RevericSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingSettingField extends StatelessWidget {
  const _ReadingSettingField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: typo.ui.copyWith(color: colors.textSecondary)),
        const SizedBox(height: RevericSpacing.sm),
        child,
      ],
    );
  }
}

class _ReadingBackgroundThemePicker extends StatelessWidget {
  const _ReadingBackgroundThemePicker({
    required this.value,
    required this.colors,
    required this.typo,
    required this.onChanged,
  });

  final ReadingBackgroundTheme value;
  final RevericColors colors;
  final RevericTypography typo;
  final ValueChanged<ReadingBackgroundTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: RevericSpacing.sm,
      runSpacing: RevericSpacing.sm,
      children: [
        for (final theme in ReadingBackgroundTheme.values)
          _ReadingBackgroundThemeOption(
            key: ValueKey('reading-background-theme-${theme.name}'),
            label: _backgroundThemeLabel(context, theme),
            color: ReadingPalette.of(theme).background,
            selected: theme == value,
            colors: colors,
            typo: typo,
            onTap: () => onChanged(theme),
          ),
      ],
    );
  }

  String _backgroundThemeLabel(BuildContext context, ReadingBackgroundTheme t) {
    switch (t) {
      case ReadingBackgroundTheme.white:
        return context.t(LocaleKeys.settingsReadingBackgroundThemeWhite);
      case ReadingBackgroundTheme.sepia:
        return context.t(LocaleKeys.settingsReadingBackgroundThemeSepia);
      case ReadingBackgroundTheme.cream:
        return context.t(LocaleKeys.settingsReadingBackgroundThemeCream);
      case ReadingBackgroundTheme.eye_care:
        return context.t(LocaleKeys.settingsReadingBackgroundThemeEyeCare);
      case ReadingBackgroundTheme.dark:
        return context.t(LocaleKeys.settingsReadingBackgroundThemeDark);
      case ReadingBackgroundTheme.night:
        return context.t(LocaleKeys.settingsReadingBackgroundThemeNight);
    }
  }
}

class _ReadingBackgroundThemeOption extends StatelessWidget {
  const _ReadingBackgroundThemeOption({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.colors,
    required this.typo,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final RevericColors colors;
  final RevericTypography typo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colors.selected : colors.surfaceContainer,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Container(
          height: RevericSizes.fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RevericRadius.medium),
            border: Border.all(
              color: selected ? colors.accent : colors.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: RevericSpacing.lg,
                height: RevericSpacing.lg,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.borderSubtle),
                ),
              ),
              const SizedBox(width: RevericSpacing.xs),
              Text(
                label,
                style: (selected ? typo.uiSemibold : typo.uiSmall).copyWith(
                  color: colors.textPrimary,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: RevericSpacing.xs),
                RevericIcon(
                  RevericIcons.check,
                  size: 14,
                  color: colors.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingModeSelector<T> extends StatelessWidget {
  const _ReadingModeSelector({
    required this.value,
    required this.colors,
    required this.typo,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final RevericColors colors;
  final RevericTypography typo;
  final List<_ReadingModeOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.xxs),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: _ReadingTransitionOption(
                label: option.label,
                selected: option.value == value,
                colors: colors,
                typo: typo,
                onTap: () => onChanged(option.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadingModeOption<T> {
  const _ReadingModeOption({required this.value, required this.label});

  final T value;
  final String label;
}

class _ReadingTransitionOption extends StatelessWidget {
  const _ReadingTransitionOption({
    required this.label,
    required this.selected,
    required this.colors,
    required this.typo,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final RevericColors colors;
  final RevericTypography typo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: RevericSizes.buttonHeight,
        padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.xs),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.selected : null,
          borderRadius: BorderRadius.circular(RevericRadius.medium),
        ),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: (selected ? typo.uiTinySemibold : typo.uiTiny).copyWith(
            color: selected ? colors.textPrimary : colors.textMuted,
          ),
        ),
      ),
    );
  }
}
