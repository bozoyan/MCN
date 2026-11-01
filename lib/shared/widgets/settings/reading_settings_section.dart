// 职责: 共享阅读设置区 — 阅读字体、字号、字距、行高、段落间距、页边距、背景主题、翻页方式、加粗。
// 关联文件:
//   lib/shared/widgets/settings/settings_section_widgets.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/reading/reading_font_family_picker.dart
//   lib/shared/widgets/reading/reading_theme_palette.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../components/reveric_switch.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/settings_providers.dart';
import '../../theme/theme.dart';
import '../reading/reading_font_family_picker.dart';
import '../reading/reading_settings_controls.dart';
import '../reading/reading_theme_palette.dart';
import 'settings_section_widgets.dart';

/// 阅读设置 section：排版（字体/字号/字距/行高/段落间距/页边距/加粗） + 背景 + 翻页。
class ReadingSettingsSection extends StatelessWidget {
  const ReadingSettingsSection({super.key, required this.platform});

  /// 翻页方式只对当前端生效，设置页只展示宿主平台的那一项。
  final ReadingSettingsPlatform platform;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ReadingTypographySection(),
          const SizedBox(height: RevericSpacing.x4l),
          const _ReadingBackgroundSection(),
          const SizedBox(height: RevericSpacing.x4l),
          switch (platform) {
            ReadingSettingsPlatform.desktop =>
              const _DesktopReadingModeSection(),
            ReadingSettingsPlatform.mobile => const _MobileReadingModeSection(),
          },
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 排版 section
// ---------------------------------------------------------------------------

class _ReadingTypographySection extends ConsumerWidget {
  const _ReadingTypographySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFont = ref.watch(readingFontFamilyProvider);
    final currentSize = ref.watch(readingFontSizeProvider);
    final currentLetterSpacing = ref.watch(readingLetterSpacingProvider);
    final currentLineHeight = ref.watch(readingLineHeightProvider);
    final currentParagraphSpacing = ref.watch(readingParagraphSpacingProvider);
    final currentMargin = ref.watch(readingMarginProvider);
    final bold = ref.watch(readingBoldProvider);
    final settingsAsync = ref.watch(appSettingsProvider);
    final language = settingsAsync.maybeWhen(
      data: (settings) => settings.language,
      orElse: () => 'zh_CN',
    );
    final notifier = ref.read(appSettingsProvider.notifier);
    final usesDefaultTypography =
        currentFont == AppSettings.defaultFontFamilyForLanguage(language) &&
        currentSize == AppSettings.defaultReadingFontSize &&
        currentLetterSpacing == AppSettings.defaultReadingLetterSpacing &&
        currentLineHeight == AppSettings.defaultReadingLineHeight &&
        currentParagraphSpacing == AppSettings.defaultReadingParagraphSpacing &&
        currentMargin == AppSettings.defaultReadingMargin &&
        bold == AppSettings.defaultReadingBold;

