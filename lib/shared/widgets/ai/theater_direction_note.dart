// 职责: 小剧场台词流中的导演指令条目 — 与角色台词区分的居中注记，可撤回。桌面面板与移动页共用。
// 关联文件:
//   lib/shared/models/theater_models.dart
//   lib/desktop/features/theater/line_list.dart
//   lib/mobile/features/theater/page_widgets.dart
import 'package:flutter/material.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/theater_models.dart';
import '../../theme/theme.dart';

class TheaterDirectionNote extends StatelessWidget {
  const TheaterDirectionNote({super.key, required this.line, this.onRemove});

  final TheaterLine line;

  /// 表演进行中不可撤回，传 null 隐藏按钮。
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final remove = onRemove;
    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.md),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(RevericRadius.xl),
            border: Border.all(color: colors.accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericIcon(
                RevericIcons.movie_outlined,
                size: 14,
                color: colors.accent,
              ),
              const SizedBox(width: RevericSpacing.xs),
              Text(
                context.t(LocaleKeys.theaterDirectionLabel),
                style: typo.uiTiny.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              Flexible(
                child: Text(
                  line.dialogue,
                  style: typo.uiSmall.copyWith(color: colors.textPrimary),
                ),
              ),
              if (remove != null) ...[
                const SizedBox(width: RevericSpacing.xs),
                Tooltip(
                  message: context.t(LocaleKeys.theaterDirectionRemove),
                  child: InkWell(
                    onTap: remove,
                    borderRadius: BorderRadius.circular(RevericRadius.small),
                    child: Padding(
                      padding: const EdgeInsets.all(RevericSpacing.xxs),
                      child: RevericIcon(
                        RevericIcons.close,
                        size: 12,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
