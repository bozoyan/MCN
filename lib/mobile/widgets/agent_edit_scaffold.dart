// 职责: 移动端「助手」管理项编辑页共享骨架 — 顶部返回/标题/保存栏、Hero、启用卡、字段块、删除按钮、模型选择 sheet 与字段行。
// 关联文件:
//   lib/mobile/pages/subagent_manage_page.dart
//   lib/mobile/pages/ai_shortcut_manage_page.dart
//   lib/mobile/pages/agent_prompt_manage_page.dart
//   lib/shared/widgets/agent_avatar.dart
//   lib/shared/widgets/ai/reasoning_effort_bars.dart
//   lib/shared/components/reveric_switch.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/components/reveric_switch.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/ai_provider.dart';
import '../../shared/providers/settings_providers.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/agent_avatar.dart';
import '../../shared/widgets/ai/reasoning_effort_bars.dart';
import '../../shared/widgets/confirm_dialog.dart';

/// 编辑页骨架：canvas 背景 + 顶部（返回 + 居中标题 + 保存）+ 可滚动表单区。
class MobileAgentEditScaffold extends StatelessWidget {
  const MobileAgentEditScaffold({
    super.key,
    required this.title,
    required this.saving,
    required this.canSave,
    required this.onSave,
    required this.children,
  });

