// 职责: AskUser 工具卡片 — 显示 AI 向用户提出的问题并收集回复
// 关联文件:
//   lib/shared/models/ai_message_block.dart
//   lib/shared/services/ai/tools_ask_user.dart
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:reveric/shared/components/reveric_text_field.dart';
import 'package:reveric/shared/localization/app_localization.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/models/ask_user_models.dart'
    show AskUserAnswer, AskUserOption, AskUserQuestion, AskUserResult;
import 'package:reveric/shared/theme/theme.dart';

/// Displays an AskUser question card with options or free text input.
class AskUserCard extends HookWidget {
  const AskUserCard({
    super.key,
    required this.block,
    required this.onSubmit,
    required this.onCancel,
    this.canSubmit,
    this.isLive,
  });

  final AiAskUserBlock block;
  final ValueChanged<AskUserResult> onSubmit;
  final VoidCallback onCancel;
  final bool Function()? canSubmit;

  /// 只查询已有请求，不应创建运行时或修改状态。
  final bool Function()? isLive;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final block = this.block.isPending && isLive?.call() == false
        ? this.block.copyWith(status: AiAskUserStatus.interrupted)
        : this.block;
    final isPending = block.isPending;
    final questions = _questionsFromBlock(block);
    final resolvedAnswers = block.answers?.map(AskUserAnswer.fromJson).toList();
    final selectedOptionsByQuestion = useState<Map<String, Set<String>>>({});
    final freeTextByQuestion = useState<Map<String, String>>({});
    final errorTextByQuestion = useState<Map<String, String>>({});

    void handleSubmit() {
      if (!isPending || canSubmit?.call() == false) {
        return;
      }

      final nextErrors = <String, String>{};
      final answers = <AskUserAnswer>[];

      for (final question in questions) {
        final selectedOptions =
            selectedOptionsByQuestion.value[question.id] ?? const <String>{};
        final answer = freeTextByQuestion.value[question.id]?.trim() ?? '';
        if (selectedOptions.isEmpty &&
            (!question.allowFreeText || answer.isEmpty)) {
          nextErrors[question.id] = context.t(
            LocaleKeys.askUserErrorSelectionRequired,
          );
        }
        answers.add(
          AskUserAnswer(
            questionId: question.id,
            answer: answer.isEmpty ? null : answer,
            selectedOptions: selectedOptions.isEmpty
                ? null
                : selectedOptions.toList(),
          ),
        );
      }

      if (nextErrors.isNotEmpty) {
        errorTextByQuestion.value = nextErrors;
        return;
      }

      final result = AskUserResult(
        ok: true,
        answers: answers,
        cancelled: false,
      );

      onSubmit(result);
    }

