// 职责: 移动端节奏点编辑页 — 编辑单个 timeline beat 的标题/状态/计划章数/正文 markdown，返回 OutlineBeatDraft。
// 关联文件:
//   lib/mobile/pages/outline_editor_page.dart
//   lib/shared/components/reveric_select.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/models/outline.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../shared/components/reveric_select.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/outline.dart';
import '../../shared/utils/short_entity_id.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/md/reveric_markdown_editor.dart';

/// 编辑单个节奏点，pop 时返回更新后的 [OutlineBeatDraft]；用户取消返回 null。
class MobileOutlineBeatEditorPage extends HookWidget {
  const MobileOutlineBeatEditorPage({super.key, this.beat});

  final OutlineBeatDraft? beat;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final current = beat;

    final titleController = useTextEditingController(
      text: current?.title ?? '',
    );
    final contentController = useTextEditingController(
      text: current?.content ?? '',
    );
    final contentFocusNode = useFocusNode();
    final status = useState<String>(current?.status ?? outlineStatusPending);
    final chapterCount = useState<int>(current?.chapterCount ?? 5);

    void submit() {
      Navigator.of(context).pop(
        (current ??
                OutlineBeatDraft(
                  id: buildShortEntityId(ShortEntityIdType.outlineBeat),
                  isNew: true,
                ))
            .copyWith(
              title: titleController.text,
              content: contentController.text,
              status: status.value,
              chapterCount: chapterCount.value,
            ),
      );
    }

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _BeatHeader(
              isNew: current == null,
              onBack: () => Navigator.of(context).maybePop(),
              onSave: submit,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.x4l,
                  RevericSpacing.lg,
                  RevericSpacing.x4l,
                  RevericSpacing.x4l,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      maxLines: 1,
                      textInputAction: TextInputAction.next,
                      autofocus: current == null,
                      style: typo.heading2.copyWith(color: colors.textPrimary),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: context.t(
                          LocaleKeys.workspaceOutlineBeatTitleHint,
                        ),
                        hintStyle: typo.heading2.copyWith(
                          color: colors.textSubtle,
                        ),
                      ),
                    ),
                    const SizedBox(height: RevericSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: RevericSelect<String>(
                            value: status.value,
                            label: context.t(LocaleKeys.commonStatus),
                            items: [
                              for (final s in outlineStatuses)
                                RevericSelectItem<String>(
                                  value: s,
                                  label: _statusLabel(context, s),
                                  color: _statusColor(s, colors),
                                ),
                            ],
                            onChanged: (next) {
                              status.value = next;
                            },
                          ),
                        ),
                        const SizedBox(width: RevericSpacing.lg),
                        _ChapterCountStepper(
                          count: chapterCount.value,
                          onChanged: (v) => chapterCount.value = v,
                        ),
                      ],
                    ),
                    const SizedBox(height: RevericSpacing.lg),
                    Row(
                      children: [
                        Text(
                          context.t(LocaleKeys.commonContent),
                          style: typo.uiSemibold.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            final template = context.t(
                              LocaleKeys.workspaceOutlineBeatContentTemplate,
                            );
                            final existing = contentController.text.trim();
                            contentController.text = existing.isEmpty
                                ? template
                                : '$existing\n\n$template';
                            contentFocusNode.requestFocus();
                            contentController.selection =
                                TextSelection.collapsed(
                                  offset: contentController.text.length,
                                );
                          },
                          icon: RevericIcon(
                            RevericIcons.format_list_bulleted,
                            size: 16,
                            color: colors.accent,
                          ),
                          label: Text(
                            context.t(
                              LocaleKeys.workspaceOutlineBeatInsertTemplate,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: RevericSpacing.sm),
                    Expanded(
                      child: RevericMarkdownEditor(
                        controller: contentController,
                        focusNode: contentFocusNode,
                        hintText: context.t(
                          LocaleKeys.workspaceOutlineBeatContentHint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeatHeader extends StatelessWidget {
  const _BeatHeader({
    required this.isNew,
    required this.onBack,
    required this.onSave,
  });

  final bool isNew;
  final VoidCallback onBack;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.xs,
        RevericSpacing.sm,
        RevericSpacing.xs,
        RevericSpacing.sm,
      ),
      child: Row(
        children: [
          _HeaderIconButton(icon: RevericIcons.arrow_back, onTap: onBack),
          Expanded(
            child: Text(
              isNew
                  ? context.t(LocaleKeys.workspaceOutlineAddBeat)
                  : context.t(LocaleKeys.commonEdit),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
          ),
          _HeaderIconButton(icon: RevericIcons.check, onTap: onSave),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.sm),
        child: RevericIcon(icon, size: 22, color: colors.textSecondary),
      ),
    );
  }
}

class _ChapterCountStepper extends StatelessWidget {
  const _ChapterCountStepper({required this.count, required this.onChanged});

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    // 与 RevericSelect(label:) 同结构：外置标签 + fieldHeight 触发器，保证与状态选择器顶对齐。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.t(LocaleKeys.workspaceOutlineBeatChapterLabel),
          style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: RevericSpacing.xs),
        Container(
          height: RevericSizes.fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(color: colors.borderInput),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepperButton(
                icon: RevericIcons.remove,
                onPressed: count > 1 ? () => onChanged(count - 1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.sm,
                ),
                child: Text(
                  '$count',
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
              ),
              _StepperButton(
                icon: RevericIcons.add,
                onPressed: count < 999 ? () => onChanged(count + 1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onPressed});

  final String icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final disabled = onPressed == null;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.xs),
        child: RevericIcon(
          icon,
          size: 16,
          color: disabled ? colors.textSubtle : colors.textMuted,
        ),
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
