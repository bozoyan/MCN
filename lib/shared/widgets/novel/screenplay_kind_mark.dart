// 职责: 在小说与剧本混排的作品库里标出剧本；小说是默认类型，不加标记。
// 关联文件:
//   lib/shared/models/content_kind.dart
//   lib/desktop/widgets/novel_list.dart
//   lib/desktop/widgets/home/resume_section.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json

import 'package:flutter/material.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

class ScreenplayKindMark extends StatelessWidget {
  const ScreenplayKindMark({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.small),
      ),
      // 单行富文本而不是 Row：宽度受限时整体省略，不会溢出。
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: RevericIcon(
                  RevericIcons.movie_outlined,
                  size: 11,
                  color: colors.textMuted,
                ),
              ),
            ),
            TextSpan(text: context.t(LocaleKeys.libraryContentKindScreenplay)),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: typo.uiTinySemibold.copyWith(color: colors.textMuted),
      ),
    );
  }
}
