// 职责: 编辑单次生图的请求级扩展参数（魔搭 LoRA/采样参数、MOSS 扩展开关）的面板区域。
// 关联文件:
//   lib/shared/models/image/extras.dart
//   lib/shared/models/image/channels.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/components/reveric_switch.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../components/reveric_switch.dart';
import '../../components/reveric_text_field.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/image/channels.dart';
import '../../models/image/extras.dart';
import '../../theme/theme.dart';

/// 单次生图的请求级扩展参数编辑面板；按协议显示对应控件，
/// 每次修改立即通过 [onChanged] 上报完整快照。
///
/// 协议分支拆成独立的 HookWidget：魔搭与 MOSS 两个 section 的 hook
/// 数量和类型不同，在同一个 element 内随 protocol 切换会触发
/// 「Type mismatch between hooks」并炸掉整个弹窗；widget 类型不同
/// 才能让 Flutter 重建 element、各自从零持有 hooks。
class ImageRequestExtrasPanel extends StatelessWidget {
  const ImageRequestExtrasPanel({
    super.key,
    required this.protocol,
    this.value,
    this.recommendedSteps,
    required this.onChanged,
  });

  final ImageProtocol protocol;
  final ImageRequestExtras? value;

  /// 当前模型的官方建议采样步数;为空时步数输入框留空(请求不带 steps,
  /// 沿用服务端模型默认),仅在已存参数没有 steps 时作为初始值。
  final int? recommendedSteps;
  final ValueChanged<ImageRequestExtras?> onChanged;

