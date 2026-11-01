// 职责: 为标准自动补全组件提供剧本时间标签和本地化常用候选。
// 关联文件:
//   lib/shared/components/reveric_autocomplete.dart
//   lib/shared/widgets/screenplay/document_heading.dart
//   lib/desktop/features/screenplay/scene_dialog.dart
//   lib/mobile/features/screenplay/scenes_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json

import 'package:flutter/material.dart';
import '../../components/reveric_autocomplete.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';

class ScreenplayTimeField extends StatelessWidget {
  const ScreenplayTimeField({
    super.key,
    required this.controller,
    this.errorText,
    this.label,
  });
  final TextEditingController controller;
  final String? errorText;
  final String? label;

  @override
  Widget build(BuildContext context) => RevericAutocomplete(
    controller: controller,
    label: label,
    hintText: context.t(LocaleKeys.screenplayTimeHint),
    errorText: errorText,
    suggestions: [
      LocaleKeys.screenplayTimeDay,
      LocaleKeys.screenplayTimeNight,
      LocaleKeys.screenplayTimeMorning,
      LocaleKeys.screenplayTimeNoon,
      LocaleKeys.screenplayTimeAfternoon,
      LocaleKeys.screenplayTimeDusk,
      LocaleKeys.screenplayTimeLateNight,
      LocaleKeys.screenplayTimeContinuous,
      LocaleKeys.screenplayTimeLater,
      LocaleKeys.screenplayTimeSameTime,
    ].map((key) => context.t(key)).toList(),
  );
}
