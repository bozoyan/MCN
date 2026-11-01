// 职责: 保留关系编辑入口，并为共享表单选择桌面弹窗或移动弹层。
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
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../mobile/widgets/sheet.dart';
import '../components/reveric_dialog.dart';
import '../database/novel_content_database.dart';
import '../entity_graph/providers.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';
import 'relation/change_form.dart';
import 'relation/support.dart';

abstract final class RelationEditDialog {
  static Future<void> show(
    BuildContext context, {
    required String databasePath,
    RelationSummary? relation,
    String? sourceType,
    String? sourceId,
    String? targetType,
    String? targetId,
  }) async {
    if (relation != null) {
      return showChange(
        context,
        databasePath: databasePath,
        relation: relation,
        intent: RelationFormIntent.correct,
      );
    }
    await _show(
      context,
      databasePath,
      RelationFormRequest(
        intent: RelationFormIntent.create,
        source: sourceType == null ? null : (sourceType, sourceId ?? ''),
        target: targetType == null ? null : (targetType, targetId ?? ''),
      ),
    );
  }

  static Future<void> showChange(
    BuildContext context, {
    required String databasePath,
    required RelationSummary relation,
    required RelationFormIntent intent,
  }) async {
    try {
      final service = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(entityRelationsServiceProvider(databasePath));
      final latest = await service.getRelationById(relation.id);
      if (!context.mounted) {
        return;
      }
      if (latest == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t(LocaleKeys.relationNotFound))),
        );
        return;
      }
      await _show(
        context,
        databasePath,
        RelationFormRequest(intent: intent, relation: latest),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(relationErrorLabel(context, error))),
        );
      }
    }
  }

  static Future<void> _show(
    BuildContext context,
    String path,
    RelationFormRequest request,
  ) async {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      await showMobileSheet<void>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        builder: (sheetContext) => MobileSheetScaffold(
          header: MobileSheetHeader(
            title: relationFormTitle(sheetContext, request.intent),
          ),
          child: Padding(
            padding: const EdgeInsets.all(RevericSpacing.lg),
            child: RelationChangeForm(
              databasePath: path,
              request: request,
              onSaved: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        ),
      );
    } else {
      await showRevericDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => RevericDialog.panel(
          key: const ValueKey('relation-dialog'),
          title: Text(relationFormTitle(dialogContext, request.intent)),
          content: SizedBox(
            width: RevericSizes.dialogWidth,
            child: RelationChangeForm(
              databasePath: path,
              request: request,
              onSaved: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ),
      );
    }
  }
}