  @override
  Widget build(BuildContext context) {
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: RevericSpacing.sm,
      children: [
        Text(
          context.t(LocaleKeys.productionImageExtras),
          style: typo.uiSmall.copyWith(color: colors.textPrimary),
        ),
        Text(
          context.t(LocaleKeys.productionImageExtrasHint),
          style: typo.uiTiny.copyWith(color: colors.textMuted),
        ),
        switch (protocol) {
          ImageProtocol.modelscope_image => _ModelScopeExtrasSection(
            value: value,
            recommendedSteps: recommendedSteps,
            onChanged: onChanged,
          ),
          ImageProtocol.moss_image => _MossExtrasSection(
            value: value,
            onChanged: onChanged,
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

// ---- 魔搭：LoRA 叠加 + 采样参数 ---------------------------------------

class _ModelScopeExtrasSection extends HookWidget {
  const _ModelScopeExtrasSection({
    required this.value,
    required this.recommendedSteps,
    required this.onChanged,
  });

  final ImageRequestExtras? value;
  final int? recommendedSteps;
  final ValueChanged<ImageRequestExtras?> onChanged;

  @override
  Widget build(BuildContext context) {
    final initial = value ?? const ImageRequestExtras();
    final loras = useState<List<ModelScopeLora>>(initial.loras);
    // 常用默认:引导 1.0、种子 -1(随机);步数按模型官方建议预填,
    // 无建议值时留空(请求不带 steps,沿用服务端默认)。
    final steps = useTextEditingController(
      text: initial.steps?.toString() ?? recommendedSteps?.toString() ?? '',
    );
    final guidance = useTextEditingController(
      text: initial.guidance?.toString() ?? '1.0',
    );
    final seed = useTextEditingController(
      text: initial.seed?.toString() ?? '-1',
    );

    void report({
      List<ModelScopeLora>? nextLoras,
      int? stepsValue,
      double? guidanceValue,
      int? seedValue,
      bool clearSteps = false,
      bool clearGuidance = false,
      bool clearSeed = false,
    }) {
      onChanged(
        ImageRequestExtras(
          loras: nextLoras ?? loras.value,
          steps: clearSteps ? null : stepsValue ?? int.tryParse(steps.text),
          guidance: clearGuidance
              ? null
              : guidanceValue ?? double.tryParse(guidance.text),
          seed: clearSeed ? null : seedValue ?? int.tryParse(seed.text),
        ),
      );
    }

    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    final weightSum = loras.value.fold<double>(
      0,
      (total, lora) => total + lora.weight,
    );
    final weightSumInvalid =
        loras.value.length >= 2 && (weightSum - 1.0).abs() > 0.001;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: RevericSpacing.sm,
      children: [
        for (var index = 0; index < loras.value.length; index++)
          _LoraRow(
            key: ValueKey('lora_$index'),
            initial: loras.value[index],
            onChanged: (lora) {
              final next = [...loras.value];
              next[index] = lora;
              loras.value = next;
              report(nextLoras: next);
            },
            onRemoved: () {
              final next = [...loras.value]..removeAt(index);
              loras.value = next;
              report(nextLoras: next);
            },
          ),
        if (weightSumInvalid)
          Text(
            context.t(LocaleKeys.productionImageLoraWeightSum),
            style: typo.uiTiny.copyWith(color: colors.error),
          ),
        if (loras.value.length < 6)
          TextButton.icon(
            onPressed: () {
              final next = [
                ...loras.value,
                const ModelScopeLora(repoId: '', weight: 1),
              ];
              loras.value = next;
              report(nextLoras: next);
            },
            icon: const Icon(Icons.add, size: 16),
            label: Text(
              context.t(LocaleKeys.productionImageLoraAdd),
              style: typo.uiSmall,
            ),
          )
        else
          Text(
            context.t(LocaleKeys.productionImageLoraMax),
            style: typo.uiTiny.copyWith(color: colors.textMuted),
          ),
        Row(
          spacing: RevericSpacing.sm,
          children: [
            Expanded(
              child: RevericTextField(
                controller: steps,
                label: context.t(LocaleKeys.productionImageSteps),
                height: 30,
                keyboardType: TextInputType.number,
                onChanged: (_) => report(),
              ),
            ),
            Expanded(
              child: RevericTextField(
                controller: guidance,
                label: context.t(LocaleKeys.productionImageGuidance),
                height: 30,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => report(),
              ),
            ),
            Expanded(
              child: RevericTextField(
                controller: seed,
                label: context.t(LocaleKeys.productionImageSeed),
                height: 30,
                keyboardType: TextInputType.number,
                onChanged: (_) => report(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---- MOSS：负向提示词 + 扩展开关 -------------------------------------

class _MossExtrasSection extends HookWidget {
  const _MossExtrasSection({required this.value, required this.onChanged});

  final ImageRequestExtras? value;
  final ValueChanged<ImageRequestExtras?> onChanged;

  @override
  Widget build(BuildContext context) {
    final initial = value ?? const ImageRequestExtras();
    final negative = useTextEditingController(text: initial.negativePrompt ?? '');
    final promptEnhance = useState(initial.promptEnhance);
    final watermark = useState(initial.outputWatermark);

    void report() {
      onChanged(
        ImageRequestExtras(
          negativePrompt: negative.text.trim().isEmpty
              ? null
              : negative.text,
          promptEnhance: promptEnhance.value,
          outputWatermark: watermark.value,
        ),
      );
    }

    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    Widget toggleRow(String label, bool value, ValueChanged<bool> onChange) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: typo.uiSmall.copyWith(color: colors.textPrimary)),
          RevericSwitch(value: value, onChanged: onChange),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: RevericSpacing.sm,
      children: [
        RevericTextField(
          controller: negative,
          label: context.t(LocaleKeys.productionImageNegativePrompt),
          height: 30,
          onChanged: (_) => report(),
        ),
        // 开关默认值与请求发送的官方默认一致:增强开(true)、水印关(false)。
        toggleRow(
          context.t(LocaleKeys.productionImagePromptEnhance),
          promptEnhance.value ?? true,
          (on) {
            promptEnhance.value = on;
            report();
          },
        ),
        toggleRow(
          context.t(LocaleKeys.productionImageWatermark),
          watermark.value ?? false,
          (on) {
            watermark.value = on;
            report();
          },
        ),
      ],
    );
  }
}

class _LoraRow extends HookWidget {
  const _LoraRow({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.onRemoved,
  });
  final ModelScopeLora initial;
  final ValueChanged<ModelScopeLora> onChanged;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    final repo = useTextEditingController(text: initial.repoId);
    final weight = useTextEditingController(
      text: initial.weight.toString(),
    );
    final colors = RevericTheme.colorsOf(context);

    void report() {
      final parsedWeight = double.tryParse(weight.text);
      onChanged(
        ModelScopeLora(
          repoId: repo.text.trim(),
          weight: parsedWeight == null || parsedWeight <= 0 ? 1 : parsedWeight,
        ),
      );
    }

    return Row(
      spacing: RevericSpacing.xs,
      children: [
        Expanded(
          flex: 3,
          child: RevericTextField(
            controller: repo,
            hintText: 'bozoyan/Q-FEIFEI',
            height: 30,
            onChanged: (_) => report(),
          ),
        ),
        Expanded(
          child: RevericTextField(
            controller: weight,
            height: 30,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => report(),
          ),
        ),
        IconButton(
          tooltip: context.t(LocaleKeys.commonDelete),
          icon: Icon(
            Icons.remove_circle_outline,
            size: 16,
            color: colors.textMuted,
          ),
          onPressed: onRemoved,
        ),
      ],
    );
  }
}
