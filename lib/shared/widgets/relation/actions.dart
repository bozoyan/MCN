// 职责: 提供关系主操作与跨平台更多菜单，并管理删除确认及操作反馈。
// 关联文件:
//   lib/shared/widgets/relation/detail.dart
//   lib/shared/widgets/relation/providers.dart
//   lib/shared/widgets/relation_edit_dialog.dart
//   lib/shared/services/entity_relations_service.dart
//   lib/mobile/widgets/sheet.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/relation.json
//   assets/translations/zh-CN/relation.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../mobile/widgets/sheet.dart';
import '../../components/reveric_button.dart';
import '../../components/reveric_context_menu.dart';
import '../../components/reveric_icon_button.dart';
import '../../database/novel_content_database.dart';
import '../../entity_graph/providers.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';
import '../confirm_dialog.dart';
import '../relation_edit_dialog.dart';
import 'change_form.dart';
import 'providers.dart';
import 'support.dart';

class RelationActions extends HookConsumerWidget {
  const RelationActions({
    super.key,
    required this.databasePath,
    required this.relation,
  });

  final String databasePath;
  final RelationSummary relation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(
      relationDetailProvider((databasePath, relation.id)),
    );
    final deleting = useState(false);
    final failure = useState<String?>(null);
    final ready = history.hasValue && !history.hasError && !deleting.value;
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    Future<void> change(RelationFormIntent intent) =>
        RelationEditDialog.showChange(
          context,
          databasePath: databasePath,
          relation: relation,
          intent: intent,
        );

    Future<void> remove() async {
      final confirmed = await showConfirmDialog(
        context,
        title: context.t(LocaleKeys.relationDeleteRelation),
        message: context.t(LocaleKeys.relationDeleteConfirm),
        confirmLabel: context.t(LocaleKeys.commonDelete),
        variant: ConfirmDialogVariant.error,
      );
      if (!confirmed || !context.mounted) {
        return;
      }
      deleting.value = true;
      failure.value = null;
      try {
        await ref
            .read(entityRelationsServiceProvider(databasePath))
            .deleteRelation(relation.id);
      } catch (error) {
        if (context.mounted) {
          failure.value = relationErrorLabel(context, error);
        }
      } finally {
        if (context.mounted) {
          deleting.value = false;
        }
      }
    }

    Future<void> showActions(BuildContext anchorContext) async {
      final ended = relation.status == 'ended';
      final entries = <RevericMenuEntry>[
        RevericMenuItem(
          label: context.t(LocaleKeys.relationCorrectRecord),
          icon: RevericIcons.edit_outlined,
          enabled: ready,
          onTap: () => change(RelationFormIntent.correct),
        ),
        RevericMenuItem(
          label: context.t(
            ended
                ? LocaleKeys.relationRestoreRelation
                : LocaleKeys.relationEndRelation,
          ),
          icon: ended ? RevericIcons.undo : RevericIcons.block_outlined,
          enabled: ready,
          onTap: () => change(
            ended ? RelationFormIntent.restore : RelationFormIntent.end,
          ),
        ),
        const RevericMenuDivider(),
        RevericMenuItem(
          label: context.t(LocaleKeys.relationDeleteRelation),
          icon: RevericIcons.delete_outline,
          labelColor: colors.error,
          iconColor: colors.error,
          onTap: remove,
        ),
      ];
      final platform = Theme.of(context).platform;
      if (platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS) {
        await showMobileSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => ListView(
            shrinkWrap: true,
            children: [
              for (final entry in entries)
                switch (entry) {
                  RevericMenuDivider() => Divider(color: colors.borderSubtle),
                  RevericMenuItem() => ListTile(
                    enabled: entry.enabled,
                    leading: RevericIcon(entry.icon!, color: entry.iconColor),
                    title: Text(
                      entry.label,
                      style: typo.ui.copyWith(color: entry.labelColor),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      entry.onTap?.call();
                    },
                  ),
                },
            ],
          ),
        );
      } else {
        final anchor = anchorContext.findRenderObject()! as RenderBox;
        await showRevericContextMenu(
          context: context,
          position: anchor.localToGlobal(Offset(0, anchor.size.height)),
          entries: entries,
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: RevericButton.primary(
                size: RevericButtonSize.compact,
                label: context.t(LocaleKeys.relationRecordChange),
                onPressed: ready
                    ? () => change(RelationFormIntent.change)
                    : null,
              ),
            ),
            const SizedBox(width: RevericSpacing.xs),
            Builder(
              builder: (anchorContext) => RevericIconButton(
                key: const ValueKey('relation-more-actions'),
                icon: RevericIcons.more_horiz,
                tooltip: context.t(LocaleKeys.commonMoreActions),
                onPressed: deleting.value
                    ? null
                    : () => showActions(anchorContext),
              ),
            ),
          ],
        ),
        if (failure.value != null) ...[
          const SizedBox(height: RevericSpacing.sm),
          Text(
            failure.value!,
            style: typo.uiSmall.copyWith(color: colors.warningText),
          ),
        ],
      ],
    );
  }
}
