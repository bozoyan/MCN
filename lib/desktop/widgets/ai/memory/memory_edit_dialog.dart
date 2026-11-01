// 职责: Memory 编辑对话框 — 新建/编辑记忆条目的表单弹窗
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   lib/shared/services/ai/memory_service.dart
//   lib/shared/database/app_database.dart
//   lib/shared/components/reveric_switch.dart
//   lib/desktop/widgets/ai/memory_list.dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/components/reveric_switch.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/providers/memory_providers.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../shared/components/reveric_dialog.dart';
import '../../../../shared/components/reveric_button.dart';

class MemoryEditDialog extends HookConsumerWidget {
  const MemoryEditDialog({super.key, this.existingMemory, this.novelId});

  final Memory? existingMemory;
  final String? novelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isEditing = existingMemory != null;

    final contentController = useTextEditingController(
      text: existingMemory?.content ?? '',
    );
    final categoryState = useState<String>(
      existingMemory?.category ?? memoryCategoryFact,
    );
    final priorityState = useState<String>(
      existingMemory?.priority ?? memoryPriorityContext,
    );
    final enabledState = useState<bool>(existingMemory?.enabled ?? true);
    final contentError = useState<String?>(null);

    final categories = [
      (memoryCategoryPreference, LocaleKeys.memoryCategoryPreference),
      (memoryCategoryFact, LocaleKeys.memoryCategoryFact),
      (memoryCategoryDecision, LocaleKeys.memoryCategoryDecision),
      (memoryCategoryStyle, LocaleKeys.memoryCategoryStyle),
      (memoryCategoryWorldview, LocaleKeys.memoryCategoryWorldview),
      (memoryCategoryCharacter, LocaleKeys.memoryCategoryCharacter),
    ];

    final priorities = [
      (memoryPriorityCore, LocaleKeys.memoryPriorityCore),
      (memoryPriorityContext, LocaleKeys.memoryPriorityContext),
    ];

    return RevericDialog.panel(
      title: Text(
        isEditing
            ? context.t(LocaleKeys.commonEdit)
            : context.t(LocaleKeys.commonCreate),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t(LocaleKeys.memoryContent),
              style: typo.uiSemibold.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: RevericSpacing.xs),
            TextField(
              controller: contentController,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                hintText: context.t(LocaleKeys.memoryContentHint),
                hintStyle: typo.ui.copyWith(color: colors.textMuted),
                filled: true,
                fillColor: colors.surfaceContainer,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.medium),
                  borderSide: BorderSide(color: colors.borderInput),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.medium),
                  borderSide: BorderSide(color: colors.borderInput),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.medium),
                  borderSide: BorderSide(color: colors.accent),
                ),
                errorText: contentError.value,
              ),
              style: typo.ui.copyWith(color: colors.textPrimary),
              onChanged: (_) {
                if (contentError.value != null) {
                  contentError.value = null;
                }
              },
            ),
            const SizedBox(height: RevericSpacing.lg),
            Text(
              context.t(LocaleKeys.memoryCategory),
              style: typo.uiSemibold.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: RevericSpacing.xs),
            Wrap(
              spacing: RevericSpacing.sm,
              runSpacing: RevericSpacing.sm,
              children: [
                for (final (value, key) in categories)
                  _buildChip(
                    context,
                    label: context.t(key),
                    isSelected: categoryState.value == value,
                    onTap: () => categoryState.value = value,
                  ),
              ],
            ),
            const SizedBox(height: RevericSpacing.lg),
            Text(
              context.t(LocaleKeys.memoryPriority),
              style: typo.uiSemibold.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: RevericSpacing.xs),
            Row(
              children: [
                for (final (value, key) in priorities)
                  Padding(
                    padding: const EdgeInsets.only(right: RevericSpacing.sm),
                    child: _buildChip(
                      context,
                      label: context.t(key),
                      isSelected: priorityState.value == value,
                      onTap: () => priorityState.value = value,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: RevericSpacing.lg),
            Row(
              children: [
                RevericSwitch(
                  value: enabledState.value,
                  onChanged: (v) => enabledState.value = v,
                ),
                const SizedBox(width: RevericSpacing.sm),
                Text(
                  enabledState.value
                      ? context.t(LocaleKeys.memoryEnabled)
                      : context.t(LocaleKeys.memoryDisabled),
                  style: typo.ui.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),

      width: 480 + RevericSpacing.x4l * 2,

      actions: [
        RevericButton.secondary(
          label: MaterialLocalizations.of(context).cancelButtonLabel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RevericButton.primary(
          label: isEditing
              ? MaterialLocalizations.of(context).saveButtonLabel
              : context.t(LocaleKeys.commonCreate),
          onPressed: () async {
            final content = contentController.text.trim();
            if (content.isEmpty) {
              contentError.value = context.t(LocaleKeys.memoryContentRequired);
              return;
            }

            final service = ref.read(memoryServiceProvider);
            if (isEditing) {
              await service.updateContent(
                id: existingMemory!.id,
                content: content,
                category: categoryState.value,
                priority: priorityState.value,
                enabled: enabledState.value,
              );
            } else {
              await service.create(
                category: categoryState.value,
                content: content,
                novelId: novelId,
                priority: priorityState.value,
                enabled: enabledState.value,
              );
            }

            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.md,
          vertical: RevericSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.accent.withValues(alpha: 0.15)
              : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          border: Border.all(
            color: isSelected ? colors.accent : colors.borderInput,
          ),
        ),
        child: Text(
          label,
          style: (isSelected ? typo.uiSmallSemibold : typo.uiSmall).copyWith(
            color: isSelected ? colors.accent : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
