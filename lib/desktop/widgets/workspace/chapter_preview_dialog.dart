// 职责: 桌面端章节阅读预览弹窗 — 设备切换 + 阅读统计 + 预览舞台，复用 shared ChapterPreviewStage。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/shared/widgets/chapter/chapter_preview_stage.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_segmented_control.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/number_format.dart';
import '../../../shared/utils/text_unit_count.dart';
import '../../../shared/widgets/chapter/chapter_preview_stage.dart';

class ChapterPreviewDialog extends ConsumerStatefulWidget {
  const ChapterPreviewDialog({
    super.key,
    required this.chapterTitle,
    required this.chapterContent,
  });

  final String chapterTitle;
  final String chapterContent;

  @override
  ConsumerState<ChapterPreviewDialog> createState() =>
      _ChapterPreviewDialogState();
}

class _ChapterPreviewDialogState extends ConsumerState<ChapterPreviewDialog> {
  static const double _deviceSwitcherWidth = 680;

  ChapterPreviewDevice _selectedDevice = ChapterPreviewDevice.phone390;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final fontFamily = ref.watch(editorFontFamilyProvider);
    final fontSize = ref.watch(editorFontSizeProvider);
    final letterSpacing = ref.watch(editorLetterSpacingProvider);
    final lineHeight = ref.watch(editorLineHeightProvider);
    final body = widget.chapterContent;
    final wordCount = countTextUnits(body);
    final locale = Localizations.localeOf(context).languageCode;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
      ),
      child: SizedBox(
        width: 980,
        height: 720,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x4l,
                RevericSpacing.x3l,
                RevericSpacing.x2l,
                RevericSpacing.x2l,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t(LocaleKeys.workspacePreview),
                          style: typo.heading2.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: RevericSpacing.xs),
                        Text(
                          context.t(
                            LocaleKeys.workspacePreviewDescription,
                            namedArgs: {
                              'width': _selectedDevice.width.toString(),
                              'height': _selectedDevice.height.toString(),
                            },
                          ),
                          style: typo.ui.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.t(LocaleKeys.commonClose),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: RevericIcon(
                      RevericIcons.close_rounded,
                      size: 18,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: RevericSizes.dividerThickness,
              color: colors.border,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.x4l,
                vertical: RevericSpacing.x2l,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: SizedBox(
                      width: _deviceSwitcherWidth,
                      child: RevericSegmentedControl<ChapterPreviewDevice>(
                        segments: [
                          for (final device in ChapterPreviewDevice.values)
                            RevericSegment<ChapterPreviewDevice>(
                              value: device,
                              label: context.t(device.labelKey),
                            ),
                        ],
                        selected: _selectedDevice,
                        onChanged: (device) {
                          setState(() {
                            _selectedDevice = device;
                          });
                        },
                      ),
                    ),
                  ),
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
                padding: const EdgeInsets.all(RevericSpacing.x4l),
                child: ChapterPreviewStage(
                  device: _selectedDevice,
                  title: widget.chapterTitle.trim(),
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
