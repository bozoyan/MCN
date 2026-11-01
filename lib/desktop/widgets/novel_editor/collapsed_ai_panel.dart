// 职责: 展示小说编辑页折叠状态下的 AI 面板展开入口。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/widgets/desktop_window_frame.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/app_background.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/app_background.dart';
import '../desktop_window_frame.dart';

class NovelEditorCollapsedAiPanel extends ConsumerWidget {
  const NovelEditorCollapsedAiPanel({super.key, required this.onExpand});

  static const double width = DesktopWindowFrame.collapsedAiRailWidth;

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final chrome = appChromeBackgroundColor(
      colors,
      ref.watch(appBackgroundActiveProvider),
      colors.surfaceContainerHigh,
    );

    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onExpand,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: chrome,
                child: SizedBox(
                  width: width,
                  height: DesktopWindowFrame.titleBarHeight,
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: chrome,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: RevericSpacing.x3l,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RevericIcon(
                          RevericIcons.auto_awesome,
                          size: 18,
                          color: colors.accent,
                        ),
                        const SizedBox(height: RevericSpacing.lg),
                        RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            context.t(LocaleKeys.commonAi),
                            style: typo.uiSmallSemibold.copyWith(
                              color: colors.textSecondary,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: RevericSpacing.xl),
                        RevericIcon(
                          RevericIcons.keyboard_arrow_left,
                          size: 18,
                          color: colors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
