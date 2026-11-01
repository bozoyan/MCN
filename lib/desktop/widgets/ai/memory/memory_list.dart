// 职责: Memory 列表组件 — 展示记忆条目列表，支持新建/编辑/删除/启禁用，全局和小说级复用
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   lib/shared/providers/memory_providers.dart
//   lib/shared/database/app_database.dart
//   lib/desktop/widgets/ai/memory/memory_edit_dialog.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/providers/memory_providers.dart';
import '../../../../shared/theme/theme.dart';
import 'memory_edit_dialog.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/components/reveric_dialog.dart';

class MemoryList extends ConsumerWidget {
  const MemoryList({
    super.key,
    this.novelId,
    this.showHeader = true,
    this.compact = false,
  });

  final String? novelId;
  final bool showHeader;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoriesAsync = novelId != null
        ? ref.watch(novelMemoriesProvider(novelId!))
        : ref.watch(globalMemoriesProvider);

    return memoriesAsync.when(
      data: (memories) => _buildContent(context, ref, memories),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<Memory> memories,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) _buildHeader(context, ref),
        if (memories.isEmpty)
          _buildEmptyState(context)
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: RevericSpacing.xs),
              itemCount: memories.length,
              itemBuilder: (context, index) =>
                  _buildMemoryRow(context, ref, memories[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x2l,
        RevericSpacing.md,
        RevericSpacing.sm,
        RevericSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            context.t(LocaleKeys.memoryTitle),
            style: typo.uiTinySemibold.copyWith(
              color: colors.textSubtle,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: context.t(LocaleKeys.commonCreate),
            onPressed: () => _showEditDialog(context, ref),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: RevericIcon(
              RevericIcons.add,
              size: 16,
              color: colors.textSubtle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x2l,
        vertical: RevericSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RevericIcon(
            RevericIcons.psychology_outlined,
            size: 24,
            color: colors.textSubtle.withValues(alpha: 0.5),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            context.t(LocaleKeys.memoryEmpty),
            style: typo.uiSmall.copyWith(color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryRow(BuildContext context, WidgetRef ref, Memory memory) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isCore = memory.priority == memoryPriorityCore;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showEditDialog(context, ref, existing: memory),
        hoverColor: colors.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.x2l,
            vertical: RevericSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: !memory.enabled
                      ? colors.textSubtle
                      : isCore
                      ? colors.accent
                      : colors.accent.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memory.content,
                      style:
                          (memory.enabled
                                  ? typo.uiSmall
                                  : typo.uiSmall.copyWith(
                                      decoration: TextDecoration.lineThrough,
                                    ))
                              .copyWith(
                                color: memory.enabled
                                    ? colors.textPrimary
                                    : colors.textMuted,
                              ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: RevericSpacing.xxs),
                    Row(
                      children: [
                        _buildTag(
                          context,
                          label: _categoryLabel(context, memory.category),
                        ),
                        const SizedBox(width: RevericSpacing.xs),
                        _buildTag(
                          context,
                          label: isCore
                              ? context.t(LocaleKeys.memoryPriorityCore)
                              : context.t(LocaleKeys.memoryPriorityContext),
                          isAccent: isCore,
                        ),
                        if (!memory.enabled) ...[
                          const SizedBox(width: RevericSpacing.xs),
                          _buildTag(
                            context,
                            label: context.t(LocaleKeys.memoryDisabled),
                            isMuted: true,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _confirmDelete(context, ref, memory),
                borderRadius: BorderRadius.circular(RevericRadius.small),
                child: Padding(
                  padding: const EdgeInsets.all(RevericSpacing.xxs),
                  child: RevericIcon(
                    RevericIcons.close,
                    size: 12,
                    color: colors.textSubtle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(
    BuildContext context, {
    required String label,
    bool isAccent = false,
    bool isMuted = false,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    Color bgColor;
    Color textColor;
    if (isMuted) {
      bgColor = colors.surfaceContainer;
      textColor = colors.textMuted;
    } else if (isAccent) {
      bgColor = colors.accent.withValues(alpha: 0.12);
      textColor = colors.accent;
    } else {
      bgColor = colors.surfaceContainer;
      textColor = colors.textSubtle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(RevericRadius.small),
      ),
      child: Text(label, style: typo.uiTiny.copyWith(color: textColor)),
    );
  }

  String _categoryLabel(BuildContext context, String category) {
    return switch (category) {
      memoryCategoryPreference => context.t(
        LocaleKeys.memoryCategoryPreference,
      ),
      memoryCategoryFact => context.t(LocaleKeys.memoryCategoryFact),
      memoryCategoryDecision => context.t(LocaleKeys.memoryCategoryDecision),
      memoryCategoryStyle => context.t(LocaleKeys.memoryCategoryStyle),
      memoryCategoryWorldview => context.t(LocaleKeys.memoryCategoryWorldview),
      memoryCategoryCharacter => context.t(LocaleKeys.memoryCategoryCharacter),
      _ => category,
    };
  }

  void _showEditDialog(
    BuildContext context,
    WidgetRef ref, {
    Memory? existing,
  }) {
    showRevericDialog(
      context: context,
      builder: (_) =>
          MemoryEditDialog(existingMemory: existing, novelId: novelId),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Memory memory,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.t(LocaleKeys.commonDelete),
      message: context.t(LocaleKeys.memoryDeleteConfirm),
      confirmLabel: context.t(LocaleKeys.commonDelete),
      variant: ConfirmDialogVariant.error,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await ref.read(memoryServiceProvider).softDelete(memory.id);
  }
}
