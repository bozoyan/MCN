// 职责: 桌面端议会设置区 — 议题输入、成员多选与编辑、讨论轮数、模型选择与开始按钮。
// 关联文件:
//   lib/shared/hooks/use_council_run.dart
//   lib/shared/widgets/ai/council/participant.dart
//   lib/desktop/features/council/panel.dart
//   lib/desktop/widgets/ai/model/model_selector.dart
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/hooks/use_council_run.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/agent_council_models.dart';
import '../../../shared/models/ai_provider.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/agent_avatar.dart';
import '../../../shared/widgets/ai/agent_message_card.dart';
import '../../../shared/widgets/ai/council/participant.dart';
import '../../widgets/ai/model/model_selector.dart';

InputDecoration _fieldDecoration(
  RevericColors colors,
  RevericTypography typo, {
  String? hint,
}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(RevericRadius.xl),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: typo.ui.copyWith(color: colors.textSubtle),
    filled: true,
    fillColor: colors.surface,
    border: border(colors.borderInput),
    enabledBorder: border(colors.borderInput),
    focusedBorder: border(colors.accent),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: RevericSpacing.lg,
      vertical: RevericSpacing.md,
    ),
  );
}

class CouncilSetupSection extends StatelessWidget {
  const CouncilSetupSection({
    super.key,
    required this.run,
    required this.modelSelector,
  });

