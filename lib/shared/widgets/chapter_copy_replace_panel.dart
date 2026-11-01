// 职责: 章节标点替换规则面板 — 复用规则编辑 UI 提供替换、复制与替换且复制动作。
// 关联文件:
//   lib/shared/utils/punctuation_replace.dart
//   lib/shared/providers/chapter_copy_replace_rules_provider.dart
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/mobile/pages/chapter_editor_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../components/dialog_feedback.dart';
import '../components/reveric_text_field.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../providers/chapter_copy_replace_rules_provider.dart';
import '../theme/theme.dart';
import '../utils/punctuation_replace.dart';

enum _ChapterPunctuationDialogMode { copy, replace }

/// 打开章节复制 UI。桌面用 Dialog，移动端用 BottomSheet。
Future<void> showChapterCopyReplace(
  BuildContext context, {
  required TextEditingController contentController,
}) {
  return _showChapterPunctuationDialog(
    context,
    contentController: contentController,
    mode: _ChapterPunctuationDialogMode.copy,
  );
}

/// 打开章节标点替换 UI，并在替换成功后由调用方保存正文。
Future<void> showChapterPunctuationReplace(
  BuildContext context, {
  required TextEditingController contentController,
  required Future<void> Function(String replaced) onReplace,
}) {
  return _showChapterPunctuationDialog(
    context,
    contentController: contentController,
    mode: _ChapterPunctuationDialogMode.replace,
    onReplace: onReplace,
  );
}

Future<void> _showChapterPunctuationDialog(
  BuildContext context, {
  required TextEditingController contentController,
  required _ChapterPunctuationDialogMode mode,
  Future<void> Function(String replaced)? onReplace,
}) {
  final colors = RevericTheme.colorsOf(context);
  final isMobile = Platform.isAndroid || Platform.isIOS;
  final panel = _ChapterCopyReplacePanel(
    contentController: contentController,
    mode: mode,
    onReplace: onReplace,
  );

  if (isMobile) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colors.surface,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(child: panel),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: DialogFeedback.intrinsic(builder: (context) => panel),
      ),
    ),
  );
}

class _ChapterCopyReplacePanel extends HookConsumerWidget {
  const _ChapterCopyReplacePanel({
    required this.contentController,
    required this.mode,
    this.onReplace,
  });

  final TextEditingController contentController;
  final _ChapterPunctuationDialogMode mode;
  final Future<void> Function(String replaced)? onReplace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final rulesAsync = ref.watch(chapterCopyReplaceRulesProvider);
    final fromController = useTextEditingController();
    final toController = useTextEditingController();
    final busy = useState(false);
    final rulesBusy = useState(false);
    final rules = rulesAsync.asData?.value ?? const <PunctuationReplaceRule>[];
    final rulesReady = rulesAsync.hasValue;
    final canEditRules = rulesReady && !busy.value && !rulesBusy.value;

