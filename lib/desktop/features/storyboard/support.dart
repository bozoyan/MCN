// 职责: 将分镜业务状态和错误映射为界面本地化文案。
// 关联文件:
//   lib/shared/services/storyboard/service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
import 'package:flutter/widgets.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/services/storyboard/service.dart';

String shotStatusLabel(BuildContext context, String status) =>
    context.t(switch (status) {
      'selected' => LocaleKeys.productionSelected,
      _ => LocaleKeys.productionUnselected,
    });
String shotError(BuildContext context, Object error) => context.t(
  error is FormatException
      ? LocaleKeys.storyboardInvalidPrompt
      : error is StoryboardException
      ? switch (error.code) {
          'source_missing' => LocaleKeys.storyboardSourceMissing,
          'invalid_config' => LocaleKeys.storyboardInvalidConfig,
          'cross_episode_move' => LocaleKeys.storyboardCrossEpisodeMove,
          _ => LocaleKeys.storyboardError,
        }
      : LocaleKeys.storyboardError,
);
