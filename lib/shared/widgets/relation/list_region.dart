// 职责: 管理实体关系列表的结束状态过滤、稳定 ID 选择与详情区域。
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
import '../../components/reveric_badge.dart';
import '../../components/reveric_button.dart';
import '../../components/reveric_switch.dart';
import '../../models/entity_relation_history.dart';
import '../../entity_graph/colors.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/novel_providers.dart';
import '../../theme/theme.dart';
import '../relation_edit_dialog.dart';
import 'detail.dart';
import 'providers.dart';
import 'support.dart';

class RelationListRegion extends HookConsumerWidget {
  const RelationListRegion({
    super.key,
    required this.databasePath,
    required this.entityKey,
    this.names = const {},
    this.onOpenDetail,
    this.onOpenEvidence,
  });
  final String databasePath;
  final String entityKey;
  final Map<String, String> names;
  final ValueChanged<String>? onOpenDetail;
  final RelationEvidenceNavigation? onOpenEvidence;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showEnded = useState(false);
    final selected = useState<String?>(null);
    final separator = entityKey.indexOf('_');
    final type = entityKey.substring(0, separator);
    final id = entityKey.substring(separator + 1);
    final relations = ref.watch(
      entityRelationsProvider(
        path: databasePath,
        entityType: type,
        entityId: id,
      ),
    );
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.lg,
            RevericSpacing.sm,
            RevericSpacing.sm,
            RevericSpacing.xxs,
          ),
          child: Row(
            children: [
              Text(
                context.t(LocaleKeys.entityGraphTabAll),
                style: typo.uiTinySemibold.copyWith(color: colors.textMuted),
              ),
              const SizedBox(width: RevericSpacing.xs),
              Text(
                '${relations.value?.where((r) => showEnded.value || r.status == 'active').length ?? ''}',
                style: typo.uiTinySemibold.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  context.t(LocaleKeys.relationShowEnded),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiTiny.copyWith(color: colors.textMuted),
                ),
              ),
              const SizedBox(width: RevericSpacing.xxs),
              RevericSwitch(
                key: const ValueKey('relation-show-ended'),
                value: showEnded.value,
                onChanged: (value) => showEnded.value = value,
              ),
            ],
          ),
        ),
        Expanded(
          child: relations.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                Center(child: Text(context.t(LocaleKeys.relationSaveFailed))),
            data: (rows) {
              final visible = rows
                  .where((r) => showEnded.value || r.status == 'active')
                  .toList();
              final activeId = visible.any((r) => r.id == selected.value)
                  ? selected.value
                  : visible.firstOrNull?.id;
              final inlineDetail = onOpenDetail == null && activeId != null;
              final list = visible.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(RevericSpacing.lg),
                        child: Text(
                          context.t(LocaleKeys.relationNoActive),
                          style: typo.uiSmall,
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: PageStorageKey('relations-$entityKey'),
                      shrinkWrap: inlineDetail,
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final row = visible[index];
                        return _RelationRow(
                          key: ValueKey('relation-row-${row.id}'),
                          row: row,
                          name:
                              names[row.sourceType == type && row.sourceId == id
                                  ? '${row.targetType}_${row.targetId}'
                                  : '${row.sourceType}_${row.sourceId}'] ??
                              context.t(LocaleKeys.commonUntitled),
                          selected: onOpenDetail == null && activeId == row.id,
                          onTap: () {
                            selected.value = row.id;
                            onOpenDetail?.call(row.id);
                          },
                        );
                      },
                    );
              return LayoutBuilder(
                builder: (context, constraints) => Column(
                  children: [
                    // 内联详情时列表按内容收缩，最多占 40%，余下全给详情。
                    if (inlineDetail)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * 0.4,
                        ),
                        child: list,
                      )
                    else
                      Expanded(child: list),
                    if (inlineDetail) ...[
                      Divider(height: 1, color: colors.borderSubtle),
                      Expanded(
                        child: SingleChildScrollView(
                          key: PageStorageKey('relation-detail-$activeId'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: RevericSpacing.lg,
                            vertical: RevericSpacing.md,
                          ),
                          child: RelationDetail(
                            key: ValueKey(activeId),
                            databasePath: databasePath,
                            relationId: activeId,
                            names: names,
                            onOpenEvidence: onOpenEvidence,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(RevericSpacing.lg),
          child: RevericButton.secondary(
            label: context.t(LocaleKeys.relationCreate),
            onPressed: () => RelationEditDialog.show(
              context,
              databasePath: databasePath,
              sourceType: type,
              sourceId: id,
            ),
          ),
        ),
      ],
    );
  }
}

class _RelationRow extends StatelessWidget {
  const _RelationRow({
    super.key,
    required this.row,
    required this.name,
    required this.selected,
    required this.onTap,
  });
  final RelationSummary row;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final ended = row.status == 'ended';
    final relationColor = ended
        ? colors.textMuted
        : getRelationColor(row.relationType);
    return Material(
      color: selected ? colors.selected : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.lg,
            vertical: RevericSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: relationColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSmall.copyWith(
                    color: ended ? colors.textMuted : colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              RevericBadge(
                label: relationLabel(
                  context,
                  row.relationType,
                  row.sourceType,
                  row.targetType,
                ),
                color: relationColor,
              ),
              const Spacer(),
              if (ended)
                RevericBadge(
                  label: context.t(LocaleKeys.relationEnded),
                  color: colors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
