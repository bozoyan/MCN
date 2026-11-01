// 职责: 展示单条关系当前状态并组合生命周期操作和独立历史区域。
// 关联文件:
//   lib/shared/widgets/relation/actions.dart
//   lib/shared/widgets/relation/providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/relation.json
//   assets/translations/zh-CN/relation.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../components/reveric_badge.dart';
import '../../entity_graph/colors.dart';
import '../../entity_graph/data.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';
import 'actions.dart';
import 'evidence.dart';
import 'history.dart';
import 'providers.dart';
import 'support.dart';

class RelationDetail extends ConsumerWidget {
  const RelationDetail({
    super.key,
    required this.databasePath,
    required this.relationId,
    this.names = const {},
    this.onOpenEvidence,
  });
  final String databasePath;
  final String relationId;
  final Map<String, String> names;
  final RelationEvidenceNavigation? onOpenEvidence;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      relationCurrentProvider((databasePath, relationId)),
    );
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return current.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text(context.t(LocaleKeys.relationSaveFailed)),
      data: (row) {
        if (row == null) {
          return Text(context.t(LocaleKeys.relationNotFound));
        }
        final sourceName =
            names['${row.sourceType}_${row.sourceId}'] ??
            context.t(LocaleKeys.commonUntitled);
        final targetName =
            names['${row.targetType}_${row.targetId}'] ??
            context.t(LocaleKeys.commonUntitled);
        final relationColor = row.status == 'ended'
            ? colors.textMuted
            : getRelationColor(row.relationType);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(RevericSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(RevericRadius.large),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$sourceName ${isRelationDirected(row.relationType) ? '→' : '↔'} $targetName',
                    style: typo.uiSmallSemibold.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: RevericSpacing.sm),
                  Wrap(
                    spacing: RevericSpacing.xs,
                    runSpacing: RevericSpacing.xs,
                    children: [
                      RevericBadge(
                        label: relationLabel(
                          context,
                          row.relationType,
                          row.sourceType,
                          row.targetType,
                        ),
                        color: relationColor,
                      ),
                      RevericBadge(
                        label: relationStatusLabel(context, row.status),
                        color: row.status == 'ended'
                            ? colors.textMuted
                            : colors.accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: RevericSpacing.md),
                  Text(
                    context.t(LocaleKeys.relationProof),
                    style: typo.uiTinySemibold.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: RevericSpacing.xxs),
                  SelectableText(
                    row.proof,
                    style: typo.uiSmall.copyWith(
                      color: colors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: RevericSpacing.xs),
                  RelationEvidence(
                    databasePath: databasePath,
                    chapterId: row.chapterId,
                    sceneId: row.sceneId,
                    onOpen: onOpenEvidence,
                  ),
                  const SizedBox(height: RevericSpacing.sm),
                  RelationActions(
                    key: ValueKey(row.id),
                    databasePath: databasePath,
                    relation: row,
                  ),
                ],
              ),
            ),
            const SizedBox(height: RevericSpacing.sm),
            RelationHistory(
              key: ValueKey('history-$relationId'),
              databasePath: databasePath,
              relationId: relationId,
              onOpenEvidence: onOpenEvidence,
            ),
          ],
        );
      },
    );
  }
}
