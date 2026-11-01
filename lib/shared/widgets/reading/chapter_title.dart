// 职责: 生成阅读场景的章节标题 — 正文章节始终带章节序号，供双端阅读页、目录与连续流共用。
// 关联文件:
//   lib/shared/models/chapter.dart
//   lib/shared/widgets/reading/reading_content_view.dart
//   lib/desktop/features/reading/reading_page.dart
//   lib/mobile/features/reading/reading_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json

import 'package:flutter/widgets.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/chapter.dart';

/// 章节有自定义标题时 [Chapter.displayTitle] 会丢掉序号；阅读时读者需要
/// 知道当前是第几章，因此正文章节统一显示为「第N章 标题」。
String readingChapterTitle(BuildContext context, Chapter chapter) {
  final number = chapter.chapterNum;
  if (!chapter.isNumberedChapter || number == null) {
    return chapter.displayTitle;
  }
  final prefix = context.t(
    LocaleKeys.commonChapterNumber,
    namedArgs: {'number': '$number'},
  );
  final name = chapter.title?.trim() ?? '';
  return name.isEmpty ? prefix : '$prefix $name';
}
