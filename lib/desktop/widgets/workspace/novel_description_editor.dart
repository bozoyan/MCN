// 职责: 作品简介编辑器 — 编辑小说标题下的长篇作品简介正文。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/shared/database/app_database.dart
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';

class NovelDescriptionEditor extends StatelessWidget {
  const NovelDescriptionEditor({
    super.key,
    required this.novelTitle,
    required this.controller,
    required this.focusNode,
  });

  final String novelTitle;
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

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
              novelTitle,
              style: typo.display.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: RevericSpacing.x3l),
            TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 24,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: typo.body.copyWith(color: colors.textPrimary, height: 1.8),
              decoration: InputDecoration(
                filled: false,
                hintText: context.t(LocaleKeys.workspaceNovelDescription),
                hintStyle: typo.body.copyWith(
                  color: colors.textSubtle,
                  height: 1.8,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
