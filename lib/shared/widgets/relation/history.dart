// 职责: 独立加载并展开关系历史，确认误录删除及安全恢复。
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
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../components/reveric_button.dart';
import '../../database/novel_content_database.dart';
import '../../entity_graph/providers.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/entity_relation_history.dart';
import '../../theme/theme.dart';
import '../confirm_dialog.dart';
import 'evidence.dart';
import 'providers.dart';
import 'support.dart';

class RelationHistory extends HookConsumerWidget {
  const RelationHistory({
    super.key,
    required this.databasePath,
    required this.relationId,
    this.onOpenEvidence,
  });
  final String databasePath;
  final String relationId;
  final RelationEvidenceNavigation? onOpenEvidence;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = useState<bool?>(null);
    final busy = useState(false);
    final error = useState<String?>(null);
    final history = ref.watch(
      relationDetailProvider((databasePath, relationId)),
    );
    final row = history.value;
    final count =
        row?.changeLogs
            .where((s) => s.kind == RelationSnapshotKind.change)
            .length ??
        0;
    final isExpanded = expanded.value ?? count == 1;
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    Future<void> remove(EntityRelation before, int index) async {
      final change = before.changeLogs[index];
      final previous = before.changeLogs[index - 1];
      final prompt = index == before.changeLogs.length - 1
          ? context.t(
              LocaleKeys.relationRemoveLatestConfirm,
              namedArgs: {
                'type': relationLabel(
                  context,
                  previous.relationType,
                  before.sourceType,
                  before.targetType,
                ),
                'status': relationStatusLabel(context, previous.status.name),
              },
            )
          : context.t(LocaleKeys.relationRemoveEarlierConfirm);
      final confirmed = await showConfirmDialog(
        context,
        title: context.t(LocaleKeys.relationRemoveChange),
        message: prompt,
        confirmLabel: context.t(LocaleKeys.commonDelete),
        variant: ConfirmDialogVariant.error,
      );
      if (!confirmed || !context.mounted) {
        return;
      }
      busy.value = true;
      error.value = null;
      try {
        await ref
            .read(entityRelationsServiceProvider(databasePath))
            .removeChange(
              id: relationId,
              snapshotId: change.id,
              expected: before,
            );
      } catch (failure) {
        if (context.mounted) {
          error.value = relationErrorLabel(context, failure);
        }
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          expanded: isExpanded,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: RevericButton.text(
              key: const ValueKey('relation-history-toggle'),
              size: RevericButtonSize.compact,
              icon: isExpanded
                  ? RevericIcons.expand_more
                  : RevericIcons.chevron_right,
              label: context.t(
                LocaleKeys.relationHistoryCount,
                namedArgs: {'count': '$count'},
              ),
              onPressed: () => expanded.value = !isExpanded,
            ),
          ),
        ),
        if (history.hasError)
          Text(
            context.t(LocaleKeys.relationHistoryFailed),
            style: typo.uiSmall.copyWith(color: colors.warningText),
          ),
        if (error.value != null)
          Text(
            error.value!,
            key: const ValueKey('relation-history-error'),
            style: typo.uiSmall.copyWith(color: colors.warningText),
          ),
        if (isExpanded)
          history.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const SizedBox.shrink(),
            data: (relation) {
              if (relation == null) {
                return Text(context.t(LocaleKeys.relationNotFound));
              }
              if (relation.changeLogs.isEmpty) {
                return Text(
                  context.t(LocaleKeys.relationNoHistory),
                  style: typo.uiSmall,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    var index = relation.changeLogs.length - 1;
                    index >= 0;
                    index--
                  )
                    Padding(
                      key: ValueKey(relation.changeLogs[index].id),
                      padding: const EdgeInsets.only(
                        left: RevericSpacing.sm,
                        bottom: RevericSpacing.sm,
                      ),
                      child: Container(
                        padding: const EdgeInsets.only(
                          left: RevericSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          border: BorderDirectional(
                            start: BorderSide(
                              color: colors.borderSubtle,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _transition(context, relation, index),
                              style: typo.uiSmallSemibold.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: RevericSpacing.xxs),
                            Text(
                              _recordedTime(
                                context,
                                relation.changeLogs[index],
                              ),
                              style: typo.uiTiny.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                            if (relation
                                .changeLogs[index]
                                .reason
                                .isNotEmpty) ...[
                              const SizedBox(height: RevericSpacing.xs),
                              Text(
                                relation.changeLogs[index].reason,
                                style: typo.uiSmall.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                            const SizedBox(height: RevericSpacing.xs),
                            SelectableText(
                              relation.changeLogs[index].proof,
                              style: typo.uiSmall.copyWith(
                                color: colors.textSecondary,
                                height: 1.6,
                              ),
                            ),
                            RelationEvidence(
                              databasePath: databasePath,
                              chapterId: relation.changeLogs[index].chapterId,
                              sceneId: relation.changeLogs[index].sceneId,
                              onOpen: onOpenEvidence,
                            ),
                            if (relation.changeLogs[index].kind ==
                                RelationSnapshotKind.change)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: RevericButton.text(
                                  size: RevericButtonSize.compact,
                                  key: ValueKey(
                                    'remove-change-${relation.changeLogs[index].id}',
                                  ),
                                  label: context.t(
                                    LocaleKeys.relationRemoveChange,
                                  ),
                                  onPressed: busy.value
                                      ? null
                                      : () => remove(relation, index),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

String _transition(BuildContext context, EntityRelation row, int index) {
  final current = row.changeLogs[index];
  String state(RelationStateSnapshot item) =>
      '${relationLabel(context, item.relationType, row.sourceType, row.targetType)} · ${relationStatusLabel(context, item.status.name)}';
  if (current.kind == RelationSnapshotKind.baseline) {
    return '${context.t(LocaleKeys.relationBaseline)} · ${state(current)}';
  }
  final previous = row.changeLogs[index - 1];
  if (previous.relationType == current.relationType &&
      previous.status == current.status) {
    return context.t(LocaleKeys.relationEvidenceAdded);
  }
  return '${state(previous)} → ${state(current)}';
}

String _recordedTime(BuildContext context, RelationStateSnapshot snapshot) {
  final time = snapshot.recordedAt.toLocal();
  final local = MaterialLocalizations.of(context);
  final label = context.t(
    snapshot.kind == RelationSnapshotKind.baseline
        ? LocaleKeys.relationBaselineTime
        : LocaleKeys.relationRecordedAt,
  );
  return '$label · ${local.formatMediumDate(time)} ${local.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
}