  final String title;
  final bool saving;
  final bool canSave;
  final Future<void> Function() onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.xs,
                RevericSpacing.sm,
                RevericSpacing.lg,
                RevericSpacing.sm,
              ),
              child: Row(
                children: [
                  InkWell(
                    key: const ValueKey('mobile_agent_edit_back'),
                    onTap: () => Navigator.of(context).maybePop(),
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(RevericSpacing.sm),
                      child: RevericIcon(
                        RevericIcons.arrow_back,
                        size: 22,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: (!canSave || saving) ? null : () => onSave(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: RevericSpacing.lg,
                      ),
                    ),
                    child: Text(
                      saving
                          ? context.t(LocaleKeys.commonSaving)
                          : context.t(LocaleKeys.commonSave),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.borderSubtle),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.x4l,
                  RevericSpacing.x2l,
                  RevericSpacing.x4l,
                  RevericSpacing.x6l,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 管理列表骨架：canvas 背景 + 顶部（返回 + 居中标题 + 次要操作/新建）+ 列表区。
class MobileManageScaffold extends StatelessWidget {
  const MobileManageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.onAdd,
    this.onSecondaryAction,
    this.secondaryActionIcon = RevericIcons.copy,
    this.secondaryActionLabel,
  });

  final String title;
  final Widget child;
  final VoidCallback? onAdd;
  final VoidCallback? onSecondaryAction;
  final String secondaryActionIcon;
  final String? secondaryActionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.xs,
                RevericSpacing.sm,
                RevericSpacing.xs,
                RevericSpacing.sm,
              ),
              child: Row(
                children: [
                  InkWell(
                    key: const ValueKey('mobile_manage_back'),
                    onTap: () => Navigator.of(context).maybePop(),
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(RevericSpacing.sm),
                      child: RevericIcon(
                        RevericIcons.arrow_back,
                        size: 22,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (onSecondaryAction != null)
                    Semantics(
                      button: true,
                      label: secondaryActionLabel,
                      child: InkWell(
                        key: const ValueKey('mobile_manage_secondary_action'),
                        onTap: onSecondaryAction,
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(RevericSpacing.sm),
                          child: RevericIcon(
                            secondaryActionIcon,
                            size: 22,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  if (onAdd != null)
                    InkWell(
                      onTap: onAdd,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(RevericSpacing.sm),
                        child: RevericIcon(
                          RevericIcons.add,
                          size: 22,
                          color: colors.textSecondary,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 38),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.borderSubtle),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// 编辑页头部：圆角图标 + 标题 + 说明。
class AgentEditHero extends StatelessWidget {
  const AgentEditHero({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.emoji,
    this.avatarPath,
    this.avatarSlug,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final String? emoji;
  final String? avatarPath;
  final String? avatarSlug;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(RevericRadius.large),
          ),
          alignment: Alignment.center,
          child: avatarPath != null || avatarSlug != null
              ? AgentAvatar(
                  avatarPath: avatarPath,
                  slug: avatarSlug,
                  avatarEmoji: emoji,
                  size: 60,
                  backgroundColor: Colors.transparent,
                )
              : emoji != null && emoji!.isNotEmpty
              ? Text(emoji!, style: const TextStyle(fontSize: 28))
              : RevericIcon(icon, size: 26, color: colors.accent),
        ),
        const SizedBox(width: RevericSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.heading2.copyWith(color: colors.textPrimary),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: RevericSpacing.xxs),
                Text(
                  subtitle!,
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 启用开关卡片（label + 说明 + 开关）。
class AgentEditEnableCard extends StatelessWidget {
  const AgentEditEnableCard({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

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
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t(LocaleKeys.subagentEnabled),
                  style: typo.uiMedium.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  context.t(LocaleKeys.mobileAssistantEnableHint),
                  style: typo.uiTiny.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: RevericSpacing.md),
          RevericSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 字段块：标签 + 可选右侧操作 + 字段内容。
class AgentEditField extends StatelessWidget {
  const AgentEditField({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
    this.hint,
  });

  final String label;
  final Widget child;
  final Widget? trailing;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: typo.uiSmallSemibold.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: RevericSpacing.xxs),
          Text(hint!, style: typo.uiTiny.copyWith(color: colors.textMuted)),
        ],
        const SizedBox(height: RevericSpacing.sm),
        child,
      ],
    );
  }
}

/// 删除按钮（整行，error 色描边）。
class AgentEditDeleteButton extends StatelessWidget {
  const AgentEditDeleteButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.error,
        side: BorderSide(color: colors.error.withValues(alpha: 0.4)),
        minimumSize: const Size(double.infinity, 46),
      ),
      icon: RevericIcon(RevericIcons.delete_outline, size: 16),
      label: Text(label),
    );
  }
}

/// 通用删除确认对话框；确认返回 true。
Future<bool> confirmAgentDelete(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: context.t(LocaleKeys.commonDelete),
    variant: ConfirmDialogVariant.error,
  );
}

/// 可点击的模型选择字段行（展示当前模型名 + chevron）。
class AgentModelField extends StatelessWidget {
  const AgentModelField({
    super.key,
    required this.modelLabel,
    required this.onTap,
  });

  final String modelLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: Container(
        height: RevericSizes.fieldHeight,
        padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.lg),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(RevericRadius.large),
          border: Border.all(color: colors.borderInput),
        ),
        child: Row(
          children: [
            RevericIcon(
              RevericIcons.psychology_outlined,
              size: 17,
              color: colors.accent,
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                modelLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSmall.copyWith(color: colors.textPrimary),
              ),
            ),
            RevericIcon(
              RevericIcons.chevron_right,
              size: 18,
              color: colors.textSubtle,
            ),
          ],
        ),
      ),
    );
  }
}

/// 可点击的推理强度字段行（展示当前档位 + chevron），点击打开 [showMobileEffortPicker]。
class AgentEffortField extends StatelessWidget {
  const AgentEffortField({
    super.key,
    required this.effort,
    required this.onTap,
  });

  final String? effort;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: Container(
        height: RevericSizes.fieldHeight,
        padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.lg),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(RevericRadius.large),
          border: Border.all(color: colors.borderInput),
        ),
        child: Row(
          children: [
            RevericIcon(
              RevericIcons.lightning,
              size: 17,
              color: colors.accentWarm,
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                reasoningEffortLabelOf(context, effort),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSmall.copyWith(color: colors.textPrimary),
              ),
            ),
            RevericIcon(
              RevericIcons.chevron_right,
              size: 18,
              color: colors.textSubtle,
            ),
          ],
        ),
      ),
    );
  }
}

