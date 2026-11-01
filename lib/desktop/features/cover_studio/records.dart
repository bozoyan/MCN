// 职责: 桌面封面生成记录列表 — 侧栏中栏的分区标题与批次列表外壳。
// 关联文件:
//   lib/shared/widgets/cover_studio/batch_row.dart
//   lib/shared/providers/cover_studio_providers.dart
//   lib/desktop/widgets/sidebar/sections.dart
//   lib/desktop/widgets/context_column/context_column_scaffold.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/data-deletion.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/cover_studio_providers.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/cover_studio/batch_row.dart';
import '../../widgets/context_column/context_column_scaffold.dart';

/// 无壳生成记录列表：由侧栏 [ContextColumnScaffold] 承载顶栏与书名头。
class CoverStudioRecordsList extends ConsumerWidget {
  const CoverStudioRecordsList({super.key, required this.novelId});

  final String novelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final state = ref.watch(coverStudioControllerProvider(novelId));
    final controller = ref.read(
      coverStudioControllerProvider(novelId).notifier,
    );
    final batches =
        ref.watch(imageBatchesProvider(novelId)).asData?.value ??
        const <ImageBatchRow>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContextColumnSectionHeader(
          title: context.t(LocaleKeys.editorCoverGenerationRecords),
          count: batches.length,
          actions: [
            // 与章节/会话列表一致：分区标题右侧 + 表示「新建」。
            // 封面场景下新建 = 画布回空态 + 设计器参数复位（提示词回默认种子）。
            Tooltip(
              message: context.t(LocaleKeys.editorCoverNew),
              child: InkWell(
                key: const ValueKey('cover-studio-new'),
                onTap: state.busy ? null : controller.startNewDraft,
                borderRadius: BorderRadius.circular(RevericRadius.small),
                child: Padding(
                  padding: const EdgeInsets.all(RevericSpacing.xs),
                  child: RevericIcon(
                    RevericIcons.add,
                    size: 16,
                    color: colors.textSubtle,
                  ),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: batches.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      context.t(LocaleKeys.editorCoverRecordsBlank),
                      textAlign: TextAlign.center,
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: batches.length,
                  itemBuilder: (context, index) {
                    final batch = batches[index];
                    return CoverBatchRow(
                      novelId: novelId,
                      batch: batch,
                      active: batch.id == state.selectedBatchId,
                      busy: state.busy,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