    Widget buildOptionChip(AskUserQuestion question, AskUserOption option) {
      final selectedOptions =
          selectedOptionsByQuestion.value[question.id] ?? const <String>{};
      final isSelected = isPending
          ? selectedOptions.contains(option.label)
          : resolvedAnswers?.any(
                  (answer) =>
                      answer.questionId == question.id &&
                      answer.selectedOptions?.contains(option.label) == true,
                ) ==
                true;
      final description = option.description?.trim();

      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: isPending
              ? () {
                  final nextSelectionByQuestion = Map<String, Set<String>>.from(
                    selectedOptionsByQuestion.value,
                  );
                  if (question.multiSelect) {
                    final newSet = Set<String>.from(selectedOptions);
                    if (isSelected) {
                      newSet.remove(option.label);
                    } else {
                      newSet.add(option.label);
                    }
                    nextSelectionByQuestion[question.id] = newSet;
                  } else {
                    nextSelectionByQuestion[question.id] = {option.label};
                  }
                  selectedOptionsByQuestion.value = nextSelectionByQuestion;
                  errorTextByQuestion.value = Map<String, String>.from(
                    errorTextByQuestion.value,
                  )..remove(question.id);
                }
              : null,
          borderRadius: BorderRadius.circular(RevericRadius.large),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.md,
              vertical: RevericSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.accent.withValues(alpha: 0.15)
                  : colors.surfaceDim,
              borderRadius: BorderRadius.circular(RevericRadius.large),
              border: Border.all(
                color: isSelected ? colors.accent : colors.borderSubtle,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (question.multiSelect)
                  Padding(
                    padding: const EdgeInsets.only(right: RevericSpacing.xs),
                    child: RevericIcon(
                      isSelected
                          ? RevericIcons.check_box_rounded
                          : RevericIcons.check_box_outline_blank_rounded,
                      size: 18,
                      color: isSelected ? colors.accent : colors.textMuted,
                    ),
                  )
                else if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: RevericSpacing.xs),
                    child: RevericIcon(
                      RevericIcons.radio_button_checked_rounded,
                      size: 18,
                      color: colors.accent,
                    ),
                  ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        style: typo.uiSemibold.copyWith(
                          color: isSelected
                              ? colors.accent
                              : colors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      if (description != null && description.isNotEmpty)
                        Text(
                          description,
                          style: typo.uiSmall.copyWith(
                            color: colors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                if (option.recommended)
                  Container(
                    margin: const EdgeInsets.only(left: RevericSpacing.xs),
                    padding: const EdgeInsets.symmetric(
                      horizontal: RevericSpacing.xs,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accentWarm.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(RevericRadius.pill),
                    ),
                    child: Text(
                      context.t(LocaleKeys.askUserRecommended),
                      style: typo.uiSmall.copyWith(
                        color: colors.accentWarm,
                        fontSize: 9,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildQuestionSection(int index, AskUserQuestion question) {
      final options = question.options;
      final errorText = isPending
          ? errorTextByQuestion.value[question.id]
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            questions.length > 1
                ? '${index + 1}. ${question.question}'
                : question.question,
            style: (questions.length > 1 ? typo.uiSemibold : typo.ui).copyWith(
              color: colors.textPrimary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (options != null && options.isNotEmpty) ...[
            const SizedBox(height: RevericSpacing.md),
            Wrap(
              spacing: RevericSpacing.sm,
              runSpacing: RevericSpacing.sm,
              children: options
                  .map((option) => buildOptionChip(question, option))
                  .toList(),
            ),
          ],
          if (question.allowFreeText && isPending) ...[
            const SizedBox(height: RevericSpacing.md),
            RevericTextField(
              fieldKey: ValueKey(
                'ask_user_text_${block.callId}_${question.id}',
              ),
              enabled: isPending,
              multiline: true,
              minLines: 1,
              maxLines: 3,
              hintText: context.t(LocaleKeys.askUserHint),
              onChanged: (value) {
                freeTextByQuestion.value = Map<String, String>.from(
                  freeTextByQuestion.value,
                )..[question.id] = value;
                errorTextByQuestion.value = Map<String, String>.from(
                  errorTextByQuestion.value,
                )..remove(question.id);
              },
            ),
          ],
          if (errorText != null) ...[
            const SizedBox(height: RevericSpacing.xs),
            Text(
              errorText,
              style: typo.uiSmall.copyWith(color: colors.deletionBorder),
            ),
          ],
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: RevericSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with icon and status
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.md,
              vertical: RevericSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceDim,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(RevericRadius.large),
              ),
            ),
            child: Row(
              children: [
                RevericIcon(
                  RevericIcons.help_outline_rounded,
                  size: 16,
                  color: colors.accent,
                ),
                const SizedBox(width: RevericSpacing.xs),
                Expanded(
                  child: Text(
                    context.t(LocaleKeys.askUserTitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSemibold.copyWith(
                      color: colors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                _buildStatusBadge(context, colors, typo, block.status),
              ],
            ),
          ),

          // Question content
          Padding(
            padding: const EdgeInsets.all(RevericSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < questions.length; i++) ...[
                  if (i > 0) const SizedBox(height: RevericSpacing.lg),
                  buildQuestionSection(i, questions[i]),
                ],

                // Answer display (when answered)
                if (block.isAnswered ||
                    block.status == AiAskUserStatus.timed_out) ...[
                  const SizedBox(height: RevericSpacing.md),
                  _AnswerSummary(block: block, colors: colors, typo: typo),
                ],

                if (block.status == AiAskUserStatus.interrupted) ...[
                  const SizedBox(height: RevericSpacing.md),
                  Text(
                    context.t(LocaleKeys.aiAskUserInterrupted),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ],

                // Cancelled state
                if (block.status == AiAskUserStatus.cancelled) ...[
                  const SizedBox(height: RevericSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(RevericSpacing.sm),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(
                        RevericRadius.medium,
                      ),
                    ),
                    child: Text(
                      context.t(LocaleKeys.askUserCancelled),
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action buttons
          if (isPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.md,
                0,
                RevericSpacing.md,
                RevericSpacing.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () {
                      errorTextByQuestion.value = {};
                      onCancel();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RevericSpacing.lg,
                        vertical: RevericSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          RevericRadius.medium,
                        ),
                        border: Border.all(color: colors.borderSubtle),
                      ),
                      child: Text(
                        context.t(LocaleKeys.commonCancel),
                        style: typo.uiSemibold.copyWith(
                          color: colors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  GestureDetector(
                    onTap: isPending ? handleSubmit : null,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RevericSpacing.lg,
                        vertical: RevericSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: isPending ? colors.accent : colors.surfaceDim,
                        borderRadius: BorderRadius.circular(
                          RevericRadius.medium,
                        ),
                      ),
                      child: Text(
                        context.t(LocaleKeys.commonConfirm),
                        style: typo.uiSemibold.copyWith(
                          color: isPending ? colors.surface : colors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
    AiAskUserStatus status,
  ) {
    final (label, color) = switch (status) {
      AiAskUserStatus.pending => (
        context.t(LocaleKeys.askUserStatusPending),
        colors.accent,
      ),
      AiAskUserStatus.answered => (
        context.t(LocaleKeys.askUserStatusAnswered),
        colors.additionBorder,
      ),
      AiAskUserStatus.cancelled => (
        context.t(LocaleKeys.askUserStatusCancelled),
        colors.textMuted,
      ),
      AiAskUserStatus.timed_out => (
        context.t(LocaleKeys.aiAskUserStatusTimedOut),
        colors.textMuted,
      ),
      AiAskUserStatus.interrupted => (
        context.t(LocaleKeys.aiAskUserStatusInterrupted),
        colors.textMuted,
      ),
      AiAskUserStatus.error => (
        context.t(LocaleKeys.askUserStatusError),
        colors.deletionBorder,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
      ),
      child: Text(
        label,
        style: typo.uiSmall.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

List<AskUserQuestion> _questionsFromBlock(AiAskUserBlock block) {
  return block.questions
      .asMap()
      .entries
      .map((entry) => AskUserQuestion.fromJson(entry.value, index: entry.key))
      .where((question) => question.question.trim().isNotEmpty)
      .toList();
}

class _AnswerSummary extends StatelessWidget {
  const _AnswerSummary({
    required this.block,
    required this.colors,
    required this.typo,
  });

  final AiAskUserBlock block;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    final answers = block.answers?.map(AskUserAnswer.fromJson).toList();
    final questionsById = {
      for (final question in _questionsFromBlock(block)) question.id: question,
    };

    return Container(
      padding: const EdgeInsets.all(RevericSpacing.sm),
      decoration: BoxDecoration(
        color: colors.additionBg,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        border: Border.all(color: colors.additionBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (block.status != AiAskUserStatus.timed_out ||
              answers?.isNotEmpty == true) ...[
            Text(
              context.t(
                block.status == AiAskUserStatus.timed_out
                    ? LocaleKeys.aiAskUserAutomaticAnswer
                    : LocaleKeys.askUserYourAnswer,
              ),
              style: typo.uiSmall.copyWith(
                color: colors.textMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: RevericSpacing.xxs),
          ],
          for (final id in block.unansweredQuestionIds ?? const <String>[]) ...[
            Text(
              questionsById[id]?.question ?? id,
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
            Text(
              context.t(LocaleKeys.aiAskUserUnanswered),
              style: typo.ui.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.sm),
          ],
          if (answers != null && answers.isNotEmpty)
            for (var i = 0; i < answers.length; i++) ...[
              if (i > 0) const SizedBox(height: RevericSpacing.sm),
              _AnswerLine(
                answer: answers[i],
                question: questionsById[answers[i].questionId],
                colors: colors,
                typo: typo,
              ),
            ],
        ],
      ),
    );
  }
}

class _AnswerLine extends StatelessWidget {
  const _AnswerLine({
    required this.answer,
    required this.question,
    required this.colors,
    required this.typo,
  });

  final AskUserAnswer answer;
  final AskUserQuestion? question;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (question != null)
          Text(
            question!.question,
            style: typo.uiSmall.copyWith(color: colors.textMuted, fontSize: 11),
          ),
        if (answer.selectedOptions != null)
          Text(
            answer.selectedOptions!.join(', '),
            style: typo.uiSemibold.copyWith(color: colors.additionBorder),
          ),
        if (answer.answer != null)
          Text(
            answer.answer!,
            style: typo.ui.copyWith(color: colors.textPrimary),
          ),
      ],
    );
  }
}