/// 模型选择底部弹窗。返回选中的 [AiModelOption] id（`providerId::model`）；
/// 选择「不指定」返回空串；取消返回 null。
///
/// 面板的 ModelSelector 门禁行为。默认不门禁，保持 subagent 编辑等既有调用方行为。
/// [modelOptions] 非空时只展示该场景可选的模型，例如图像生成模型。
Future<String?> showMobileModelPicker(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
  List<AiModelOption>? modelOptions,

  Set<String> disabledModelIds = const {},
}) {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);
  final models =
      modelOptions ??
      ref.read(availableAiModelsProvider) ??
      const <AiModelOption>[];

  return showModalBottomSheet<String?>(
    context: context,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RevericRadius.x2l),
      ),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(RevericSpacing.lg),
              child: Text(
                sheetContext.t(LocaleKeys.mobileChatModelTitle),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ),

            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: RevericSpacing.lg),
                children: [
                  ListTile(
                    title: Text(
                      sheetContext.t(LocaleKeys.subagentModelNotSelected),
                      style: typo.body.copyWith(color: colors.textPrimary),
                    ),
                    trailing: (selectedId == null || selectedId.isEmpty)
                        ? RevericIcon(
                            RevericIcons.check,
                            size: 18,
                            color: colors.accent,
                          )
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(''),
                  ),
                  if (models.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        RevericSpacing.lg,
                        0,
                        RevericSpacing.lg,
                        RevericSpacing.lg,
                      ),
                      child: Text(
                        sheetContext.t(LocaleKeys.subagentNoModelsAvailable),
                        style: typo.uiSmall.copyWith(color: colors.textMuted),
                      ),
                    )
                  else
                    for (final AiModelOption option in models)
                      _buildMobileModelPickerRow(
                        sheetContext: sheetContext,
                        option: option,
                        selected: option.id == selectedId,
                        disabled: disabledModelIds.contains(option.id),

                        colors: colors,
                        typo: typo,
                      ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _buildMobileModelPickerRow({
  required BuildContext sheetContext,
  required AiModelOption option,
  required bool selected,
  required bool disabled,

  required RevericColors colors,
  required RevericTypography typo,
}) {
  return ListTile(
    enabled: !disabled,
    title: Text(
      option.displayModelName,
      style: typo.body.copyWith(
        color: disabled ? colors.textSubtle : colors.textPrimary,
      ),
    ),
    subtitle: Text(
      option.providerDisplayName,
      style: typo.uiSmall.copyWith(color: colors.textMuted),
    ),
    trailing: selected
        ? RevericIcon(RevericIcons.check, size: 18, color: colors.accent)
        : null,
    onTap: disabled ? null : () => Navigator.of(sheetContext).pop(option.id),
  );
}

/// 把模型 id（`providerId::model`）解析为展示名；未选择/空返回占位文案。
String mobileModelLabel(BuildContext context, WidgetRef ref, String? modelId) {
  if (modelId == null || modelId.isEmpty) {
    return context.t(LocaleKeys.subagentModelNotSelected);
  }
  final models = ref.read(availableAiModelsProvider);
  for (final option in models) {
    if (option.id == modelId) {
      return option.displayModelName;
    }
  }
  // 已选模型当前不在可用列表（provider 未配置）时，回退展示 id 的模型段。
  final parts = modelId.split('::');
  return parts.length == 2 ? parts[1] : modelId;
}

/// 推理强度选择底部弹窗。返回选中的 effort wire 值；取消返回 null。
/// [efforts] 为该模型支持的档位顺序（低→高）。
Future<String?> showMobileEffortPicker(
  BuildContext context, {
  required List<String> efforts,
  required String? selected,
}) {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RevericRadius.x2l),
      ),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(RevericSpacing.lg),
              child: Text(
                sheetContext.t(LocaleKeys.aiReasoningEffort),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ),
            for (int i = 0; i < efforts.length; i++)
              ListTile(
                leading: ReasoningEffortBars(total: efforts.length, level: i),
                title: Text(
                  reasoningEffortLabelOf(sheetContext, efforts[i]),
                  style: typo.body.copyWith(
                    color: efforts[i] == selected
                        ? colors.accent
                        : colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  reasoningEffortHintOf(sheetContext, efforts[i]),
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
                trailing: efforts[i] == selected
                    ? RevericIcon(
                        RevericIcons.check,
                        size: 18,
                        color: colors.accent,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(efforts[i]),
              ),
            const SizedBox(height: RevericSpacing.sm),
          ],
        ),
      );
    },
  );
}