    void showFailure() {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
      );
    }

    Future<void> persistRules(
      List<PunctuationReplaceRule> next, {
      bool clearInputs = false,
    }) async {
      if (!canEditRules) {
        return;
      }
      rulesBusy.value = true;
      try {
        await ref.read(chapterCopyReplaceRulesProvider.notifier).save(next);
        if (clearInputs) {
          fromController.clear();
          toController.clear();
        }
      } catch (_) {
        showFailure();
      } finally {
        if (context.mounted) {
          rulesBusy.value = false;
        }
      }
    }

    Future<void> addRule() async {
      final from = fromController.text;
      final to = toController.text;
      if (from.isEmpty) {
        return;
      }
      await persistRules([
        ...rules,
        PunctuationReplaceRule(from: from, to: to),
      ], clearInputs: true);
    }

    Future<void> removeRule(int index) async {
      if (index < 0 || index >= rules.length) {
        return;
      }
      final next = [...rules]..removeAt(index);
      await persistRules(next);
    }

    Future<void> runAction(
      Future<void> Function() action, {
      required String successLabel,
    }) async {
      if (busy.value) {
        return;
      }
      busy.value = true;
      try {
        await action();
        if (!context.mounted) {
          return;
        }
        final messenger = DialogFeedback.hostMessengerOf(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(content: Text(successLabel)));
      } catch (_) {
        showFailure();
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    }

    Future<void> copyOnly() async {
      await runAction(
        () => Clipboard.setData(ClipboardData(text: contentController.text)),
        successLabel: context.t(LocaleKeys.commonCopied),
      );
    }

    Future<void> replaceAndCopy() async {
      if (!rulesReady) {
        return;
      }
      final replaced = applyPunctuationReplace(contentController.text, rules);
      await runAction(
        () => Clipboard.setData(ClipboardData(text: replaced)),
        successLabel: context.t(LocaleKeys.commonCopied),
      );
    }

    Future<void> replace() async {
      if (!rulesReady || onReplace == null) {
        return;
      }
      final replaced = applyPunctuationReplace(contentController.text, rules);
      await runAction(
        () => onReplace!(replaced),
        successLabel: context.t(LocaleKeys.commonSaved),
      );
    }

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(RevericRadius.x2l),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RevericSpacing.x3l,
          RevericSpacing.x3l,
          RevericSpacing.x3l,
          RevericSpacing.x2l,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t(LocaleKeys.workspaceChapterCopyReplaceTitle),
              style: typo.heading2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.x2l),
            Text(
              context.t(LocaleKeys.workspaceChapterCopyRules),
              style: typo.uiSemibold.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: RevericSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: rulesAsync.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : rulesAsync.hasError
                  ? Center(
                      child: Text(
                        context.t(LocaleKeys.commonLoadFailed),
                        style: typo.ui.copyWith(color: colors.error),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: rules.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: RevericSpacing.sm),
                      itemBuilder: (context, index) {
                        final rule = rules[index];
                        return _RuleRow(
                          rule: rule,
                          onDelete: canEditRules
                              ? () => removeRule(index)
                              : null,
                        );
                      },
                    ),
            ),
            const SizedBox(height: RevericSpacing.x2l),
            Text(
              context.t(LocaleKeys.workspaceChapterCopyAddRule),
              style: typo.uiSemibold.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: RevericSpacing.md),
            Row(
              children: [
                Expanded(
                  child: RevericTextField(
                    controller: fromController,
                    enabled: canEditRules,
                    hintText: context.t(LocaleKeys.workspaceChapterCopyFrom),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.md,
                  ),
                  child: Text(
                    '→',
                    style: typo.ui.copyWith(color: colors.textMuted),
                  ),
                ),
                Expanded(
                  child: RevericTextField(
                    controller: toController,
                    enabled: canEditRules,
                    hintText: context.t(LocaleKeys.workspaceChapterCopyTo),
                  ),
                ),
                const SizedBox(width: RevericSpacing.sm),
                Tooltip(
                  message: context.t(LocaleKeys.workspaceChapterCopyAddRule),
                  child: IconButton.filled(
                    onPressed: canEditRules ? addRule : null,
                    icon: RevericIcon(
                      RevericIcons.add,
                      size: 18,
                      color: colors.onAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: RevericSpacing.x3l),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy.value
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(context.t(LocaleKeys.commonCancel)),
                ),
                const SizedBox(width: RevericSpacing.sm),
                if (mode == _ChapterPunctuationDialogMode.copy) ...[
                  TextButton(
                    onPressed: busy.value ? null : copyOnly,
                    child: Text(context.t(LocaleKeys.workspaceChapterCopy)),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                ],
                FilledButton(
                  onPressed: busy.value || rulesBusy.value || !rulesReady
                      ? null
                      : mode == _ChapterPunctuationDialogMode.copy
                      ? replaceAndCopy
                      : replace,
                  child: Text(
                    mode == _ChapterPunctuationDialogMode.copy
                        ? context.t(
                            LocaleKeys.workspaceChapterCopyReplaceAction,
                          )
                        : context.t(LocaleKeys.workspaceChapterReplace),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule, required this.onDelete});

  final PunctuationReplaceRule rule;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: RevericSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.large),
      ),
      child: Row(
        children: [
          _RuleChip(text: rule.from),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.md),
            child: Text('→', style: typo.ui.copyWith(color: colors.textMuted)),
          ),
          _RuleChip(text: rule.to),
          const Spacer(),
          Tooltip(
            message: context.t(LocaleKeys.commonDelete),
            child: IconButton(
              onPressed: onDelete,
              icon: RevericIcon(
                RevericIcons.delete_outline,
                size: 16,
                color: colors.textMuted,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 36),
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.md,
        vertical: RevericSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.small),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Text(
        text,
        style: typo.uiSemibold.copyWith(color: colors.textPrimary),
      ),
    );
  }
}
