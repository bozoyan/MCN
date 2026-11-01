// 职责: 移动端章节预览页 — 设备切换 + 阅读统计 + 预览舞台，复用 shared ChapterPreviewStage 与编辑器排版设置。
// 关联文件:
//   lib/shared/widgets/chapter/chapter_preview_stage.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/utils/number_format.dart
//   lib/shared/utils/text_unit_count.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/components/reveric_segmented_control.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/providers/settings_providers.dart';
import '../../shared/theme/theme.dart';
import '../../shared/utils/number_format.dart';
import '../../shared/utils/text_unit_count.dart';
import '../../shared/widgets/chapter/chapter_preview_stage.dart';

/// 章节预览页（全屏）。按设备画布渲染当前标题与正文，展示字数与预计阅读时间。
class MobileChapterPreviewPage extends HookConsumerWidget {
  const MobileChapterPreviewPage({
    super.key,
    required this.chapterTitle,
    required this.chapterContent,
  });

  final String chapterTitle;
  final String chapterContent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final selectedDevice = useState<ChapterPreviewDevice>(
      ChapterPreviewDevice.phone390,
    );

    final fontFamily = ref.watch(editorFontFamilyProvider);
    final fontSize = ref.watch(editorFontSizeProvider);
    final letterSpacing = ref.watch(editorLetterSpacingProvider);
    final lineHeight = ref.watch(editorLineHeightProvider);
    final body = chapterContent;
    final wordCount = countTextUnits(body);
    final locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        title: Text(
          context.t(LocaleKeys.workspacePreview),
          style: typo.uiSemibold,
        ),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const RevericIcon(RevericIcons.arrow_back, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.md,
                vertical: RevericSpacing.sm,
              ),
              child: Column(
                children: [
                  Text(
                    context.t(
                      LocaleKeys.workspacePreviewDescription,
                      namedArgs: {
                        'width': selectedDevice.value.width.toString(),
                        'height': selectedDevice.value.height.toString(),
                      },
                    ),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: RevericSpacing.sm),
                  RevericSegmentedControl<ChapterPreviewDevice>(
                    segments: [
                      for (final device in ChapterPreviewDevice.values)
                        RevericSegment<ChapterPreviewDevice>(
                          value: device,
                          label: context.t(device.labelKey),
                        ),
                    ],
                    selected: selectedDevice.value,
                    onChanged: (device) => selectedDevice.value = device,
                  ),
                  const SizedBox(height: RevericSpacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      context.t(
                        LocaleKeys.workspacePreviewStats,
                        namedArgs: {
                          'words': formatCompactWordCount(
                            wordCount,
                            languageCode: locale,
                          ),
                          'minutes': _readingMinutes(wordCount).toString(),
                        },
                      ),
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: colors.surfaceDim,
                padding: const EdgeInsets.all(RevericSpacing.xl),
                child: ChapterPreviewStage(
                  device: selectedDevice.value,
                  title: chapterTitle.trim(),
                  body: body,
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  letterSpacing: letterSpacing,
                  lineHeight: lineHeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _readingMinutes(int wordCount) {
    return math.max(1, (wordCount / 500).ceil());
  }
}
