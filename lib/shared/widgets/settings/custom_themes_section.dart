// 职责: 展示自定义主题配色与选中状态，通过既有主题命令切换应用主题。
// 关联文件:
//   lib/shared/providers/custom_themes_provider.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/settings/appearance_settings_section.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../logger/app_logger.dart';
import '../../providers/custom_themes_provider.dart';
import '../../providers/settings_providers.dart';
import '../../theme/theme.dart';

final _log = AppLogger.forModule('CustomThemes');

class CustomThemesSection extends HookConsumerWidget {
  const CustomThemesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themes = ref.watch(customThemesProvider);
    final settings = ref.watch(appSettingsProvider);
    final applying = useState(false);
    final failed = useState(false);
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final entries = themes.asData?.value;
    final brightness = colors.brightness;

    if (!themes.hasError && (entries == null || entries.isEmpty)) {
      return const SizedBox.shrink();
    }

    Future<void> apply(String id) async {
      applying.value = true;
      failed.value = false;
      try {
        final result = await ref
            .read(appSettingsProvider.notifier)
            .runThemeCommand({'action': 'apply', 'id': id});
        if (result['ok'] != true) {
          throw StateError('Theme apply failed: $result');
        }
      } catch (error, stack) {
        _log.error(
          'Unable to apply custom theme',
          error: error,
          stackTrace: stack,
        );
        if (context.mounted) {
          failed.value = true;
        }
      } finally {
        if (context.mounted) {
          applying.value = false;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t(LocaleKeys.settingsCustomThemes),
          style: typo.uiSemibold.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: RevericSpacing.md),
        if (themes.hasError) ...[
          Text(
            context.t(LocaleKeys.settingsCustomThemesLoadError),
            style: typo.ui.copyWith(color: colors.textMuted),
          ),
          TextButton(
            onPressed: () => ref.invalidate(customThemesProvider),
            child: Text(context.t(LocaleKeys.commonRetry)),
          ),
        ],
        for (final theme in entries ?? []) ...[
          Builder(
            builder: (context) {
              final selected =
                  settings.asData?.value.customTheme?.id == theme.id;
              final palette = resolveThemePalette(
                baseTheme: theme.baseTheme,
                brightness: brightness,
                overrides: brightness == Brightness.dark
                    ? theme.darkOverrides
                    : theme.lightOverrides,
              ).colors;
              return Semantics(
                selected: selected,
                child: Material(
                  color: selected ? colors.selected : colors.canvas,
                  borderRadius: BorderRadius.circular(RevericRadius.large),
                  child: InkWell(
                    key: ValueKey('custom-theme-${theme.id}'),
                    borderRadius: BorderRadius.circular(RevericRadius.large),
                    hoverColor: colors.hover,
                    onTap: applying.value || !settings.hasValue || selected
                        ? null
                        : () => apply(theme.id),
                    child: Container(
                      padding: const EdgeInsets.all(RevericSpacing.lg),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          RevericRadius.large,
                        ),
                        border: Border.all(
                          color: selected ? colors.accent : colors.borderInput,
                        ),
                      ),
                      child: Row(
                        children: [
                          ExcludeSemantics(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final color in [
                                  palette.canvas,
                                  palette.surface,
                                  palette.accent,
                                  palette.textPrimary,
                                ])
                                  Container(
                                    width: RevericSpacing.lg,
                                    height: RevericSpacing.x2l,
                                    color: color,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: RevericSpacing.lg),
                          Expanded(
                            child: Text(
                              theme.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: typo.uiSemibold.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: RevericSpacing.sm),
                            RevericIcon(
                              RevericIcons.check_circle,
                              size: 20,
                              color: colors.accent,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: RevericSpacing.md),
        ],
        if (failed.value)
          Text(
            context.t(LocaleKeys.settingsCustomThemeApplyError),
            style: typo.ui.copyWith(color: colors.textMuted),
          ),
        const SizedBox(height: RevericSpacing.xl),
      ],
    );
  }
}
