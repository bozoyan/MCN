// 职责: 桌面端角色扮演底部输入栏 — 可选「切换写作模式」、文本框、模型选择与发送；开局前后共用。
// 关联文件:
//   lib/desktop/features/roleplay/panel.dart
//   lib/shared/hooks/use_roleplay_run.dart
//   lib/desktop/widgets/ai/model/model_selector.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/roleplay.json
//   assets/translations/zh-CN/roleplay.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'package:flutter/material.dart';

import '../../../shared/hooks/use_roleplay_run.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/ai_provider.dart';
import '../../../shared/theme/theme.dart';
import '../../widgets/ai/model/model_selector.dart';

class RoleplayComposer extends StatelessWidget {
  const RoleplayComposer({
    super.key,
    required this.run,
    required this.characterName,
    this.onSwitchToWriteMode,
  });

  final RoleplayRun run;

  /// 输入框占位里的角色名；尚未选角色时为空串。
  final String characterName;
  final Future<void> Function()? onSwitchToWriteMode;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final models = run.models;
    final resolved = models.displayed;
    final enabled = run.canCompose && !run.isSending;
    final switchToWrite = onSwitchToWriteMode;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x2l,
        RevericSpacing.sm,
        RevericSpacing.x2l,
        RevericSpacing.x2l,
      ),
      color: colors.surfaceContainerHigh.withValues(alpha: 0.96),
      child: SafeArea(
        child: Row(
          children: [
            if (switchToWrite != null) ...[
              Tooltip(
                message: context.t(LocaleKeys.aiSwitchToWriteMode),
                child: InkWell(
                  borderRadius: BorderRadius.circular(RevericRadius.pill),
                  onTap: run.isSending ? null : switchToWrite,
                  child: Padding(
                    padding: const EdgeInsets.all(RevericSpacing.xs),
                    child: RevericIcon(
                      RevericIcons.edit_note_outlined,
                      size: 20,
                      color: run.isSending
                          ? colors.textSubtle
                          : colors.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
            ],
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(RevericRadius.x2l),
                  border: Border.all(color: colors.borderInput),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: run.inputController,
                      style: typo.ui.copyWith(color: colors.textPrimary),
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: context.t(
                          LocaleKeys.roleplayInputHint,
                          namedArgs: {'name': characterName},
                        ),
                        hintStyle: typo.ui.copyWith(color: colors.textSubtle),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: RevericSpacing.xl,
                          vertical: RevericSpacing.lg,
                        ),
                      ),
                      onSubmitted: enabled ? (_) => run.send() : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        RevericSpacing.sm,
                        0,
                        RevericSpacing.sm,
                        RevericSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          const Spacer(),
                          if (models.availableModels.isNotEmpty)
                            ModelSelector.compact(
                              colors: colors,
                              typo: typo,
                              modelName: resolved?.displayModelName ?? '',
                              resolvedId: resolved?.id ?? '',
                              availableModels: models.availableModels,
                              disabledModelIds: const <String>{},

                              selectedEffort: reasoningEffortForOption(
                                resolved,
                                models.selectedEffort,
                              ),
                              onSelect: models.select,
                              onSelectWithEffort: models.selectWithEffort,
                            ),
                          const SizedBox(width: RevericSpacing.sm),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: run.inputController,
                            builder: (context, value, child) {
                              final hasDraft = value.text.trim().isNotEmpty;
                              return IconButton(
                                onPressed: enabled && hasDraft
                                    ? run.send
                                    : null,
                                icon: RevericIcon(
                                  RevericIcons.arrow_upward_rounded,
                                  color: colors.accent,
                                  size: 18,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: colors.accent.withValues(
                                    alpha: 0.12,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
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
