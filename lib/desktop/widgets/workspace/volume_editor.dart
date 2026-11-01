// 职责: 桌面端分卷编辑器 — 编辑卷标题与卷大纲，不展示章节正文与章节统计。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';

class VolumeEditor extends ConsumerWidget {
  const VolumeEditor({
    super.key,
    required this.volume,
    this.volumeNumber,
    required this.titleController,
    required this.outlineController,
    required this.titleFocusNode,
    required this.outlineFocusNode,
  });

  final Chapter volume;
  final int? volumeNumber;
  final TextEditingController titleController;
  final TextEditingController outlineController;
  final FocusNode titleFocusNode;
  final FocusNode outlineFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final editorFontFamily = ref.watch(editorFontFamilyProvider);
    final editorFontSize = ref.watch(editorFontSizeProvider);
    final editorLetterSpacing = ref.watch(editorLetterSpacingProvider);
    final editorLineHeight = ref.watch(editorLineHeightProvider);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RevericSpacing.x6l,
          RevericSpacing.x4l,
          RevericSpacing.x6l,
          RevericSpacing.x6l,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _volumeLabel(context, volume, volumeNumber),
              style: typo.uiSemibold.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: RevericSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: TextField(
                controller: titleController,
                focusNode: titleFocusNode,
                style: typo.display.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontFamily: editorFontFamily,
                ),
                decoration: InputDecoration(
                  hintText: context.t(LocaleKeys.workspaceNewVolumeHint),
                  hintStyle: typo.display.copyWith(
                    color: colors.textSubtle,
                    fontFamily: editorFontFamily,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: RevericSpacing.x2l),
            SizedBox(
              height: 520,
              child: RevericMarkdownEditor(
                controller: outlineController,
                focusNode: outlineFocusNode,
                hintText: context.t(LocaleKeys.workspaceOutlineContentHint),
                fontFamily: editorFontFamily,
                fontSize: editorFontSize,
                letterSpacing: editorLetterSpacing,
                lineHeight: editorLineHeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _volumeLabel(BuildContext context, Chapter volume, int? volumeNumber) {
  final volumeNum = volume.volumeNum ?? volumeNumber;
  if (volumeNum == null) {
    return context.t(LocaleKeys.workspaceVolume);
  }
  return context.t(
    LocaleKeys.workspaceVolumeNumber,
    namedArgs: {'number': '$volumeNum'},
  );
}
