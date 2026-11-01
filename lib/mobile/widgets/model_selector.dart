// 职责: 移动端统一「模型 + 推理强度」选择触发器 — pill（聊天输入条）/ bar（各 AI 模式启动条）两种形态，
//   展示当前模型名与 effort 竖条，点击打开 showAiModelEffortSheet 下钻选择（对齐桌面端 ModelSelector）。
// 关联文件:
//   lib/mobile/widgets/model_effort_sheet.dart
//   lib/shared/widgets/ai/provider_model_icon.dart
//   lib/shared/widgets/ai/reasoning_effort_bars.dart
//   lib/shared/models/ai_provider.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
// 遵循的 Rules:
//   .agents/rules/icons.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/ai_provider.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/ai/provider_model_icon.dart';
import '../../shared/widgets/ai/reasoning_effort_bars.dart';
import 'model_effort_sheet.dart';

enum _ModelSelectorVariant { pill, bar }

/// 统一模型/推理强度选择触发器。
///
/// - [MobileModelSelector.pill]：聊天输入条用的紧凑药丸（模型名 + effort 竖条 + 箭头）。
/// - [MobileModelSelector.bar]：各 AI 模式启动条用的整宽行（provider 图标 + 模型名 + effort + 箭头）。
///
/// 两种形态点击都打开 [showAiModelEffortSheet]：模型列表 + 推理模型下钻推理强度。展示的
/// effort 经 [reasoningEffortForOption] 回落到默认档位（对齐桌面端）。[models] 为空且提供
/// [onEmpty] 时，点击改走 [onEmpty]（如引导配置可用模型）。
class MobileModelSelector extends StatelessWidget {
  const MobileModelSelector.pill({
    super.key,
    required this.models,
    required this.selectedId,
    required this.selectedEffort,
    this.disabledModelIds = const {},
    this.onSelectModel,
    this.onSelectEffort,

    this.onTap,
    this.onEmpty,
    this.placeholder,
  }) : _variant = _ModelSelectorVariant.pill;

  const MobileModelSelector.bar({
    super.key,
    required this.models,
    required this.selectedId,
    required this.selectedEffort,
    this.disabledModelIds = const {},
    this.onSelectModel,
    this.onSelectEffort,

    this.onTap,
    this.onEmpty,
    this.placeholder,
  }) : _variant = _ModelSelectorVariant.bar;

  final _ModelSelectorVariant _variant;

  /// 候选模型（由调用方按需过滤，通常为 chat kind）。
  final List<AiModelOption> models;

  /// 当前选中模型 id（`providerId::model`）；null / 不在列表内时展示占位。
  final String? selectedId;

  /// 当前会话已选 effort；null 表示跟随模型默认档位。
  final String? selectedEffort;

  final Set<String> disabledModelIds;

  /// 内部打开弹窗时的选择回调；提供 [onTap]（外部自管打开）时可省略。
  final ValueChanged<AiModelOption>? onSelectModel;
  final void Function(AiModelOption option, String effort)? onSelectEffort;

  /// 点击处理覆盖：非空时点击改走 [onTap]（调用方自行打开弹窗，如聊天页与
  /// ChatSessionController 共用同一入口），此时仅复用触发器的展示。
  final VoidCallback? onTap;

  /// [models] 为空时点击的兜底回调（如配置引导）；为 null 时空列表也照常打开弹窗。
  final VoidCallback? onEmpty;

  /// 未选中模型时展示的占位文案；null 时用「默认模型」。
  final String? placeholder;

  AiModelOption? get _currentOption {
    final id = selectedId;
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final option in models) {
      if (option.id == id) {
        return option;
      }
    }
    return null;
  }

  void _handleTap(BuildContext context) {
    if (onTap != null) {
      onTap!();
      return;
    }
    if (models.isEmpty && onEmpty != null) {
      onEmpty!();
      return;
    }
    final selectModel = onSelectModel;
    final selectEffort = onSelectEffort;
    if (selectModel == null || selectEffort == null) {
      return;
    }
    showAiModelEffortSheet(
      context,
      title: context.t(LocaleKeys.mobileChatModelTitle),
      subtitle: context.t(LocaleKeys.mobileChatModelSubtitle),
      models: models,
      selectedId: selectedId,
      selectedEffort: selectedEffort,
      disabledModelIds: disabledModelIds,

      onSelectModel: selectModel,
      onSelectEffort: selectEffort,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final option = _currentOption;
    final label =
        option?.displayModelName ??
        placeholder ??
        context.t(LocaleKeys.mobileChatModelDefault);
    final effort = reasoningEffortForOption(option, selectedEffort);
    final efforts = option?.reasoningEfforts;
    final showEffort = effort != null && efforts != null;

    return _variant == _ModelSelectorVariant.pill
        ? _buildPill(context, colors, typo, label, efforts, effort, showEffort)
        : _buildBar(
            context,
            colors,
            typo,
            option,
            label,
            efforts,
            effort,
            showEffort,
          );
  }

  // 聊天输入条：紧凑药丸。
  Widget _buildPill(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
    String label,
    List<String>? efforts,
    String? effort,
    bool showEffort,
  ) {
    return GestureDetector(
      onTap: () => _handleTap(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.sm,
          vertical: RevericSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(RevericRadius.full),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSmall.copyWith(color: colors.textSecondary),
              ),
            ),
            if (showEffort) ...[
              const SizedBox(width: RevericSpacing.xs),
              Container(width: 1, height: 11, color: colors.border),
              const SizedBox(width: RevericSpacing.xs),
              ReasoningEffortBars(
                total: efforts!.length,
                level: efforts.indexOf(effort!),
              ),
              const SizedBox(width: RevericSpacing.xxs),
              Text(
                reasoningEffortLabelOf(context, effort),
                style: typo.uiTiny.copyWith(
                  color: colors.accentWarm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(width: RevericSpacing.xxs),
            RevericIcon(
              RevericIcons.keyboard_arrow_down,
              size: 16,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  // 模式启动条：整宽行。
  Widget _buildBar(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
    AiModelOption? option,
    String label,
    List<String>? efforts,
    String? effort,
    bool showEffort,
  ) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: InkWell(
        onTap: () => _handleTap(context),
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(color: colors.borderInput),
          ),
          child: Row(
            children: [
              RevericIcon(
                option == null
                    ? RevericIcons.psychology_outlined
                    : providerModelIcon(option.providerId),
                size: 17,
                color: colors.accent,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.ui.copyWith(color: colors.textPrimary),
                ),
              ),
              if (showEffort) ...[
                const SizedBox(width: RevericSpacing.sm),
                Container(width: 1, height: 12, color: colors.border),
                const SizedBox(width: RevericSpacing.sm),
                ReasoningEffortBars(
                  total: efforts!.length,
                  level: efforts.indexOf(effort!),
                ),
                const SizedBox(width: RevericSpacing.xxs),
                Text(
                  reasoningEffortLabelOf(context, effort),
                  style: typo.uiTiny.copyWith(
                    color: colors.accentWarm,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              RevericIcon(
                RevericIcons.expand_more,
                size: 18,
                color: colors.textSubtle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
