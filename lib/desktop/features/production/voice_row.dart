// 职责: 渲染音色列表中的一行：就地试听、名称、选中态与行尾操作。
// 关联文件:
//   lib/desktop/features/production/voice_preview.dart
//   lib/desktop/features/production/voices.dart
//   lib/desktop/features/production/builtin_voices.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

class ProductionVoiceRow extends StatelessWidget {
  const ProductionVoiceRow({
    super.key,
    required this.name,
    required this.playing,
    required this.onPlay,
    this.detail,
    this.selected = false,
    this.onTap,
    this.trailing = const [],
  });
  final String name;
  final String? detail;
  final bool playing;
  final VoidCallback? onPlay;
  final bool selected;
  final VoidCallback? onTap;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      color: selected ? colors.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.xs,
            vertical: RevericSpacing.xxs,
          ),
          child: Row(
            children: [
              RevericIconButton(
                icon: playing
                    ? RevericIcons.stop_rounded
                    : RevericIcons.play_arrow,
                tooltip: context.t(
                  playing ? LocaleKeys.commonStop : LocaleKeys.commonPlay,
                ),
                onPressed: onPlay,
              ),
              const SizedBox(width: RevericSpacing.xs),
              Expanded(
                child: Text(
                  name,
                  style: typo.ui,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(left: RevericSpacing.sm),
                  child: Text(
                    detail!,
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ),
              if (selected && onTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: RevericSpacing.sm),
                  child: RevericIcon(
                    RevericIcons.check,
                    size: 16,
                    color: colors.accent,
                  ),
                ),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}