  final CouncilRun run;
  final Widget modelSelector;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final t = context.t;
    final participants = run.participants;
    final selected = run.selectedParticipantIds;
    final compactButton = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(RevericSpacing.x2l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SetupBlock(
                  icon: RevericIcons.edit_note_outlined,
                  accentColor: colors.accent,
                  title: t(LocaleKeys.councilTopic),
                  child: TextField(
                    controller: run.topicController,
                    maxLines: 3,
                    minLines: 2,
                    style: typo.ui.copyWith(color: colors.textPrimary),
                    decoration: _fieldDecoration(
                      colors,
                      typo,
                      hint: t(LocaleKeys.councilTopicHint),
                    ),
                  ),
                ),
                const SizedBox(height: RevericSpacing.x2l),
                _SetupBlock(
                  icon: RevericIcons.groups_outlined,
                  accentColor: colors.accentWarm,
                  title: t(LocaleKeys.councilSelectParticipants),
                  trailing: Text(
                    t(
                      LocaleKeys.councilParticipantsCountFmt,
                      namedArgs: {
                        'selected': '${selected.length}',
                        'total': '${participants.length}',
                      },
                    ),
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TextButton(
                            onPressed: selected.length == participants.length
                                ? null
                                : () => run.setSelectedParticipants({
                                    for (final p in participants) p.id,
                                  }),
                            style: compactButton,
                            child: Text(
                              t(LocaleKeys.commonSelectAll),
                              style: typo.uiTiny.copyWith(color: colors.accent),
                            ),
                          ),
                          TextButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () => run.setSelectedParticipants(const {}),
                            style: compactButton,
                            child: Text(
                              t(LocaleKeys.commonClearSelection),
                              style: typo.uiTiny.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: RevericSpacing.sm),
                      Wrap(
                        spacing: RevericSpacing.sm,
                        runSpacing: RevericSpacing.sm,
                        children: [
                          for (final participant in participants)
                            CouncilParticipantChip(
                              participant: participant,
                              isSelected: selected.contains(participant.id),
                              density: AgentMessageDensity.panel,
                              onToggle: () =>
                                  run.toggleParticipant(participant.id),
                              onEdit: () => showRevericDialog<void>(
                                context: context,
                                builder: (_) => _ParticipantEditDialog(
                                  participant: participant,
                                  run: run,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: RevericSpacing.x2l),
                _SetupBlock(
                  icon: RevericIcons.history_rounded,
                  accentColor: colors.accentAmber,
                  title: t(LocaleKeys.councilDiscussionRounds),
                  trailing: Text(
                    '${run.config.maxRounds}',
                    style: typo.uiSemibold.copyWith(color: colors.accentAmber),
                  ),
                  child: Slider(
                    value: run.config.maxRounds.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: run.config.maxRounds.toString(),
                    onChanged: (value) => run.setMaxRounds(value.toInt()),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(RevericSpacing.lg),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerLeft, child: modelSelector),
                const SizedBox(height: RevericSpacing.md),
                FilledButton.icon(
                  onPressed: run.canStart ? run.start : null,
                  icon: run.isRunning
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.surface,
                          ),
                        )
                      : RevericIcon(RevericIcons.groups_rounded, size: 18),
                  label: Text(
                    run.isRunning
                        ? t(LocaleKeys.councilDiscussing)
                        : t(LocaleKeys.councilStart),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SetupBlock extends StatelessWidget {
  const _SetupBlock({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String icon;
  final Color accentColor;
  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RevericIcon(icon, size: 14, color: accentColor),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              title,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            if (trailing != null) ...[const Spacer(), trailing!],
          ],
        ),
        const SizedBox(height: RevericSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(RevericSpacing.lg),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(RevericRadius.x2l),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// 编辑成员的名字、提示词与专属模型；保存后写回对应的专家设定。
class _ParticipantEditDialog extends HookConsumerWidget {
  const _ParticipantEditDialog({required this.participant, required this.run});

  final CouncilParticipant participant;
  final CouncilRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final t = context.t;
    final models = run.models;
    final nameController = useTextEditingController(
      text: participant.resolveName(t),
    );
    final promptController = useTextEditingController(
      text: participant.resolvePrompt(t),
    );
    final modelOptionId = useState<String?>(
      const <String>{}.contains(participant.modelOptionId)
          ? null
          : participant.modelOptionId,
    );
    final saving = useState(false);

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
      child: Text(text, style: typo.uiSmall.copyWith(color: colors.textMuted)),
    );

    return RevericDialog.panel(
      title: Text(t(LocaleKeys.commonEdit)),
      width: 420 + RevericSpacing.x4l * 2,
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AgentAvatar(
                    avatarPath: participant.avatarPath,
                    slug: participant.id,
                    avatarEmoji: participant.avatarEmoji,
                    size: 24,
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  Expanded(
                    child: Text(
                      participant.resolveName(t),
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RevericSpacing.x2l),
              label(t(LocaleKeys.councilParticipantNameLabel)),
              TextField(
                controller: nameController,
                style: typo.ui.copyWith(color: colors.textPrimary),
                decoration: _fieldDecoration(colors, typo),
              ),
              const SizedBox(height: RevericSpacing.x2l),
              label(t(LocaleKeys.councilParticipantPromptLabel)),
              TextField(
                controller: promptController,
                maxLines: 6,
                minLines: 3,
                style: typo.ui.copyWith(color: colors.textPrimary),
                decoration: _fieldDecoration(colors, typo),
              ),
              const SizedBox(height: RevericSpacing.x2l),
              label(t(LocaleKeys.councilCustomModel)),
              ModelSelector.field(
                availableModels: [
                  for (final m in models.availableModels)
                    if (m.kind == AiModelKind.chat) m,
                ],
                selectedId: modelOptionId.value,
                unsetLabel: t(LocaleKeys.councilDefaultModel),
                disabledModelIds: const <String>{},

                onChanged: (value) => modelOptionId.value = value,
              ),
            ],
          ),
        ),
      ),
      actions: [
        RevericButton.secondary(
          label: t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        RevericButton.primary(
          label: t(LocaleKeys.commonSave),
          onPressed: saving.value
              ? null
              : () async {
                  final name = nameController.text.trim();
                  final prompt = promptController.text.trim();
                  saving.value = true;
                  await run.updateParticipant(
                    participant.copyWith(
                      name: name.isNotEmpty ? name : participant.name,
                      prompt: prompt.isNotEmpty ? prompt : participant.prompt,
                      modelOptionId: modelOptionId.value,
                      clearModelOptionId: modelOptionId.value == null,
                    ),
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
        ),
      ],
    );
  }
}
