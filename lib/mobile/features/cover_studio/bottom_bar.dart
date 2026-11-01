// 职责: 移动端封面工作台底部常驻条 — 「设计」入口与生成脚（预估、生成张数、停止）。
// 关联文件:
//   lib/mobile/features/cover_studio/studio_page.dart
//   lib/shared/widgets/cover_studio/generate_footer.dart
//   lib/shared/providers/cover_studio_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/cover_studio_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/cover_studio/generate_footer.dart';

/// 生成入口常驻在底部：参数藏进抽屉之后，作者仍然一眼看得到「花多少、出几张」。
class MobileCoverStudioBottomBar extends ConsumerWidget {
  const MobileCoverStudioBottomBar({
    super.key,
    required this.novelId,
    required this.onOpenDesigner,
    required this.onGenerate,
  });

  final String novelId;
  final VoidCallback onOpenDesigner;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final generating = ref.watch(
      coverStudioControllerProvider(
        novelId,
      ).select((state) => state.generating),
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.x2l,
            RevericSpacing.md,
            RevericSpacing.x2l,
            RevericSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 出图中整条让给进度与停止：这时候点「设计」改参数也影响不了这一批。
              if (!generating) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onOpenDesigner,
                    icon: const RevericIcon(
                      RevericIcons.settings_outlined,
                      size: 15,
                    ),
                    label: Text(context.t(LocaleKeys.editorCoverDesigner)),
                  ),
                ),
                const SizedBox(height: RevericSpacing.sm),
              ],
              CoverGenerateFooter(novelId: novelId, onGenerate: onGenerate),
            ],
          ),
        ),
      ),
    );
  }
}