    return SettingsSection(
      titleKey: LocaleKeys.settingsReadingSection,
      descriptionKey: LocaleKeys.settingsReadingDescription,
      trailing: usesDefaultTypography
          ? null
          : _ReadingResetTypographyButton(
              onPressed: notifier.resetReadingTypography,
            ),
      child: SettingsCard(
        children: [
          _ReadingPreview(
            fontFamily: currentFont,
            fontSize: currentSize,
            letterSpacing: currentLetterSpacing,
            lineHeight: currentLineHeight,
            bold: bold,
          ),
          const SettingsRowDivider(),
          const SettingsRow(
            labelKey: LocaleKeys.settingsReadingFont,
            child: ReadingFontFamilyPicker(),
          ),
          const SettingsRowDivider(),
          SettingsRow(
            labelKey: LocaleKeys.settingsReadingFontSize,
            child: _ReadingMetricSlider(
              value: currentSize.toDouble(),
              min: 12,
              max: 36,
              divisions: 24,
              valueLabel: '$currentSize',
              onChanged: (v) => notifier.setReadingFontSize(v.round()),
            ),
          ),
          const SettingsRowDivider(),
          SettingsRow(
            labelKey: LocaleKeys.settingsReadingLetterSpacing,
            child: _ReadingMetricSlider(
              value: currentLetterSpacing,
              min: -1,
              max: 4,
              divisions: 50,
              valueLabel: currentLetterSpacing.toStringAsFixed(1),
              onChanged: notifier.setReadingLetterSpacing,
            ),
          ),
          const SettingsRowDivider(),
          SettingsRow(
            labelKey: LocaleKeys.settingsReadingLineHeight,
            child: _ReadingMetricSlider(
              value: currentLineHeight,
              min: 1.2,
              max: 2.8,
              divisions: 32,
              valueLabel: currentLineHeight.toStringAsFixed(2),
              onChanged: notifier.setReadingLineHeight,
            ),
          ),
          const SettingsRowDivider(),
          SettingsRow(
            labelKey: LocaleKeys.settingsReadingParagraphSpacing,
            child: _ReadingMetricSlider(
              value: currentParagraphSpacing,
              min: 0.5,
              max: 3.0,
              divisions: 25,
              valueLabel: currentParagraphSpacing.toStringAsFixed(1),
              onChanged: notifier.setReadingParagraphSpacing,
            ),
          ),
          const SettingsRowDivider(),
          SettingsRow(
            labelKey: LocaleKeys.settingsReadingMargin,
            child: _ReadingMetricSlider(
              value: currentMargin,
              min: 8,
              max: 96,
              divisions: 22,
              valueLabel: currentMargin.round().toString(),
              onChanged: notifier.setReadingMargin,
            ),
          ),
          const SettingsRowDivider(),
          SettingsRow(
            labelKey: LocaleKeys.settingsReadingBold,
            child: Align(
              alignment: Alignment.centerLeft,
              child: RevericSwitch(
                value: bold,
                onChanged: notifier.setReadingBold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 背景主题 section
// ---------------------------------------------------------------------------

class _ReadingBackgroundSection extends ConsumerWidget {
  const _ReadingBackgroundSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(readingBackgroundThemeProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return SettingsSection(
      titleKey: LocaleKeys.settingsReadingBackgroundTheme,
      child: SettingsCard(
        children: [
          Wrap(
            spacing: RevericSpacing.sm,
            runSpacing: RevericSpacing.sm,
            children: [
              for (final t in ReadingBackgroundTheme.values)
                _ReadingToggleChip(
                  label: _backgroundThemeLabel(t, context),
                  isSelected: t == theme,
                  colorPreview: _backgroundThemeColor(t),
                  onTap: () => notifier.setReadingBackgroundTheme(t),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _backgroundThemeLabel(
    ReadingBackgroundTheme t,
    BuildContext context,
  ) {
    return switch (t) {
      ReadingBackgroundTheme.white => context.t(
        LocaleKeys.settingsReadingBackgroundThemeWhite,
      ),
      ReadingBackgroundTheme.sepia => context.t(
        LocaleKeys.settingsReadingBackgroundThemeSepia,
      ),
      ReadingBackgroundTheme.cream => context.t(
        LocaleKeys.settingsReadingBackgroundThemeCream,
      ),
      ReadingBackgroundTheme.eye_care => context.t(
        LocaleKeys.settingsReadingBackgroundThemeEyeCare,
      ),
      ReadingBackgroundTheme.dark => context.t(
        LocaleKeys.settingsReadingBackgroundThemeDark,
      ),
      ReadingBackgroundTheme.night => context.t(
        LocaleKeys.settingsReadingBackgroundThemeNight,
      ),
    };
  }

  static Color _backgroundThemeColor(ReadingBackgroundTheme t) {
    return ReadingPalette.of(t).background;
  }
}

// ---------------------------------------------------------------------------
// 平台阅读模式 section
// ---------------------------------------------------------------------------

class _DesktopReadingModeSection extends ConsumerWidget {
  const _DesktopReadingModeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(desktopReadingModeProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return SettingsSection(
      titleKey: LocaleKeys.settingsReadingPageTurn,
      child: SettingsCard(
        children: [
          Wrap(
            spacing: RevericSpacing.sm,
            runSpacing: RevericSpacing.sm,
            children: [
              for (final option in DesktopReadingMode.values)
                _ReadingToggleChip(
                  label: _desktopModeLabel(option, context),
                  isSelected: option == mode,
                  onTap: () => notifier.setDesktopReadingMode(option),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _desktopModeLabel(
    DesktopReadingMode mode,
    BuildContext context,
  ) {
    return switch (mode) {
      DesktopReadingMode.chapter => context.t(
        LocaleKeys.settingsDesktopReadingChapter,
      ),
      DesktopReadingMode.continuous_scroll => context.t(
        LocaleKeys.settingsDesktopReadingContinuousScroll,
      ),
    };
  }
}

class _MobileReadingModeSection extends ConsumerWidget {
  const _MobileReadingModeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(mobileReadingModeProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return SettingsSection(
      titleKey: LocaleKeys.settingsReadingPageTurn,
      child: SettingsCard(
        children: [
          Wrap(
            spacing: RevericSpacing.sm,
            runSpacing: RevericSpacing.sm,
            children: [
              for (final option in MobileReadingMode.values)
                _ReadingToggleChip(
                  label: _mobileModeLabel(option, context),
                  isSelected: option == mode,
                  onTap: () => notifier.setMobileReadingMode(option),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _mobileModeLabel(MobileReadingMode mode, BuildContext context) {
    return switch (mode) {
      MobileReadingMode.vertical_scroll => context.t(
        LocaleKeys.settingsMobileReadingScroll,
      ),
      MobileReadingMode.horizontal_page => context.t(
        LocaleKeys.settingsMobileReadingHorizontal,
      ),
    };
  }
}

// ---------------------------------------------------------------------------
// Reusable controls
// ---------------------------------------------------------------------------

class _ReadingResetTypographyButton extends StatelessWidget {
  const _ReadingResetTypographyButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const RevericIcon(RevericIcons.undo, size: 14),
      label: Text(context.t(LocaleKeys.settingsReadingResetTypography)),
    );
  }
}

class _ReadingPreview extends StatelessWidget {
  const _ReadingPreview({
    required this.fontFamily,
    required this.fontSize,
    required this.letterSpacing,
    required this.lineHeight,
    required this.bold,
  });

  final String fontFamily;
  final int fontSize;
  final double letterSpacing;
  final double lineHeight;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: RevericSpacing.md),
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(LocaleKeys.readingFontPreview),
            style: TextStyle(
              color: colors.textPrimary,
              fontFamily: fontFamily,
              fontSize: (fontSize + 6).toDouble(),
              height: lineHeight,
              letterSpacing: letterSpacing,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            'The quick brown fox jumps over the lazy dog.',
            style: TextStyle(
              color: colors.textPrimary,
              fontFamily: fontFamily,
              fontSize: fontSize.toDouble(),
              height: lineHeight,
              letterSpacing: letterSpacing,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            '秋风萧瑟天气凉，草木摇落露为霜。',
            style: TextStyle(
              color: colors.textPrimary,
              fontFamily: fontFamily,
              fontSize: fontSize.toDouble(),
              height: lineHeight,
              letterSpacing: letterSpacing,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingToggleChip extends StatelessWidget {
  const _ReadingToggleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.colorPreview,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? colorPreview;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final bg = isSelected ? colors.selected : Colors.transparent;
    final borderColor = isSelected ? colors.accent : colors.borderSubtle;
    final textColor = isSelected ? colors.textPrimary : colors.textSecondary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.hover,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: RevericSpacing.sm,
            horizontal: RevericSpacing.lg,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RevericRadius.medium),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (colorPreview != null) ...[
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: colorPreview,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.borderSubtle),
                  ),
                ),
                const SizedBox(width: RevericSpacing.sm),
              ],
              Text(
                label,
                style: typo.uiSmall.copyWith(
                  color: textColor,
                  fontWeight: isSelected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingMetricSlider extends StatelessWidget {
  const _ReadingMetricSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              activeColor: colors.accent,
              inactiveColor: colors.border,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: RevericSpacing.md),
        Container(
          constraints: const BoxConstraints(minWidth: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.small),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            valueLabel,
            style: typo.uiSmallSemibold.copyWith(color: colors.accent),
          ),
        ),
      ],
    );
  }
}
