// 职责: 统一跨平台剧本季、集、场次标签与时长格式化。
// 关联文件:
//   lib/desktop/features/screenplay/context_panel.dart
//   lib/desktop/features/screenplay/scenes.dart
//   lib/shared/models/screenplay.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/screenplay.dart';
import '../../database/novel_content_database.dart'
    show ScreenplayEpisodeRow, ScreenplaySeasonRow;

String screenplayEpisodeLabel(
  BuildContext context,
  ScreenplayEpisodeRow episode,
) {
  final fallback = context.t(
    LocaleKeys.screenplayEpisode,
    namedArgs: {'number': '${episode.episodeNumber}'},
  );
  return episode.title.trim().isEmpty ? fallback : episode.title.trim();
}

/// 集号本身（`第 3 集`），与自定义标题分开 —— 集列表要同时显示两者。
String screenplayEpisodeNumberLabel(
  BuildContext context,
  ScreenplayEpisodeRow episode,
) {
  return context.t(
    LocaleKeys.screenplayEpisode,
    namedArgs: {'number': '${episode.episodeNumber}'},
  );
}

String screenplaySeasonLabel(BuildContext context, ScreenplaySeasonRow season) {
  final number = context.t(
    LocaleKeys.screenplaySeason,
    namedArgs: {'number': '${season.seasonNumber}'},
  );
  final title = season.title.trim();
  return title.isEmpty ? number : '$number · $title';
}

String screenplaySceneLabel(
  BuildContext context,
  ScreenplaySceneSummary scene,
) {
  return context.t(
    LocaleKeys.screenplayScene,
    namedArgs: {'number': '${scene.sceneNumber}'},
  );
}

/// 场次头的地点部分。华语剧本地点优先，所以它单独成一段，排在拍摄条件前面。
String screenplaySceneLocation(
  BuildContext context,
  ScreenplaySceneSummary scene, {
  Map<String, String> locationNames = const {},
}) {
  if (scene.locationId case final locationId?) {
    return locationNames[locationId] ??
        context.t(LocaleKeys.screenplayDeletedLocation);
  }
  return context.t(LocaleKeys.screenplayUntitledScene);
}

/// 场次头的拍摄条件部分：`时间 / 内外`。斜线只绑定这一组，不用来劈开地点。
(String time, String interiorExterior) screenplaySceneCondition(
  BuildContext context,
  ScreenplaySceneSummary scene,
) {
  final interiorExterior = screenplayInteriorExteriorLabel(
    context,
    scene.interiorExterior,
  );
  return (scene.timeLabel.trim(), interiorExterior);
}

/// 场次头的纯文本形态（`嘉兴码头 昏 / 外`），用于缩略、tooltip 等单行场合。
String screenplaySceneHeading(
  BuildContext context,
  ScreenplaySceneSummary scene, {
  Map<String, String> locationNames = const {},
}) {
  final place = screenplaySceneLocation(
    context,
    scene,
    locationNames: locationNames,
  );
  final (time, interiorExterior) = screenplaySceneCondition(context, scene);
  final condition = [
    time,
    interiorExterior,
  ].where((part) => part.isNotEmpty).join(' / ');
  return condition.isEmpty ? place : '$place $condition';
}

String screenplayInteriorExteriorLabel(BuildContext context, String? value) =>
    switch (value) {
      screenplayInterior => context.t(LocaleKeys.screenplayInterior),
      screenplayExterior => context.t(LocaleKeys.screenplayExterior),
      screenplayInteriorExterior => context.t(
        LocaleKeys.screenplayInteriorAndExterior,
      ),
      _ => '',
    };

String screenplaySceneTitle(
  BuildContext context,
  ScreenplaySceneSummary scene, {
  Map<String, String> locationNames = const {},
}) => scene.title.trim().isNotEmpty
    ? scene.title.trim()
    : screenplaySceneLocation(context, scene, locationNames: locationNames);

const int _inUseVisibleScenes = 10;

/// 删除被剧本引用的人物 / 地点前的拦截说明，作为 `ConfirmDialog.blockedReason`。
///
/// 没有引用时为 null；否则 [introKey] 之后逐行列出场次，超出部分只给数量。
Future<String?> screenplayInUseBlockedReason(
  BuildContext context, {
  required String introKey,
  required Future<List<ScreenplaySceneReference>> references,
}) async {
  final scenes = await references;
  if (scenes.isEmpty) {
    return null;
  }
  if (!context.mounted) {
    throw StateError('Context unmounted before delete reference check.');
  }
  return _screenplayInUseMessage(
    context,
    intro: context.t(introKey),
    scenes: scenes,
  );
}

String _screenplayInUseMessage(
  BuildContext context, {
  required String intro,
  required List<ScreenplaySceneReference> scenes,
}) {
  String sceneLine(ScreenplaySceneReference scene) {
    final parts = [
      if (scene.seasonNumber case final number?)
        context.t(
          LocaleKeys.screenplaySeason,
          namedArgs: {'number': '$number'},
        ),
      if (scene.episodeNumber case final number?)
        context.t(
          LocaleKeys.screenplayEpisode,
          namedArgs: {'number': '$number'},
        ),
      context.t(
        LocaleKeys.screenplayScene,
        namedArgs: {'number': '${scene.sceneNumber}'},
      ),
      if (scene.title.trim().isNotEmpty) scene.title.trim(),
    ];
    return '· ${parts.join(' · ')}';
  }

  final hidden = scenes.length - _inUseVisibleScenes;
  return [
    intro,
    for (final scene in scenes.take(_inUseVisibleScenes)) sceneLine(scene),
    if (hidden > 0)
      context.t(
        LocaleKeys.screenplayInUseMore,
        namedArgs: {'count': '$hidden'},
      ),
  ].join('\n');
}
