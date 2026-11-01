// 职责: 移动端大纲分区列表 — 列出大纲条目（状态色点 + 标题 + 正文预览 + beat 数）、新建、左滑删除、点击进入大纲编辑页。
// 关联文件:
//   lib/mobile/pages/outline_editor_page.dart
//   lib/mobile/widgets/section_scaffold.dart
//   lib/mobile/widgets/delete_confirm.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/models/outline.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/outline.dart';
import '../../shared/providers/novel_providers.dart';
import '../../shared/theme/theme.dart';
import '../pages/outline_editor_page.dart';
import 'delete_confirm.dart';
import 'section_scaffold.dart';

class MobileOutlinesPanel extends ConsumerWidget {
  const MobileOutlinesPanel({
    super.key,
    required this.databasePath,
    required this.onCreate,
    required this.onImport,
  });

  final String databasePath;

  /// 新建入口由标题栏右上角承载；空状态引导按钮复用同一回调。
  final VoidCallback onCreate;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(outlinesProvider(databasePath));
    final outlines = async.asData?.value ?? const <OutlineDraft>[];
    final enabled = outlines.enabled.sorted;

    if (async.isLoading && outlines.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    Future<void> openEditor(OutlineDraft draft) async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MobileOutlineEditorPage(
            databasePath: databasePath,
            outlineId: draft.documentId,
          ),
        ),
      );
    }

    Future<void> deleteEntry(OutlineDraft draft) async {
      final confirmed = await showMobileDeleteConfirm(
        context,
        title: draft.title,
      );
      if (!confirmed) {
        return;
      }
      final service = ref.read(novelContentServiceProvider(databasePath));
      await service.outlineService.deleteOutline(draft.documentId);
    }

    // 新建入口由外部标题栏承载；空状态仍保留引导按钮（走 onCreate）。
    return MobileSectionListScaffold(
      createLabel: context.t(LocaleKeys.workspaceNewOutline),
      onCreate: onCreate,
      showCreateBar: false,
      bottomAction: MobileSectionBottomAction(
        label: context.t(LocaleKeys.workspaceImportFile),
        onTap: onImport,
      ),
      emptyIcon: RevericIcons.timeline_outlined,
      emptySectionLabel: context.t(LocaleKeys.workspaceOutlines),
      emptyHint: context.t(LocaleKeys.workspaceOutlinesHint),
      itemCount: enabled.length,
      itemBuilder: (_, index) => _OutlineCard(
        d: enabled[index],
        onTap: openEditor,
        onDelete: deleteEntry,
      ),
    );
  }
}

class _OutlineCard extends StatelessWidget {
  const _OutlineCard({
    required this.d,
    required this.onTap,
    required this.onDelete,
  });

  final OutlineDraft d;
  final ValueChanged<OutlineDraft> onTap;
  final ValueChanged<OutlineDraft> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final title = d.title.trim().isEmpty
        ? context.t(LocaleKeys.commonUntitled)
        : d.title.trim();
    final preview = d.content.trim();
    final statusColor = _statusColor(d.status, colors);
    final statusLabel = _statusLabel(context, d.status);

    return MobileSectionCard(
      onTap: () => onTap(d),
      onDelete: () => onDelete(d),
      deleteLabel: context.t(LocaleKeys.commonDelete),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MobileSectionStatusHeader(
            statusColor: statusColor,
            title: title,
            statusLabel: statusLabel,
          ),
          const SizedBox(height: RevericSpacing.sm),
          MobileSectionPreviewText(
            preview: preview,
            emptyPlaceholder: context.t(LocaleKeys.mobileEditorEntryNoContent),
          ),
          if (d.beats.isNotEmpty) ...[
            const SizedBox(height: RevericSpacing.sm),
            Row(
              children: [
                RevericIcon(
                  RevericIcons.timeline_outlined,
                  size: 12,
                  color: colors.textSubtle,
                ),
                const SizedBox(width: RevericSpacing.xxs),
                Text(
                  context.t(
                    LocaleKeys.workspaceOutlineBeatChapterCountValue,
                    namedArgs: {'count': '${d.beats.length}'},
                  ),
                  style: typo.uiTiny.copyWith(color: colors.textSubtle),
                ),
                const Spacer(),
                const MobileSectionTrailingChevron(),
              ],
            ),
          ] else ...[
            const SizedBox(height: RevericSpacing.sm),
            const Align(
              alignment: Alignment.centerRight,
              child: MobileSectionTrailingChevron(),
            ),
          ],
        ],
      ),
    );
  }
}

Color _statusColor(String status, RevericColors colors) {
  return switch (status) {
    outlineStatusInProgress => colors.accent,
    outlineStatusFinished => colors.accentWarm,
    _ => colors.warningText,
  };
}

String _statusLabel(BuildContext context, String status) {
  return switch (status) {
    outlineStatusInProgress => context.t(
      LocaleKeys.workspaceOutlineStatusInProgress,
    ),
    outlineStatusFinished => context.t(
      LocaleKeys.workspaceOutlineStatusFinished,
    ),
    _ => context.t(LocaleKeys.workspaceOutlineStatusPending),
  };
}
