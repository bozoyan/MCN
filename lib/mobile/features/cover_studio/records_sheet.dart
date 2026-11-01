// 职责: 移动端封面生成记录抽屉 — 列出历史批次，支持选中回看、删除与新建一稿。
// 关联文件:
//   lib/shared/widgets/cover_studio/batch_row.dart
//   lib/shared/providers/cover_studio_providers.dart
//   lib/mobile/features/cover_studio/studio_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/data-deletion.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/cover_studio_providers.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/cover_studio/batch_row.dart';

Future<void> openMobileCoverRecordsSheet(
  BuildContext context, {
  required String novelId,
}) {
  final colors = RevericTheme.colorsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RevericRadius.x2l),
      ),
    ),
    builder: (_) => _RecordsSheet(novelId: novelId),
  );
}

class _RecordsSheet extends ConsumerWidget {
  const _RecordsSheet({required this.novelId});

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

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x2l,
                0,
                RevericSpacing.sm,
                RevericSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t(LocaleKeys.editorCoverGenerationRecords),
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  // 新建 = 画布回空态 + 设计器参数复位（提示词回默认种子）。
                  TextButton.icon(
                    key: const ValueKey('cover-studio-new'),
                    onPressed: state.busy
                        ? null
                        : () {
                            controller.startNewDraft();
                            Navigator.of(context).pop();
                          },
                    icon: const RevericIcon(RevericIcons.add, size: 15),
                    label: Text(context.t(LocaleKeys.editorCoverNew)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: batches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(RevericSpacing.x4l),
                      child: Text(
                        context.t(LocaleKeys.editorCoverRecordsBlank),
                        textAlign: TextAlign.center,
                        style: typo.uiSmall.copyWith(color: colors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(
                        RevericSpacing.md,
                        0,
                        RevericSpacing.md,
                        RevericSpacing.x2l,
                      ),
                      itemCount: batches.length,
                      itemBuilder: (context, index) {
                        final batch = batches[index];
                        return CoverBatchRow(
                          novelId: novelId,
                          batch: batch,
                          active: batch.id == state.selectedBatchId,
                          busy: state.busy,
                          // 选完就回画布看图，不用再手动关抽屉。
                          onSelected: () => Navigator.of(context).pop(),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
