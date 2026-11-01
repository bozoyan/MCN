// 职责: 统一关系界面的状态、类型和安全错误文案。
// 关联文件:
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/widgets/relation/providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/relation.json
//   assets/translations/zh-CN/relation.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md
import 'package:flutter/material.dart';
import '../../entity_graph/labels.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/entity_relation_history.dart';
import '../../models/screenplay.dart';

String relationStatusLabel(BuildContext context, String status) => context.t(
  status == 'ended' ? LocaleKeys.relationEnded : LocaleKeys.relationActive,
);
String relationLabel(
  BuildContext context,
  String type,
  String source,
  String target,
) => localizeRelationTypeLabel(
  context,
  type,
  sourceType: source,
  targetType: target,
);
String relationErrorCode(Object error) => switch (error) {
  RelationServiceException e => e.code,
  ScreenplayServiceException e => e.errorCode,
  _ => '',
};
String relationErrorLabel(BuildContext context, Object error) =>
    context.t(switch (relationErrorCode(error)) {
      'relation_changed' => LocaleKeys.relationChangedError,
      'not_found' => LocaleKeys.relationNotFound,
      'invalid_relation_history' => LocaleKeys.relationHistoryFailed,
      'invalid_chapter_ref' ||
      'invalid_scene_ref' ||
      'mutually_exclusive_fields' => LocaleKeys.relationInvalidEvidence,
      _ => LocaleKeys.relationSaveFailed,
    });
