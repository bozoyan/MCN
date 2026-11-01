// 职责: 章节批注气泡卡片 — 展示被批注的原文并编辑、解决或删除这条批注。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_comment_session.dart
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/shared/models/chapter_comment.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/comment.json
//   assets/translations/zh-CN/comment.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/chapter_comment.dart';
import '../../../shared/theme/theme.dart';

/// 批注气泡的宽度。定位方也要用它做视口边界收拢，所以公开。
const double chapterCommentPopoverWidth = 340;

/// 锚定在正文选区旁的批注卡片。
///
/// [comment] 为 null 表示正在新建；否则是查看/编辑一条既有批注。
/// 内容始终可编辑（一条批注 = 一段可修改的文字），有改动才出现保存/取消。
class ChapterCommentPopover extends HookWidget {
  const ChapterCommentPopover({
    super.key,
    this.comment,
    required this.quote,
    this.orphaned = false,
    required this.onSubmit,
    required this.onContentChanged,
    required this.onClose,
    required this.onCancel,
    this.onToggleResolved,
    this.onDelete,
  });

  final ChapterComment? comment;

  /// 被批注的正文片段。新建时是当前选区文本。
  final String quote;

  /// 原文已被改写、锚点失效。
  final bool orphaned;

  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onContentChanged;
  final VoidCallback onClose;
  final VoidCallback onCancel;
  final VoidCallback? onToggleResolved;
  final VoidCallback? onDelete;

  bool get _isDraft => comment == null;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    final controller = useTextEditingController(text: comment?.content ?? '');
    final focusNode = useFocusNode();
    final draft = useState(controller.text);
    final commentId = comment?.id;

    // 切到另一条批注时把编辑框换成那一条的内容。
    useEffect(() {
      controller.text = comment?.content ?? '';
      draft.value = controller.text;
      return null;
    }, [commentId]);

    useOnListenableChange(controller, () {
      draft.value = controller.text;
    });

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          focusNode.requestFocus();
        }
      });
      return null;
    }, [commentId]);

    final text = draft.value.trim();
    final isDirty = text != (comment?.content ?? '').trim();
    final canSubmit = text.isNotEmpty && isDirty;
    final resolved = comment?.isResolved ?? false;

    void submit() {
      if (!canSubmit) {
        return;
      }
      onSubmit(text);
    }

    return Material(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(RevericRadius.x2l),
      color: colors.surfaceContainer,
      child: Container(
        width: chapterCommentPopoverWidth,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RevericRadius.x2l),
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              isDraft: _isDraft,
              resolved: resolved,
              onToggleResolved: onToggleResolved,
              onDelete: onDelete,
              onClose: onClose,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x2l,
                RevericSpacing.lg,
                RevericSpacing.x2l,
                RevericSpacing.x2l,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Quote(quote: quote),
                  if (orphaned) ...[
                    const SizedBox(height: RevericSpacing.md),
                    _OrphanedNotice(),
                  ],
                  const SizedBox(height: RevericSpacing.lg),
                  _Field(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onContentChanged,
                  ),
                  const SizedBox(height: RevericSpacing.md),
                  _Actions(
                    canSubmit: canSubmit,
                    isDirty: isDirty,
                    isDraft: _isDraft,
                    onSubmit: submit,
                    onCancel: () {
                      if (_isDraft) {
                        onCancel();
                        return;
                      }
                      if (!isDirty) {
                        onClose();
                        return;
                      }
                      controller.text = comment?.content ?? '';
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isDraft,
    required this.resolved,
    required this.onToggleResolved,
    required this.onDelete,
    required this.onClose,
  });

  final bool isDraft;
  final bool resolved;
  final VoidCallback? onToggleResolved;
  final VoidCallback? onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x2l,
        RevericSpacing.sm,
        RevericSpacing.sm,
        RevericSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          RevericIcon(
            RevericIcons.chat_outlined,
            size: 14,
            color: colors.textMuted,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              context.t(
                isDraft
                    ? LocaleKeys.commonCreate
                    : resolved
                    ? LocaleKeys.commentResolvedTitle
                    : LocaleKeys.commentTitle,
              ),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isDraft && onToggleResolved != null)
            IconButton(
              tooltip: context.t(
                resolved ? LocaleKeys.commentReopen : LocaleKeys.commentResolve,
              ),
              onPressed: onToggleResolved,
              iconSize: 14,
              padding: const EdgeInsets.all(RevericSpacing.xs),
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              icon: RevericIcon(
                resolved ? RevericIcons.undo : RevericIcons.check,
                size: 14,
                color: resolved ? colors.textMuted : colors.success,
              ),
            ),
          if (!isDraft && onDelete != null)
            IconButton(
              tooltip: context.t(LocaleKeys.commonDelete),
              onPressed: onDelete,
              iconSize: 14,
              padding: const EdgeInsets.all(RevericSpacing.xs),
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              icon: RevericIcon(
                RevericIcons.delete_outline,
                size: 14,
                color: colors.textMuted,
              ),
            ),
          IconButton(
            tooltip: context.t(LocaleKeys.commonClose),
            onPressed: onClose,
            iconSize: 14,
            padding: const EdgeInsets.all(RevericSpacing.xs),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            icon: RevericIcon(
              RevericIcons.close_rounded,
              size: 14,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.quote});

  final String quote;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      padding: const EdgeInsets.only(left: RevericSpacing.lg),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colors.blockquoteBorder, width: 2),
        ),
      ),
      child: Text(
        quote,
        style: typo.bodySmall.copyWith(
          color: colors.textSecondary,
          fontStyle: FontStyle.italic,
          height: 1.6,
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _OrphanedNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: RevericIcon(
            RevericIcons.warning_amber_rounded,
            size: 13,
            color: colors.accentAmber,
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        Expanded(
          child: Text(
            context.t(LocaleKeys.commentOrphanedHint),
            style: typo.uiTiny.copyWith(color: colors.textMuted, height: 1.45),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      minLines: 3,
      maxLines: 6,
      style: typo.bodySmall.copyWith(color: colors.textPrimary, height: 1.6),
      decoration: InputDecoration(
        hintText: context.t(LocaleKeys.commentContentHint),
        hintStyle: typo.bodySmall.copyWith(color: colors.textSubtle),
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.all(RevericSpacing.lg),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RevericRadius.large),
          borderSide: BorderSide(color: colors.borderInput),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RevericRadius.large),
          borderSide: BorderSide(color: colors.borderInput),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RevericRadius.large),
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.canSubmit,
    required this.isDirty,
    required this.isDraft,
    required this.onSubmit,
    required this.onCancel,
  });

  final bool canSubmit;
  final bool isDirty;
  final bool isDraft;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Row(
      children: [
        const Spacer(),
        if (isDraft || isDirty)
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, RevericSizes.buttonHeightSm),
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.lg,
              ),
              foregroundColor: colors.textSecondary,
              textStyle: typo.uiSmall,
            ),
            child: Text(context.t(LocaleKeys.commonCancel)),
          ),
        const SizedBox(width: RevericSpacing.sm),
        FilledButton(
          onPressed: canSubmit ? onSubmit : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, RevericSizes.buttonHeightSm),
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.x2l,
            ),
            textStyle: typo.uiSmall,
          ),
          child: Text(context.t(LocaleKeys.commonSave)),
        ),
      ],
    );
  }
}
